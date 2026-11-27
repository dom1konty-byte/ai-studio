import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:path/path.dart' as p;

import '../core/catalog.dart';
import '../core/cleaner.dart';
import '../core/disk_map.dart';
import '../core/journal.dart';
import '../core/leftovers.dart';
import '../core/models.dart';
import '../core/programs.dart';
import '../core/scanner.dart';
import '../core/stats.dart';
import '../core/whitelist.dart';
import '../platform/platform_api.dart';

enum Phase { idle, analyzing, ready, cleaning, done }

enum Section { main, downloads, big, map, programs }

/// Порог «Мало места»: свободно меньше 10 ГБ на системном диске.
const lowSpaceBytes = 10 * 1024 * 1024 * 1024;

enum LoadState { idle, loading, loaded, error }

enum RowStatus { pending, scanning, done, error }

class CategoryRow {
  CategoryRow(this.category);
  final Category category;
  int? bytes;
  int files = 0;
  RowStatus status = RowStatus.pending;
  bool selected = true;

  bool get isEmpty => status == RowStatus.done && (bytes ?? 0) == 0;
  bool get active => status == RowStatus.done && !isEmpty;
}

typedef DownloadsScan = Future<List<FileInfo>> Function(String dir);
typedef FolderSizer = Future<FolderSize> Function(String path);

Future<FolderSize> _defaultFolderSizer(String path) => Isolate.run(() => measureFolderSync(path));

typedef LargeScan = Future<List<FileInfo>> Function(List<String> dirs, int n);

Future<List<FileInfo>> _defaultDownloadsScan(String dir) {
  final now = DateTime.now();
  return Isolate.run(() => scanOldDownloadsSync(dir, now));
}

Future<int> _defaultSizeOf(String path, bool isDir) {
  if (!isDir) {
    try {
      return Future.value(File(path).lengthSync());
    } catch (_) {
      return Future.value(0);
    }
  }
  return Isolate.run(() => measureFolderSync(path).bytes);
}

Future<List<FileInfo>> _defaultLargeScan(List<String> dirs, int n) =>
    Isolate.run(() => scanLargestSync(dirs, n));

class AppController extends ChangeNotifier {
  AppController({
    required this.platform,
    Env? env,
    DownloadsScan? downloadsScan,
    LargeScan? largeScan,
    FolderSizer? folderSizer,
    String? dataDir,
    DirLister? listDir,
    SizeOf? sizeOf,
    this.leftoverGuard,
  })  : env = env ?? Env.system(),
        _downloadsScan = downloadsScan ?? _defaultDownloadsScan,
        _folderSizer = folderSizer ?? _defaultFolderSizer,
        _largeScan = largeScan ?? _defaultLargeScan,
        _listDir = listDir ?? listDirReal,
        _sizeOf = sizeOf ?? _defaultSizeOf {
    systemDrive = systemDriveRoot(this.env);
    // Журнал и статистика: %LOCALAPPDATA%\ChistoDisk, иначе %APPDATA%\ChistoDisk.
    // Во временную папку не пишем; если негде — очистка не запускается.
    final local = this.env['LOCALAPPDATA'];
    final roaming = this.env['APPDATA'];
    final base = dataDir ??
        (local != null
            ? '$local\\ChistoDisk'
            : roaming != null
                ? '$roaming\\ChistoDisk'
                : null);
    if (base != null) {
      logFile = File('$base${Platform.pathSeparator}log.txt');
      _stats = StatsStore(File('$base${Platform.pathSeparator}stats.json'));
    }
    final profile = this.env['USERPROFILE'];
    if (profile != null) {
      downloadsDir = '$profile\\Downloads';
      final candidates = [
        downloadsDir!,
        '$profile\\Documents',
        '$profile\\Desktop',
        if (this.env['OneDrive'] != null) ...[
          '${this.env['OneDrive']}\\Documents',
          '${this.env['OneDrive']}\\Desktop',
        ],
      ];
      userRoots = [
        for (final r in candidates)
          if (isSafeCleanTarget(r, minSegments: 3) && isInsideAllowedRoot(r, [profile])) r,
      ];
    }
  }

  final PlatformApi platform;
  final Env env;
  final DownloadsScan _downloadsScan;
  final LargeScan _largeScan;
  final FolderSizer _folderSizer;
  final DirLister _listDir;
  final SizeOf _sizeOf;
  final PathGuard? leftoverGuard;
  File? logFile;
  StatsStore? _stats;

