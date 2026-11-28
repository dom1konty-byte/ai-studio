import 'dart:async';

import 'package:pult_studii/models/models.dart';
import 'package:pult_studii/services/direct_install.dart';
import 'package:pult_studii/services/app_storage.dart';
import 'package:pult_studii/services/process_runner.dart';

class FakeRunning implements RunningProcess {
  FakeRunning(this.lines, {this.code = 0, this.err = '', this.stream});

  final List<String> lines;
  final int code;
  final String err;

  /// Если задан — вывод идёт из него, а kill() закрывает его («висящий» процесс).
  final StreamController<String>? stream;
  bool killed = false;

  @override
  Stream<String> get stdoutLines => stream?.stream ?? Stream.fromIterable(lines);

  @override
  Future<String> get stderrText async => err;

  @override
  Future<int> get exitCode async => code;

  @override
  Future<void> kill() async {
    killed = true;
    stream?.close();
  }
}

typedef RunHandler = ProcResult Function(String exe, List<String> args, String? cwd);

class FakeProc implements ProcessRunner {
  FakeProc(this.handler);

  RunHandler handler;

  /// Каждый вызов run: «exe arg1 arg2».
  final calls = <String>[];

  /// Аргументы всех start().
  final started = <List<String>>[];
  final stdins = <String?>[];

  /// Что вернёт следующий start().
  final queue = <FakeRunning>[];

  String? exeName = 'claude';

  /// Если задан — start() ждёт, пока его завершат (для теста «стоп до старта»).
  Completer<void>? startGate;

  @override
  Future<ProcResult> run(String exe, List<String> args,
      {String? cwd, Duration timeout = const Duration(seconds: 120)}) async {
    calls.add([exe, ...args].join(' '));
    return handler(exe, args, cwd);
  }

  @override
  Future<RunningProcess> start(String exe, List<String> args,
      {String? cwd, String? stdin}) async {
    await startGate?.future;
    started.add([exe, ...args]);
    stdins.add(stdin);
    return queue.isNotEmpty ? queue.removeAt(0) : FakeRunning(const []);
  }

  @override
  Future<String?> resolveExecutable(String name) async =>
      name == 'claude' ? exeName : name;

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
  Future<String> fetchText(Uri url) async {
    fetched.add(url.toString());
    final t = texts[url.toString()];
    if (t == null) throw DownloadException('нет ответа');
    return t;
  }

  @override
  Future<void> download(
      Uri url, String destPath, void Function(int percent) onProgress) async {
    if (failDownload) throw DownloadException('Не удалось скачать');
    downloaded.add(url.toString());
    onProgress(50);
    onProgress(100);
  }
}
