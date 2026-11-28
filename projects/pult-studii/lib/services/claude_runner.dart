import 'process_runner.dart';
import 'stream_json.dart';

class ClaudeTurn {
  ClaudeTurn(this.events, this.exitCode, this.stderr, this.stop);

  /// События; поток закрывается, когда процесс закончил вывод.
  final Stream<ClaudeEvent> events;
  final Future<int> exitCode;
  final Future<String> stderr;
  final void Function() stop;
}

class ClaudeRunner {
  ClaudeRunner(this._proc);

  final ProcessRunner _proc;

  static const defaultAllowedTools = [
    'Bash(git *)',
    'Bash(gh *)',
    'Bash(python *)',
    'Bash(python3 *)',
    'Bash(flutter *)',
    'Bash(dart *)',
    'Bash(npm *)',
    'Bash(node *)',
  ];

  /// Аргументы ровно по architecture.md. Каждый — отдельный элемент списка.
  /// [prompt] == null → запрос пойдёт через stdin (для claude.cmd).
  /// Флаги со списками (--disallowedTools, --allowedTools) идут в конце,
  /// чтобы не «съесть» текст запроса.
  static List<String> buildArgs({
    String? prompt,
    String? sessionId,
    required List<String> allowedTools,
  }) {
    return [
      '-p',
      if (prompt != null) prompt.startsWith('-') ? ' $prompt' : prompt,
      if (sessionId != null && sessionId.isNotEmpty) ...['--resume', sessionId],
      '--output-format',
      'stream-json',
      '--verbose',
      '--include-partial-messages',
      '--permission-mode',
      'acceptEdits',
      '--disallowedTools',
      'AskUserQuestion',
      '--allowedTools',
      ...allowedTools,
    ];
  }

  Future<ClaudeTurn> start({
    required String prompt,
    required String cwd,
    String? sessionId,
    List<String> extraTools = const [],
  }) async {
    final exe = await _proc.resolveExecutable('claude');
    final viaStdin = isShellScript(exe);
    final tools = <String>{...defaultAllowedTools, ...extraTools}.toList();
    final args = buildArgs(
      prompt: viaStdin ? null : prompt,
      sessionId: sessionId,
      allowedTools: tools,
    );
    final proc =
        await _proc.start(exe, args, cwd: cwd, stdin: viaStdin ? prompt : null);
    return ClaudeTurn(
      proc.stdoutLines.expand(parseStreamLine),
      proc.exitCode,
      proc.stderrText,
      proc.kill,
    );
  }
}

/// Понятный текст ошибки; если похоже на отсутствие входа — подсказка.
String friendlyError(String raw) {
  final t = raw.trim();
  if (RegExp(r'log ?in|authenticat|api key|credential|not logged|unauthorized|401',
          caseSensitive: false)
      .hasMatch(t)) {
    return 'Claude Code не вошёл в аккаунт. Открой терминал, введи `claude` '
        'и войди аккаунтом.\n\n$t';
  }
  if (RegExp(r'no conversation found', caseSensitive: false).hasMatch(t)) {
    return 'Прежний разговор не найден. Нажми «Новый чат» и начни заново.\n\n$t';
  }
  return t;
}
