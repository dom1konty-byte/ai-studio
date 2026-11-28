import 'dart:convert';

import 'app_storage.dart';
import 'process_runner.dart';

/// Репозиторий студии по умолчанию.
const defaultRepoSlug = 'dom1konty-byte/ai-studio';

/// Страница «Установщик приложений» (winget) в Microsoft Store.
const wingetStoreUrl = 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1';

final _slugRe =
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_][A-Za-z0-9._-]{0,99}$');

/// owner/name: только безопасные символы, имя не начинается с «-» и «.».
bool isValidRepoSlug(String s) => _slugRe.hasMatch(s.trim());

/// Путь к папке: полный (C:\\… или /…) и не похож на ключ командной строки.
bool isAcceptablePath(String s) {
  final t = s.trim();
  if (t.isEmpty || t.startsWith('-') || t.contains('\n') || t.contains('\r')) {
    return false;
  }
  return RegExp(r'^([A-Za-z]:[\\/]|/|\\\\)').hasMatch(t);
}

class ToolSpec {
  const ToolSpec({
    required this.id,
    required this.title,
    required this.hint,
    required this.wingetId,
    required this.exe,
    this.mandatory = true,
  });

  final String id;
  final String title;
  final String hint;
  final String wingetId;

  /// Команда для проверки `--version`.
  final String exe;
  final bool mandatory;
}

/// Порядок важен: Node.js раньше Claude Code (запасной путь через npm).
const toolSpecs = [
  ToolSpec(
      id: 'git',
      title: 'Git',
      hint: 'хранит версии файлов студии',
      wingetId: 'Git.Git',
      exe: 'git'),
  ToolSpec(
      id: 'node',
      title: 'Node.js',
      hint: 'нужен для работы помощника',
      wingetId: 'OpenJS.NodeJS.LTS',
      exe: 'node'),
  ToolSpec(
      id: 'gh',
      title: 'GitHub CLI',
      hint: 'связь с GitHub',
      wingetId: 'GitHub.cli',
      exe: 'gh'),
  ToolSpec(
      id: 'claude',
      title: 'Claude Code',
      hint: 'помощник-директор студии',
      wingetId: 'Anthropic.ClaudeCode',
      exe: 'claude'),
  ToolSpec(
      id: 'python',
      title: 'Python 3.12',
      hint: 'для скриптов студии (можно без него)',
      wingetId: 'Python.Python.3.12',
      exe: 'python',
      mandatory: false),
];

enum LoginState { yes, no, unknown }

enum FolderState { invalid, ready, needsClone, foreign }

/// Последние строки вывода без «крутилок» winget.
String shortLog(ProcResult r) {
  final lines = '${r.stdout}\n${r.stderr}'
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => RegExp(r'[A-Za-zА-Яа-я0-9]{3}').hasMatch(l))
      .toList();
  final tail = lines.length > 3 ? lines.sublist(lines.length - 3) : lines;
  var s = tail.join('\n');
  if (s.length > 300) s = s.substring(s.length - 300);
  return s;
}

/// Путь можно безопасно дать `cmd /c start`.
bool _safeForCmd(String path) => !RegExp(r'[&|<>^%!"\r\n]').hasMatch(path);

class LaunchResult {
  const LaunchResult({this.error, this.plain = false});

  /// Текст ошибки (null — окно открыто).
  final String? error;

  /// Запущена просто `claude` (без `auth login`).
  final bool plain;
}

/// Установка и вход: все команды с фиксированными аргументами.
class SetupService {
  SetupService(this._proc, this._storage);

  final ProcessRunner _proc;
  final AppStorage _storage;

  Future<void> refreshEnvironment() => _proc.refreshEnvironment();

  Future<bool> hasWinget() async => (await _proc.run('winget', ['--version'])).ok;

  Future<bool> isInstalled(String id) async {
    if (id == 'python') return _python();
    final spec = toolSpecs.firstWhere((t) => t.id == id);
    return (await _proc.run(spec.exe, ['--version'])).ok;
  }

  /// Заглушка WindowsApps — не настоящий Python.
  Future<bool> _python() async {
    const variants = [
      ['python', '--version'],
      ['python3', '--version'],
      ['py', '-3', '--version'],
    ];
    for (final v in variants) {
      final path = await _proc.resolveExecutable(v[0]);
      if (path == null || path.toLowerCase().contains('windowsapps')) continue;
      final r = await _proc.run(v[0], v.sublist(1));
      final line = '${r.stdout}${r.stderr}'.trim().toLowerCase();
      if (r.ok && line.startsWith('python')) return true;
    }
    return false;
  }

  Future<ProcResult> wingetInstall(ToolSpec t) => _proc.run(
      'winget',
      [
        'install',
        '--id',
        t.wingetId,
        '-e',
        '--silent',
        '--accept-source-agreements',
        '--accept-package-agreements',
      ],
      timeout: const Duration(minutes: 20));

  Future<ProcResult> npmInstallClaude() => _proc.run(
      'npm', ['install', '-g', '@anthropic-ai/claude-code'],
      timeout: const Duration(minutes: 10));

  Future<void> openWingetStore() =>
      _proc.run('rundll32', ['url.dll,FileProtocolHandler', wingetStoreUrl]);

