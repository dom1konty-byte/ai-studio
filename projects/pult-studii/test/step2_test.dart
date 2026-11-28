import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pult_studii/models/models.dart';
import 'package:pult_studii/models/safety.dart';
import 'package:pult_studii/services/app_storage.dart';
import 'package:pult_studii/services/git_service.dart';
import 'package:pult_studii/services/process_runner.dart';
import 'package:pult_studii/services/remote_control.dart';
import 'package:pult_studii/state/app_controller.dart';

import 'fakes.dart';

const _main = 'C:\\ai';
final _wtAlpha = p.join(p.dirname(_main), 'ai-studio-wt', 'alpha');
final _wtBeta = p.join(p.dirname(_main), 'ai-studio-wt', 'beta');

const _sidA = '11111111-2222-3333-4444-555555555555';
const _sidB = '11111111-2222-3333-4444-666666666666';
const _sidO = '11111111-2222-3333-4444-777777777777';
const _sidG = '11111111-2222-3333-4444-888888888888';

String _init(String sid) =>
    '{"type":"system","subtype":"init","session_id":"$sid"}';
String _result(String sid) =>
    '{"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"$sid"}';

const _alpha = Project(
    name: 'Альфа',
    slug: 'alpha',
    type: 'Сайт',
    stage: 'Разработка',
    branch: 'alpha',
    branchExists: true);
const _beta = Project(
    name: 'Бета',
    slug: 'beta',
    type: 'Сайт',
    stage: 'Разработка',
    branch: 'beta',
    branchExists: true);

const _gammaReadme = '''
| Имя | Папка | Тип | Этап | Ветка | Создан |
|---|---|---|---|---|---|
| Гамма | [`gamma`](gamma/) | Сайт | Бриф | `gamma` | 2026-11-28 |
''';

/// Фейковый репозиторий: ветки, worktree, правки.
class FakeRepo {
  String mainBranch = 'ai-office';
  final locals = <String>{'ai-office'};
  final origins = <String>{'main', 'ai-office', 'alpha', 'beta'};

  /// ветка -> путь worktree
  final worktrees = <String, String>{};
  final dirty = <String>{};
  final unpushed = <String, int>{};
  final readmes = <String, String>{};
  String? addError;
  String logOut = '';
  bool fetchFails = false;

  /// Как будто Офис создал проект и запушил ветку.
  void addProject(String slug, String readme) {
    origins.add(slug);
    readmes[slug] = readme;
  }

  String? _branchAt(String? cwd) {
    if (cwd == _main) return mainBranch;
    for (final e in worktrees.entries) {
      if (cwd != null && p.equals(e.value, cwd)) return e.key;
    }
    return null;
  }

  ProcResult call(String exe, List<String> args, String? cwd) {
    final k = args.join(' ');
    if (fetchFails && k.startsWith('fetch')) {
      return const ProcResult(1, '', 'нет сети');
    }
    if (k == 'worktree list --porcelain') {
      final b = StringBuffer(
          'worktree $_main\nHEAD aaa\nbranch refs/heads/$mainBranch\n\n');
      for (final e in worktrees.entries) {
        b.write('worktree ${e.value.replaceAll('\\', '/')}\n'
            'HEAD bbb\nbranch refs/heads/${e.key}\n\n');
      }
      return ProcResult(0, b.toString());
    }
    if (k.startsWith('worktree add ')) {
      if (addError != null) return ProcResult(128, '', addError!);
      if (args[2] == '-b') {
        worktrees[args[3]] = args[4];
        locals.add(args[3]);
      } else {
        worktrees[args[3]] = args[2];
      }
      return const ProcResult(0);
    }
    if (k == 'branch --show-current') {
      return ProcResult(0, '${_branchAt(cwd) ?? ''}\n');
    }
    if (k == 'status --porcelain') {
      return ProcResult(0, dirty.contains(cwd) ? ' M file.txt\n' : '');
    }
    if (k.startsWith('rev-parse --verify --quiet refs/heads/')) {
      final b = k.split('refs/heads/').last;
      return locals.contains(b) ? const ProcResult(0, 'aaa\n') : const ProcResult(1);
    }
    if (k.startsWith('rev-parse --verify --quiet origin/')) {
      final b = k.split('origin/').last;
      return origins.contains(b)
          ? const ProcResult(0, 'fff0000\n')
          : const ProcResult(1);
    }
    if (k.startsWith('switch -c ')) {
      mainBranch = args[2];
      locals.add(args[2]);
      return const ProcResult(0);
    }
    if (k.startsWith('switch ')) {
      mainBranch = args[1];
      return const ProcResult(0);
    }
    if (k == 'rev-parse HEAD') return const ProcResult(0, 'eee0000\n');
    if (k.startsWith('rev-list --count origin/')) {
      final b = args[2].substring(7).split('..').first;
      return ProcResult(0, '${unpushed[b] ?? 0}\n');
    }
    if (k.startsWith('branch -r')) {
      return ProcResult(0, origins.map((b) => 'origin/$b').join('\n'));
    }
    if (k == 'show origin/main:projects/README.md') {
      return const ProcResult(0, sampleReadme);
    }
    if (k.startsWith('show origin/')) {
      final b = k.substring(12).split(':').first;
      final t = readmes[b];
      return t == null ? const ProcResult(128, '', 'fatal') : ProcResult(0, t);
    }
    if (k.startsWith('log ')) return ProcResult(0, logOut);
    if (k == 'remote get-url origin') return const ProcResult(1);
    if (k.startsWith('api ')) return const ProcResult(1, '', 'нет');
    return const ProcResult(0);
  }
}

