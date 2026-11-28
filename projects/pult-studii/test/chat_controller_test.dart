import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pult_studii/models/models.dart';
import 'package:pult_studii/services/app_storage.dart';
import 'package:pult_studii/services/claude_runner.dart';
import 'package:pult_studii/services/git_service.dart';
import 'package:pult_studii/services/process_runner.dart';
import 'package:pult_studii/state/chat_controller.dart';

import 'fakes.dart';

const _init = '{"type":"system","subtype":"init","session_id":"s1"}';
const _d1 =
    '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Прив"}}}';
const _d2 =
    '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"ет"}}}';
const _full =
    '{"type":"assistant","message":{"content":[{"type":"text","text":"Привет"}]}}';
const _resultDenied =
    '{"type":"result","subtype":"success","is_error":false,"result":"Привет","session_id":"s1","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"rm -rf build"}}]}';

Future<(ChatController, FakeProc, StateRepo, MemoryStorage)> _make(
    {String? lastSeen, String log = ''}) async {
  final storage = MemoryStorage(
    state: {
      'repoPath': 'C:\\ai',
      if (lastSeen != null)
        'projects': {
          'alpha': {'lastSeenSha': lastSeen}
        },
    },
    readme: sampleReadme,
  );
  final proc = FakeProc((exe, args, cwd) {
    final k = args.join(' ');
    if (k == 'branch --show-current') return const ProcResult(0, 'alpha\n');
    if (k == 'rev-parse --verify --quiet origin/alpha') {
      return const ProcResult(0, 'fff0000\n');
    }
    if (k.startsWith('log ')) return ProcResult(0, log);
    return const ProcResult(0);
  });
  final state = StateRepo(storage);
  await state.load();
  final git = GitService(proc, storage)..repoPath = 'C:\\ai';
  final chat = ChatController(
    slug: 'alpha',
    git: git,
    claude: ClaudeRunner(proc),
    state: state,
    storage: storage,
    onTurnDone: () async {},
  );
  await chat.open();
  return (chat, proc, state, storage);
}

void main() {
  test('ход: стриминг, session_id, отказ, «Разрешить и повторить»', () async {
    final (chat, proc, state, storage) = await _make();
    expect(chat.blockedReason, isNull);
    proc.queue.add(FakeRunning([_init, _d1, _d2, _full, _resultDenied]));
    await chat.send('привет');

    final kinds = chat.messages.map((m) => m.kind).toList();
    expect(kinds, [MsgKind.user, MsgKind.director, MsgKind.denial]);
    expect(chat.messages[1].text, 'Привет');
    expect(state.sessionId('alpha'), 's1');
    expect(proc.started.single, isNot(contains('--resume')));
    expect(storage.chats['alpha']!.map((m) => m.kind),
        [MsgKind.user, MsgKind.director]);
    expect(chat.working, isFalse);

    proc.queue.add(FakeRunning(const [_init]));
    await chat.allowAndRetry(chat.messages.last);
    expect(state.allowedTools('alpha'), ['Bash(rm *)']);
    final args = proc.started.last;
    expect(args, containsAllInOrder(['--resume', 's1']));
    expect(args, contains('Bash(rm *)'));
    // без result и с кодом 0 — понятная ошибка, а не тишина
    expect(chat.messages.last.kind, MsgKind.error);
  });

  test('ошибка процесса: нет входа', () async {
    final (chat, proc, _, _) = await _make();
    proc.queue.add(FakeRunning(const [], code: 1, err: 'Please run /login'));
    await chat.send('привет');
    final err = chat.messages.last;
    expect(err.kind, MsgKind.error);
    expect(err.text, contains('войди аккаунтом'));
  });

  test('сводка с телефона добавляется к первому сообщению один раз', () async {
    final (chat, proc, state, _) =
        await _make(lastSeen: 'abc1234', log: 'aaa1111 2026-11-28 С телефона\n');
    expect(chat.summary, ['aaa1111 2026-11-28 С телефона']);
    expect(state.lastSeenSha('alpha'), 'fff0000');
    proc.queue
      ..add(FakeRunning(const [_init]))
      ..add(FakeRunning(const [_init]));
    await chat.send('продолжай');
    await chat.send('ещё');
    expect(proc.started[0], contains(startsWith('С телефона сделаны коммиты')));
    expect(proc.started[0].join('\n'), contains('продолжай'));
    expect(proc.started[1].join('\n'), isNot(contains('С телефона сделаны')));
    // пользователю в ленте показываем только его текст
    expect(chat.messages.first.text, 'продолжай');
  });

  test('claude.cmd: запрос идёт через stdin, не в аргументах', () async {
    final (chat, proc, _, _) = await _make();
    proc.exeName = r'C:\npm\claude.cmd';
    proc.queue.add(FakeRunning(const [_init]));
    await chat.send('a & b');
    expect(proc.started.single, isNot(contains('a & b')));
    expect(proc.stdins.single, 'a & b');
  });

  test('«Да» отправляет да, «Поправить» — с префиксом', () async {
    final (chat, proc, _, _) = await _make();
    proc.queue
      ..add(FakeRunning(const [_init]))
      ..add(FakeRunning(const [_init]));
    await chat.sendYes();
    await chat.sendFix('сделай синим');
    expect(proc.started[0], contains('да'));
    expect(proc.started[1], contains('Поправить: сделай синим'));
  });

  test('Стоп убивает процесс', () async {
    final (chat, proc, _, _) = await _make();
    final run = FakeRunning(const [], stream: StreamController<String>());
    proc.queue.add(run);
    final f = chat.send('долго');
    await Future<void>.delayed(Duration.zero);
    chat.stop();
    await f;
    expect(run.killed, isTrue);
    expect(chat.messages.any((m) => m.text == 'Остановлено'), isTrue);
  });
}
