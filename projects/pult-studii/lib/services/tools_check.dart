import 'app_storage.dart';
import 'process_runner.dart';

class ToolStatus {
  const ToolStatus({
    required this.id,
    required this.title,
    required this.ok,
    required this.detail,
    this.installCommand,
    this.blocking = true,
  });

  final String id;
  final String title;
  final bool ok;
  final String detail;
  final String? installCommand;

  /// false — только предупреждение, работать можно.
  final bool blocking;
}

class ToolsCheck {
  ToolsCheck(this._proc, this._storage);

  final ProcessRunner _proc;
  final AppStorage _storage;

  static const notFound = 'не найдено';

  String _firstLine(ProcResult r) {
    final t = r.stdout.trim().isNotEmpty ? r.stdout : r.stderr;
    return t.trim().split('\n').first.trim();
  }

  Future<ToolStatus> _simple(
      String id, String title, String exe, String install) async {
    final r = await _proc.run(exe, ['--version']);
    return ToolStatus(
      id: id,
      title: title,
      ok: r.ok,
      detail: r.ok ? _firstLine(r) : notFound,
      installCommand: r.ok ? null : install,
    );
  }

  Future<ToolStatus> _gh() async {
    final v = await _proc.run('gh', ['--version']);
    if (!v.ok) {
      return const ToolStatus(
          id: 'gh',
          title: 'GitHub CLI (gh)',
          ok: false,
          detail: notFound,
          installCommand: 'winget install GitHub.cli');
    }
    final a = await _proc.run('gh', ['auth', 'status']);
    return ToolStatus(
      id: 'gh',
      title: 'GitHub CLI (gh) + вход',
      ok: a.ok,
      detail: a.ok ? _firstLine(v) : 'нет входа в аккаунт GitHub',
      installCommand: a.ok ? null : 'gh auth login',
    );
  }

  /// Пробуем python, python3, py -3. Заглушка WindowsApps = не установлен.
  Future<ToolStatus> _python() async {
    const variants = [
      ['python', <String>['--version']],
      ['python3', <String>['--version']],
      ['py', <String>['-3', '--version']],
    ];
    for (final v in variants) {
      final exe = v[0] as String;
      final path = await _proc.resolveExecutable(exe);
      if (path == null || path.toLowerCase().contains('windowsapps')) continue;
      final r = await _proc.run(exe, v[1] as List<String>);
      final line = _firstLine(r);
      if (r.ok && line.toLowerCase().startsWith('python')) {
        return ToolStatus(
            id: 'python', title: 'Python', ok: true, detail: line, blocking: false);
      }
    }
    return const ToolStatus(
      id: 'python',
      title: 'Python (нужен для скриптов студии; без него Рубка работает)',
      ok: false,
      detail: 'не установлен',
      installCommand: 'winget install Python.Python.3.12',
      blocking: false,
    );
  }

  /// Claude Code + вход (`claude auth status`, если команда есть).
  Future<ToolStatus> _claude() async {
    const title = 'Claude Code (при первом запуске войди: команда claude)';
    final v = await _proc.run('claude', ['--version']);
    if (!v.ok) {
      return const ToolStatus(
          id: 'claude',
          title: title,
          ok: false,
          detail: notFound,
          installCommand: 'npm install -g @anthropic-ai/claude-code');
    }
    final a = await _proc.run('claude', ['auth', 'status']);
    if (a.ok) {
      return ToolStatus(
          id: 'claude', title: title, ok: true, detail: '${_firstLine(v)}, вход выполнен');
    }
    final text = '${a.stdout}${a.stderr}';
    final noCommand = a.exitCode < 0 ||
        RegExp(r'unknown command|unknown option|invalid|too many arguments|'
                r'not a (valid )?command|did you mean',
                caseSensitive: false)
            .hasMatch(text);
    if (noCommand) {
      return ToolStatus(
          id: 'claude',
          title: title,
          ok: true,
          detail: '${_firstLine(v)}; вход не проверен (старая версия). '
              'Если ответов нет — введи в терминале команду claude и войди.');
    }
    return const ToolStatus(
        id: 'claude',
        title: title,
        ok: false,
        detail: 'нет входа в аккаунт Claude',
        installCommand: 'claude');
  }

  Future<ToolStatus> _folder(String? path) async {
    final ok = path != null && await _storage.repoLooksValid(path);
    return ToolStatus(
      id: 'folder',
      title: 'Папка ai-studio',
      ok: ok,
      detail: ok
          ? path
          : (path == null
              ? 'не выбрана'
              : 'в $path нет .claude/agents или projects/README.md'),
    );
  }

  Future<List<ToolStatus>> check(String? repoPath) async {
    return Future.wait([
      _simple('git', 'Git', 'git', 'winget install Git.Git'),
      _simple('node', 'Node.js', 'node', 'winget install OpenJS.NodeJS.LTS'),
      _claude(),
      _gh(),
      _python(),
      _folder(repoPath),
    ]);
  }
}
