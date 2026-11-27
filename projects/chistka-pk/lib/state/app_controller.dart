import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../core/catalog.dart';
import '../core/cleaner.dart';
import '../core/journal.dart';
import '../core/models.dart';
import '../core/scanner.dart';
import '../core/stats.dart';
import '../platform/platform_api.dart';

enum Phase { idle, analyzing, ready, cleaning, done }

enum Section { main, downloads, big }

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
typedef LargeScan = Future<List<FileInfo>> Function(List<String> dirs, int n);

Future<List<FileInfo>> _defaultDownloadsScan(String dir) {
  final now = DateTime.now();
  return Isolate.run(() => scanOldDownloadsSync(dir, now));
}

Future<List<FileInfo>> _defaultLargeScan(List<String> dirs, int n) =>
    Isolate.run(() => scanLargestSync(dirs, n));

class AppController extends ChangeNotifier {
  AppController({
    required this.platform,
    Env? env,
    DownloadsScan? downloadsScan,
    LargeScan? largeScan,
    String? dataDir,
  })  : env = env ?? Env.system(),
        _downloadsScan = downloadsScan ?? _defaultDownloadsScan,
        _largeScan = largeScan ?? _defaultLargeScan {
    final local = this.env['LOCALAPPDATA'];
    final base = dataDir ??
        (local != null ? '$local\\ChistoDisk' : '${Directory.systemTemp.path}${Platform.pathSeparator}ChistoDisk');
    logFile = File('$base${Platform.pathSeparator}log.txt');
    _stats = StatsStore(File('$base${Platform.pathSeparator}stats.json'));
    final profile = this.env['USERPROFILE'];
    if (profile != null) {
      downloadsDir = '$profile\\Downloads';
      userRoots = [
        downloadsDir!,
        '$profile\\Documents',
        '$profile\\Desktop',
        if (this.env['OneDrive'] != null) ...[
          '${this.env['OneDrive']}\\Documents',
          '${this.env['OneDrive']}\\Desktop',
        ],
      ];
    }
  }

  final PlatformApi platform;
  final Env env;
  final DownloadsScan _downloadsScan;
  final LargeScan _largeScan;
  late final File logFile;
  late final StatsStore _stats;
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

  Future<void> init() async {
    totalFreedEver = await _stats.load();
    disk = await platform.diskSpace(r'C:\');
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
    disk = await platform.diskSpace(r'C:\');
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
    phase = Phase.cleaning;
    failedAll = false;
    progressText = 'Очищаю…';
    progressFraction = 1;
    notifyListeners();
    try {
      final log = CleanLog(logFile);
      await log.note('Очистка начата');
      final cleaner = Cleaner(platform, log);
      summary = await cleaner.run(
        categories: categories,
        filesToRecycle: files,
        userRoots: userRoots,
        skipBrowsers: skipBrowsers,
        onProgress: (t, f) {
          progressText = t;
          progressFraction = f;
          notifyListeners();
        },
      );
      totalFreedEver = await _stats.add(summary!.freedBytes);
    } catch (_) {
      failedAll = true;
    }
    phase = Phase.done;
    notifyListeners();
  }

  Future<void> openLog() async {
    try {
      if (!logFile.existsSync()) {
        await logFile.parent.create(recursive: true);
        await logFile.writeAsString('Журнал ЧистоДиск пока пуст.\n');
      }
    } catch (_) {}
    await platform.openFile(logFile.path);
  }
}
