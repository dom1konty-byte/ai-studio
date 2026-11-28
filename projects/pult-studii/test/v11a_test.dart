import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pult_studii/models/models.dart';
import 'package:pult_studii/services/git_service.dart';
import 'package:pult_studii/services/notifications.dart';
import 'package:pult_studii/services/process_runner.dart';
import 'package:pult_studii/services/rate_limit.dart';
import 'package:pult_studii/services/stream_json.dart';
import 'package:pult_studii/services/temp_cleanup.dart';
import 'package:pult_studii/services/updater.dart';
import 'package:pult_studii/services/usage.dart';
import 'package:pult_studii/state/app_controller.dart';

import 'fakes.dart';

const _main = 'C:\\ai';
const _sidO = '11111111-2222-3333-4444-777777777777';

final _now = DateTime(2026, 11, 28, 12, 0);
const _repoName = 'dom/ai-studio';

int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

String _runs(List<Map<String, Object?>> runs) =>
    jsonEncode({'workflow_runs': runs});

Map<String, Object?> _run(int id, int number, String branch,
        {String event = 'push',
        String conclusion = 'success',
        String repo = 'dom/ai-studio'}) =>
    {
      'id': id,
      'run_number': number,
      'head_branch': branch,
      'event': event,
      'status': 'completed',
      'conclusion': conclusion,
      'head_repository': {'full_name': repo},
    };

class FakeNotifier implements AppNotifier {
  final shown = <String>[];
  final keys = <String>[];
  void Function(String key)? click;

  @override
  Future<void> init(void Function(String key) onClick) async => click = onClick;

  @override
  Future<void> show(
      {required String title, required String body, required String key}) async {
    expect(title, 'AI Studio');
    shown.add(body);
    keys.add(key);
  }
}

Future<void> _pump() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Окружение: доска из одного проекта «Альфа», сборки, чат Офиса, обновления.
class _Env {
  String alphaStage = 'Дизайн';
  String runJson = '{"workflow_runs":[]}';
  String updateJson = '{"workflow_runs":[]}';
  bool failNewArtifact = false;
  String? tempDir;

  String readme() => '| Имя | Папка | Тип | Этап | Ветка | Создан |\n'
      '|---|---|---|---|---|---|\n'
      '| Альфа | [`alpha`](alpha/) | Сайт | $alphaStage | `alpha` | 2026-11-01 |\n';

  ProcResult call(String exe, List<String> args, String? cwd) {
    final k = args.join(' ');
    if (k == 'remote get-url origin') {
      return const ProcResult(0, 'https://github.com/dom/ai-studio.git\n');
    }
    if (k.startsWith('branch -r')) {
      return const ProcResult(0, 'origin/main\norigin/alpha\n');
    }
    if (k.startsWith('show origin/')) return ProcResult(0, readme());
    if (k == 'branch --show-current') return const ProcResult(0, 'ai-office\n');
    if (k.startsWith('rev-parse --verify --quiet')) {
      return const ProcResult(0, 'fff0000\n');
    }
    if (k == 'rev-parse HEAD') return const ProcResult(0, 'eee0000\n');
    if (k.startsWith('rev-list --count')) return const ProcResult(0, '0\n');
    if (k == 'worktree list --porcelain') {
      return const ProcResult(
          0, 'worktree $_main\nHEAD aaa\nbranch refs/heads/ai-office\n\n');
    }
    if (exe == 'gh' && args.first == 'api') {
      if (k.contains('/workflows/pult-studii.yml/runs')) {
        return ProcResult(0, updateJson);
      }
      if (k.contains('/workflows/alpha.yml/runs')) return ProcResult(0, runJson);
      return const ProcResult(1, '', 'Not Found (HTTP 404)');
    }
    if (exe == 'gh' && args.first == 'run') {
      final name = args[args.indexOf('-n') + 1];
      final dir = args[args.indexOf('-D') + 1];
      if (name == 'AI-Studio-setup' && failNewArtifact) {
        return const ProcResult(1, '', 'no artifact');
      }
      final sub = Directory(p.join(dir, 'x'))..createSync(recursive: true);
      File(p.join(sub.path, '$name.exe')).writeAsStringSync('MZ');
      File(p.join(dir, 'readme.txt')).writeAsStringSync('hi');
      return const ProcResult(0);
    }
    return const ProcResult(0);
  }
}

