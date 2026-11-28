import 'app_storage.dart';
import 'process_runner.dart';

class ToolStatus {
  const ToolStatus({
    required this.id,
    required this.title,
    required this.ok,
    required this.detail,
    this.installCommand,
  });

  final String id;
  final String title;
  final bool ok;
  final String detail;
  final String? installCommand;
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

  Future<ToolStatus> _python() async {
    var r = await _proc.run('python', ['--version']);
    if (!r.ok) r = await _proc.run('python3', ['--version']);
    return ToolStatus(
      id: 'python',
      title: 'Python',
      ok: r.ok,
      detail: r.ok ? _firstLine(r) : notFound,
      installCommand: r.ok ? null : 'winget install Python.Python.3.12',
    );
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
      _simple('claude', 'Claude Code (при первом запуске войди: команда claude)',
          'claude', 'npm install -g @anthropic-ai/claude-code'),
      _gh(),
      _python(),
      _folder(repoPath),
    ]);
  }
}
