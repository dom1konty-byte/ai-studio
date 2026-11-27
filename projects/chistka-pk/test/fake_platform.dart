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
    return (free: 45 * 1024 * 1024 * 1024, total: 237 * 1024 * 1024 * 1024);
  }

  @override
  Future<List<String>> runningBrowsers() async => browsers;

  @override
  Future<String?> steamPath() async => null;

  @override
  Future<void> openFile(String path) async {}
}