  /// Корень диска системы (из SystemRoot), например `C:\`.
  late final String systemDrive;
  String get systemDriveLabel => systemDrive.substring(0, 2);

  /// true, пока на главном экране идёт подтверждение/запуск очистки (защита от двойного нажатия).
  bool cleanBusy = false;
  String? errorMessage;
  String? downloadsDir;
  List<String> userRoots = const [];

  Phase phase = Phase.idle;
  Section section = Section.main;
  String progressText = '';
  double progressFraction = 1;
  List<CategoryRow> rows = [];
  int totalFreedEver = 0;
  ({int free, int total})? disk;

  LoadState downloadsState = LoadState.idle;
  List<FileInfo> downloads = [];
  final Set<String> downloadsSelected = {};

  LoadState bigState = LoadState.idle;
  List<FileInfo> big = [];
  final Set<String> bigSelected = {};

  CleanSummary? summary;
  bool failedAll = false;

  bool get lowSpace => disk != null && disk!.free < lowSpaceBytes;

  Future<void> init() async {
    totalFreedEver = await _stats?.load() ?? 0;
    disk = await platform.diskSpace(systemDrive);
    await _showCatalog();
    notifyListeners();
  }

  /// Список категорий без размеров (до анализа).
  Future<void> _showCatalog() async {
    final steam = await platform.steamPath();
    rows = buildCatalog(env, steamPath: steam).map(CategoryRow.new).toList();
  }

  // ---------- вычисляемое ----------

  int get downloadsSelectedBytes => downloads
      .where((f) => downloadsSelected.contains(f.path))
      .fold(0, (a, f) => a + f.size);

  int get bigSelectedBytes =>
      big.where((f) => bigSelected.contains(f.path)).fold(0, (a, f) => a + f.size);

  int get selectedBytes =>
      rows.where((r) => r.selected && r.active).fold(0, (a, r) => a + (r.bytes ?? 0)) +
      downloadsSelectedBytes;

  bool get hasSelection =>
      rows.any((r) => r.selected && r.active) || downloadsSelected.isNotEmpty;

  bool get canAnalyze => phase == Phase.idle || phase == Phase.ready;
  bool get canClean => phase == Phase.ready && hasSelection;
  bool get downloadsOn => downloadsSelected.isNotEmpty;

  // ---------- навигация ----------

  void go(Section s) {
    section = s;
    if (phase == Phase.done) reset();
    notifyListeners();
  }

  void reset() {
    phase = Phase.idle;
    section = Section.main;
    rows = rows.map((r) => CategoryRow(r.category)).toList();
    summary = null;
    failedAll = false;
    downloads = [];
    downloadsSelected.clear();
    downloadsState = LoadState.idle;
    big = [];
    bigSelected.clear();
    bigState = LoadState.idle;
    progressText = '';
    notifyListeners();
  }

  // ---------- анализ ----------

  Future<void> analyze() async {
    if (!canAnalyze) return;
    phase = Phase.analyzing;
    progressText = 'Считаю…';
    final steam = await platform.steamPath();
    rows = buildCatalog(env, steamPath: steam).map(CategoryRow.new).toList();
    disk = await platform.diskSpace(systemDrive);
    notifyListeners();
    for (final r in rows) {
      r.status = RowStatus.scanning;
      progressText = 'Считаю: ${r.category.title}…';
      notifyListeners();
      try {
        if (r.category.id == CategoryId.recycle) {
          final info = await platform.recycleBinInfo();
          if (info == null) throw StateError('bin');
          r.bytes = info.bytes;
          r.files = info.items;
        } else {
          final res = await scanTargets(r.category.targets);
          r.bytes = res.bytes;
          r.files = res.files;
        }
        r.status = RowStatus.done;
        if (r.isEmpty) r.selected = false;
      } catch (_) {
        r.status = RowStatus.error;
        r.selected = false;
      }
      notifyListeners();
    }
    phase = Phase.ready;
    progressText = '';
    notifyListeners();
  }

  void toggleRow(CategoryRow r, bool v) {
    if (!r.active) return;
    r.selected = v;
    notifyListeners();
  }

  // ---------- Загрузки ----------

