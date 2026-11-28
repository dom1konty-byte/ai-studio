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

  Future<int> get exitCode;

  /// Убить процесс вместе с дочерними.
  void kill();
}

abstract class ProcessRunner {
  /// Запустить и дождаться конца. Каждый аргумент — отдельный элемент списка.
  /// Если программа не найдена — вернуть exitCode -1 (не бросать).
  Future<ProcResult> run(String exe, List<String> args, {String? cwd});

  /// Запустить и читать вывод по ходу. [stdin] — текст для stdin (потом stdin закрывается).
  Future<RunningProcess> start(String exe, List<String> args,
      {String? cwd, String? stdin});

  /// Полный путь к программе (на Windows предпочитаем .exe, потом .cmd/.bat).
  Future<String> resolveExecutable(String name);
}

/// `.cmd`/`.bat` на Windows запускаются через оболочку; текст запроса
/// тогда нельзя класть в аргументы (инъекция) — отдаём его через stdin.
bool isShellScript(String exePath) {
  final l = exePath.toLowerCase();
  return l.endsWith('.cmd') || l.endsWith('.bat');
}
