import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pult_studii/services/app_storage.dart';
import 'package:pult_studii/services/direct_install.dart';
import 'package:pult_studii/services/process_runner.dart';
import 'package:pult_studii/services/setup_service.dart';
import 'package:pult_studii/state/wizard_controller.dart';

import 'fakes.dart';

const _folder = r'C:\Users\d\ai-studio';

const _wingetToExe = {
  'Git.Git': 'git',
  'OpenJS.NodeJS.LTS': 'node',
  'GitHub.cli': 'gh',
  'Anthropic.ClaudeCode': 'claude',
  'Python.Python.3.12': 'python',
};

/// Игрушечный компьютер: что установлено, кто вошёл, что в git config.
class Env {
  Env({Set<String>? installed})
      : installed = installed ?? {'winget'} {
    storage = MemoryStorage()..validRepos = {};
    proc = FakeProc(_handle);
  }

  final Set<String> installed;
  late final MemoryStorage storage;
  late final FakeProc proc;

  final failWinget = <String>{};
  final downloader = FakeDownloader()
    ..texts.addAll({
      'https://api.github.com/repos/git-for-windows/git/releases/latest':
          '{"assets":[{"name":"Git-2.50.0-64-bit.exe","browser_download_url":'
              '"https://github.com/git-for-windows/git/releases/download/v/Git-2.50.0-64-bit.exe"}]}',
      'https://api.github.com/repos/cli/cli/releases/latest':
          '{"assets":[{"name":"gh_2.70.0_windows_amd64.msi","browser_download_url":'
              '"https://github.com/cli/cli/releases/download/v/gh_2.70.0_windows_amd64.msi"}]}',
      'https://nodejs.org/dist/index.json':
          '[{"version":"v22.1.0","lts":"Jod","files":["win-x64-msi"]}]',
    });
  bool failDirect = false;
  bool badSignature = false;
  bool psClaudeFails = false;
  final wingetIds = <String>[];
  bool ghAuth = false;
  bool claudeAuth = false;
  bool claudeHasAuthCommand = true;
  final gitConfig = <String, String>{};

  List<String> get calls => proc.calls;

  ProcResult _handle(String exe, List<String> args, String? cwd) {
    final k = args.join(' ');
    if (args.contains('--version')) {
      if (!installed.contains(exe)) return const ProcResult(-1, '', 'нет');
      return ProcResult(0, exe == 'python' ? 'Python 3.12.1\n' : '$exe 1.0\n');
    }
    if (exe == 'winget' && args.first == 'install') {
      final id = args[2];
      wingetIds.add(id);
      if (failWinget.contains(id)) {
        return const ProcResult(1, '', 'Установка не удалась');
      }
      installed.add(_wingetToExe[id]!);
      return const ProcResult(0, 'Successfully installed');
    }
    if (exe == 'powershell') {
      if (k.contains('install.ps1')) {
        if (psClaudeFails) return const ProcResult(1, '', 'ps упал');
        installed.add('claude');
        return const ProcResult(0);
      }
      final subj = k.contains('Git-')
          ? 'CN=Johannes Schindelin'
          : k.contains('gh_')
              ? 'CN=GitHub, Inc.'
              : k.contains('node-')
                  ? 'CN=OpenJS Foundation'
                  : 'CN=Python Software Foundation';
      return ProcResult(0,
          '{"Status":${badSignature ? 2 : 0},"S":"${badSignature ? 'CN=Evil' : subj}"}');
    }
    if (exe == 'msiexec') {
      installed.add(args[1].contains('gh_') ? 'gh' : 'node');
      return const ProcResult(0);
    }
    if (exe.endsWith('.exe')) {
      installed.add(exe.contains('Git-') ? 'git' : 'python');
      return const ProcResult(0);
    }
    if (exe == 'npm' && k == 'install -g @anthropic-ai/claude-code') {
      installed.add('claude');
      return const ProcResult(0, 'added 1 package');
    }
    if (exe == 'gh' && k == 'auth status') {
      return ProcResult(ghAuth ? 0 : 1);
    }
    if (exe == 'claude' && k == 'auth status') {
      if (!claudeHasAuthCommand) {
        return const ProcResult(1, '', "error: unknown command 'auth'");
      }
      return ProcResult(claudeAuth ? 0 : 1, '', claudeAuth ? '' : 'Not logged in');
    }
    if (exe == 'gh' && k == 'api user') {
      return const ProcResult(0, '{"login":"damir-x","id":4242}');
    }
    if (exe == 'git' && args.length == 3 && args[0] == 'config') {
      final v = gitConfig[args[2]];
      return v == null ? const ProcResult(1) : ProcResult(0, '$v\n');
    }
    if (exe == 'git' && args.length == 4 && args[0] == 'config') {
      gitConfig[args[2]] = args[3];
      return const ProcResult(0);
    }
    if (exe == 'gh' && k.startsWith('repo clone ')) {
      storage.validRepos!.add(args[3]);
      return const ProcResult(0);
    }
    return const ProcResult(0);
  }

