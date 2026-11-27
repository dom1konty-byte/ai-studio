import 'package:chistka_pk/core/programs.dart';
import 'package:chistka_pk/platform/platform_api.dart';

class FakePlatform implements PlatformApi {
  final moved = <String>[];
  int moveCalls = 0;
  int diskCalls = 0;
  bool binEmptied = false;
  bool throwOnSecondDisk = false;
  List<String> browsers = [];

  /// Причины пропуска по путям (как у настоящей платформы).
  final skipReasons = <String, String>{};

  @override
  Future<Map<String, String?>> moveToRecycleBin(List<String> paths) async {
    moveCalls++;
    final res = <String, String?>{};
    for (final p in paths) {
      final r = skipReasons[p];
      res[p] = r;
      if (r == null) moved.add(p);
    }
    return res;
  }

  @override
  Future<({int bytes, int items})?> recycleBinInfo() async => (bytes: 1000, items: 2);

  @override
  Future<bool> emptyRecycleBin() async {
    binEmptied = true;
    return true;
  }

  @override
  Future<({int free, int total})?> diskSpace(String root) async {
    diskCalls++;
    if (throwOnSecondDisk && diskCalls >= 2) throw StateError('disk');
    return (free: freeBytes, total: 237 * 1024 * 1024 * 1024);
  }

  @override
  Future<List<String>> runningBrowsers() async => browsers;

  @override
  Future<String?> steamPath() async => null;

  @override
  Future<void> openFile(String path) async {}

  @override
  Future<void> openFolder(String path) async {}

  // --- программы и реестр ---
  List<RawUninstall> uninstallEntries = [];
  final regTree = <String, List<String>>{};
  final uninstallCalls = <String>[];
  UninstallRun uninstallResult = const UninstallRun(started: true, exitCode: 0);
  void Function()? onUninstall;
  bool exportOk = true;
  bool deleteOk = true;
  final exported = <String>[];
  final deleted = <String>[];
  final callOrder = <String>[];

  @override
  Future<List<RawUninstall>> readUninstallEntries() async => uninstallEntries;

  @override
  Future<List<String>> regSubKeys(String key) async => regTree[key] ?? const [];

  @override
  Future<UninstallRun> runUninstaller(String exe, String args) async {
    uninstallCalls.add('$exe|$args');
    onUninstall?.call();
    return uninstallResult;
  }

  @override
  Future<bool> exportRegKey(String key, String file) async {
    callOrder.add('export $key');
    if (exportOk) exported.add(key);
    return exportOk;
  }

  @override
  Future<bool> deleteRegKey(String key) async {
    callOrder.add('delete $key');
    if (deleteOk) deleted.add(key);
    return deleteOk;
  }

  /// Свободное место для виджет-тестов (по умолчанию 45 ГБ).
  int freeBytes = 45 * 1024 * 1024 * 1024;
}
