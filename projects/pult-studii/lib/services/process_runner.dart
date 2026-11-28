/// Абстракция запуска процессов: в тестах подменяется фейком.
class ProcResult {
  const ProcResult(this.exitCode, [this.stdout = '', this.stderr = '']);

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;
}

abstract class RunningProcess {
  /// Строки stdout (UTF-8). Подписаться можно один раз.
  Stream<String> get stdoutLines;

  /// Весь stderr (накапливается сразу).
  Future<String> get stderrText;

  /// Строки stderr по ходу (подписаться можно один раз).
  Stream<String> get stderrLines;

  Future<int> get exitCode;

  /// Убить процесс вместе с дочерними (дождаться результата).
  Future<void> kill();
}

abstract class ProcessRunner {
  /// Запустить и дождаться конца. Каждый аргумент — отдельный элемент списка.
  /// Если программа не найдена — вернуть exitCode -1 (не бросать).
  /// Дольше [timeout] — процесс убивается, exitCode 124.
  Future<ProcResult> run(String exe, List<String> args,
      {String? cwd, Duration timeout = const Duration(seconds: 120)});

  /// Запустить и читать вывод по ходу. [stdin] — текст для stdin (потом stdin закрывается).
  /// [environment] — добавки к окружению процесса.
  Future<RunningProcess> start(String exe, List<String> args,
      {String? cwd, String? stdin, Map<String, String>? environment});

  /// Полный путь к программе (на Windows предпочитаем .exe, потом .cmd/.bat).
  /// Не найдена → null (голое имя не запускаем).
  Future<String?> resolveExecutable(String name);

  /// Перечитать PATH из реестра (после установки программ).
  Future<void> refreshEnvironment();
}

/// Программа не найдена.
class ToolNotFound implements Exception {
  ToolNotFound(this.name);
  final String name;

  String get message => '$name: не найдено. Установи программу и нажми '
      '«Проверить снова» в настройках (если не помогло — перезапусти Рубку).';

  @override
  String toString() => message;
}

/// `.cmd`/`.bat` на Windows запускаются через оболочку; текст запроса
/// тогда нельзя класть в аргументы (инъекция) — отдаём его через stdin.
bool isShellScript(String exePath) {
  final l = exePath.toLowerCase();
  return l.endsWith('.cmd') || l.endsWith('.bat');
}
