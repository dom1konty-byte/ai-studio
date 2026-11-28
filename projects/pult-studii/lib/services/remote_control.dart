import '../models/safety.dart';
import 'process_runner.dart';

/// Команда открытия терминала.
class RcLaunch {
  const RcLaunch(this.exe, this.args);

  final String exe;
  final List<String> args;
}

class RcException implements Exception {
  RcException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// «Открыть для телефона»: терминал с `claude --resume <id> --remote-control`
/// в папке проекта. Аргументы фиксированные, путь и id проверены.
class RemoteControl {
  RemoteControl(this._proc);

  final ProcessRunner _proc;

  /// Собирает команду `cmd /c start …`. Каждый аргумент — отдельный элемент.
  static RcLaunch build({
    required String dir,
    required String claudePath,
    required String? sessionId,
    String? wtPath,
  }) {
    if (!isValidSessionId(sessionId)) {
      throw RcException('Нет сессии: сначала напиши директору.');
    }
    if (!isSafeLaunchPath(dir)) {
      throw RcException(
          'Путь к папке проекта содержит недопустимые символы: $dir');
    }
    if (!isSafeLaunchPath(claudePath)) {
      throw RcException(
          'Путь к claude содержит недопустимые символы: $claudePath');
    }
    if (wtPath != null && !isSafeLaunchPath(wtPath)) {
      throw RcException('Путь к Windows Terminal содержит недопустимые символы.');
    }
    final tail = [claudePath, '--resume', sessionId!, '--remote-control'];
    return RcLaunch(sys32('cmd.exe'), [
      '/c',
      'start',
      '', // заголовок окна: без него start примет путь за заголовок
      if (wtPath != null)
        ...[wtPath, '-d', dir, ...tail]
      else
        // /k: окно остаётся открытым, если claude завершился с ошибкой.
        ...['/D', dir, sys32('cmd.exe'), '/k', ...tail],
    ]);
  }

  /// Открыть терминал. Вернёт текст ошибки или null.
  Future<String?> open({required String dir, required String? sessionId}) async {
    final claude = await _proc.resolveExecutable('claude');
    if (claude == null) return ToolNotFound('claude').message;
    final wt = await _proc.resolveExecutable('wt');
    final RcLaunch launch;
    try {
      launch = build(
          dir: dir, claudePath: claude, sessionId: sessionId, wtPath: wt);
    } on RcException catch (e) {
      return e.message;
    }
    // cwd не задаём: папку передаём через /D или wt -d.
    final r = await _proc.run(launch.exe, launch.args,
        timeout: const Duration(seconds: 20));
    if (!r.ok) {
      final t = r.stderr.trim().isNotEmpty ? r.stderr.trim() : r.stdout.trim();
      return 'Не удалось открыть терминал: '
          '${t.isEmpty ? 'код ${r.exitCode}' : t}';
    }
    return null;
  }
}