(GitService, FakeProc, FakeRepo) _git([FakeRepo? repo]) {
  final r = repo ?? FakeRepo();
  final proc = FakeProc(r.call);
  final git = GitService(proc, MemoryStorage())..repoPath = _main;
  return (git, proc, r);
}

Future<void> _pump() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<(AppController, FakeProc, FakeRepo, List<String>, List<String>)> _app({
  Map<String, dynamic>? projects,
  FakeRepo? repo,
}) async {
  final r = repo ?? FakeRepo();
  final proc = FakeProc(r.call);
  final copied = <String>[];
  final toasts = <String>[];
  final app = AppController(
    proc: proc,
    storage: MemoryStorage(
        state: {'repoPath': _main, if (projects != null) 'projects': projects},
        readme: sampleReadme),
    downloadsDir: 'C:\\d',
    autoRefresh: null,
    copyText: (t) async => copied.add(t),
  );
  app.toasts.listen(toasts.add);
  await app.state.load();
  await app.git.setRepoPath(_main);
  return (app, proc, r, copied, toasts);
}

void main() {
  group('worktree', () {
    test('есть локальная ветка: worktree add <путь> <ветка>, longpaths только -c',
        () async {
      final (git, proc, repo) = _git();
      repo.locals.add('alpha');
      final res = await git.prepareProject('alpha');
      expect(res.blockedReason, isNull);
      expect(res.dir, _wtAlpha);
      expect(proc.calls, contains('git worktree add $_wtAlpha alpha'));
      await git.prepareProject('beta');
      // глобальный конфиг не трогаем, длинные пути — ключом -c на запуск
      expect(proc.calls.where((c) => c.contains('--global')), isEmpty);
      expect(proc.calls.where((c) => c.contains(' config ')), isEmpty);
      expect(proc.rawCalls,
          contains('git -c core.longpaths=true worktree add $_wtAlpha alpha'));
      // в worktree: без сети, перемотка до origin/<ветка>
      expect(proc.calls, contains('git merge --ff-only origin/alpha'));
      expect(proc.calls.where((c) => c == 'git pull --ff-only'), isEmpty);
      final i = proc.calls.indexOf('git merge --ff-only origin/alpha');
      expect(proc.cwds[i], _wtAlpha);
      expect(proc.rawCalls.where((c) => c.contains('merge --ff-only origin/alpha')).single,
          startsWith('git -c core.longpaths=true '));
    });

    test('нет локальной ветки: worktree add -b <ветка> <путь> origin/<ветка>',
        () async {
      final (git, proc, _) = _git();
      final res = await git.prepareProject('alpha');
      expect(res.blockedReason, isNull);
      expect(proc.calls,
          contains('git worktree add -b alpha $_wtAlpha origin/alpha'));
    });

    test('worktree уже есть: переиспользуем, второй не создаём', () async {
      final repo = FakeRepo()..worktrees['alpha'] = _wtAlpha;
      final (git, proc, _) = _git(repo);
      final res = await git.prepareProject('alpha');
      expect(res.dir, isNotNull);
      expect(p.equals(res.dir!, _wtAlpha), isTrue);
      await git.prepareProject('alpha');
      expect(proc.calls.where((c) => c.startsWith('git worktree add')), isEmpty);
      expect(proc.calls, contains('git worktree list --porcelain'));
    });

    test('ветки нет нигде: чат закрыт с понятным текстом', () async {
      final repo = FakeRepo()..origins.remove('alpha');
      final (git, proc, _) = _git(repo);
      final res = await git.prepareProject('alpha');
      expect(res.blockedReason, contains('нет ни на компьютере'));
      expect(proc.calls.where((c) => c.startsWith('git worktree add')), isEmpty);
    });

    test('основная папка стоит на ветке проекта: сначала освобождаем её',
        () async {
      final repo = FakeRepo(); // шаг 1: main на alpha
      repo.mainBranch = 'alpha';
      repo.locals.add('alpha');
      final (git, proc, _) = _git(repo);
      final res = await git.prepareProject('alpha');
      expect(res.blockedReason, isNull);
      final sw = proc.calls.indexOf('git switch ai-office');
      final add = proc.calls.indexOf('git worktree add $_wtAlpha alpha');
      expect(sw, greaterThanOrEqualTo(0));
      expect(add, greaterThan(sw));
    });

    test('в основной папке правки и ветка проекта: не трогаем', () async {
      final repo = FakeRepo()
        ..mainBranch = 'alpha'
        ..locals.add('alpha')
        ..dirty.add(_main);
      final (git, proc, _) = _git(repo);
      final res = await git.prepareProject('alpha');
      expect(res.blockedReason, contains('незакоммиченные'));
      expect(proc.calls.where((c) => c.startsWith('git switch')), isEmpty);
    });

    test('длинный путь: подсказка про core.longpaths', () async {
      final repo = FakeRepo()
        ..locals.add('alpha')
        ..addError = 'error: Filename too long';
      final (git, _, _) = _git(repo);
      final res = await git.prepareProject('alpha');
      expect(res.blockedReason, contains('слишком длинный'));
      expect(res.blockedReason, isNot(contains('--global')));
    });

    test('worktree add: «already exists», папка пуста → удаляем и повторяем',
        () async {
      final repo = FakeRepo()..locals.add('alpha');
      var adds = 0;
      final proc = FakeProc((exe, args, cwd) {
        if (args.join(' ').startsWith('worktree add ')) {
          adds++;
          if (adds == 1) {
            return ProcResult(128, '', "fatal: '$_wtAlpha' already exists");
          }
        }
        return repo.call(exe, args, cwd);
      });
      final storage = MemoryStorage()..folderKinds[_wtAlpha] = FolderKind.empty;
      final git = GitService(proc, storage)..repoPath = _main;
      final res = await git.prepareProject('alpha');
      expect(res.blockedReason, isNull);
      expect(adds, 2);
      expect(storage.deletedDirs, [_wtAlpha]);
    });

    test('worktree add: «already exists», папка не пуста → просим удалить',
        () async {
      final repo = FakeRepo()
        ..locals.add('alpha')
        ..addError = "fatal: '$_wtAlpha' already exists";
      final proc = FakeProc(repo.call);
      final storage = MemoryStorage()..folderKinds[_wtAlpha] = FolderKind.notEmpty;
      final git = GitService(proc, storage)..repoPath = _main;
      final res = await git.prepareProject('alpha');
      expect(res.dir, isNull);
      expect(res.blockedReason, contains('Удали папку $_wtAlpha и открой проект снова'));
      expect(storage.deletedDirs, isEmpty);
      expect(proc.calls.where((c) => c.startsWith('git worktree add')), hasLength(1));
    });

    test('merge --ff-only не удался: предупреждение, чат работает', () async {
      final repo = FakeRepo()..worktrees['alpha'] = _wtAlpha;
      final proc = FakeProc((exe, args, cwd) => args.join(' ') == 'merge --ff-only origin/alpha'
          ? const ProcResult(1, '', 'not possible to fast-forward')
          : repo.call(exe, args, cwd));
      final git = GitService(proc, MemoryStorage())..repoPath = _main;
      final res = await git.prepareProject('alpha');
      expect(res.blockedReason, isNull);
      expect(res.pulled, isFalse);
      expect(res.warning, contains('merge --ff-only'));
    });

    test('Офис работает: основную папку с ветки проекта не уводим', () async {
      final repo = FakeRepo()
        ..mainBranch = 'alpha'
        ..locals.add('alpha');
      final (git, proc, _) = _git(repo);
      git.officeBusy = () => true;
      final res = await git.prepareProject('alpha');
      expect(res.blockedReason, contains('Подожди, пока Офис закончит'));
      expect(proc.calls.where((c) => c.startsWith('git switch')), isEmpty);
      expect(proc.calls.where((c) => c.startsWith('git worktree add')), isEmpty);
    });

    test('pendingWork: ветки нет на GitHub → сравниваем с origin/main', () async {
      final repo = FakeRepo()..origins.remove('alpha');
      final (git, proc, _) = _git(repo);
      final w = await git.pendingWork(_main, 'alpha');
      expect(w.noRemoteBranch, isTrue);
      expect(w.clean, isFalse);
      expect(w.describe(), contains('ветки ещё нет на GitHub'));
      expect(proc.calls, contains('git rev-list --count origin/main..HEAD'));
    });

    test('мьютекс: путь в разном регистре — одна очередь', () async {
      final (git, _, _) = _git();
      final order = <String>[];
      final a = git.pendingWork('C:\\Ai', 'alpha').then((_) => order.add('a'));
      final b = git.pendingWork('c:\\ai', 'alpha').then((_) => order.add('b'));
      await Future.wait([a, b]);
      expect(order, ['a', 'b']);
    });

    test('небезопасный slug отклоняется без запуска git', () async {
      final (git, proc, _) = _git();
      final res = await git.prepareProject('--evil');
      expect(res.blockedReason, isNotNull);
      expect(proc.calls, isEmpty);
    });

    test('parseWorktrees читает ветки и пути с пробелами', () {
      final list = parseWorktrees('worktree C:/a b/ai\nHEAD x\nbranch refs/heads/ai-office\n\n'
          'worktree C:/wt/x\nHEAD y\ndetached\n');
      expect(list, hasLength(2));
      expect(list[0].path, 'C:/a b/ai');
      expect(list[0].branch, 'ai-office');
      expect(list[1].branch, isNull);
    });
  });

  group('офис', () {
    test('есть на origin, нет локальной: switch -c ai-office origin/ai-office',
        () async {
      final repo = FakeRepo()
        ..mainBranch = 'main'
        ..locals.clear();
      final (git, proc, _) = _git(repo);
      final res = await git.prepareOffice();
      expect(res.blockedReason, isNull);
      expect(res.dir, _main);
      expect(proc.calls, contains('git switch -c ai-office origin/ai-office'));
    });

    test('нет и на origin: от origin/main без отслеживания', () async {
      final repo = FakeRepo()
        ..mainBranch = 'main'
        ..locals.clear()
        ..origins.remove('ai-office');
      final (git, proc, _) = _git(repo);
      final res = await git.prepareOffice();
      expect(res.blockedReason, isNull);
      expect(proc.calls,
          contains('git switch -c ai-office --no-track origin/main'));
    });

    test('есть локальная: switch ai-office', () async {
      final repo = FakeRepo()..mainBranch = 'main';
      final (git, proc, _) = _git(repo);
      await git.prepareOffice();
      expect(proc.calls, contains('git switch ai-office'));
    });
  });

  group('чаты проектов', () {
    test('два проекта работают параллельно, у каждого свой процесс и сессия',
        () async {
      final (app, proc, _, _, _) = await _app();
      expect(app.select(_alpha), isNull);
      expect(app.select(_beta), isNull); // переключение не блокируется
      final a = app.chats['alpha']!;
      final b = app.chats['beta']!;
      await a.ready();
      await b.ready();
      expect(a.blockedReason, isNull);
      expect(b.blockedReason, isNull);

      final ca = StreamController<String>();
      final cb = StreamController<String>();
      proc.queue.add(FakeRunning(const [], stream: ca));
      final f1 = a.send('один');
      await _pump();
      proc.queue.add(FakeRunning(const [], stream: cb));
      final f2 = b.send('два');
      await _pump();
      expect(a.working, isTrue);
      expect(b.working, isTrue);
      expect(app.isWorking('alpha'), isTrue);
      expect(app.isWorking('beta'), isTrue);
      expect(proc.started, hasLength(2));
      expect(proc.startCwds.map((c) => p.normalize(c!)).toSet(),
          {p.normalize(_wtAlpha), p.normalize(_wtBeta)});

      // переключение во время работы тоже можно
      expect(app.select(_alpha), isNull);

      ca
        ..add(_init(_sidA))
        ..add(_result(_sidA));
      cb
        ..add(_init(_sidB))
        ..add(_result(_sidB));
      await ca.close();
      await cb.close();
      await f1;
      await f2;
      expect(app.state.sessionId('alpha'), _sidA);
      expect(app.state.sessionId('beta'), _sidB);
      expect(a.working, isFalse);
      expect(app.anyBusy, isFalse);
      app.dispose();
    });

    test('stopAll останавливает все процессы', () async {
      final (app, proc, _, _, _) = await _app();
      app.select(_alpha);
      app.select(_beta);
      await app.chats['alpha']!.ready();
      await app.chats['beta']!.ready();
      final r1 = FakeRunning(const [], stream: StreamController<String>());
      final r2 = FakeRunning(const [], stream: StreamController<String>());
      proc.queue
        ..add(r1)
        ..add(r2);
      final f1 = app.chats['alpha']!.send('а');
      final f2 = app.chats['beta']!.send('б');
      await _pump();
      await app.stopAll();
      await f1;
      await f2;
      expect(r1.killed, isTrue);
      expect(r2.killed, isTrue);
      app.dispose();
    });

    test('старая сессия шага 1 сбрасывается при переходе на worktree', () async {
      final (app, proc, _, _, _) = await _app(projects: {
        'alpha': {'sessionId': _sidA}
      });
      app.select(_alpha);
      final c = app.chats['alpha']!;
      await c.ready();
      expect(app.state.sessionId('alpha'), isNull);
      expect(c.messages.any((m) =>
              m.kind == MsgKind.note &&
              m.text == 'Новая папка — начинаю новый разговор'),
          isTrue);
      expect(app.state.worktree('alpha'), isNotNull);

      proc.queue.add(FakeRunning([_init(_sidB), _result(_sidB)]));
      await c.send('привет');
      expect(proc.started.single, isNot(contains('--resume')));
      app.dispose();
    });

    test('та же папка: сессия сохраняется', () async {
      final (app, proc, repo, _, _) = await _app();
      repo.worktrees['alpha'] = _wtAlpha;
      app.select(_alpha);
      final c = app.chats['alpha']!;
      await c.ready();
      await app.state.setSessionId('alpha', _sidA);
      // повторное открытие той же папки
      await c.open();
      expect(app.state.sessionId('alpha'), _sidA);
      proc.queue.add(FakeRunning([_init(_sidA), _result(_sidA)]));
      await c.send('дальше');
      expect(proc.started.single, containsAllInOrder(['--resume', _sidA]));
      app.dispose();
    });

    test('стартовые тексты: первое сообщение нового разговора, дальше без них',
        () async {
      final (app, proc, _, _, _) = await _app();
      app.select(_alpha);
      final c = app.chats['alpha']!;
      await c.ready();
      proc.queue
        ..add(FakeRunning([_init(_sidA), _result(_sidA)]))
        ..add(FakeRunning([_init(_sidA), _result(_sidA)]));
      await c.send('привет');
      await c.send('ещё');
      expect(proc.started[0][2],
          'Проект: Альфа (alpha). Ветка: alpha. Задача: привет');
      expect(proc.started[1][2], 'ещё');
      expect(c.messages.first.text, 'привет'); // в ленте — только текст Дамира

      await c.newChat(); // новый разговор — снова со стартовым текстом
      proc.queue.add(FakeRunning([_init(_sidB), _result(_sidB)]));
      await c.send('заново');
      expect(proc.started[2][2],
          'Проект: Альфа (alpha). Ветка: alpha. Задача: заново');

      app.openOffice();
      final o = app.chats[officeKey]!;
      await o.ready();
      await o.send('что нового');
      expect(proc.started.last[2],
          'Офис студии. Ветка: ai-office. Задача: что нового');
      expect(proc.startCwds.last, _main);
      app.dispose();
    });

    test('значок «новое N» на карточке', () async {
      final (app, _, repo, _, _) = await _app(projects: {
        'beta': {'lastSeenSha': 'abc1234'}
      });
      repo.logOut = 'aaa1111 2026-11-28 раз\nbbb2222 2026-11-28 два\n';
      await app.refreshBoard();
      expect(app.newCounts['beta'], 2);
      app.select(_beta);
      expect(app.newCounts['beta'], isNull);
      app.dispose();
    });
  });

  group('новый проект', () {
    test('Офис создаёт проект → worktree и первое сообщение с вопросом',
        () async {
      final repo = FakeRepo();
      final (app, proc, _, _, toasts) = await _app(repo: repo);
      await app.refreshBoard();
      expect(app.projects.map((p) => p.slug), ['alpha', 'beta']);

      // Офис «создаёт» проект во время хода
      proc.onStart = (i) {
        if (i == 0) repo.addProject('gamma', _gammaReadme);
      };
      proc.queue
        ..add(FakeRunning([_init(_sidO), _result(_sidO)]))
        ..add(FakeRunning([_init(_sidG), _result(_sidG)]));

      final err = await app.startNewProject(
          name: 'Гамма', type: 'site', idea: 'сайт кофейни');
      expect(err, isNull);
      expect(toasts, isEmpty);

      final office = proc.started[0].join('\n');
      expect(office, contains('Офис студии. Ветка: ai-office. Задача: '));
      expect(
          office,
          contains('Новый проект: Гамма, тип: site (Сайт). Идея: сайт кофейни. '
              'Создай через /new-project, сессию проекта не запускай — '
              'AI Studio откроет его. Потом запушь ветку gamma '
              '(git push -u origin gamma).'));
      expect(app.activeKey, 'gamma');
      expect(proc.calls.where((c) => c.startsWith('git worktree add -b gamma ')),
          hasLength(1));
      expect(
          proc.started[1][2],
          'Проект: Гамма (gamma). Ветка: gamma. Задача: Начни с этапа Бриф: '
          'задай мне 1–2 вопроса. О проекте: сайт кофейни');
      expect(proc.startCwds[1], p.join(p.dirname(_main), 'ai-studio-wt', 'gamma'));
      expect(app.state.sessionId('gamma'), _sidG);
      app.dispose();
    });

    test('доска не загрузилась: Офису ничего не отправляем', () async {
      final repo = FakeRepo()..fetchFails = true;
      final (app, proc, _, _, _) = await _app(repo: repo);
      final err = await app.startNewProject(
          name: 'Гамма', type: 'site', idea: 'сайт');
      expect(err, contains('Доска'));
      expect(proc.started, isEmpty);
      app.dispose();
    });

    test('идёт загрузка доски: ждём её и берём известные проекты из неё',
        () async {
      final repo = FakeRepo();
      final (app, proc, _, _, _) = await _app(repo: repo);
      final loading = app.refreshBoard(); // уже идёт
      proc.queue.add(FakeRunning([_init(_sidO), _result(_sidO)]));
      proc.onStart = (i) {
        // к моменту отправки доска уже загружена
        expect(app.projects.map((p) => p.slug), ['alpha', 'beta']);
        repo.addProject('gamma', _gammaReadme);
      };
      proc.queue.add(FakeRunning([_init(_sidG), _result(_sidG)]));
      final err = await app.startNewProject(
          name: 'Гамма', type: 'site', idea: 'сайт');
      await loading;
      expect(err, isNull);
      expect(app.activeKey, 'gamma');
      app.dispose();
    });

    test('проект уже есть с таким адресом: не отправляем', () async {
      final (app, proc, _, _, _) = await _app();
      final err = await app.startNewProject(
          name: 'Alpha', type: 'site', idea: 'сайт');
      expect(err, contains('уже есть'));
      expect(proc.started, isEmpty);
      app.dispose();
    });

    test('Офис упал: проект не открываем, даже если ветка появилась', () async {
      final repo = FakeRepo();
      final (app, proc, _, _, toasts) = await _app(repo: repo);
      proc.onStart = (i) => repo.addProject('gamma', _gammaReadme);
      proc.queue.add(FakeRunning(const [], code: 1, err: 'boom'));
      await app.startNewProject(name: 'Гамма', type: 'site', idea: 'сайт');
      await _pump();
      expect(proc.started, hasLength(1));
      expect(app.activeKey, officeKey);
      expect(app.chats.containsKey('gamma'), isFalse);
      expect(toasts.single, contains('не закончил'));
      app.dispose();
    });

    test('появился другой проект, не заказанный: не открываем его', () async {
      final repo = FakeRepo();
      final (app, proc, _, _, toasts) = await _app(repo: repo);
      proc.onStart = (i) => repo.addProject(
          'omega', _gammaReadme.replaceAll('gamma', 'omega').replaceAll('Гамма', 'Омега'));
      proc.queue.add(FakeRunning([_init(_sidO), _result(_sidO)]));
      await app.startNewProject(name: 'Гамма', type: 'site', idea: 'сайт');
      await _pump();
      expect(proc.started, hasLength(1));
      expect(app.activeKey, officeKey);
      expect(app.chats.containsKey('omega'), isFalse);
      expect(toasts.single, contains('«gamma»'));
      app.dispose();
    });

    test('slug как в scripts/new_project.py', () {
      expect(projectSlug('Мой сайт'), 'moy-sait');
      expect(projectSlug('Гамма'), 'gamma');
      expect(projectSlug('Кофе №1!'), 'kofe-1');
      expect(projectSlug('!!!'), '');
    });

    test('проект не появился: подсказка, второй чат не открывается', () async {
      final (app, proc, _, _, toasts) = await _app();
      await app.refreshBoard();
      proc.queue.add(FakeRunning([_init(_sidO), _result(_sidO)]));
      await app.startNewProject(name: 'Дельта', type: 'bot', idea: 'бот');
      await _pump();
      expect(proc.started, hasLength(1));
      expect(toasts.single, contains('не создал проект'));
      expect(app.activeKey, officeKey);
      app.dispose();
    });

    test('проверка полей', () async {
      final (app, proc, _, _, _) = await _app();
      expect(await app.startNewProject(name: ' ', type: 'site', idea: 'x'),
          isNotNull);
      expect(await app.startNewProject(name: 'X', type: 'zzz', idea: 'x'),
          isNotNull);
      expect(await app.startNewProject(name: 'X', type: 'site', idea: ' '),
          isNotNull);
      expect(proc.started, isEmpty);
      app.dispose();
    });
  });

  group('продолжить на телефоне', () {
    test('чисто: копируется стартовый текст и тост', () async {
      final (app, _, _, copied, toasts) = await _app();
      app.select(_alpha);
      final c = app.chats['alpha']!;
      await c.ready();
      final w = await app.continueOnPhone(c);
      await _pump();
      expect(w, isNull);
      expect(copied, [
        'Проект: Альфа (alpha). Ветка: alpha. Задача: продолжи с текущего этапа'
      ]);
      expect(toasts,
          ['Скопировано — вставь в новую сессию Claude Code на телефоне']);
      app.dispose();
    });

    test('офис: свой стартовый текст', () async {
      final (app, _, _, copied, _) = await _app();
      app.openOffice();
      final c = app.chats[officeKey]!;
      await c.ready();
      await app.continueOnPhone(c);
      expect(copied.single,
          'Офис студии. Ветка: ai-office. Задача: продолжи с текущего этапа');
      app.dispose();
    });

    test('есть правки или неотправленные коммиты: не копируем, предупреждаем',
        () async {
      final (app, proc, repo, copied, _) = await _app();
      app.select(_alpha);
      final c = app.chats['alpha']!;
      await c.ready();

      repo.dirty.add(c.workDir);
      final w1 = await app.continueOnPhone(c);
      expect(w1, isNotNull);
      expect(w1!.dirty, isTrue);
      expect(copied, isEmpty);

      repo.dirty.clear();
      repo.unpushed['alpha'] = 2;
      final w2 = await app.continueOnPhone(c);
      expect(w2!.unpushed, 2);
      expect(w2.describe(), contains('неотправленных коммитов: 2'));
      expect(copied, isEmpty);
      expect(proc.calls, contains('git rev-list --count origin/alpha..HEAD'));

      // «Скопировать всё равно»
      await app.continueOnPhone(c, force: true);
      expect(copied, hasLength(1));

      // «Отправить директору»
      proc.queue.add(FakeRunning([_init(_sidA), _result(_sidA)]));
      await c.send(commitAndPushText);
      expect(proc.started.single.join('\n'), contains('Закоммить и запушь всё'));
      app.dispose();
    });
  });

  group('Remote Control', () {
    test('аргументы: Windows Terminal и запасной вариант', () {
      final wt = RemoteControl.build(
          dir: r'C:\ai-studio-wt\alpha',
          claudePath: r'C:\Users\d\.local\bin\claude.exe',
          sessionId: _sidA,
          wtPath: r'C:\Users\d\AppData\Local\Microsoft\WindowsApps\wt.exe');
      expect(wt.exe, sys32('cmd.exe'));
      expect(wt.args, [
        '/c', 'start', '', //
        r'C:\Users\d\AppData\Local\Microsoft\WindowsApps\wt.exe', '-d',
        r'C:\ai-studio-wt\alpha', //
        r'C:\Users\d\.local\bin\claude.exe', '--resume', _sidA,
        '--remote-control',
      ]);
      final plain = RemoteControl.build(
          dir: r'C:\ai-studio-wt\alpha',
          claudePath: 'claude.exe',
          sessionId: _sidA);
      expect(plain.args, [
        '/c', 'start', '', '/D', r'C:\ai-studio-wt\alpha', //
        sys32('cmd.exe'), '/k', 'claude.exe', //
        '--resume', _sidA, '--remote-control',
      ]);
    });

    test('проверка id и путей', () {
      RcLaunch mk({String? sid = _sidA, String dir = r'C:\wt\a'}) =>
          RemoteControl.build(
              dir: dir, claudePath: 'claude.exe', sessionId: sid, wtPath: 'wt');
      expect(() => mk(sid: null), throwsA(isA<RcException>()));
      expect(() => mk(sid: 'abc; calc'), throwsA(isA<RcException>()));
      expect(() => mk(dir: r'C:\wt\a & calc'), throwsA(isA<RcException>()));
      expect(() => mk(dir: r'C:\wt\a"b'), throwsA(isA<RcException>()));
      expect(() => mk(dir: '--evil'), throwsA(isA<RcException>()));
      expect(isSafeLaunchPath(r'C:\Program Files (x86)\ai-studio'), isTrue);
      expect(isSafeLaunchPath(r'C:\a%PATH%'), isFalse);
      expect(isSafeLaunchPath(' C:\\a'), isFalse);
      expect(isSafeLaunchPath(''), isFalse);
    });

    test('открыть: терминал, блокировка чата, возврат', () async {
      final (app, proc, _, _, _) = await _app();
      proc.exeName = r'C:\Users\d\.local\bin\claude.exe';
      app.select(_alpha);
      final c = app.chats['alpha']!;
      await c.ready();

      // сессии ещё нет — кнопка неактивна
      expect(c.rcDisabledReason, isNotNull);
      expect(await c.openRemoteControl(), isNotNull);
      expect(proc.runs.where((r) => r.first == sys32('cmd.exe')), isEmpty);

      proc.queue.add(FakeRunning([_init(_sidA), _result(_sidA)]));
      await c.send('привет');
      expect(c.rcDisabledReason, isNull);

      expect(await c.openRemoteControl(), isNull);
      final run = proc.runs.lastWhere((r) => r.first == sys32('cmd.exe'));
      expect(proc.cwds.last, isNull); // cwd для start не задаём
      expect(run, [
        sys32('cmd.exe'), '/c', 'start', '', 'wt', '-d', c.workDir, //
        r'C:\Users\d\.local\bin\claude.exe', '--resume', _sidA,
        '--remote-control',
      ]);
      expect(c.rcOpen, isTrue);
      expect(c.canSend, isFalse);
      expect(app.state.rcOpen('alpha'), isTrue);

      final before = proc.started.length;
      await c.send('пока терминал открыт');
      expect(proc.started.length, before); // чат заблокирован

      proc.queue.add(FakeRunning([_init(_sidA), _result(_sidA)]));
      await c.returnFromRc();
      expect(c.rcOpen, isFalse);
      expect(c.canSend, isTrue);
      expect(app.state.rcOpen('alpha'), isFalse);
      await c.send('снова в AI Studio');
      expect(proc.started.length, before + 1);
      app.dispose();
    });

    test('нет Windows Terminal: cmd /c start "" /D <папка> …', () async {
      final (app, proc, _, _, _) = await _app();
      proc.wtAvailable = false;
      app.select(_alpha);
      final c = app.chats['alpha']!;
      await c.ready();
      proc.queue.add(FakeRunning([_init(_sidA), _result(_sidA)]));
      await c.send('привет');
      expect(await c.openRemoteControl(), isNull);
      final run = proc.runs.lastWhere((r) => r.first == sys32('cmd.exe'));
      expect(run.sublist(0, 8), [
        sys32('cmd.exe'), '/c', 'start', '', '/D', c.workDir, //
        sys32('cmd.exe'), '/k',
      ]);
      expect(run.last, '--remote-control');
      app.dispose();
    });

    test('во время хода кнопка неактивна', () async {
      final (app, proc, _, _, _) = await _app();
      app.select(_alpha);
      final c = app.chats['alpha']!;
      await c.ready();
      proc.queue.add(FakeRunning([_init(_sidA), _result(_sidA)]));
      await c.send('привет');
      final run = FakeRunning(const [], stream: StreamController<String>());
      proc.queue.add(run);
      final f = c.send('долго');
      await _pump();
      expect(c.rcDisabledReason, contains('Дождись'));
      await c.stop();
      await f;
      app.dispose();
    });
  });
}
