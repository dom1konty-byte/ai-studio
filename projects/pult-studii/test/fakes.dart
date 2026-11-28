import 'dart:async';

import 'package:pult_studii/models/models.dart';
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
  void kill() {
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

  String exeName = 'claude';

  @override
  Future<ProcResult> run(String exe, List<String> args, {String? cwd}) async {
    calls.add([exe, ...args].join(' '));
    return handler(exe, args, cwd);
  }

  @override
  Future<RunningProcess> start(String exe, List<String> args,
      {String? cwd, String? stdin}) async {
    started.add([exe, ...args]);
    stdins.add(stdin);
    return queue.isNotEmpty ? queue.removeAt(0) : FakeRunning(const []);
  }

  @override
  Future<String> resolveExecutable(String name) async =>
      name == 'claude' ? exeName : name;
}

class MemoryStorage implements AppStorage {
  MemoryStorage({Map<String, dynamic>? state, this.readme = ''})
      : state = state ?? {};

  Map<String, dynamic> state;
  String readme;
  final chats = <String, List<ChatMessage>>{};

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
  Future<bool> repoLooksValid(String path) async => path.isNotEmpty;
}

const sampleReadme = '''
# Проекты студии

| Имя | Папка | Тип | Этап | Ветка | Создан |
|---|---|---|---|---|---|
| Альфа | [`alpha`](alpha/) | Сайт | Дизайн ✅ ждёт «да» | `alpha` | 2026-11-01 |
| Бета | [`beta`](beta/) | Программа Windows | Разработка | `beta` | 2026-11-02 |
''';