  Future<void> loadDownloads() async {
    final dir = downloadsDir;
    if (dir == null) {
      downloadsState = LoadState.error;
      notifyListeners();
      return;
    }
    downloadsState = LoadState.loading;
    notifyListeners();
    try {
      if (!Directory(dir).existsSync()) throw const FileSystemException('нет папки');
      downloads = await _downloadsScan(dir);
      downloadsSelected.removeWhere((p) => !downloads.any((f) => f.path == p));
      downloadsState = LoadState.loaded;
    } catch (_) {
      downloadsState = LoadState.error;
    }
    notifyListeners();
  }

  void toggleDownload(String path, bool v) {
    v ? downloadsSelected.add(path) : downloadsSelected.remove(path);
    notifyListeners();
  }

  void setAllDownloads(bool v) {
    downloadsSelected.clear();
    if (v) downloadsSelected.addAll(downloads.map((f) => f.path));
    notifyListeners();
  }

  // ---------- Большие файлы ----------

  Future<void> loadBig() async {
    final dirs = userRoots.where((d) => Directory(d).existsSync()).toList();
    bigState = LoadState.loading;
    notifyListeners();
    try {
      big = await _largeScan(dirs, 50);
      bigSelected.removeWhere((p) => !big.any((f) => f.path == p));
      bigState = LoadState.loaded;
    } catch (_) {
      bigState = LoadState.error;
    }
    notifyListeners();
  }

  void toggleBig(String path, bool v) {
    v ? bigSelected.add(path) : bigSelected.remove(path);
    notifyListeners();
  }

  /// Отмеченные большие файлы — только в Корзину (после подтверждения в UI).
  Future<void> recycleBig() async {
    final files = big.where((f) => bigSelected.contains(f.path)).toList();
    if (files.isEmpty) return;
    await _runClean(categories: const [], files: files, skipBrowsers: false);
  }

  // ---------- Очистка ----------

  /// Названия запущенных браузеров, если категория «Кэш браузеров» отмечена.
  Future<List<String>> browsersToClose() async {
    final on = rows.any((r) => r.selected && r.active && r.category.id == CategoryId.browsers);
    if (!on) return const [];
    return platform.runningBrowsers();
  }

  Future<void> clean({bool skipBrowsers = false}) async {
    if (!canClean) return;
    final cats = rows.where((r) => r.selected && r.active).map((r) => r.category).toList();
    final files = downloads.where((f) => downloadsSelected.contains(f.path)).toList();
    await _runClean(categories: cats, files: files, skipBrowsers: skipBrowsers);
  }

  Future<void> _runClean({
    required List<Category> categories,
    required List<FileInfo> files,
    required bool skipBrowsers,
  }) async {
    if (logFile == null) {
      failedAll = true;
      errorMessage =
          'Некуда писать журнал: не найдены папки LOCALAPPDATA и APPDATA. Очистка не запущена.';
      phase = Phase.done;
      notifyListeners();
      return;
    }
    phase = Phase.cleaning;
    failedAll = false;
    errorMessage = null;
    progressText = 'Очищаю…';
    progressFraction = 1;
    notifyListeners();
    final sum = CleanSummary();
    summary = sum;
    try {
      final log = CleanLog(logFile!);
      await log.note('Очистка начата');
      final cleaner = Cleaner(platform, log, systemDrive: systemDrive);
      await cleaner.run(
        categories: categories,
        filesToRecycle: files,
        userRoots: userRoots,
        skipBrowsers: skipBrowsers,
        into: sum,
        onProgress: (t, f) {
          progressText = t;
          progressFraction = f;
          notifyListeners();
        },
      );
    } catch (_) {
      failedAll = true;
      errorMessage = 'Очистка прервана из-за ошибки. Уже сделанное сохранено в журнале.';
    } finally {
      try {
        totalFreedEver = await _stats?.add(sum.freedBytes) ?? totalFreedEver;
      } catch (_) {}
    }
    try {
      disk = await platform.diskSpace(systemDrive) ?? disk;
    } catch (_) {}
    phase = Phase.done;
    notifyListeners();
  }

  // ---------- Карта диска (только просмотр) ----------

  late String mapPath = systemDrive;
  LoadState mapState = LoadState.idle;
  List<FolderSize> mapEntries = [];
  String mapProgress = '';
  final Map<String, List<FolderSize>> _mapCache = {};
  int _mapToken = 0;

  bool get mapCanGoBack => mapPath.toLowerCase() != systemDrive.toLowerCase();

