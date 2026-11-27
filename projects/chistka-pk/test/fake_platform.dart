import 'dart:typed_data';

import 'package:chistka_pk/core/procs.dart';
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

  final openedFolders = <String>[];
  @override
  Future<void> openFolder(String path) async => openedFolders.add(path);

  // --- программы и реестр ---
  List<RawUninstall> uninstallEntries = [];
  final regTree = <String, List<String>>{};
  final uninstallCalls = <String>[];
  UninstallRun uninstallResult = const UninstallRun(started: true, exitCode: 0);
  void Function()? onUninstall;
  void Function()? onRead;
  bool exportOk = true;
  bool deleteOk = true;
  final exported = <String>[];
  final deleted = <String>[];
  final callOrder = <String>[];

  @override
  Future<List<RawUninstall>> readUninstallEntries() async {
    onRead?.call();
    return uninstallEntries;
  }

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

  // --- значения реестра: фейк по ключу (без учёта регистра) ---
  final regStrings = <String, Map<String, String>>{};
  final regBinaries = <String, Map<String, Uint8List>>{};
  final writableKeys = <String>{};
  bool allWritable = true;
  final notifications = <String>[];

  String _k(String key) => key.toLowerCase();

  @override
  Future<Map<String, String>> regStringValues(String key) async =>
      Map.of(regStrings[_k(key)] ?? const {});

  @override
  Future<Uint8List?> regReadBinary(String key, String name) async =>
      regBinaries[_k(key)]?[name];

  @override
  Future<bool> regWriteBinary(String key, String name, Uint8List data) async {
    if (!await regCanWrite(key)) return false;
    (regBinaries[_k(key)] ??= {})[name] = data;
    return true;
  }

  @override
  Future<bool> regWriteString(String key, String name, String value) async {
    if (!await regCanWrite(key)) return false;
    (regStrings[_k(key)] ??= {})[name] = value;
    return true;
  }

  @override
  Future<bool> regDeleteValue(String key, String name) async {
    if (!await regCanWrite(key)) return false;
    regStrings[_k(key)]?.remove(name);
    regBinaries[_k(key)]?.remove(name);
    return true;
  }

  @override
  Future<bool> regCanWrite(String key) async =>
      allWritable ? !key.toUpperCase().startsWith('HKLM') || writableKeys.contains(_k(key)) : false;

  @override
  Future<void> notify(String title, String text) async => notifications.add('$title|$text');

  // --- режим администратора, инструменты, значки ---
  bool elevated = false;
  RelaunchResult relaunchResult = RelaunchResult.started;
  final relaunches = <bool>[];
  final tools = <String>[];
  int? toolCode = 0;
  void Function(String call)? onTool;
  final iconCalls = <String>[];
  Uint8List? iconBytes;

  @override
  Future<bool> isElevated() async => elevated;

  @override
  Future<RelaunchResult> relaunch({required bool elevated}) async {
    relaunches.add(elevated);
    return relaunchResult;
  }

  @override
  Future<int?> runTool(String exe, List<String> args) async {
    final call = '$exe ${args.join(' ')}';
    tools.add(call);
    onTool?.call(call);
    return toolCode;
  }

  /// Вывод `sc query` (по умолчанию служба работает).
  String? toolOutput = 'SERVICE_NAME: wuauserv\n        STATE              : 4  RUNNING\n';
  final queries = <String>[];

  @override
  Future<String?> runToolOutput(String exe, List<String> args) async {
    queries.add('$exe ${args.join(' ')}');
    return toolOutput;
  }

  @override
  Future<Uint8List?> programIcon(String path, int index) async {
    iconCalls.add('$path,$index');
    return iconBytes;
  }

  /// Свободное место для виджет-тестов (по умолчанию 45 ГБ).
  int freeBytes = 45 * 1024 * 1024 * 1024;

  // --- компьютер ---
  String? utf8Output;
  final utf8Calls = <String>[];
  Duration? utf8Timeout;

  @override
  Future<String?> runToolUtf8(String exe, List<String> args, {required Duration timeout}) async {
    utf8Calls.add('$exe ${args.join(' ')}');
    utf8Timeout = timeout;
    return utf8Output;
  }

  /// Снимки подряд (последний повторяется); пусто — null.
  List<SysSample> samples = [];
  int sampleCalls = 0;

  @override
  Future<SysSample?> systemSample() async {
    if (samples.isEmpty) return null;
    final i = sampleCalls < samples.length ? sampleCalls : samples.length - 1;
    sampleCalls++;
    return samples[i];
  }

  final killed = <int>[];
  KillResult killResult = KillResult.ok;

  @override
  Future<KillResult> killProcess(int pid) async {
    killed.add(pid);
    return killResult;
  }
}