  // ---------- GitHub ----------

  Future<bool> ghAuthOk() async => (await _proc.run('gh', ['auth', 'status'])).ok;

  Future<LaunchResult> launchGhLogin() async {
    final exe = await _proc.resolveExecutable('gh');
    if (exe == null) return const LaunchResult(error: 'GitHub CLI не найден.');
    return _startConsole(exe, const [
      'auth',
      'login',
      '--web',
      '--git-protocol',
      'https',
      '--hostname',
      'github.com',
    ]);
  }

  Future<ProcResult> ghSetupGit() => _proc.run('gh', ['auth', 'setup-git']);

  // ---------- Claude ----------

  Future<LoginState> claudeLogin() async {
    final a = await _proc.run('claude', ['auth', 'status']);
    if (a.ok) return LoginState.yes;
    final text = '${a.stdout}${a.stderr}';
    final noCommand = a.exitCode < 0 ||
        RegExp(
                r'unknown command|unknown option|invalid|too many arguments|'
                r'not a (valid )?command|did you mean',
                caseSensitive: false)
            .hasMatch(text);
    return noCommand ? LoginState.unknown : LoginState.no;
  }

  Future<LaunchResult> launchClaudeLogin() async {
    final exe = await _proc.resolveExecutable('claude');
    if (exe == null) return const LaunchResult(error: 'Claude Code не найден.');
    final plain = await claudeLogin() == LoginState.unknown;
    final r = await _startConsole(exe, plain ? const [] : const ['auth', 'login']);
    return LaunchResult(error: r.error, plain: plain);
  }

  /// Отдельное окно консоли: `cmd.exe /c start "" <exe> <args>`.
  Future<LaunchResult> _startConsole(String exe, List<String> args) async {
    if (!_safeForCmd(exe)) {
      return const LaunchResult(
          error: 'В пути к программе есть странные символы — окно не открыто.');
    }
    final r = await _proc.run('cmd', ['/c', 'start', '', exe, ...args],
        timeout: const Duration(seconds: 30));
    return r.ok
        ? const LaunchResult()
        : LaunchResult(error: 'Не удалось открыть окно: ${shortLog(r)}');
  }

  // ---------- Папка студии ----------

  Future<FolderState> inspectFolder(String path) async {
    if (!isAcceptablePath(path)) return FolderState.invalid;
    final t = path.trim();
    if (await _storage.repoLooksValid(t)) return FolderState.ready;
    final k = await _storage.folderKind(t);
    return k == FolderKind.notEmpty ? FolderState.foreign : FolderState.needsClone;
  }

  /// `gh repo clone owner/name путь`. Вернёт текст ошибки или null.
  Future<String?> cloneStudio(String slug, String path) async {
    if (!isValidRepoSlug(slug)) {
      return 'Адрес студии должен быть вида владелец/название.';
    }
    if (await inspectFolder(path) != FolderState.needsClone) {
      return 'В эту папку скачать нельзя: она занята или путь неверный.';
    }
    final r = await _proc.run('gh', ['repo', 'clone', slug.trim(), path.trim()],
        timeout: const Duration(minutes: 15));
    if (!r.ok) {
      final log = shortLog(r);
      return 'Не удалось скачать${log.isEmpty ? '' : ': $log'}';
    }
    if (await inspectFolder(path) != FolderState.ready) {
      return 'Скачалось, но это не похоже на папку студии. '
          'Проверь адрес студии.';
    }
    return null;
  }

  // ---------- Имя и почта для Git ----------

  Future<String> _gitGlobal(String key) async {
    final r = await _proc.run('git', ['config', '--global', key]);
    return r.ok ? r.stdout.trim() : '';
  }

  Future<bool> hasGitIdentity() async =>
      (await _gitGlobal('user.name')).isNotEmpty &&
      (await _gitGlobal('user.email')).isNotEmpty;

  /// Заполнить пустые user.name / user.email из GitHub. Вернёт ошибку или null.
  Future<String?> ensureGitIdentity() async {
    final needName = (await _gitGlobal('user.name')).isEmpty;
    final needEmail = (await _gitGlobal('user.email')).isEmpty;
    if (!needName && !needEmail) return null;
    final api = await _proc.run('gh', ['api', 'user']);
    if (!api.ok) {
      return 'Не удалось узнать имя на GitHub. Проверь вход в GitHub.';
    }
    String login;
    int id;
    try {
      final j = jsonDecode(api.stdout);
      login = (j as Map)['login'] as String;
      id = (j['id'] as num).toInt();
    } catch (_) {
      return 'GitHub ответил непонятно. Попробуй ещё раз.';
    }
    if (!RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$').hasMatch(login)) {
      return 'GitHub вернул странное имя.';
    }
    if (needName) {
      final r = await _proc.run('git', ['config', '--global', 'user.name', login]);
      if (!r.ok) return 'Не удалось записать имя в Git.';
    }
    if (needEmail) {
      final r = await _proc.run('git',
          ['config', '--global', 'user.email', '$id+$login@users.noreply.github.com']);
      if (!r.ok) return 'Не удалось записать почту в Git.';
    }
    return null;
  }
}
