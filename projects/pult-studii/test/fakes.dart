import 'dart:async';

import 'package:pult_studii/models/models.dart';
import 'package:pult_studii/services/direct_install.dart';
import 'package:pult_studii/services/app_storage.dart';
import 'package:pult_studii/services/process_runner.dart';

class FakeRunning implements RunningProcess {
  FakeRunning(this.lines,
      {this.code = 0, this.err = '', this.stream, this.exitGate});

  final List<String> lines;
  final int code;
  final String err;

  /// Если задан — вывод идёт из него, а kill() закрывает его («висящий» процесс).
  final StreamController<String>? stream;
  bool killed = false;

  /// Если задан — exitCode ждёт его; kill() завершает кодом 1.
  final Completer<int>? exitGate;

  @override
  Stream<String> get stdoutLines => stream?.stream ?? Stream.fromIterable(lines);

  @override
  Future<String> get stderrText async => err;

  @override
  Stream<String> get stderrLines =>
      Stream.fromIterable(err.isEmpty ? const <String>[] : err.split('\n'));

  @override
  Future<int> get exitCode {
    final g = exitGate;
    return g != null ? g.future : Future<int>.value(code);
  }

  @override
  Future<void> kill() async {
    killed = true;
    stream?.close();
    final g = exitGate;
    if (g != null && !g.isCompleted) g.complete(1);
  }
}

typedef RunHandler = ProcResult Function(String exe, List<String> args, String? cwd);

class FakeProc implements ProcessRunner {
  FakeProc(this.handler);

  RunHandler handler;

  /// Каждый вызов run: «exe arg1 arg2».
  final calls = <String>[];

  /// cwd всех run().
  final cwds = <String?>[];

  /// [exe, ...args] всех run() (без склейки в строку).
  final runs = <List<String>>[];

  /// Как calls, но с `-c core.longpaths=true` (calls и handler его не видят).
  final rawCalls = <String>[];

  /// cwd всех start().
  final startCwds = <String?>[];

  /// Есть ли Windows Terminal (wt).
  bool wtAvailable = true;

  /// Аргументы всех start().
  final started = <List<String>>[];
  final stdins = <String?>[];
  final environments = <Map<String, String>?>[];

  /// Что вернёт следующий start().
  final queue = <FakeRunning>[];

  String? exeName = 'claude';

  /// Вызывается в start() с номером запуска (0, 1, …): «директор что-то сделал».
  void Function(int index)? onStart;

  /// Если задан — start() ждёт, пока его завершат (для теста «стоп до старта»).
  Completer<void>? startGate;

  @override
  Future<ProcResult> run(String exe, List<String> args,
      {String? cwd, Duration timeout = const Duration(seconds: 120)}) async {
    rawCalls.add([exe, ...args].join(' '));
    final a = args.length >= 2 && args[0] == '-c' && args[1] == 'core.longpaths=true'
        ? args.sublist(2)
        : args;
    calls.add([exe, ...a].join(' '));
    cwds.add(cwd);
    runs.add([exe, ...a]);
    return handler(exe, a, cwd);
  }

  @override
  Future<RunningProcess> start(String exe, List<String> args,
      {String? cwd, String? stdin, Map<String, String>? environment}) async {
    await startGate?.future;
    onStart?.call(started.length);
    started.add([exe, ...args]);
    startCwds.add(cwd);
    stdins.add(stdin);
    environments.add(environment);
    return queue.isNotEmpty ? queue.removeAt(0) : FakeRunning(const []);
  }

  @override
  Future<String?> resolveExecutable(String name) async =>
      name == 'claude' ? exeName : (name == 'wt' && !wtAvailable ? null : name);

  @override
  Future<void> refreshEnvironment() async {}
}

class MemoryStorage implements AppStorage {
  MemoryStorage({Map<String, dynamic>? state, this.readme = ''})
      : state = state ?? {};

  Map<String, dynamic> state;
  String readme;
  final chats = <String, List<ChatMessage>>{};

  /// Если задан — «студией» считаются только эти пути.
  Set<String>? validRepos;

  /// Что лежит по пути (нет записи — папки нет).
  final folderKinds = <String, FolderKind>{};

  @override
  Future<Map<String, dynamic>> loadState() async => state;

  @override
  Future<void> saveState(Map<String, dynamic> s) async => state = s;

  @override
  Future<List<ChatMessage>> loadChat(String slug) async =>
      List.of(chats[slug] ?? const []);

  @override
  Future<void> appendChat(String slug, ChatMessage m) async =>
      (chats[slug] ??= []).add(m);

  @override
  Future<String?> readText(String path) async =>
      path.endsWith('README.md') ? readme : null;

  @override
  Future<bool> repoLooksValid(String path) async =>
      validRepos?.contains(path) ?? path.isNotEmpty;

  @override
  Future<FolderKind> folderKind(String path) async =>
      folderKinds[path] ?? FolderKind.missing;

  /// Удалённые пустые папки.
  final deletedDirs = <String>[];

  @override
  Future<bool> deleteEmptyDir(String path) async {
    if (folderKinds[path] == FolderKind.notEmpty) return false;
    folderKinds.remove(path);
    deletedDirs.add(path);
    return true;
  }
}

const sampleReadme = '''
# Проекты студии

| Имя | Папка | Тип | Этап | Ветка | Создан |
|---|---|---|---|---|---|
| Альфа | [`alpha`](alpha/) | Сайт | Дизайн ✅ ждёт «да» | `alpha` | 2026-11-01 |
| Бета | [`beta`](beta/) | Программа Windows | Разработка | `beta` | 2026-11-02 |
''';

/// Фейковый загрузчик: тексты по адресу, список «скачанного».
class FakeDownloader implements Downloader {
  final texts = <String, String>{};
  final fetched = <String>[];
  final downloaded = <String>[];
  final progress = <int>[];
  bool failDownload = false;

  @override
  Future<String> fetchText(Uri url, DownloadRule rule) async {
    fetched.add(url.toString());
    final t = texts[url.toString()];
    if (t == null) throw DownloadException('нет ответа');
    return t;
  }

  @override
  Future<void> download(Uri url, String destPath, DownloadRule rule,
      void Function(int percent) onProgress) async {
    if (failDownload) throw DownloadException('Не удалось скачать');
    downloaded.add(url.toString());
    onProgress(50);
    onProgress(100);
  }
}

class _FakeHeld implements HeldFile {
  _FakeHeld(this._fs, this._path);
  final FakeInstallFs _fs;
  final String _path;

  @override
  Future<String> sha256() async => _fs.hashes[_path] ?? _fs.defaultHash;

  @override
  Future<void> close() async => _fs.closed.add(_path);
}

/// Файлы установки без диска: хэш задаётся тестом.
class FakeInstallFs implements InstallFs {
  FakeInstallFs([this.root = '/tmp/rubka-test']);

  final String root;
  static const okHash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  String defaultHash = okHash;
  final hashes = <String, String>{};
  final opened = <String>[];
  final closed = <String>[];
  final deletedDirs = <String>[];
  final createdDirs = <String>[];
  var _n = 0;

  @override
  Future<String> createTempDir() async {
    final d = '$root/rubka-${_n++}';
    createdDirs.add(d);
    return d;
  }

  @override
  Future<HeldFile> open(String path) async {
    opened.add(path);
    return _FakeHeld(this, path);
  }

  @override
  Future<void> deleteDir(String dir) async => deletedDirs.add(dir);
}