  /// Показывает папку [path]: из кэша или сканированием.
  Future<void> openMapFolder(String path, {bool force = false}) async {
    final token = ++_mapToken;
    mapPath = path;
    final cached = _mapCache[path];
    if (cached != null && !force) {
      mapEntries = cached;
      mapState = LoadState.loaded;
      notifyListeners();
      return;
    }
    mapState = LoadState.loading;
    mapEntries = [];
    mapProgress = 'Считаю…';
    notifyListeners();
    try {
      final result = <FolderSize>[];
      for (final d in listSubdirs(path)) {
        if (token != _mapToken) return; // ушли в другую папку
        mapProgress = 'Считаю: ${d.path.split(RegExp(r'[\\/]')).last}';
        notifyListeners();
        try {
          result.add(await _folderSizer(d.path));
        } catch (_) {
          result.add(FolderSize(d.path.split(RegExp(r'[\\/]')).last, d.path, 0, denied: true));
        }
      }
      if (token != _mapToken) return;
      mapEntries = sortBySize(result);
      _mapCache[path] = mapEntries;
      mapState = LoadState.loaded;
    } catch (_) {
      if (token != _mapToken) return;
      mapState = LoadState.error;
    }
    notifyListeners();
  }

  Future<void> mapBack() async {
    if (!mapCanGoBack) return;
    final crumbs = breadcrumbs(systemDrive, mapPath);
    await openMapFolder(crumbs[crumbs.length - 2].path);
  }

  Future<void> openInExplorer(String path) => platform.openFolder(path);

  Future<void> openLog() async {
    final lf = logFile;
    if (lf == null) return;
    try {
      if (!lf.existsSync()) {
        await lf.parent.create(recursive: true);
        await lf.writeAsString('Журнал ЧистоДиск пока пуст.\n');
      }
    } catch (_) {}
    await platform.openFile(lf.path);
  }

  // ---------- программы ----------

  LoadState programsState = LoadState.idle;
  List<Program> programs = [];
  String programQuery = '';
  ProgramSort programSort = ProgramSort.size;

  /// Сообщение над списком программ (итог запуска удаления, ошибка).
  String? programMessage;

  /// true, пока идёт удаление программы (ждём её программу удаления).
  bool uninstallBusy = false;

  List<Program> get visiblePrograms => filterAndSort(programs, programQuery, programSort);

  void setProgramQuery(String q) {
    programQuery = q;
    notifyListeners();
  }

  void setProgramSort(ProgramSort s) {
    programSort = s;
    notifyListeners();
  }

  Future<void> loadPrograms() async {
    if (programsState == LoadState.loading) return;
    programsState = LoadState.loading;
    notifyListeners();
    try {
      programs = buildPrograms(await platform.readUninstallEntries());
      programsState = LoadState.loaded;
    } catch (_) {
      programsState = LoadState.error;
    }
    notifyListeners();
  }

  /// Штатное удаление: запуск программы удаления, ожидание, затем «Остатки».
  Future<void> uninstall(Program prog) async {
    if (uninstallBusy) return;
    final cmd = parseUninstallString(prog.uninstallString, env: env.vars);
    if (cmd == null) {
      programMessage =
          'У «${prog.name}» нет программы удаления. Можно выбрать «Принудительно удалить…».';
      notifyListeners();
      return;
    }
    uninstallBusy = true;
    programMessage = 'Идёт удаление «${prog.name}»… Дождитесь окончания в окне программы удаления.';
    notifyListeners();
    UninstallRun run;
    try {
      run = await platform.runUninstaller(cmd.exe, cmd.args);
    } catch (e) {
      run = UninstallRun(started: false, error: '$e');
    }
    uninstallBusy = false;
    if (!run.started) {
      programMessage = run.cancelled
          ? 'Удаление отменено (не дали права администратора).'
          : 'Не удалось запустить удаление «${prog.name}».';
      notifyListeners();
      return;
    }
    // Удаление могли отменить внутри программы: если запись осталась — остатки не ищем.
    List<Program> after = const [];
    try {
      after = buildPrograms(await platform.readUninstallEntries());
    } catch (_) {}
    if (after.isEmpty) {
      programMessage = 'Не удалось проверить список программ после удаления. Остатки не ищу.';
      notifyListeners();
      return;
    }
    programs = after;
    programsState = LoadState.loaded;
    final still = after.any((a) => a.keyPath.toLowerCase() == prog.keyPath.toLowerCase());
    if (still) {
      programMessage =
          '«${prog.name}» всё ещё в списке: удаление отменено или ещё идёт. Остатки не ищу.';
      notifyListeners();
      return;
    }
    programMessage = null;
    await startLeftovers(prog, forced: false);
  }