Future<(AppController, FakeProc, FakeNotifier, MemoryStorage)> _app(
  _Env env, {
  bool focused = false,
  int build = 5,
  Future<void> Function()? quit,
  List<String>? windowLog,
}) async {
  final proc = FakeProc(env.call);
  final storage = MemoryStorage(state: {'repoPath': _main});
  final notifier = FakeNotifier();
  final app = AppController(
    proc: proc,
    storage: storage,
    downloadsDir: 'C:\\d',
    autoRefresh: null,
    updateEvery: null,
    build: build,
    updater: UpdateService(proc, makeTempDir: () async {
      final d = Directory.systemTemp.createTempSync('ai-studio-test-');
      env.tempDir = d.path;
      addTearDown(() {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      });
      return d.path;
    }),
    notifier: notifier,
    isWindowFocused: () async => focused,
    showWindow: () async => windowLog?.add('show'),
    quitApp: quit,
  );
  await app.state.load();
  await app.git.setRepoPath(_main);
  await notifier.init(app.openFromNotification);
  addTearDown(app.dispose);
  return (app, proc, notifier, storage);
}

void main() {
  group('переименование', () {
    test('тексты без «Рубка», везде «AI Studio»', () {
      expect(notifyTitle, 'AI Studio');
      expect(ToolNotFound('x').message, contains('AI Studio'));
      expect(ToolNotFound('x').message, isNot(contains('Рубк')));
      const d = PermissionDenial(toolName: 'Edit', input: {});
      expect(d.decision.refusal, contains('AI Studio'));
      expect(d.decision.refusal, isNot(contains('Рубк')));
      expect(setupArtifacts, ['AI-Studio-setup', 'Rubka-setup']);
    });

    test('установщик: имя, AppId прежний', () {
      final iss = File('installer/setup.iss').readAsStringSync();
      expect(iss, contains('AppName=AI Studio'));
      expect(iss, contains('OutputBaseFilename=AI-Studio-setup'));
      expect(iss, contains('3F7A9C52-8D14-4B6E-9A31-5C2E7B0D4F68'));
      expect(iss, contains(r'DefaultDirName={localappdata}\Programs\AI Studio'));
      expect(iss, isNot(contains('UsePreviousAppDir=no')));
      expect(iss, contains('SetupIconFile='));
      expect(iss, contains('Check: WizardSilent'));
    });
  });

  group('выбор обновления', () {
    test('берёт самый свежий успешный только на main', () {
      final json = _runs([
        _run(1, 10, 'pult-studii'),
        _run(2, 12, 'main'),
        _run(3, 13, 'pult-studii'),
        _run(4, 11, 'main'),
      ]);
      final u = pickUpdate(json, 5, _repoName)!;
      expect(u.runId, 2);
      expect(u.runNumber, 12);
      expect(u.branch, 'main');
    });

    test('номер не больше текущего — обновления нет', () {
      final json = _runs([_run(1, 10, 'main')]);
      expect(pickUpdate(json, 10, _repoName), isNull);
      expect(pickUpdate(json, 11, _repoName), isNull);
      expect(pickUpdate(json, 9, _repoName)!.runNumber, 10);
    });

    test('0 = dev-сборка: не предлагаем', () {
      expect(pickUpdate(_runs([_run(1, 10, 'main')]), 0, _repoName), isNull);
    });

    test('чужие ветки, события и неуспешные запуски пропускаем', () {
      final json = _runs([
        _run(1, 20, 'feature'),
        _run(2, 21, 'main', event: 'pull_request'),
        _run(3, 22, 'main', conclusion: 'failure'),
        _run(4, 13, 'main', event: 'workflow_dispatch'),
        _run(5, 30, 'main', repo: 'evil/ai-studio'),
        _run(6, 31, 'pult-studii'),
      ]);
      expect(pickUpdate(json, 5, _repoName)!.runId, 4);
    });

    test('мусор в ответе — null', () {
      expect(pickUpdate('не json', 1, _repoName), isNull);
      expect(pickUpdate('{"workflow_runs":"x"}', 1, _repoName), isNull);
      expect(pickUpdate('{"workflow_runs":[1,{"id":"a"}]}', 1, _repoName), isNull);
    });

    test('buildNumber по умолчанию 0 (dev)', () {
      expect(buildNumber, 0);
    });
  });

  group('обновление: безопасность', () {
    test('ошибка скачивания удаляет временную папку', () async {
      final d = Directory.systemTemp.createTempSync('ai-studio-test-');
      addTearDown(() {
        if (d.existsSync()) d.deleteSync(recursive: true);
      });
      final s = UpdateService(
          FakeProc((e, a, c) => const ProcResult(1, '', 'нет')),
          makeTempDir: () async => d.path);
      await expectLater(
          s.download(const RepoRemote('dom', 'ai-studio'),
              const UpdateInfo(runId: 1, runNumber: 9, branch: 'main')),
          throwsA(isA<UpdateException>()));
      expect(d.existsSync(), isFalse);
    });

    test('install: файла нет — ошибка, процесс не запускается', () async {
      final proc = FakeProc((e, a, c) => const ProcResult(0));
      final s = UpdateService(proc);
      await expectLater(s.install(p.join(Directory.systemTemp.path, 'нет-такого.exe')),
          throwsA(isA<UpdateException>()));
      expect(proc.detached, isEmpty);
    });

    test('старые ai-studio-update-* чистятся, свежие и чужие — нет', () async {
      final root = Directory.systemTemp.createTempSync('v11a-clean-');
      addTearDown(() => root.deleteSync(recursive: true));
      final upd = Directory(p.join(root.path, 'ai-studio-update-abc'))..createSync();
      final other = Directory(p.join(root.path, 'other-dir'))..createSync();
      await cleanOldTempDirs('ai-studio-update-', root: root); // свежая — остаётся
      expect(upd.existsSync(), isTrue);
      await UpdateService.cleanOld(
          root: root, now: DateTime.now().add(const Duration(hours: 2)));
      expect(upd.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
    });
  });

  group('расходы: мусор в файле', () {
    test('NaN, бесконечность, минус и огромные числа — 0', () {
      final t = UsageTotals.fromJson({
        'cost': double.nan,
        'in': -5,
        'out': double.infinity,
        'cr': 2e12,
        'cc': 7,
        'n': 1,
      });
      expect(t.cost, 0);
      expect(t.input, 0);
      expect(t.output, 0);
      expect(t.cacheRead, 0);
      expect(t.cacheCreate, 7);
      expect(t.turns, 1);
      expect(UsageTotals.fromJson({'cost': 1e13}).cost, 0);
      expect(UsageTotals.fromJson({'cost': 2.5}).cost, 2.5);
    });
  });

  group('поиск установщика', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ai-studio-find-'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('находит *setup*.exe, в том числе во вложенной папке', () async {
      Directory(p.join(dir.path, 'a', 'b')).createSync(recursive: true);
      File(p.join(dir.path, 'a', 'b', 'AI-Studio-setup.exe'))
          .writeAsStringSync('MZ');
      File(p.join(dir.path, 'other.exe')).writeAsStringSync('MZ');
      File(p.join(dir.path, 'notes.txt')).writeAsStringSync('x');
      final found = await findSetupExe(dir.path);
      expect(found, p.join(dir.path, 'a', 'b', 'AI-Studio-setup.exe'));
      expect(p.isWithin(dir.path, found!), isTrue);
    });

    test('нет установщика или нет папки — null', () async {
      File(p.join(dir.path, 'other.exe')).writeAsStringSync('MZ');
      expect(await findSetupExe(dir.path), isNull);
      expect(await findSetupExe(p.join(dir.path, 'нет')), isNull);
    });
  });

  group('обновление: сервис и контроллер', () {
    test('check: gh api с нужным адресом; ошибка gh — null', () async {
      final env = _Env()..updateJson = _runs([_run(1, 9, 'main')]);
      final proc = FakeProc(env.call);
      final s = UpdateService(proc);
      final u = await s.check(const RepoRemote('dom', 'ai-studio'), 5);
      expect(u!.runNumber, 9);
      expect(
          proc.calls.single,
          'gh api repos/dom/ai-studio/actions/workflows/pult-studii.yml/runs'
          '?branch=main&status=success&per_page=5&exclude_pull_requests=true');
      final bad = UpdateService(FakeProc((e, a, c) => const ProcResult(1)));
      expect(await bad.check(const RepoRemote('dom', 'ai-studio'), 5), isNull);
      expect(await s.check(const RepoRemote('dom', 'ai-studio'), 0), isNull);
    });

    test('Обновить: скачать, тихо поставить отдельным процессом, закрыться',
        () async {
      final env = _Env()..updateJson = _runs([_run(77, 9, 'main')]);
      var quit = 0;
      final (app, proc, _, _) = await _app(env, quit: () async => quit++);
      await app.checkUpdate();
      expect(app.update!.runId, 77);
      expect(app.updateVisible, isTrue);

      await app.applyUpdate();
      final dl = proc.runs.firstWhere((r) => r.length > 1 && r[1] == 'run');
      expect(dl.sublist(1, 8),
          ['run', 'download', '77', '-R', 'dom/ai-studio', '-n', 'AI-Studio-setup']);
      expect(dl[dl.indexOf('-D') + 1], env.tempDir);
      expect(proc.detached.single, [
        p.join(env.tempDir!, 'x', 'AI-Studio-setup.exe'),
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
      ]);
      expect(quit, 1);
      expect(app.updateStatus, UpdateStatus.installing);
    });

    test('нет нового артефакта — пробуем Rubka-setup', () async {
      final env = _Env()
        ..updateJson = _runs([_run(77, 9, 'main')])
        ..failNewArtifact = true;
      final (app, proc, _, _) = await _app(env, quit: () async {});
      await app.checkUpdate();
      await app.applyUpdate();
      expect(proc.detached.single.first,
          p.join(env.tempDir!, 'x', 'Rubka-setup.exe'));
    });

    test('ошибка скачивания: плашка с ошибкой, программа не закрывается',
        () async {
      final env = _Env()..updateJson = _runs([_run(77, 9, 'main')]);
      var quit = 0;
      final proc = FakeProc((e, a, c) =>
          a.first == 'run' ? const ProcResult(1, '', 'boom') : env.call(e, a, c));
      final app = AppController(
        proc: proc,
        storage: MemoryStorage(state: {'repoPath': _main}),
        downloadsDir: 'C:\\d',
        autoRefresh: null,
        updateEvery: null,
        build: 5,
        updater: UpdateService(proc,
            makeTempDir: () async => Directory.systemTemp.path),
        quitApp: () async => quit++,
      );
      addTearDown(app.dispose);
      await app.state.load();
      await app.git.setRepoPath(_main);
      await app.checkUpdate();
      await app.applyUpdate();
      expect(app.updateStatus, UpdateStatus.error);
      expect(app.updateError, contains('boom'));
      expect(proc.detached, isEmpty);
      expect(quit, 0);
      app.dismissUpdate();
      expect(app.updateVisible, isFalse);
    });

    test('dev-сборка (0): gh не спрашиваем, плашки нет', () async {
      final env = _Env()..updateJson = _runs([_run(77, 9, 'main')]);
      final (app, proc, _, _) = await _app(env, build: 0);
      await app.checkUpdate();
      expect(app.update, isNull);
      expect(app.updateVisible, isFalse);
      expect(proc.calls.where((c) => c.startsWith('gh api')), isEmpty);
    });

    test('не новее — плашки нет', () async {
      final env = _Env()..updateJson = _runs([_run(77, 5, 'main')]);
      final (app, _, _, _) = await _app(env);
      await app.checkUpdate();
      expect(app.updateVisible, isFalse);
    });
  });

  group('расходы', () {
    test('результат хода: стоимость и токены', () {
      final e = parseStreamLine('{"type":"result","subtype":"success",'
              '"is_error":false,"result":"ok","total_cost_usd":0.25,'
              '"usage":{"input_tokens":10,"output_tokens":20,'
              '"cache_read_input_tokens":30,"cache_creation_input_tokens":40}}')
          .single as ResultEvent;
      expect(e.usage!.cost, 0.25);
      expect(e.usage!.input, 10);
      expect(e.usage!.output, 20);
      expect(e.usage!.cacheRead, 30);
      expect(e.usage!.cacheCreate, 40);
      final none = parseStreamLine('{"type":"result","subtype":"success",'
              '"is_error":false,"result":"ok"}')
          .single as ResultEvent;
      expect(none.usage, isNull);
    });

    test('агрегация по дням: сегодня / 7 дней / всего', () {
      final data = <String, Map<String, UsageTotals>>{
        'alpha': {
          '2026-11-28': UsageTotals(cost: 1, input: 10, turns: 1),
          '2026-11-22': UsageTotals(cost: 2, output: 20, turns: 2), // 6 дней назад
          '2026-11-21': UsageTotals(cost: 4, cacheRead: 40, turns: 1), // 7 дней назад
        },
        'ai-office': {
          '2026-11-28': UsageTotals(cost: 0.5, cacheCreate: 5, turns: 1),
        },
      };
      final s = summarizeUsage(data, _now);
      final a = s.rows['alpha']!;
      expect(a.today.cost, 1);
      expect(a.week.cost, 3);
      expect(a.all.cost, 7);
      expect(a.all.tokens, 70);
      expect(a.all.turns, 4);
      expect(s.rows['ai-office']!.week.cost, 0.5);
      expect(s.total.today.cost, 1.5);
      expect(s.total.week.cost, 3.5);
      expect(s.total.all.cost, 7.5);
      expect(s.isEmpty, isFalse);
      expect(summarizeUsage({}, _now).isEmpty, isTrue);
    });

    test('UsageRepo копит ходы по ключу и дню и пишет usage.json', () async {
      final storage = MemoryStorage();
      final repo = UsageRepo(storage);
      await repo.record('alpha', const TurnUsage(cost: 1, input: 5), _now);
      await repo.record('alpha', const TurnUsage(cost: 2, output: 7), _now);
      await repo.record('ai-office', const TurnUsage(cost: 3),
          DateTime(2026, 11, 27, 23, 59));
      final day = storage.usage['alpha']['2026-11-28'] as Map;
      expect(day['cost'], 3);
      expect(day['in'], 5);
      expect(day['out'], 7);
      expect(day['n'], 2);
      // перезагрузка из файла
      final again = UsageRepo(storage);
      await again.load();
      final s = again.summary(_now);
      expect(s.rows['alpha']!.today.cost, 3);
      expect(s.rows['ai-office']!.today.cost, 0);
      expect(s.rows['ai-office']!.week.cost, 3);
    });

    test('ход в чате попадает в расходы по ключу чата', () async {
      final env = _Env();
      final (app, proc, _, storage) = await _app(env);
      app.openOffice();
      final o = app.chats[officeKey]!;
      await o.ready();
      proc.queue.add(FakeRunning([
        '{"type":"system","subtype":"init","session_id":"$_sidO"}',
        '{"type":"result","subtype":"success","is_error":false,"result":"ok",'
            '"session_id":"$_sidO","total_cost_usd":0.5,'
            '"usage":{"input_tokens":1,"output_tokens":2,'
            '"cache_read_input_tokens":3,"cache_creation_input_tokens":4}}',
      ]));
      await o.send('привет');
      await _pump();
      final row = app.usageSummary.rows[officeKey]!;
      expect(row.today.cost, 0.5);
      expect(row.today.tokens, 10);
      expect(storage.usage[officeKey], isNotNull);
    });
  });

  group('лимит', () {
    final epoch = _epoch(DateTime(2026, 11, 28, 18, 40));

    test('rate_limit_event: отказ с временем сброса', () {
      final line = '{"type":"rate_limit_event","rate_limit_info":'
          '{"status":"rejected","resetsAt":$epoch}}';
      final e = parseStreamLine(line, now: _now).single as RateLimitEvent;
      expect(e.resetsAt, DateTime(2026, 11, 28, 18, 40));
    });

    test('rate_limit_event: «allowed» и предупреждение не блокируют', () {
      for (final st in ['allowed', 'allowed_warning']) {
        final line = '{"type":"rate_limit_event","rate_limit_info":'
            '{"status":"$st","resetsAt":$epoch}}';
        expect(parseStreamLine(line, now: _now), isEmpty);
      }
    });

    test('system с rate_limit_info (миллисекунды, ISO)', () {
      final ms = '{"type":"system","subtype":"api_retry","rate_limit_info":'
          '{"status":"rejected","resets_at":${epoch * 1000}}}';
      expect((parseStreamLine(ms, now: _now).single as RateLimitEvent).resetsAt,
          DateTime(2026, 11, 28, 18, 40));
      final iso = DateTime(2026, 11, 28, 18, 40).toUtc().toIso8601String();
      final line = '{"type":"system","subtype":"x","rate_limit_info":'
          '{"status":"rejected","resetsAt":"$iso"}}';
      expect((parseStreamLine(line, now: _now).single as RateLimitEvent).resetsAt,
          DateTime(2026, 11, 28, 18, 40));
    });

    test('время сброса уже прошло — лимит не ставим', () {
      final past = _epoch(DateTime(2026, 11, 28, 9, 0));
      final line = '{"type":"rate_limit_event","rate_limit_info":'
          '{"status":"rejected","resetsAt":$past}}';
      expect(parseStreamLine(line, now: _now), isEmpty);
    });

    test('текст: «usage limit reached|<epoch>»', () {
      expect(parseLimitText('Claude AI usage limit reached|$epoch', _now),
          DateTime(2026, 11, 28, 18, 40));
    });

    test('текст: «limit reached ∙ resets 6pm» и 24-часовой формат', () {
      expect(parseLimitText('5-hour limit reached ∙ resets 6pm', _now),
          DateTime(2026, 11, 28, 18, 0));
      expect(parseLimitText('Usage limit reached. Resets at 18:40', _now),
          DateTime(2026, 11, 28, 18, 40));
    });

    test('текст: время уже прошло — завтра; дата и пояс в скобках', () {
      // 12:00 UTC = 15:00 в Москве: 11:30 уже прошло, значит завтра
      final utcNow = DateTime.utc(2026, 11, 28, 12, 0);
      expect(
          parseLimitText(
                  "You've hit your limit · resets 11:30am (Europe/Moscow)", utcNow)!
              .toUtc(),
          DateTime.utc(2026, 11, 29, 8, 30));
      expect(
          parseLimitText('Usage limit reached. Resets at 18:00 (Europe/Moscow)',
                  utcNow)!
              .toUtc(),
          DateTime.utc(2026, 11, 28, 15, 0));
      expect(
          parseLimitText('Usage limit reached. Resets at 18:00 (UTC+5)', utcNow)!
              .toUtc(),
          DateTime.utc(2026, 11, 28, 13, 0));
      expect(
          parseLimitText('Usage limit reached. Resets at 18:00 (UTC)', utcNow)!
              .toUtc(),
          DateTime.utc(2026, 11, 28, 18, 0));
      // незнакомый пояс — местное время
      expect(
          parseLimitText('Usage limit reached. Resets at 18:00 (Mars/Base)', _now),
          DateTime(2026, 11, 28, 18, 0));
      expect(parseLimitText('Weekly limit reached ∙ resets Dec 1 at 10am', _now),
          DateTime(2026, 12, 1, 10, 0));
    });

    test('время сброса далеко (больше 8 суток) или в прошлом — null', () {
      final far = _epoch(_now.add(const Duration(days: 9)));
      final near = _epoch(_now.add(const Duration(days: 7)));
      expect(parseLimitText('Claude AI usage limit reached|$far', _now), isNull);
      expect(parseLimitText('Claude AI usage limit reached|$near', _now),
          isNotNull);
      expect(
          parseStreamLine(
              '{"type":"rate_limit_event","rate_limit_info":'
              '{"status":"rejected","resetsAt":$far}}',
              now: _now),
          isEmpty);
      // Dec 1 следующего года — слишком далеко
      expect(
          parseLimitText('Weekly limit reached ∙ resets Nov 20 at 10am', _now),
          isNull);
    });

    test('текст без времени или не про лимит — null', () {
      expect(parseLimitText('Usage limit reached', _now), isNull);
      expect(parseLimitText('Что-то сломалось, resets 6pm', _now), isNull);
      expect(parseLimitText('', _now), isNull);
    });

    test('результат с ошибкой-лимитом даёт RateLimitEvent', () {
      final ev = parseStreamLine(
          '{"type":"result","subtype":"success","is_error":true,'
          '"result":"5-hour limit reached ∙ resets 6pm"}',
          now: _now);
      expect(ev, hasLength(2));
      expect(ev[0], isA<ResultEvent>());
      expect((ev[1] as RateLimitEvent).resetsAt, DateTime(2026, 11, 28, 18, 0));
    });

    test('hhmm', () {
      expect(hhmm(DateTime(2026, 1, 1, 8, 5)), '08:05');
    });

    test('лимит блокирует отправку во всех чатах, «Всё равно» снимает',
        () async {
      final env = _Env();
      final (app, proc, _, _) = await _app(env);
      app.openOffice();
      final o = app.chats[officeKey]!;
      await o.ready();
      final until = DateTime.now().add(const Duration(hours: 3));
      proc.queue.add(FakeRunning([
        '{"type":"system","subtype":"init","session_id":"$_sidO"}',
        '{"type":"rate_limit_event","rate_limit_info":'
            '{"status":"rejected","resetsAt":${_epoch(until)}}}',
        '{"type":"result","subtype":"success","is_error":true,'
            '"result":"limit","session_id":"$_sidO"}',
      ]));
      await o.send('привет');
      expect(app.limited, isTrue);
      expect(app.activeLimit!.difference(until).inSeconds.abs(), lessThan(2));
      expect(o.limitBlocked, isTrue);

      await o.send('ещё раз');
      expect(proc.started, hasLength(1)); // не ушло

      app.clearLimit();
      expect(o.limitBlocked, isFalse);
      proc.queue.add(FakeRunning([
        '{"type":"result","subtype":"success","is_error":false,"result":"ok",'
            '"session_id":"$_sidO"}',
      ]));
      await o.send('ещё раз');
      expect(proc.started, hasLength(2));
    });
  });

  group('уведомления', () {
    test('первая загрузка доски не шлёт, смена этапа шлёт один раз', () async {
      final env = _Env()..alphaStage = 'Дизайн ✅ ждёт «да»';
      final (app, _, n, _) = await _app(env);
      await app.refreshBoard(); // уже ждёт «да», но это первая загрузка
      await _pump();
      expect(n.shown, isEmpty);

      env.alphaStage = 'Разработка';
      await app.refreshBoard();
      expect(n.shown, isEmpty);

      env.alphaStage = 'Тесты и ревью ✅ ждёт «да»';
      await app.refreshBoard();
      await _pump();
      expect(n.shown, ['Альфа ждёт «да» — Тесты и ревью']);
      expect(n.keys, ['alpha']);

      await app.refreshBoard(); // этап тот же — повтора нет
      await _pump();
      expect(n.shown, hasLength(1));
    });

    test('выключенный тип не шлётся', () async {
      final env = _Env();
      final (app, _, n, _) = await _app(env);
      await app.refreshBoard();
      await app.setNotifyEnabled(NotifyKind.waitsYes, false);
      expect(app.state.notifyEnabled(NotifyKind.waitsYes), isFalse);
      expect(app.state.notifyEnabled(NotifyKind.buildOk), isTrue);
      env.alphaStage = 'Дизайн ✅ ждёт «да»';
      await app.refreshBoard();
      await _pump();
      expect(n.shown, isEmpty);
    });

    test('сборка: готова / упала при смене статуса последнего запуска',
        () async {
      final env = _Env()
        ..runJson = '{"workflow_runs":[{"event":"push","head_repository":{"full_name":"dom/ai-studio"},"id":1,"status":"in_progress",'
            '"conclusion":null,"updated_at":"2999-01-01T00:00:00Z"}]}';
      final (app, _, n, _) = await _app(env);
      await app.refreshBoard();
      await _pump();
      expect(n.shown, isEmpty); // первое наблюдение

      env.runJson = '{"workflow_runs":[{"event":"push","head_repository":{"full_name":"dom/ai-studio"},"id":1,"status":"completed",'
          '"conclusion":"success","updated_at":"2999-01-01T00:00:00Z"}]}';
      await app.refreshBoard();
      await _pump();
      expect(n.shown, ['Альфа: сборка готова']);

      env.runJson = '{"workflow_runs":[{"event":"push","head_repository":{"full_name":"dom/ai-studio"},"id":2,"status":"completed",'
          '"conclusion":"failure","updated_at":"2999-01-01T00:00:00Z"}]}';
      await app.refreshBoard();
      await _pump();
      expect(n.shown, ['Альфа: сборка готова', 'Альфа: сборка упала']);

      await app.refreshBoard(); // без изменений
      await _pump();
      expect(n.shown, hasLength(2));
    });

    test('«директор ответил» — только когда окно не в фокусе', () async {
      for (final focused in [true, false]) {
        final env = _Env();
        final (app, proc, n, _) = await _app(env, focused: focused);
        app.openOffice();
        final o = app.chats[officeKey]!;
        await o.ready();
        proc.queue.add(FakeRunning([
          '{"type":"system","subtype":"init","session_id":"$_sidO"}',
          '{"type":"result","subtype":"success","is_error":false,'
              '"result":"ok","session_id":"$_sidO"}',
        ]));
        await o.send('привет');
        await _pump();
        expect(n.shown, focused ? isEmpty : ['Директор ответил: Офис студии']);
      }
    });

    test('клик открывает чат проекта и показывает окно', () async {
      final env = _Env();
      final log = <String>[];
      final (app, _, n, _) = await _app(env, windowLog: log);
      await app.refreshBoard();
      n.click!('alpha');
      await _pump();
      expect(log, ['show']);
      expect(app.activeKey, 'alpha');
      n.click!(officeKey);
      await _pump();
      expect(app.activeKey, officeKey);
    });

    test('NotifyTracker: этапы', () {
      Project pr(String slug, String stage) => Project(
          name: slug,
          slug: slug,
          type: 'Сайт',
          stage: stage,
          branch: slug,
          branchExists: true);
      final t = NotifyTracker();
      expect(t.newlyWaiting(const []), isEmpty); // пустая доска — не «первая»
      expect(t.newlyWaiting([pr('a', 'ТЗ ✅ ждёт «да»'), pr('b', 'Бриф')]),
          isEmpty);
      expect(
          t
              .newlyWaiting([pr('a', 'ТЗ ✅ ждёт «да»'), pr('b', 'Дизайн ✅ ждёт «да»')])
              .map((e) => e.slug),
          ['b']);
      expect(t.newlyWaiting([pr('a', 'Дизайн'), pr('b', 'Дизайн ✅ ждёт «да»')]),
          isEmpty);
      expect(t.newlyWaiting([pr('a', 'ТЗ ✅ ждёт «да»'), pr('b', 'Дизайн')]).single.slug,
          'a'); // снова ждёт
    });

    test('stageName и тексты', () {
      expect(stageName('Дизайн ✅ ждёт «да»'), 'Дизайн');
      expect(stageName('Разработка'), 'Разработка');
      expect(notifyBody(NotifyKind.buildFailed, 'Альфа'), 'Альфа: сборка упала');
      expect(notifyBody(NotifyKind.waitsYes, 'Альфа'), 'Альфа ждёт «да»');
    });

    test('notifyBody: без управляющих символов и <>&, не длиннее 80', () {
      final b = notifyBody(NotifyKind.buildOk, 'A<b>&\n\x07c');
      expect(b, 'A b c: сборка готова');
      final long = notifyBody(NotifyKind.directorReply, 'я' * 300);
      expect(long.runes.length, lessThanOrEqualTo(80));
      expect(RegExp(r'[<>&\x00-\x1f]').hasMatch(long), isFalse);
    });
  });
}
