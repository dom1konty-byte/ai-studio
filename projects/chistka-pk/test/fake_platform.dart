import 'package:chistka_pk/platform/platform_api.dart';

class FakePlatform implements PlatformApi {
  final moved = <String>[];
  bool binEmptied = false;
  List<String> browsers = [];

  @override
  Future<bool> moveToRecycleBin(String path) async {
    moved.add(path);
    return true;
  }

  @override
  Future<({int bytes, int items})?> recycleBinInfo() async => (bytes: 1000, items: 2);

  @override
  Future<bool> emptyRecycleBin() async {
    binEmptied = true;
    return true;
  }

  @override
  Future<({int free, int total})?> diskSpace(String root) async =>
      (free: 45 * 1024 * 1024 * 1024, total: 237 * 1024 * 1024 * 1024);

  @override
  Future<List<String>> runningBrowsers() async => browsers;

  @override
  Future<String?> steamPath() async => null;

  @override
  Future<void> openFile(String path) async {}
}
