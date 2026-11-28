import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' show sha256;

import 'package:flutter/foundation.dart' show ChangeNotifier, visibleForTesting;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:path/path.dart' as p;

import 'computer_service.dart';
import '../core/catalog.dart';
import '../core/cleaner.dart';
import '../core/disk_map.dart';
import '../core/duplicates.dart';
import '../core/empty_dirs.dart';
import '../core/journal.dart';
import '../core/killable.dart';
import '../core/leftovers.dart';
import '../core/models.dart';
import '../core/format.dart';
import '../core/async_pool.dart';
import '../core/programs.dart';
import '../core/store_apps.dart';
import '../core/scanner.dart';
import '../core/settings.dart';
import '../core/speed.dart';
import '../core/startup.dart';
import '../core/stats.dart';
import '../core/update.dart';
import '../core/whitelist.dart';
import '../platform/platform_api.dart';
import 'startup_service.dart';
import 'update_network.dart';

enum Phase { idle, analyzing, ready, cleaning, done }

enum Section { main, computer, programs, startup, internet, settings }

/// Экран поверх «Очистки» (кнопка «Назад» возвращает к плиткам).
enum Layer { none, downloads, big, dupes, emptyDirs, map, health, procs, battery }

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

typedef EmptyDirsScan = Future<List<String>> Function(List<String> roots);

Future<List<String>> _killableEmptyDirs(List<String> roots, KillGroup g) =>
    runKillable(() => findEmptyDirsSync(roots), g);

typedef LargeScan = Future<List<FileInfo>> Function(List<String> dirs, int n);

Future<List<FileInfo>> _killableDownloads(String dir, KillGroup g) =>
    runKillable(() => scanAllFilesSync(dir), g);

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

Future<List<FileInfo>> _killableLarge(List<String> dirs, int n, KillGroup g) =>
    runKillable(() => scanLargestSync(dirs, n), g);

