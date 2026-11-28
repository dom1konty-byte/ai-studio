import 'package:flutter_test/flutter_test.dart';
import 'package:pult_studii/models/models.dart';
import 'package:pult_studii/services/claude_runner.dart';
import 'package:pult_studii/services/gh_service.dart';
import 'package:pult_studii/services/git_service.dart';
import 'package:pult_studii/services/process_runner.dart';
import 'package:pult_studii/services/readme_parser.dart';
import 'package:pult_studii/services/stream_json.dart';

import 'fakes.dart';

const _sid = '11111111-2222-3333-4444-555555555555';

void main() {
  group('stream-json', () {
    test('system/init даёт session_id', () {
      final e = parseStreamLine(
          '{"type":"system","subtype":"init","session_id":"abc-1","tools":[]}');
      expect(e, hasLength(1));
      expect((e.single as SessionInit).sessionId, 'abc-1');
    });

    test('text_delta и законченный текст', () {
      final d = parseStreamLine(
          '{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"При"}}}');
      expect((d.single as TextDelta).text, 'При');
      final a = parseStreamLine(
          '{"type":"assistant","message":{"content":[{"type":"text","text":"Привет"},{"type":"tool_use","name":"Bash","input":{"command":"git push"}}]}}');
      expect(a, hasLength(2));
      expect((a[0] as AssistantText).text, 'Привет');
      expect((a[1] as ToolUse).summary, 'git push');
    });

    test('result: текст, id, стоимость, отказы', () {
      final e = parseStreamLine(
          '{"type":"result","subtype":"success","is_error":false,"result":"Готово","session_id":"s2","total_cost_usd":0.25,'
          '"permission_denials":[{"tool_name":"Bash","tool_use_id":"t1","tool_input":{"command":"rm -rf build"}}]}');
      final r = e.single as ResultEvent;
      expect(r.text, 'Готово');
      expect(r.sessionId, 's2');
      expect(r.isError, isFalse);
      expect(r.costUsd, 0.25);
      expect(r.denials.single.display, 'rm -rf build');
      expect(r.denials.single.decision.canAllow, isFalse);
    });

    test('ошибка result и мусор', () {
      final e = parseStreamLine(
          '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"Not logged in"}');
      expect((e.single as ResultEvent).isError, isTrue);
      expect(parseStreamLine('не json'), isEmpty);
      expect(parseStreamLine(''), isEmpty);
      expect(parseStreamLine('{"type":"unknown"}'), isEmpty);
      expect(
          parseStreamLine(
              '{"type":"assistant","parent_tool_use_id":"x","message":{"content":[{"type":"text","text":"sub"}]}}'),
          isEmpty);
    });

    test('аргументы claude: отдельные элементы, --resume только со своей сессией', () {
      final first = ClaudeRunner.buildArgs(
          prompt: 'привет "мир" & dir', allowedTools: ClaudeRunner.defaultAllowedTools);
      expect(first.take(2), ['-p', 'привет "мир" & dir']);
      expect(first, isNot(contains('--resume')));
      expect(first, containsAllInOrder(['--disallowedTools', 'AskUserQuestion', '--allowedTools', 'Bash(git *)']));
      final next = ClaudeRunner.buildArgs(
          prompt: 'да', sessionId: _sid, allowedTools: const ['X']);
      expect(next, containsAllInOrder(['--resume', _sid]));
      expect(
          ClaudeRunner.buildArgs(
              prompt: 'x', sessionId: 'bad id', allowedTools: const []),
          isNot(contains('--resume')));
      expect(next.last, 'X');
    });
  });

  group('README', () {
    test('строки таблицы', () {
      final rows = parseReadmeRows(sampleReadme);
      expect(rows.map((r) => r.slug), ['alpha', 'beta']);
      expect(rows[0].name, 'Альфа');
      expect(rows[0].stage, 'Дизайн ✅ ждёт «да»');
      expect(rows[1].branch, 'beta');
    });

    test('ждёт «да»', () {
      expect(stageWaitsYes('Дизайн ✅ ждёт «да»'), isTrue);
      expect(stageWaitsYes('ТЗ ✅ ждёт "да"'), isTrue);
      expect(stageWaitsYes('Выпуск ✅ ждет да'), isTrue);
      expect(stageWaitsYes('Разработка (шаг 1)'), isFalse);
      expect(stageWaitsYes('Готово'), isFalse);
    });
  });

  group('git и gh', () {
    test('сводка коммитов', () {
      final c = parseCommitLog('abc1234 2026-11-28 Правка\n\n  def5678 2026-11-27 Ещё\n');
      expect(c, ['abc1234 2026-11-28 Правка', 'def5678 2026-11-27 Ещё']);
      expect(phoneSummaryPrompt(c), contains('abc1234 2026-11-28 Правка'));
    });

    test('owner/repo из remote', () {
      expect(parseRemote('https://github.com/dom/ai-studio.git\n')!.repo, 'ai-studio');
      expect(parseRemote('git@github.com:dom/ai-studio.git')!.owner, 'dom');
      expect(parseRemote('http://x@127.0.0.1:1234/git/dom/ai-studio')!.owner, 'dom');
    });

    test('последняя сборка', () {
      final ok = parseLatestRun(
          '{"workflow_runs":[{"id":42,"status":"completed","conclusion":"success","html_url":"u","updated_at":"2026-11-28T10:00:00Z"}]}');
      expect(ok.state, BuildState.success);
      expect(ok.id, 42);
      expect(parseLatestRun('{"workflow_runs":[{"id":1,"status":"in_progress"}]}').state,
          BuildState.running);
      expect(parseLatestRun('{"workflow_runs":[{"id":1,"status":"completed","conclusion":"failure"}]}').state,
          BuildState.failed);
      expect(parseLatestRun('{"workflow_runs":[]}').state, BuildState.none);
    });

    test('prepare: нет локальной ветки → checkout -b, сводка с телефона', () async {
      final proc = FakeProc((exe, args, cwd) {
        final k = args.join(' ');
        if (k == 'status --porcelain') return const ProcResult(0);
        if (k == 'branch --show-current') return const ProcResult(0, 'main\n');
        if (k == 'rev-parse --verify --quiet origin/alpha') return const ProcResult(0, 'fff0000\n');
        if (k == 'rev-parse --verify --quiet refs/heads/alpha') return const ProcResult(1);
        if (k.startsWith('log ')) return const ProcResult(0, 'aaa1111 2026-11-28 С телефона\n');
        return const ProcResult(0);
      });
      final git = GitService(proc, MemoryStorage())..repoPath = 'C:\\ai';
      final r = await git.prepare('alpha', lastSeenSha: 'abc1234');
      expect(r.blockedReason, isNull);
      expect(r.newCommits, ['aaa1111 2026-11-28 С телефона']);
      expect(r.originSha, 'fff0000');
      expect(proc.calls, contains('git checkout -b alpha origin/alpha'));
      expect(proc.calls, contains('git pull --ff-only'));
      expect(proc.calls, contains('git log --format=%h %cs %s abc1234..origin/alpha'));
    });

    test('prepare: есть правки на другой ветке → не переключать', () async {
      final proc = FakeProc((exe, args, cwd) {
        final k = args.join(' ');
        if (k == 'status --porcelain') return const ProcResult(0, ' M file.txt\n');
        if (k == 'branch --show-current') return const ProcResult(0, 'beta\n');
        return const ProcResult(0, 'x\n');
      });
      final git = GitService(proc, MemoryStorage())..repoPath = 'C:\\ai';
      final r = await git.prepare('alpha');
      expect(r.blockedReason, isNotNull);
      expect(proc.calls.where((c) => c.contains('checkout')), isEmpty);
    });

    test('prepare: небезопасное имя ветки отклоняется', () async {
      final git = GitService(FakeProc((a, b, c) => const ProcResult(0)), MemoryStorage())
        ..repoPath = 'C:\\ai';
      expect((await git.prepare('--upload-pack=x')).blockedReason, isNotNull);
    });

    test('loadProjects: этап берётся из ветки', () async {
      const branchReadme = '''
| Имя | Папка | Тип | Этап | Ветка | Создан |
|---|---|---|---|---|---|
| Альфа | [`alpha`](alpha/) | Сайт | Выпуск ✅ ждёт «да» | `alpha` | 2026-11-01 |
''';
      final proc = FakeProc((exe, args, cwd) {
        final k = args.join(' ');
        if (k.startsWith('branch -r')) {
          return const ProcResult(0, 'origin\norigin/HEAD\norigin/main\norigin/alpha\norigin/ai-office\norigin/claude/x\n');
        }
        if (k == 'show origin/main:projects/README.md') return const ProcResult(0, sampleReadme);
        if (k == 'show origin/alpha:projects/README.md') return const ProcResult(0, branchReadme);
        if (k.startsWith('show ')) return const ProcResult(128, '', 'fatal');
        return const ProcResult(0);
      });
      final git = GitService(proc, MemoryStorage())..repoPath = 'C:\\ai';
      final res = await git.loadProjects();
      expect(res.projects.map((p) => p.slug), ['alpha', 'beta']);
      expect(res.projects[0].stage, 'Выпуск ✅ ждёт «да»');
      expect(res.projects[0].branchExists, isTrue);
      expect(res.projects[1].branchExists, isFalse);
    });
  });
}