  WizardController wizard({
    String? folder = _folder,
    Future<bool> Function(String)? onFinish,
  }) =>
      WizardController(
        service: SetupService(proc, storage,
            direct: DirectInstaller(
                proc: proc,
                downloader: downloader..failDownload = failDirect,
                tempDir: '/tmp/rubka-test')),
        defaultFolder: _folder,
        initialFolder: folder,
        onFinish: onFinish ?? (_) async => true,
      );
}

void main() {
  group('проверка owner/name и пути', () {
    test('допустимые и недопустимые адреса', () {
      expect(isValidRepoSlug('dom1konty-byte/ai-studio'), isTrue);
      expect(isValidRepoSlug(' a/b.c_d-e '), isTrue);
      for (final bad in [
        '',
        'ai-studio',
        'a/b/c',
        '-a/b',
        'a/-b',
        'a/..',
        'a/.hidden',
        'a b/c',
        'a/b;rm',
        'a/b&c',
        'https://github.com/a/b',
        'a/b c',
        'a//b',
      ]) {
        expect(isValidRepoSlug(bad), isFalse, reason: bad);
      }
    });

    test('путь к папке', () {
      expect(isAcceptablePath(r'C:\Users\d\ai-studio'), isTrue);
      expect(isAcceptablePath('C:/x'), isTrue);
      expect(isAcceptablePath(''), isFalse);
      expect(isAcceptablePath('ai-studio'), isFalse);
      expect(isAcceptablePath('--upload-pack=x'), isFalse);
    });
  });

  group('шаг «Программы»', () {
    test('по умолчанию отмечены только недостающие', () async {
      final env = Env(installed: {'winget', 'git'});
      final w = env.wizard();
      await w.refresh();
      expect(w.tool('git').installed, isTrue);
      expect(w.tool('git').selected, isFalse);
      for (final id in ['node', 'gh', 'claude', 'python']) {
        expect(w.tool(id).installed, isFalse, reason: id);
        expect(w.tool(id).selected, isTrue, reason: id);
      }
      expect(w.programsDone, isFalse);
      expect(w.hasSelection, isTrue);
      // установленное нельзя отметить
      w.toggle('git', true);
      expect(w.tool('git').selected, isFalse);
      // снятая вручную галочка не возвращается при перепроверке
      w.toggle('python', false);
      await w.refresh();
      expect(w.tool('python').selected, isFalse);
    });

    test('Python необязателен', () async {
      final env = Env(installed: {'winget', 'git', 'node', 'gh', 'claude'});
      final w = env.wizard();
      await w.refresh();
      expect(w.programsDone, isTrue);
    });

    test('установка по очереди с нужными ключами', () async {
      final env = Env(installed: {'winget', 'git'});
      final w = env.wizard();
      await w.refresh();
      await w.installSelected();
      expect(env.wingetIds, [
        'OpenJS.NodeJS.LTS',
        'GitHub.cli',
        'Anthropic.ClaudeCode',
        'Python.Python.3.12',
      ]);
      expect(
          env.calls,
          contains('winget install --id GitHub.cli -e --silent '
              '--accept-source-agreements --accept-package-agreements'));
      expect(w.programsDone, isTrue);
      expect(w.tool('node').run, InstallRun.ok);
      expect(w.installMessage, 'Готово.');
      expect(w.busy, isFalse);
    });

    test('ошибка winget не останавливает остальные', () async {
      final env = Env(installed: {'winget', 'git'})
        ..failWinget.add('GitHub.cli')
        ..failDirect = true;
      final w = env.wizard();
      await w.refresh();
      await w.installSelected();
      expect(env.wingetIds.length, 4); // дошли до конца очереди
      expect(w.tool('gh').run, InstallRun.failed);
      expect(w.tool('gh').installed, isFalse);
      expect(w.tool('gh').log, contains('Установка не удалась'));
      expect(w.tool('gh').selected, isTrue); // можно нажать ещё раз
      expect(w.tool('node').installed, isTrue);
      expect(w.tool('claude').installed, isTrue);
      expect(w.installMessage, contains('GitHub CLI'));
      expect(w.programsDone, isFalse);

      env.failWinget.clear();
      await w.installSelected();
      expect(w.tool('gh').installed, isTrue);
      expect(w.programsDone, isTrue);
    });

    test('Claude: winget не вышел → npm', () async {
      final env = Env(installed: {'winget', 'git', 'node', 'gh', 'python'})
        ..failWinget.add('Anthropic.ClaudeCode')
        ..psClaudeFails = true;
      final w = env.wizard();
      await w.refresh();
      await w.installSelected();
      expect(env.calls, contains('npm install -g @anthropic-ai/claude-code'));
      expect(w.tool('claude').installed, isTrue);
      expect(w.tool('claude').run, InstallRun.ok);
      expect(w.programsDone, isTrue);
    });

    test('Claude: winget не вышел и Node.js нет → npm не зовём', () async {
      final env = Env(installed: {'winget', 'git', 'gh', 'python'})
        ..failWinget.add('Anthropic.ClaudeCode')
        ..psClaudeFails = true;
      final w = env.wizard();
      await w.refresh();
      w.toggle('node', false);
      await w.installSelected();
      expect(env.calls.any((c) => c.startsWith('npm ')), isFalse);
      expect(w.tool('claude').run, InstallRun.failed);
      expect(w.tool('claude').log, contains('Node.js'));
    });

    test('нет winget: всё ставится прямой загрузкой', () async {
      final env = Env(installed: {'git'});
      final w = env.wizard();
      await w.refresh();
      expect(w.wingetOk, isFalse);
      expect(w.hasSelection, isTrue);
      await w.installSelected();
      expect(env.wingetIds, isEmpty);
      expect(env.downloader.downloaded, [
        'https://nodejs.org/dist/v22.1.0/node-v22.1.0-x64.msi',
        'https://github.com/cli/cli/releases/download/v/gh_2.70.0_windows_amd64.msi',
        'https://www.python.org/ftp/python/$pythonDirectVersion/'
            'python-$pythonDirectVersion-amd64.exe',
      ]);
      expect(w.programsDone, isTrue);
      expect(w.tool('claude').installed, isTrue);
    });

    test('winget упал → прямая загрузка для этой программы', () async {
      final env = Env(installed: {'winget', 'git', 'node', 'claude', 'python'})
        ..failWinget.add('GitHub.cli');
      final w = env.wizard();
      await w.refresh();
      await w.installSelected();
      expect(env.wingetIds, ['GitHub.cli']);
      expect(env.downloader.downloaded.length, 1);
      expect(w.tool('gh').installed, isTrue);
    });

    test('подпись плохая → не запускаем, ошибка, Повторить', () async {
      final env = Env(installed: {'git', 'node', 'claude', 'python'})
        ..badSignature = true;
      final w = env.wizard();
      await w.refresh();
      await w.installSelected();
      expect(env.calls.any((c) => c.startsWith('msiexec')), isFalse);
      expect(w.tool('gh').run, InstallRun.failed);
      expect(w.tool('gh').log, contains('Подпись'));
      env.badSignature = false;
      await w.retry('gh');
      expect(w.tool('gh').installed, isTrue);
    });
  });

  group('входы', () {
    test('разбор кода из строк gh', () {
      expect(parseGhCode('! First copy your one-time code: AB12-CD34'),
          'AB12-CD34');
      expect(parseGhCode('Press Enter to open https://github.com/login/device'),
          isNull);
      expect(parseGhCode('abcd-1234'), isNull);
    });

    test('GitHub: код из stderr, копирование, открытие, успех', () async {
      final env = Env(installed: {'winget', 'git', 'gh'});
      env.proc.queue.add(FakeRunning(const [],
          err: '! First copy your one-time code: AB12-CD34\n'
              'Press Enter to open https://github.com/login/device in your '
              'browser...\n'));
      final copied = <String>[];
      final w = WizardController(
        service: SetupService(env.proc, env.storage),
        defaultFolder: _folder,
        initialFolder: _folder,
        onFinish: (_) async => true,
        copyText: copied.add,
      );
      await w.refresh();
      final login = w.startGhLogin(); // первая проверка входа уже сделана
      env.ghAuth = true; // «пользователь вошёл» к концу процесса
      await login;
      expect(env.proc.started.single, [
        'gh', 'auth', 'login', '--web', '--git-protocol', 'https',
        '--hostname', 'github.com', //
      ]);
      expect(env.proc.environments.single, containsPair('GH_BROWSER', isNotEmpty));
      expect(copied, ['AB12-CD34']);
      expect(
          env.calls,
          contains('rundll32 url.dll,FileProtocolHandler '
              'https://github.com/login/device'));
      expect(w.ghOk, isTrue);
      expect(w.ghDone, isTrue);
      expect(w.ghError, isEmpty);
      expect(env.calls, contains('gh auth setup-git'));
      expect(w.busy, isFalse);
      expect(w.ghLoginRunning, isFalse);
    });

    test('GitHub: код может прийти в stdout', () async {
      final env = Env(installed: {'winget', 'git', 'gh'});
      env.proc.queue.add(FakeRunning(const ['code: ZZ99-0AA1']));
      final copied = <String>[];
      final w = WizardController(
        service: SetupService(env.proc, env.storage),
        defaultFolder: _folder,
        initialFolder: _folder,
        onFinish: (_) async => true,
        copyText: copied.add,
      );
      await w.refresh();
      final f = w.startGhLogin();
      env.ghAuth = true;
      await f;
      expect(copied, ['ZZ99-0AA1']);
    });

    test('GitHub: ошибка процесса → текст и повторная попытка', () async {
      final env = Env(installed: {'winget', 'git', 'gh'});
      env.proc.queue.add(FakeRunning(const [],
          code: 1, err: '! First copy your one-time code: AB12-CD34\nexpired'));
      final w = env.wizard();
      await w.refresh();
      await w.startGhLogin();
      expect(w.ghOk, isFalse);
      expect(w.ghError, contains('Вход не удался'));
      expect(w.ghError, contains('expired'));
      expect(w.ghCode, isEmpty);
      expect(env.calls, isNot(contains('gh auth setup-git')));
      expect(w.busy, isFalse);

      env.proc.queue.add(FakeRunning(const []));
      final f = w.startGhLogin();
      env.ghAuth = true;
      await f;
      expect(w.ghError, isEmpty);
      expect(w.ghDone, isTrue);
    });

    test('GitHub: процесс завершился, а входа нет → ошибка', () async {
      final env = Env(installed: {'winget', 'git', 'gh'});
      env.proc.queue.add(FakeRunning(const []));
      final w = env.wizard();
      await w.refresh();
      await w.startGhLogin();
      expect(w.ghOk, isFalse);
      expect(w.ghError, isNotEmpty);
    });

    test('GitHub: отмена убивает процесс', () async {
      final env = Env(installed: {'winget', 'git', 'gh'});
      final gate = Completer<int>();
      final running = FakeRunning(const [],
          err: '! First copy your one-time code: AB12-CD34', exitGate: gate);
      env.proc.queue.add(running);
      final w = env.wizard();
      await w.refresh();
      final f = w.startGhLogin();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(w.ghLoginRunning, isTrue);
      expect(w.ghCode, 'AB12-CD34');
      await w.cancelGhLogin();
      await f;
      expect(running.killed, isTrue);
      expect(w.ghError, contains('отменён'));
      expect(w.ghOk, isFalse);
      expect(w.ghLoginRunning, isFalse);
      expect(w.busy, isFalse);
    });

    test('GitHub: уже вошёл → процесс не запускается, сразу готово', () async {
      final env = Env(installed: {'winget', 'git', 'gh'})..ghAuth = true;
      final w = env.wizard();
      await w.refresh();
      await w.startGhLogin();
      expect(env.proc.started, isEmpty);
      expect(w.ghDone, isTrue);
      expect(env.calls, contains('gh auth setup-git'));
    });

    test('GitHub: проверка без запуска (кнопка «Проверить»)', () async {
      final env = Env(installed: {'winget', 'git', 'gh'});
      final w = env.wizard();
      await w.refresh();
      await w.checkGh();
      expect(w.ghOk, isFalse);
      env.ghAuth = true;
      await w.checkGh();
      expect(w.ghDone, isTrue);
    });

    test('Claude: auth login, а в старой версии просто claude', () async {
      final env = Env(installed: {'winget', 'claude'});
      final w = env.wizard();
      await w.refresh();
      await w.launchClaudeLogin();
      expect(env.calls, contains('cmd /c start  claude auth login'));
      await w.checkClaude();
      expect(w.claudeDone, isFalse);
      env.claudeAuth = true;
      await w.checkClaude();
      expect(w.claudeDone, isTrue);

      final old = Env(installed: {'winget', 'claude'})
        ..claudeHasAuthCommand = false;
      final w2 = old.wizard();
      await w2.refresh();
      await w2.launchClaudeLogin();
      expect(old.calls, contains('cmd /c start  claude'));
      expect(w2.claudeMessage, contains('/login'));
    });
  });

  group('папка студии', () {
    Env ready() {
      final env = Env(installed: {'winget', 'git', 'node', 'gh', 'claude'})
        ..ghAuth = true;
      return env;
    }

    test('нет папки → скачивание', () async {
      final env = ready();
      final w = env.wizard();
      await w.refresh();
      expect(w.folderState, FolderState.needsClone);
      await w.downloadStudio();
      expect(env.calls,
          contains('gh repo clone dom1konty-byte/ai-studio $_folder'));
      expect(w.folderState, FolderState.ready);
      expect(w.folderDone, isTrue);
    });

    test('пустая существующая папка тоже подходит для скачивания', () async {
      final env = ready();
      env.storage.folderKinds[_folder] = FolderKind.empty;
      final w = env.wizard();
      await w.refresh();
      expect(w.folderState, FolderState.needsClone);
    });

    test('уже есть правильная папка → используем, не качаем', () async {
      final env = ready();
      env.storage.validRepos!.add(_folder);
      final w = env.wizard();
      await w.refresh();
      expect(w.folderState, FolderState.ready);
      await w.downloadStudio();
      expect(env.calls.any((c) => c.startsWith('gh repo clone')), isFalse);
    });

    test('чужая папка → ошибка, не качаем', () async {
      final env = ready();
      env.storage.folderKinds[_folder] = FolderKind.notEmpty;
      final w = env.wizard();
      await w.refresh();
      expect(w.folderState, FolderState.foreign);
      expect(w.folderMessage, contains('не студия'));
      await w.downloadStudio();
      expect(env.calls.any((c) => c.startsWith('gh repo clone')), isFalse);
      expect(w.folderDone, isFalse);
    });

    test('неверный адрес репозитория → не качаем', () async {
      final env = ready();
      final w = env.wizard();
      await w.refresh();
      w.setRepoSlug('плохо; адрес');
      await w.downloadStudio();
      expect(env.calls.any((c) => c.startsWith('gh repo clone')), isFalse);
      expect(w.folderMessage, contains('владелец/название'));
    });

    test('без входа в GitHub скачать нельзя', () async {
      final env = ready()..ghAuth = false;
      final w = env.wizard();
      await w.refresh();
      await w.downloadStudio();
      expect(env.calls.any((c) => c.startsWith('gh repo clone')), isFalse);
      expect(w.folderMessage, contains('GitHub'));
    });

    test('неверный путь', () async {
      final env = ready();
      final w = env.wizard();
      await w.setFolder('ai-studio');
      expect(w.folderState, FolderState.invalid);
    });

    test('пустые имя и почта в git заполняются из GitHub', () async {
      final env = ready();
      env.storage.validRepos!.add(_folder);
      final w = env.wizard();
      await w.refresh();
      expect(env.gitConfig['user.name'], 'damir-x');
      expect(env.gitConfig['user.email'], '4242+damir-x@users.noreply.github.com');
      expect(w.identityOk, isTrue);
      expect(w.folderDone, isTrue);
    });

    test('уже заданное имя не трогаем', () async {
      final env = ready();
      env.storage.validRepos!.add(_folder);
      env.gitConfig['user.name'] = 'Дамир';
      final w = env.wizard();
      await w.refresh();
      expect(env.gitConfig['user.name'], 'Дамир');
      expect(env.gitConfig['user.email'], '4242+damir-x@users.noreply.github.com');
    });

    test('без входа в GitHub имя не заполнить — шаг не готов', () async {
      final env = ready()..ghAuth = false;
      env.storage.validRepos!.add(_folder);
      final w = env.wizard();
      await w.refresh();
      expect(w.identityOk, isFalse);
      expect(w.folderDone, isFalse);
      expect(env.gitConfig, isEmpty);
    });
  });

  group('«Готово»', () {
    test('доступно только когда всё готово; зовёт onFinish с папкой', () async {
      final env = Env(installed: {'winget', 'git', 'node', 'gh', 'claude'})
        ..ghAuth = true
        ..claudeAuth = true;
      env.storage.validRepos!.add(_folder);
      String? got;
      final w = env.wizard(onFinish: (f) async {
        got = f;
        return true;
      });
      await w.refresh(pickStep: true);
      expect(w.allDone, isTrue);
      await w.finish();
      expect(got, _folder);
    });

    test('не готово — onFinish не вызывается', () async {
      final env = Env(installed: {'winget', 'git'});
      var called = false;
      final w = env.wizard(onFinish: (_) async {
        called = true;
        return true;
      });
      await w.refresh(pickStep: true);
      expect(w.allDone, isFalse);
      expect(w.step, 0);
      await w.finish();
      expect(called, isFalse);
    });
  });
}