class AppController extends ChangeNotifier {
  AppController({
    required this.platform,
    Env? env,
    DupScanner? dupScanner,
    EmptyDirsScan? emptyDirsScan,
    DownloadsScan? downloadsScan,
    LargeScan? largeScan,
    FolderSizer? folderSizer,
    String? dataDir,
    SpeedNetwork? speedNetwork,
    DirLister? listDir,
    SizeOf? sizeOf,
    this.leftoverGuard,
    FolderLister? startupLister,
    String? exePath,
    this.fileExists,
    this.dirExists,
    this.exitApp,
    UpdateNetwork? updateNetwork,
    this.launchInstaller,
    DateTime Function()? clock,
    this.uninstallPollInterval = const Duration(seconds: 3),
    this.uninstallTimeout = const Duration(minutes: 10),
  })  : env = env ?? Env.system(),
        speedNetwork = speedNetwork ?? CloudflareSpeedNetwork(),
        updateNetwork = updateNetwork ?? HttpUpdateNetwork(version: appVersion),
        _clock = clock ?? DateTime.now,
        _dupScanner = dupScanner ?? startDupScan,
        _folderSizer = folderSizer ?? _defaultFolderSizer,
        _listDir = listDir ?? listDirReal,
        exePath = exePath ?? Platform.resolvedExecutable,
        _sizeOf = sizeOf ?? _defaultSizeOf {
    _downloadsScan = downloadsScan ?? ((d) => _killableDownloads(d, _downloadsKill));
    _emptyDirsScan = emptyDirsScan ?? ((r) => _killableEmptyDirs(r, _emptyKill));
    _largeScan = largeScan ?? ((d, n) => _killableLarge(d, n, _bigKill));
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
    _dataBase = base;
    if (base != null) {
      updateDir = '$base${Platform.pathSeparator}update';
      logFile = File('$base${Platform.pathSeparator}log.txt');
      _stats = StatsStore(File('$base${Platform.pathSeparator}stats.json'));
      speedStore = SpeedHistoryStore(File('$base${Platform.pathSeparator}speed.json'));
      _settingsStore = SettingsStore(File('$base${Platform.pathSeparator}settings.json'));
    }
    startupService = StartupService(platform, this.env, lister: startupLister);
    final profile = this.env['USERPROFILE'];
    if (profile != null) {
      downloadsDir = '$profile\\Downloads';
      final candidates = [
        downloadsDir!,
        '$profile\\Documents',
        '$profile\\Desktop',
        '$profile\\Pictures',
        '$profile\\Videos',
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

  /// Найденная новая версия (null — нет или ещё не проверяли).
  UpdateInfo? availableUpdate;
  bool updateBannerHidden = false;
  bool updateChecking = false;
  bool updateInstalling = false;

  /// Доля скачанного 0..1; null — размер неизвестен или не качаем.
  double? updateProgress;

  bool get showUpdateBanner => availableUpdate != null && !updateBannerHidden;

  final PlatformApi platform;
  final Env env;
  late final DownloadsScan _downloadsScan;
  final DupScanner _dupScanner;
  late final EmptyDirsScan _emptyDirsScan;
  late final LargeScan _largeScan;
  final KillGroup _downloadsKill = KillGroup();
  final KillGroup _emptyKill = KillGroup();
  final KillGroup _bigKill = KillGroup();
  final FolderSizer _folderSizer;
  final DirLister _listDir;
  final SizeOf _sizeOf;
  final PathGuard? leftoverGuard;
  /// Проверка существования файла программы удаления (в тестах подменяется).
  final bool Function(String path)? fileExists;

  /// Проверка существования папки установки (в тестах подменяется).
  final bool Function(String path)? dirExists;

  /// Выход из программы после перезапуска с другими правами (main подставляет
  /// закрытие трея и окна; в тестах — заглушка). По умолчанию `exit(0)`.
  Future<void> Function()? exitApp;

  /// Как часто и как долго смотреть, исчезла ли запись удаляемой программы.
  final Duration uninstallPollInterval;
  final Duration uninstallTimeout;
  final String exePath;
  late final StartupService startupService;
  SettingsStore? _settingsStore;
  final UpdateNetwork updateNetwork;
  final DateTime Function() _clock;

  /// Запуск установщика (в тестах подменяется).
  final Future<void> Function(String exe, List<String> args)? launchInstaller;

  /// %LOCALAPPDATA%\ChistoDisk\update — сюда качается установщик.
  String? updateDir;

  /// Тест скорости: сеть и история (speed.json рядом с настройками).
  final SpeedNetwork speedNetwork;
  SpeedHistoryStore? speedStore;
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

  /// Все файлы Загрузок (фильтр «Все / Новые / Старше 30 дней» — в [visibleDownloads]).
  List<FileInfo> downloads = [];
  final Set<String> downloadsSelected = {};
  DownloadsFilter downloadsFilter = DownloadsFilter.old;
  int _downloadsToken = 0;

  /// Сколько отправлено в Корзину из Загрузок / Больших файлов (null — не было).
  int? downloadsRecycled;
  int? bigRecycled;
  int _bigToken = 0;

  /// Экран поверх «Очистки» и подробный итог.
  Layer layer = Layer.none;
  bool showDetails = false;

  LoadState bigState = LoadState.idle;
  List<FileInfo> big = [];
  final Set<String> bigSelected = {};

  CleanSummary? summary;
  bool failedAll = false;

  bool get lowSpace => disk != null && disk!.free < lowSpaceBytes;

  Future<void>? _initFuture;

  /// Повторный вызов ничего не делает (init зовут и main, и экран).
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    totalFreedEver = await _stats?.load() ?? 0;
    final store = _settingsStore;
    if (store != null) settings = await store.load();
    settingsLoaded = true;
    try {
      adminMode = await platform.isElevated();
    } catch (_) {
      adminMode = false;
    }
    await _syncAutostart();
    disk = await platform.diskSpace(systemDrive);
    await _showCatalog();
    notifyListeners();
  }

  /// Список категорий без размеров (до анализа).
  Future<void> _showCatalog() async {
    final steam = await platform.steamPath();
    rows = buildCatalog(env, steamPath: steam, admin: adminMode).map(CategoryRow.new).toList();
  }

  // ---------- вычисляемое ----------

  List<FileInfo> get visibleDownloads =>
      filterDownloads(downloads, DateTime.now(), downloadsFilter);

  int get downloadsSelectedBytes => downloads
      .where((f) => downloadsSelected.contains(f.path))
      .fold(0, (a, f) => a + f.size);

  int get bigSelectedBytes =>
      big.where((f) => bigSelected.contains(f.path)).fold(0, (a, f) => a + f.size);

  int get selectedBytes =>
      rows.where((r) => r.selected && r.active).fold(0, (a, r) => a + (r.bytes ?? 0));

  bool get hasSelection => rows.any((r) => r.selected && r.active);

  /// Идёт любая операция, при которой нельзя запускать другую (очистка, плитки, удаление).
  bool get anyBusy =>
      _quickBusy ||
      tileBusy ||
      cleanBusy ||
      uninstallBusy ||
      leftoverBusy ||
      emptyBusy ||
      phase == Phase.analyzing ||
      phase == Phase.cleaning;

  /// true, пока файлы плитки (Загрузки, Большие, Дубликаты) уходят в Корзину.
  /// Это не «Быстрая очистка»: её полоса и итог не затрагиваются.
  bool tileBusy = false;

  bool get canAnalyze => !_quickBusy && !tileBusy && (phase == Phase.idle || phase == Phase.ready);
  bool get canClean => !_quickBusy && !tileBusy && phase == Phase.ready && hasSelection;

  /// true, пока идёт быстрая очистка из трея.
  bool get quickBusy => _quickBusy;

  // ---------- навигация ----------

  void go(Section s) {
    section = s;
    layer = Layer.none;
    showDetails = false;
    notifyListeners();
  }

  void openLayer(Layer l) {
    if (phase == Phase.analyzing || phase == Phase.cleaning) return;
    section = Section.main;
    layer = l;
    notifyListeners();
  }

  /// Подробности экрана «Компьютер» поверх плиток (раздел не меняется).
  void openComputerLayer(Layer l) {
    layer = l;
    notifyListeners();
  }

  /// Окно спрятано в трей — опрос процессов не нужен.
  void pauseComputerPolling() => _computer?.stopPolling();

  /// Окно показано снова: опрос возобновляется, если открыт экран «Компьютер».
  void resumeComputerPolling() {
    if (section == Section.computer) _computer?.startPolling();
  }

  /// Данные экрана «Компьютер» (создаются при первом обращении).
  ComputerService get computer => _computer ??= ComputerService(platform, env);
  ComputerService? _computer;

  void closeLayer() {
    if (layer == Layer.none) return;
    layer = Layer.none;
    notifyListeners();
  }

  void openDetails() {
    if (phase != Phase.done) return;
    showDetails = true;
    notifyListeners();
  }

  void closeDetails() {
    showDetails = false;
    notifyListeners();
  }

  void reset() {
    phase = Phase.idle;
    section = Section.main;
    layer = Layer.none;
    showDetails = false;
    downloadsRecycled = null;
    bigRecycled = null;
    _downloadsToken++;
    _bigToken++;
    _emptyToken++;
    _downloadsKill.killAll();
    _bigKill.killAll();
    _emptyKill.killAll();
    rows = rows.map((r) => CategoryRow(r.category)).toList();
    summary = null;
    failedAll = false;
    downloads = [];
    downloadsSelected.clear();
    downloadsState = LoadState.idle;
    big = [];
    bigSelected.clear();
    bigState = LoadState.idle;
    emptyDirs = [];
    emptySelected.clear();
    emptyRecycled = null;
    emptySkipped = 0;
    emptyState = LoadState.idle;
    dupSkipped = 0;
    _dupToken++;
    _dupJob?.cancel();
    _dupJob = null;
    dupGroups = [];
    dupSelected.clear();
    dupRecycled = null;
    dupState = LoadState.idle;
    progressText = '';
    notifyListeners();
  }

  // ---------- анализ ----------

  bool _autoAnalyzed = false;

  /// При первом открытии экрана «Очистка» в фоне считает, что можно убрать
  /// (чтобы в полосе сразу была сумма). Один раз за запуск программы.
  Future<void> autoAnalyzeOnce() async {
    if (_autoAnalyzed) return;
    _autoAnalyzed = true;
    await init();
    if (canAnalyze && phase == Phase.idle) await analyze();
  }

  Future<void> analyze() async {
    if (!canAnalyze) return;
    phase = Phase.analyzing;
    progressText = 'Считаю…';
    final steam = await platform.steamPath();
    rows = buildCatalog(env, steamPath: steam, admin: adminMode).map(CategoryRow.new).toList();
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
        // Выбор прошлой очистки запоминается.
        if (settings.quickCategories.isNotEmpty &&
            !settings.quickCategories.contains(r.category.id.name)) {
          r.selected = false;
        }
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
    final token = ++_downloadsToken;
    _downloadsKill.killAll();
    downloadsRecycled = null;
    downloadsState = LoadState.loading;
    notifyListeners();
    try {
      if (!Directory(dir).existsSync()) throw const FileSystemException('нет папки');
      final res = await _downloadsScan(dir);
      if (token != _downloadsToken) return; // нажали «Стоп»
      downloads = res;
      downloadsSelected.removeWhere((p) => !downloads.any((f) => f.path == p));
      downloadsState = LoadState.loaded;
    } catch (_) {
      if (token != _downloadsToken) return;
      downloadsState = LoadState.error;
    }
    notifyListeners();
  }

  /// «Стоп» в плитке: результат поиска будет проигнорирован.
  void cancelDownloads() {
    _downloadsToken++;
    _downloadsKill.killAll();
    downloadsState = LoadState.idle;
    notifyListeners();
  }

  void setDownloadsFilter(DownloadsFilter f) {
    downloadsFilter = f;
    final vis = visibleDownloads.map((x) => x.path).toSet();
    downloadsSelected.removeWhere((p) => !vis.contains(p));
    notifyListeners();
  }

  void toggleDownload(String path, bool v) {
    v ? downloadsSelected.add(path) : downloadsSelected.remove(path);
    notifyListeners();
  }

  /// Отметить/снять все файлы текущего фильтра.
  void setAllDownloads(bool v) {
    downloadsSelected.clear();
    if (v) downloadsSelected.addAll(visibleDownloads.map((f) => f.path));
    notifyListeners();
  }

  /// Отмеченные файлы Загрузок — только в Корзину (после подтверждения в UI).
  Future<void> recycleDownloads() async {
    final files = downloads.where((f) => downloadsSelected.contains(f.path)).toList();
    if (files.isEmpty) return;
    final sum = await _recycleFiles(files);
    if (sum == null) {
      downloadsState = LoadState.error;
      notifyListeners();
      return;
    }
    downloadsRecycled = sum.recycledBytes;
    downloads = [];
    downloadsSelected.clear();
    downloadsState = LoadState.idle;
    notifyListeners();
  }

  // ---------- Дубликаты ----------

  LoadState dupState = LoadState.idle;
  String dupProgress = 'Ищу…';
  List<DupGroup> dupGroups = [];
  final Set<String> dupSelected = {};
  int? dupRecycled;
  int dupSkipped = 0;
  int _dupToken = 0;
  DupScanJob? _dupJob;

  int get dupWasted => dupGroups.fold(0, (a, g) => a + g.wasted);

  List<FileInfo> get dupSelectedFiles => [
        for (final g in dupGroups)
          for (final f in g.files)
            if (dupSelected.contains(f.path)) f
      ];
  int get dupSelectedBytes => dupSelectedFiles.fold(0, (a, f) => a + f.size);

  Future<void> loadDuplicates() async {
    final roots = userRoots.where((d) => Directory(d).existsSync()).toList();
    final token = ++_dupToken;
    _dupJob?.cancel();
    dupRecycled = null;
    dupSkipped = 0;
    dupProgress = 'Ищу…';
    dupState = LoadState.loading;
    notifyListeners();
    try {
      final throttle = ProgressThrottle();
      final job = _dupScanner(roots, (t) {
        if (token != _dupToken || !throttle.allow()) return;
        dupProgress = t;
        notifyListeners();
      });
      _dupJob = job;
      final res = await job.result;
      if (token != _dupToken) return;
      dupGroups = res;
      dupSelected
        ..clear()
        ..addAll(defaultDupSelection(res));
      dupState = LoadState.loaded;
    } catch (_) {
      if (token != _dupToken) return;
      dupState = LoadState.error;
    }
    _dupJob = null;
    notifyListeners();
  }

  void cancelDuplicates() {
    _dupToken++;
    _dupJob?.cancel();
    _dupJob = null;
    dupState = LoadState.idle;
    notifyListeners();
  }

  /// false — это последняя неотмеченная копия группы (одна копия остаётся всегда).
  bool toggleDup(DupGroup g, String path, bool on) {
    final ok = trySelectDup(g, dupSelected, path, on);
    notifyListeners();
    return ok;
  }

  /// Отмеченные копии — только в Корзину (после подтверждения в UI), с перепроверкой.
  Future<void> recycleDuplicates() async {
    final plan = planDupDelete(dupGroups, dupSelected);
    dupSkipped = plan.skipped;
    if (plan.files.isEmpty) {
      notifyListeners();
      return;
    }
    final sum = await _recycleFiles(plan.files);
    if (sum == null) {
      dupState = LoadState.error;
      notifyListeners();
      return;
    }
    dupRecycled = sum.recycledBytes;
    dupGroups = [];
    dupSelected.clear();
    dupState = LoadState.idle;
    notifyListeners();
  }

  // ---------- Пустые папки ----------

  LoadState emptyState = LoadState.idle;
  List<String> emptyDirs = [];
  final Set<String> emptySelected = {};
  int? emptyRecycled;
  int emptySkipped = 0;
  int _emptyToken = 0;
  bool emptyBusy = false;

  Future<void> loadEmptyDirs() async {
    final roots = userRoots.where((d) => Directory(d).existsSync()).toList();
    final token = ++_emptyToken;
    _emptyKill.killAll();
    emptyRecycled = null;
    emptySkipped = 0;
    emptyState = LoadState.loading;
    notifyListeners();
    try {
      final res = await _emptyDirsScan(roots);
      if (token != _emptyToken) return;
      emptyDirs = res;
      final od = env['OneDrive'];
      emptySelected
        ..clear()
        ..addAll(res.where((d) => !isInOneDrive(d, od)));
      emptyState = LoadState.loaded;
    } catch (_) {
      if (token != _emptyToken) return;
      emptyState = LoadState.error;
    }
    notifyListeners();
  }

  void cancelEmptyDirs() {
    _emptyToken++;
    _emptyKill.killAll();
    emptyState = LoadState.idle;
    notifyListeners();
  }

  void toggleEmptyDirPath(String path, bool on) {
    toggleEmptyDir(emptyDirs, emptySelected, path, on);
    notifyListeners();
  }

  void setAllEmptyDirs(bool on) {
    emptySelected.clear();
    if (on) emptySelected.addAll(emptyDirs);
    notifyListeners();
  }

  /// Отмеченные пустые папки — только в Корзину (после подтверждения в UI).
  Future<void> recycleEmptyDirs() async {
    if (emptyBusy || emptySelected.isEmpty) return;
    final lf = logFile;
    if (lf == null) {
      emptyState = LoadState.error;
      notifyListeners();
      return;
    }
    emptyBusy = true;
    notifyListeners();
    try {
      final log = CleanLog(lf);
      await log.note('Пустые папки: удаление');
      final res = await EmptyDirCleaner(
        platform: platform,
        log: log,
        userRoots: userRoots,
        guard: leftoverGuard,
      ).run(emptyDirs.where(emptySelected.contains).toList());
      emptyRecycled = res.recycled;
      emptySkipped = res.skipped;
      emptyDirs = [];
      emptySelected.clear();
      emptyState = LoadState.idle;
    } catch (_) {
      emptyState = LoadState.error;
    }
    emptyBusy = false;
    notifyListeners();
  }

  // ---------- Большие файлы ----------

  Future<void> loadBig() async {
    final dirs = userRoots.where((d) => Directory(d).existsSync()).toList();
    final token = ++_bigToken;
    _bigKill.killAll();
    bigRecycled = null;
    bigState = LoadState.loading;
    notifyListeners();
    try {
      final res = await _largeScan(dirs, 50);
      if (token != _bigToken) return;
      big = res;
      bigSelected.removeWhere((p) => !big.any((f) => f.path == p));
      bigState = LoadState.loaded;
    } catch (_) {
      if (token != _bigToken) return;
      bigState = LoadState.error;
    }
    notifyListeners();
  }

  void cancelBig() {
    _bigToken++;
    _bigKill.killAll();
    bigState = LoadState.idle;
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
    final sum = await _recycleFiles(files);
    if (sum == null) {
      bigState = LoadState.error;
      notifyListeners();
      return;
    }
    bigRecycled = sum.recycledBytes;
    big = [];
    bigSelected.clear();
    bigState = LoadState.idle;
    notifyListeners();
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
    const files = <FileInfo>[];
    if (cats.isNotEmpty) {
      // Запоминаем выбор для «Быстрой очистки» из трея.
      await _saveSettings(settings.copyWith(quickCategories: [for (final c in cats) c.id.name]));
    }
    await _runClean(categories: cats, files: files, skipBrowsers: skipBrowsers);
  }

  /// Отправляет файлы плитки в Корзину. Не трогает фазу «Быстрой очистки» и
  /// результаты других плиток. null — не удалось (нет журнала, ошибка, занято).
  Future<CleanSummary?> _recycleFiles(List<FileInfo> files) async {
    if (anyBusy) return null;
    final lf = logFile;
    if (lf == null) {
      errorMessage =
          'Некуда писать журнал: не найдены папки LOCALAPPDATA и APPDATA. Очистка не запущена.';
      return null;
    }
    tileBusy = true;
    errorMessage = null;
    notifyListeners();
    final sum = CleanSummary();
    var ok = true;
    try {
      final log = CleanLog(lf);
      await log.note('Файлы в Корзину: начато');
      await Cleaner(platform, log, systemDrive: systemDrive, systemRoot: _systemRoot, admin: adminMode)
          .run(
        categories: const [],
        filesToRecycle: files,
        userRoots: userRoots,
        skipBrowsers: false,
        into: sum,
      );
    } catch (_) {
      ok = false;
      errorMessage = 'Операция прервана из-за ошибки. Уже сделанное сохранено в журнале.';
    }
    try {
      disk = await platform.diskSpace(systemDrive) ?? disk;
    } catch (_) {}
    layer = Layer.none;
    tileBusy = false;
    if (ok) _playDrop();
    notifyListeners();
    return ok ? sum : null;
  }

  Future<void> _runClean({
    required List<Category> categories,
    required List<FileInfo> files,
    required bool skipBrowsers,
  }) async {
    if (_quickBusy || tileBusy || phase == Phase.cleaning || phase == Phase.analyzing) return;
    if (logFile == null) {
      failedAll = true;
      errorMessage =
          'Некуда писать журнал: не найдены папки LOCALAPPDATA и APPDATA. Очистка не запущена.';
      layer = Layer.none;
      phase = Phase.done;
      notifyListeners();
      return;
    }
    cleanTotalBytes = selectedBytes;
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
      final cleaner = Cleaner(platform, log,
          systemDrive: systemDrive, systemRoot: _systemRoot, admin: adminMode);
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
    layer = Layer.none;
    showDetails = false;
    phase = Phase.done;
    if (!failedAll) _playDrop();
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

  /// Переключатель «Обычные / Из Microsoft Store / Все».
  ProgramKind programKind = ProgramKind.regular;
  List<Program> storeApps = [];
  LoadState storeState = LoadState.idle;

  List<Program> get visiblePrograms => filterAndSort(
      programsOfKind(programs, storeApps, programKind), programQuery, programSort, programApprox);

  void setProgramKind(ProgramKind k) {
    programKind = k;
    notifyListeners();
    if (k != ProgramKind.regular && storeState == LoadState.idle) unawaited(loadStoreApps());
  }

  /// Список Store-приложений (PowerShell, до 30 с).
  Future<void> loadStoreApps() async {
    if (storeState == LoadState.loading) return;
    storeState = LoadState.loading;
    notifyListeners();
    try {
      final r = await platform.runPowerShell(storeListScript,
          timeout: const Duration(seconds: 30));
      if (r == null || (r.code != 0 && r.out.trim().isEmpty)) {
        storeState = LoadState.error;
      } else {
        storeApps = parseStoreApps(r.out);
        storeState = LoadState.loaded;
      }
    } catch (_) {
      storeState = LoadState.error;
    }
    notifyListeners();
  }

  Future<void> _logStore(String path, String result) async {
    final lf = logFile;
    if (lf == null) return;
    try {
      final log = CleanLog(lf);
      await log.add('Microsoft Store', path, 0, result);
      await log.flush();
    } catch (_) {}
  }

  /// Удаление Store-приложения (подтверждение — в UI). Имя пакета — через CD_PKG.
  Future<void> uninstallStore(Program p) async {
    final full = p.storeFullName;
    if (uninstallBusy || full == null || p.locked) return;
    if (!isValidPackageFullName(full)) {
      programMessage = 'Некорректное имя пакета «${p.name}». Не удаляю.';
      notifyListeners();
      return;
    }
    uninstallBusy = true;
    recheckProgram = null;
    forceOffer = null;
    programMessage = 'Удаляю «${p.name}»…';
    notifyListeners();
    String result;
    try {
      final r = await platform.runPowerShell(storeRemoveScript,
          env: {'CD_PKG': full}, timeout: const Duration(seconds: 120));
      if (r == null) {
        result = 'ошибка: не запустилось или не уложилось в 120 с';
      } else if (r.code == 0) {
        result = 'удалено';
      } else {
        final e = r.err.trim().split('\n').first.trim();
        result = 'ошибка: ${e.isEmpty ? 'код ${r.code}' : e}';
      }
    } catch (e) {
      result = 'ошибка: $e';
    }
    await _logStore(full, result);
    uninstallBusy = false;
    programMessage = result == 'удалено'
        ? '«${p.name}» удалено.'
        : 'Не удалось удалить «${p.name}» ($result).';
    notifyListeners();
    storeState = LoadState.idle;
    await loadStoreApps();
  }

  /// Ярлык на рабочий стол (обычные и Store).
  Future<void> createDesktopShortcut(Program p) async {
    String? target, args;
    var icon = '';
    if (p.isStore) {
      args = storeShortcutArgs(p);
      if (args != null) target = '$_systemRoot\\explorer.exe';
    } else {
      target = shortcutTargetOf(p, env: env.vars, fileExists: fileExists);
      if (target != null) icon = target;
    }
    if (target == null) {
      programMessage = 'Не нашёл, на что вести ярлык «${p.name}».';
      notifyListeners();
      return;
    }
    final name = shortcutFileName(p.name);
    String msg;
    try {
      final r = await platform.runPowerShell(shortcutScript,
          env: {
            'CD_NAME': name,
            'CD_TARGET': target,
            'CD_ARGS': args ?? '',
            'CD_ICON': icon,
          },
          timeout: const Duration(seconds: 30));
      msg = r != null && r.code == 0
          ? 'Ярлык «$name» создан на рабочем столе.'
          : 'Не удалось создать ярлык «$name».';
    } catch (_) {
      msg = 'Не удалось создать ярлык «$name».';
    }
    programMessage = msg;
    notifyListeners();
  }

  Future<void> openAllApps() => platform.openAllApps();

  /// Размеры программ без EstimatedSize, посчитанные по папке (keyPath → байты).
  /// Показываются как «≈ X».
  final Map<String, int> programApprox = {};
  final AsyncPool _sizePool = AsyncPool(2);
  int _sizeToken = 0;

  @visibleForTesting
  Future<void> debugStartProgramSizes() => _startProgramSizes();

  /// Кэш «папка → размер»: одна папка считается один раз.
  final Map<String, Future<int>> _folderSizeCache = {};

  /// Считает размеры папок программ без EstimatedSize в фоне (очередь, не более 2).
  Future<void> _startProgramSizes() async {
    final token = ++_sizeToken;
    programApprox.clear();
    String? steam;
    try {
      steam = await platform.steamPath();
    } catch (_) {}
    if (token != _sizeToken) return;
    final plan = planProgramSizeFolders(programs,
        env: env.vars, steamPath: steam, dirExists: dirExists, fileExists: fileExists);
    for (final prog in programs) {
      final dir = plan[prog.keyPath];
      if (dir == null) continue;
      _sizePool.run(() async {
        if (token != _sizeToken) return;
        try {
          final bytes =
              await _folderSizeCache.putIfAbsent(dir.toLowerCase(), () => _sizeOf(dir, true));
          if (token != _sizeToken || bytes <= 0) return;
          programApprox[prog.keyPath] = bytes;
          notifyListeners();
        } catch (_) {
          _folderSizeCache.remove(dir.toLowerCase());
        }
      });
    }
  }

  void setProgramQuery(String q) {
    programQuery = q;
    notifyListeners();
  }

  void setProgramSort(ProgramSort s) {
    programSort = s;
    notifyListeners();
  }

  final _storeIconCache = <String, Future<Uint8List?>>{};
  final _iconCache = <IconSource, Future<Uint8List?>>{};

  /// PNG значка программы (кэш в памяти; значок извлекается в отдельном Isolate).
  /// null — значка нет: интерфейс показывает общую иконку.
  Future<Uint8List?> programIcon(Program p) {
    if (p.isStore) {
      if (p.iconFile.isEmpty) return Future.value(null);
      return _storeIconCache.putIfAbsent(p.iconFile, () async {
        try {
          final f = File(p.iconFile);
          if (!f.existsSync() || f.lengthSync() > 2 * 1024 * 1024) return null;
          return await f.readAsBytes();
        } catch (_) {
          return null;
        }
      });
    }
    final src = iconSourceOf(p, env: env.vars, fileExists: fileExists);
    if (src == null) return Future.value(null);
    return _iconCache.putIfAbsent(src, () async {
      try {
        return await platform.programIcon(src.path, src.index);
      } catch (_) {
        return null;
      }
    });
  }

  /// Папка установки для ссылки в списке (null — не известна).
  String? installFolder(Program p) => _folderCache.putIfAbsent(
      p.keyPath,
      () => installFolderOf(p, env: env.vars, dirExists: dirExists, fileExists: fileExists));
  final _folderCache = <String, String?>{};

  Future<void> loadPrograms() async {
    if (programsState == LoadState.loading) return;
    programsState = LoadState.loading;
    _folderCache.clear();
    _folderSizeCache.clear();
    notifyListeners();
    try {
      programs = buildPrograms(await platform.readUninstallEntries());
      programsState = LoadState.loaded;
      unawaited(_startProgramSizes());
      if (programKind != ProgramKind.regular && storeState != LoadState.loading) {
        unawaited(loadStoreApps());
      }
    } catch (_) {
      programsState = LoadState.error;
    }
    notifyListeners();
  }

  /// Программа, для которой ждали удаление, но запись не исчезла (таймаут/отмена):
  /// на экране кнопка «Проверить и найти остатки».
  Program? recheckProgram;

  /// Программа без найденной программы удаления: кнопка «Принудительно удалить…».
  Program? forceOffer;

  /// true, пока ждём исчезновения записи из реестра (кнопка «Отмена»).
  bool uninstallWaiting = false;
  Completer<void>? _waitCancel;

  void cancelUninstallWait() {
    final c = _waitCancel;
    if (c != null && !c.isCompleted) c.complete();
  }

  bool _entryGone(List<Program> list, Program prog) =>
      !list.any((a) => a.keyPath.toLowerCase() == prog.keyPath.toLowerCase());

  /// Штатное удаление: запуск программы удаления, ожидание исчезновения записи
  /// (опрос реестра), затем «Остатки».
  Future<void> uninstall(Program prog) async {
    if (uninstallBusy) return;
    recheckProgram = null;
    forceOffer = null;
    final cmd = parseUninstallString(prog.uninstallString,
        env: env.vars, fileExists: fileExists);
    if (cmd == null) {
      programMessage = 'Программа удаления не найдена. Можно выбрать «Принудительно удалить…».';
      forceOffer = prog;
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
    if (!run.started) {
      uninstallBusy = false;
      programMessage = run.cancelled
          ? 'Удаление отменено (не дали права администратора).'
          : run.error == 'Программа удаления не найдена'
              ? 'Программа удаления не найдена. Можно выбрать «Принудительно удалить…».'
              : 'Не удалось запустить удаление «${prog.name}».';
      if (run.error == 'Программа удаления не найдена') forceOffer = prog;
      notifyListeners();
      return;
    }
    final code = run.exitCode;
    final codeText = code != null && code != 0 ? ' Программа удаления завершилась с кодом $code.' : '';
    final procText = run.timedOut ? ' Программа удаления не закрылась за 10 минут.' : '';

    // Ждём, пока запись исчезнет из списка (удаление могут отменить или передать другому процессу).
    uninstallWaiting = true;
    final cancel = _waitCancel = Completer<void>();
    programMessage = 'Жду завершения удаления…';
    notifyListeners();
    final deadline = DateTime.now().add(uninstallTimeout);
    var gone = false;
    var cancelled = false;
    var sawList = false;
    List<Program> after = const [];
    while (true) {
      List<Program> cur = const [];
      try {
        cur = buildPrograms(await platform.readUninstallEntries());
      } catch (_) {}
      if (cur.isNotEmpty) {
        sawList = true;
        after = cur;
        if (_entryGone(cur, prog)) {
          gone = true;
          break;
        }
      }
      if (cancel.isCompleted) {
        cancelled = true;
        break;
      }
      if (!DateTime.now().isBefore(deadline)) break;
      await Future.any<void>([Future<void>.delayed(uninstallPollInterval), cancel.future]);
      if (cancel.isCompleted) {
        cancelled = true;
        // последняя проверка перед выходом выполнится на следующем витке
      }
    }
    uninstallWaiting = false;
    _waitCancel = null;
    uninstallBusy = false;
    if (sawList) {
      programs = after;
      programsState = LoadState.loaded;
    }
    if (!gone) {
      recheckProgram = prog;
      programMessage = !sawList
          ? 'Не удалось проверить список программ. Остатки не ищу.$codeText$procText '
              'Когда удаление закончится, нажмите «Проверить и найти остатки».'
          : cancelled
              ? 'Ожидание отменено: «${prog.name}» всё ещё в списке.$codeText$procText '
                  'Когда удаление закончится, нажмите «Проверить и найти остатки».'
              : '«${prog.name}» всё ещё в списке: удаление отменено или не завершилось за '
                  '${uninstallTimeout.inMinutes} мин.$codeText$procText '
                  'Остатки не ищу. Когда удаление закончится, нажмите «Проверить и найти остатки».';
      notifyListeners();
      return;
    }
    programMessage = null;
    await startLeftovers(prog, forced: false);
    if (codeText.isNotEmpty) leftoverMessage = codeText.trim();
    notifyListeners();
  }

  /// Кнопка «Проверить и найти остатки»: запись исчезла — ищем остатки; нет — сообщение.
  Future<void> recheckAndFindLeftovers() async {
    final prog = recheckProgram;
    if (prog == null || uninstallBusy) return;
    List<Program> after = const [];
    try {
      after = buildPrograms(await platform.readUninstallEntries());
    } catch (_) {}
    if (after.isEmpty) {
      programMessage = 'Не удалось проверить список программ. Остатки не ищу.';
      notifyListeners();
      return;
    }
    programs = after;
    programsState = LoadState.loaded;
    if (!_entryGone(after, prog)) {
      programMessage = '«${prog.name}» всё ещё в списке программ. Остатки не ищу.';
      notifyListeners();
      return;
    }
    recheckProgram = null;
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
        admin: adminMode,
        otherPrograms: [
          for (final o in programs)
            if (o.keyPath.toLowerCase() != prog.keyPath.toLowerCase())
              OtherProgram(o.name, o.installLocation),
        ],
      );
      if (forced) {
        list.insert(
          0,
          Leftover(
            kind: LeftoverKind.registry,
            path: prog.keyPath,
            exact: true,
            deletable: prog.isUserHive || adminMode,
            isUninstallEntry: true,
            note: prog.isUserHive || adminMode
                ? 'Запись в списке программ'
                : 'Запись в списке программ. Нужны права администратора',
          ),
        );
      }
      leftovers = list;
      for (final l in list) {
        if (l.exact && l.deletable && l.preselect) leftoverSelected.add(l);
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
    leftoverMessage = 'Удаляю остатки…';
    notifyListeners();
    final log = CleanLog(lf);
    final cleaner = LeftoverCleaner(
      platform: platform,
      log: log,
      env: env,
      backupDir: bd,
      admin: adminMode,
      guard: leftoverGuard,
    );
    final todo = leftovers.where(leftoverSelected.contains).toList();
    try {
      final outcomes = await cleaner.run(todo, onProgress: (t) {
        leftoverMessage = t;
        notifyListeners();
      });
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

  // ---------- Настройки, автозапуск, быстрая очистка ----------

  AppSettings settings = const AppSettings();

  /// Настройки прочитаны с диска (до этого подсказки не показываем).
  bool settingsLoaded = false;

  /// Значение «ChistoDisk» есть в HKCU\…\Run (истина — реестр, не файл настроек).
  bool autostartOn = false;

  Future<void> _saveSettings(AppSettings s) async {
    settings = s;
    await _settingsStore?.save(s);
    notifyListeners();
  }

  Future<void> _syncAutostart() async {
    final v = await platform.regStringValues(autostartRunKey);
    autostartOn = v.containsKey(autostartValueName);
    if (settings.autostart != autostartOn) {
      settings = settings.copyWith(autostart: autostartOn);
    }
  }

  /// Включает/выключает запуск с Windows: пишет или удаляет только своё значение Run.
  Future<bool> setAutostart(bool on) async {
    final ok = on
        ? await platform.regWriteString(
            autostartRunKey, autostartValueName, autostartCommand(exePath))
        : await platform.regDeleteValue(autostartRunKey, autostartValueName);
    if (ok) {
      autostartOn = on;
      await _saveSettings(settings.copyWith(autostart: on));
    } else {
      notifyListeners();
    }
    return ok;
  }

  /// Режим администратора: определяется по токену процесса (не по настройке).
  bool adminMode = false;

  /// true, пока идёт перезапуск с другими правами.
  bool adminBusy = false;

  /// Переключатель можно трогать, когда ничего не очищается и не удаляется.
  bool get canToggleAdmin =>
      !adminBusy &&
      !cleanBusy &&
      !tileBusy &&
      !uninstallBusy &&
      !leftoverBusy &&
      phase != Phase.analyzing &&
      phase != Phase.cleaning;

  String get _systemRoot => env['SystemRoot'] ?? env['WINDIR'] ?? r'C:\Windows';

  /// Перезапускает программу с правами администратора ([on] true) или обычным.
  /// `started` — новый процесс запущен, текущий выходит; `cancelled` — отказ в UAC.
  Future<RelaunchResult> setAdminMode(bool on) async {
    if (!canToggleAdmin || on == adminMode) return RelaunchResult.failed;
    adminBusy = true;
    notifyListeners();
    RelaunchResult r;
    try {
      r = await platform.relaunch(elevated: on);
    } catch (_) {
      r = RelaunchResult.failed;
    }
    if (r == RelaunchResult.started) {
      // adminBusy остаётся true: интерфейс закрывается.
      final exitFn = exitApp ?? (() async => exit(0));
      await exitFn();
      return r;
    }
    adminBusy = false;
    notifyListeners();
    return r;
  }

  /// Ширина левой панели: сразу в памяти, на диск — по окончании перетаскивания.
  void previewNavWidth(double w) {
    settings = settings.copyWith(navWidth: w);
    notifyListeners();
  }

  Future<void> setNavWidth(double w) => _saveSettings(settings.copyWith(navWidth: w));

  Future<void> setMinimizeToTray(bool on) => _saveSettings(settings.copyWith(minimizeToTray: on));

  Future<void> markTrayHintShown() => _saveSettings(settings.copyWith(trayHintShown: true));

  bool _quickBusy = false;

  /// Быстрая очистка из трея: категории прошлого выбора, без Загрузок, Больших
  /// файлов и кэша запущенных браузеров; тот же Cleaner. Итог — уведомление.
  /// Возвращает текст итога (null — уже что-то делается).
  Future<String?> quickClean() async {
    if (_quickBusy || tileBusy || cleanBusy || phase == Phase.analyzing || phase == Phase.cleaning) {
      return null;
    }
    _quickBusy = true;
    quickFreedBytes = null;
    notifyListeners();
    String msg;
    try {
      if (settings.quickCategories.isEmpty) {
        msg = 'Сначала выполните обычную очистку: быстрая очистка повторяет ваш прошлый выбор.';
      } else if (logFile == null) {
        msg = 'Очистка не запущена: некуда писать журнал.';
      } else {
        final running = await platform.runningBrowsers();
        final pick = pickQuickCategories(settings.quickCategories,
            browserRunning: running.isNotEmpty);
        final steam = await platform.steamPath();
        final cats = buildCatalog(env, steamPath: steam, admin: adminMode)
            .where((c) => pick.ids.contains(c.id))
            .toList();
        final sum = CleanSummary();
        try {
          final log = CleanLog(logFile!);
          await log.note('Быстрая очистка начата');
          await Cleaner(
            platform,
            log,
            systemDrive: systemDrive,
            systemRoot: _systemRoot,
            admin: adminMode,
          ).run(
            categories: cats,
            filesToRecycle: const [],
            userRoots: userRoots,
            skipBrowsers: running.isNotEmpty,
            into: sum,
          );
        } catch (_) {
          // Уже сделанное сохранено в журнале.
        } finally {
          try {
            totalFreedEver = await _stats?.add(sum.freedBytes) ?? totalFreedEver;
          } catch (_) {}
        }
        try {
          disk = await platform.diskSpace(systemDrive) ?? disk;
        } catch (_) {}
        quickFreedBytes = sum.freedBytes;
        _playDrop();
        msg = 'Освобождено ${formatSize(sum.freedBytes)}';
        if (pick.skippedBrowsers) msg += '. Кэш браузера пропущен: браузер запущен.';
      }
    } finally {
      _quickBusy = false;
    }
    if (phase == Phase.ready) {
      // размеры в списке устарели
      phase = Phase.idle;
      rows = rows.map((r) => CategoryRow(r.category)).toList();
    }
    await platform.notify('ЧистоДиск', msg);
    notifyListeners();
    return msg;
  }

  // ---------- Автозагрузка ----------

  LoadState startupState = LoadState.idle;
  List<StartupItem> startupItems = [];

  Future<void> loadStartup() async {
    startupState = LoadState.loading;
    notifyListeners();
    try {
      startupItems = await startupService.load();
      startupState = LoadState.loaded;
    } catch (_) {
      startupState = LoadState.error;
    }
    notifyListeners();
  }

  /// Переключает запись; при неудаче состояние в списке не меняется.
  Future<bool> toggleStartup(StartupItem item, bool on) async {
    final ok = await startupService.setEnabled(item, on);
    if (ok) {
      final i = startupItems.indexWhere((e) => e.source == item.source && e.name == item.name);
      if (i >= 0) startupItems[i] = startupItems[i].copyWith(enabled: on);
    }
    notifyListeners();
    return ok;
  }
  Future<void> setCleanSound(bool on) => _saveSettings(settings.copyWith(cleanSound: on));

  // ---------- Подсказки первого запуска ----------

  /// «Понятно» / «Пропустить»: больше не показывать.
  Future<void> finishOnboarding() => _saveSettings(settings.copyWith(onboardingDone: true));

  /// «Показать подсказки снова»: открывает «Очистку» и запускает подсказки.
  Future<void> restartOnboarding() async {
    section = Section.main;
    layer = Layer.none;
    notifyListeners();
    // Ждём кадр: главный экран должен успеть показаться под подсказками.
    await WidgetsBinding.instance.endOfFrame;
    await _saveSettings(settings.copyWith(onboardingDone: false));
  }

  // ---------- Звук ----------

  String? _dataBase;

  /// Размер, который «можно освободить» в начале очистки (для счёта вниз).
  int cleanTotalBytes = 0;

  /// Сколько освободила последняя быстрая очистка (мини-окно); null — идёт/не было.
  int? quickFreedBytes;

  void _playDrop() {
    final base = _dataBase;
    if (!settings.cleanSound || base == null) return;
    final asset = [
      File(exePath).parent.path,
      'data',
      'flutter_assets',
      'assets',
      'sounds',
      'drop.wav'
    ].join(Platform.pathSeparator);
    platform.playDropSound(asset, base).catchError((Object _) {});
  }

  // ---------- Мини-окно ----------

  /// Окно сейчас в мини-режиме (360×480 у часов).
  bool miniMode = false;

  /// Меняет оконные параметры (рамка, размер, позиция); ставит TrayService.
  Future<void> Function(bool mini)? miniWindowHook;

  /// Спрятать мини-окно (Esc, потеря фокуса); ставит TrayService.
  Future<void> Function()? hideMiniHook;

  Future<void> hideMini() async {
    final h = hideMiniHook;
    if (h != null) {
      await h();
    } else {
      await setMiniMode(false);
    }
  }

  Future<void> setMiniMode(bool on) async {
    if (miniMode == on) return;
    miniMode = on;
    if (on) {
      layer = Layer.none;
      unawaited(loadLastSpeed());
    }
    notifyListeners();
    try {
      await miniWindowHook?.call(on);
    } catch (_) {}
  }

  SpeedResult? lastSpeed;
  bool speedBusy = false;

  Future<void> loadLastSpeed() async {
    final h = await speedStore?.load() ?? const <SpeedResult>[];
    lastSpeed = h.isEmpty ? lastSpeed : h.first;
    notifyListeners();
  }

  /// Короткий замер для мини-окна (пинг 4 раза, по 3 с вниз и вверх).
  Future<void> quickSpeedTest() async {
    if (speedBusy) return;
    speedBusy = true;
    notifyListeners();
    try {
      await for (final e in SpeedTester(speedNetwork,
              pingCount: 4, phaseDuration: const Duration(seconds: 3))
          .run(SpeedCancel())) {
        final r = e.result;
        if (e.phase == SpeedPhase.done && r != null) {
          lastSpeed = r;
          final old = await speedStore?.load() ?? const <SpeedResult>[];
          await speedStore?.save(addToHistory(old, r));
        }
      }
    } catch (_) {
      // нет сети — остаётся прошлый замер
    } finally {
      speedBusy = false;
      notifyListeners();
    }
  }

  Future<void> setAutoUpdate(bool on) => _saveSettings(settings.copyWith(autoUpdate: on));
  Future<void> setTransparentPanel(bool on) =>
      _saveSettings(settings.copyWith(transparentPanel: on));

  /// Проверка при запуске: если включена, прошли сутки и (в трее) выдержана [delay].
  /// Ошибки сети молча игнорируются.
  Future<void> autoCheckUpdates({Duration delay = Duration.zero}) async {
    await init();
    if (!settings.autoUpdate || !isUpdateCheckDue(settings.lastUpdateCheck, _clock())) return;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    await checkForUpdates();
  }

  /// Спрашивает сеть о новой версии. Успех (даже «новее нет») запоминается как проверка.
  Future<UpdateCheck> checkForUpdates() async {
    if (updateChecking) return UpdateCheck.error;
    updateChecking = true;
    notifyListeners();
    try {
      final info = await updateNetwork.fetchLatest();
      await _saveSettings(settings.copyWith(lastUpdateCheck: _clock()));
      if (info != null && isNewerVersion(info.version, appVersion)) {
        if (availableUpdate?.version != info.version) updateBannerHidden = false;
        availableUpdate = info;
        return UpdateCheck.available;
      }
      availableUpdate = null;
      return UpdateCheck.upToDate;
    } catch (_) {
      return UpdateCheck.error;
    } finally {
      updateChecking = false;
      notifyListeners();
    }
  }

  void hideUpdateBanner() {
    updateBannerHidden = true;
    notifyListeners();
  }

  /// Этап обновления и скачанные байты (для диалога).
  UpdateStage updateStage = UpdateStage.downloading;
  int updateReceived = 0;
  int updateTotal = 0;
  Completer<void>? _updateCancel;

  /// «Отмена» в диалоге обновления: скачивание прерывается, частичный файл удаляется.
  void cancelUpdate() {
    final c = _updateCancel;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// Качает установщик, сверяет SHA-256, запускает тихую установку и выходит.
  /// Возвращает текст ошибки, '' (отмена) или null (установщик запущен, программа закрывается).
  Future<String?> installUpdate() async {
    final info = availableUpdate;
    final dir = updateDir;
    if (info == null || dir == null) return 'Не удалось скачать обновление.';
    if (updateInstalling) return null;
    if (anyBusy ||
        downloadsState == LoadState.loading ||
        bigState == LoadState.loading ||
        dupState == LoadState.loading ||
        emptyState == LoadState.loading) {
      return 'Дождитесь окончания операции.';
    }
    final version = parseVersion(info.version)?.join('.');
    if (version == null) return 'Не удалось скачать обновление.';
    updateInstalling = true;
    updateProgress = 0;
    updateStage = UpdateStage.downloading;
    updateReceived = 0;
    updateTotal = 0;
    final cancel = _updateCancel = Completer<void>();
    notifyListeners();
    final file = File('$dir${Platform.pathSeparator}ChistoDisk-setup-$version.exe');
    void dropFile() {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }

    try {
      final text = await updateNetwork.fetchText(info.checksumUrl);
      if (text.length > maxChecksumBytes) throw const FormatException('sha256');
      final expected = parseSha256(text);
      if (expected == null) throw const FormatException('sha256');
      final digest = info.installerDigest;
      if (digest != null && digest != expected) {
        return 'Файл повреждён, попробуйте позже.';
      }
      final dl = updateNetwork.download(info.installerUrl, file, (got, total) {
        if (cancel.isCompleted) throw const _UpdateCancelled();
        updateReceived = got;
        updateTotal = total;
        updateProgress = total > 0 ? (got / total).clamp(0.0, 1.0) : null;
        notifyListeners();
      });
      final first = await Future.any<bool>([dl.then((_) => true), cancel.future.then((_) => false)]);
      if (!first) {
        // Дадим загрузке закрыть файл (она остановится на следующем куске), затем удалим.
        try {
          await dl.timeout(const Duration(seconds: 3));
        } catch (_) {}
        dropFile();
        return '';
      }
      updateStage = UpdateStage.verifying;
      updateProgress = null;
      notifyListeners();
      final size = file.lengthSync();
      if (size <= 0 || size > maxInstallerBytes) {
        dropFile();
        return 'Файл повреждён, попробуйте позже.';
      }
      final head = await file.openRead(0, 2).expand((b) => b).toList();
      final actual = (await sha256.bind(file.openRead()).first).toString();
      if (!looksLikeExe(head) || actual != expected || (digest != null && actual != digest)) {
        dropFile();
        return 'Файл повреждён, попробуйте позже.';
      }
      updateStage = UpdateStage.launching;
      notifyListeners();
      const args = ['/SP-', '/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'];
      final launch = launchInstaller ??
          ((exe, a) => Process.start(exe, a, mode: ProcessStartMode.detached).then((_) {}));
      await launch(file.path, args);
      final exitFn = exitApp ?? (() async => exit(0));
      await exitFn();
      return null;
    } catch (_) {
      dropFile();
      if (cancel.isCompleted) return '';
      return 'Не удалось скачать обновление. Проверьте интернет и попробуйте позже.';
    } finally {
      updateInstalling = false;
      updateProgress = null;
      _updateCancel = null;
      notifyListeners();
    }
  }
}

class _UpdateCancelled implements Exception {
  const _UpdateCancelled();
}

enum UpdateCheck { upToDate, available, error }