  /// Принудительное удаление: программа удаления не запускается.
  Future<void> forceRemove(Program prog) => startLeftovers(prog, forced: true);

  // ---------- остатки ----------

  Program? leftoverProgram;
  bool leftoverForced = false;
  LoadState leftoverState = LoadState.idle;
  List<Leftover> leftovers = [];
  final Set<Leftover> leftoverSelected = {};
  Map<Leftover, String> leftoverResults = {};
  bool leftoverBusy = false;
  String? leftoverMessage;

  int get leftoverSelectedBytes =>
      leftovers.where(leftoverSelected.contains).fold(0, (a, l) => a + l.bytes);

  Future<void> startLeftovers(Program prog, {required bool forced}) async {
    leftoverProgram = prog;
    leftoverForced = forced;
    leftoverState = LoadState.loading;
    leftovers = [];
    leftoverSelected.clear();
    leftoverResults = {};
    leftoverMessage = null;
    notifyListeners();
    try {
      final list = await findLeftovers(
        name: prog.name,
        publisher: prog.publisher,
        installLocation: prog.installLocation,
        env: env,
        listDir: _listDir,
        regSubKeys: platform.regSubKeys,
        sizeOf: _sizeOf,
      );
      if (forced) {
        list.insert(
          0,
          Leftover(
            kind: LeftoverKind.registry,
            path: prog.keyPath,
            exact: true,
            deletable: prog.isUserHive,
            isUninstallEntry: true,
            note: prog.isUserHive
                ? 'Запись в списке программ'
                : 'Запись в списке программ. Нужны права администратора',
          ),
        );
      }
      leftovers = list;
      for (final l in list) {
        if (l.exact && l.deletable) leftoverSelected.add(l);
      }
      leftoverState = LoadState.loaded;
    } catch (_) {
      leftoverState = LoadState.error;
    }
    notifyListeners();
  }

  void toggleLeftover(Leftover l, bool on) {
    if (leftoverBusy || !l.deletable) return;
    on ? leftoverSelected.add(l) : leftoverSelected.remove(l);
    notifyListeners();
  }

  /// Папка резервных копий реестра: `<данные>\backup`.
  String? get backupDir {
    final lf = logFile;
    return lf == null ? null : p.join(lf.parent.path, 'backup');
  }

  Future<void> deleteLeftovers() async {
    if (leftoverBusy || leftoverSelected.isEmpty) return;
    final lf = logFile;
    final bd = backupDir;
    if (lf == null || bd == null) {
      leftoverMessage = 'Некуда писать журнал и резервные копии — удаление не запущено.';
      notifyListeners();
      return;
    }
    leftoverBusy = true;
    leftoverMessage = null;
    notifyListeners();
    final log = CleanLog(lf);
    final cleaner = LeftoverCleaner(
      platform: platform,
      log: log,
      env: env,
      backupDir: bd,
      guard: leftoverGuard,
    );
    final todo = leftovers.where(leftoverSelected.contains).toList();
    try {
      final outcomes = await cleaner.run(todo);
      var ok = 0;
      var bad = 0;
      for (final o in outcomes) {
        leftoverResults[o.item] = o.message;
        o.ok ? ok++ : bad++;
      }
      final removed = {for (final o in outcomes) if (o.ok) o.item};
      leftovers = leftovers.where((l) => !removed.contains(l)).toList();
      leftoverSelected.removeAll(removed);
      leftoverMessage = 'Удалено: $ok, пропущено: $bad. Файлы ушли в Корзину.';
    } catch (_) {
      leftoverMessage = 'Ошибка при удалении. Подробности — в журнале.';
    }
    await log.flush();
    leftoverBusy = false;
    notifyListeners();
  }

  void closeLeftovers() {
    leftoverProgram = null;
    leftovers = [];
    leftoverSelected.clear();
    leftoverResults = {};
    leftoverMessage = null;
    leftoverState = LoadState.idle;
    programsState = LoadState.idle; // список обновится при открытии
    notifyListeners();
  }

  Future<void> openBackupFolder() async {
    final bd = backupDir;
    if (bd == null) return;
    try {
      await Directory(bd).create(recursive: true);
    } catch (_) {}
    await platform.openFolder(bd);
  }
}
