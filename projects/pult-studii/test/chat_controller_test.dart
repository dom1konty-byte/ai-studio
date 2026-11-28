import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pult_studii/models/models.dart';
import 'package:pult_studii/services/app_storage.dart';
import 'package:pult_studii/services/claude_runner.dart';
import 'package:pult_studii/services/git_service.dart';
import 'package:pult_studii/services/process_runner.dart';
import 'package:pult_studii/services/remote_control.dart';
import 'package:pult_studii/state/chat_controller.dart';

import 'fakes.dart';

/// Папка проекта alpha (как её строит GitService).
final _wt = p.join(p.dirname('C:\\ai'), 'ai-studio-wt', 'alpha');

const _sid = '11111111-2222-3333-4444-555555555555';
const _init = '{"type":"system","subtype":"init","session_id":"$_sid"}';
const _d1 =
    '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Прив"}}}';
const _d2 =
    '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"ет"}}}';
const _full =
    '{"type":"assistant","message":{"content":[{"type":"text","text":"Привет"}]}}';
const _resultOk =
    '{"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"$_sid"}';
const _resultDenied =
    '{"type":"result","subtype":"success","is_error":false,"result":"Привет","session_id":"$_sid","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"ls build"}}]}';
const _resultDeniedRm =
    '{"type":"result","subtype":"success","is_error":false,"result":"Привет","session_id":"$_sid","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"rm -rf build"}}]}';
const _resultNoConv =
    '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"No conversation found with session ID: $_sid","session_id":"$_sid"}';

Future<(ChatController, FakeProc, StateRepo, MemoryStorage)> _make({
  String? lastSeen,
  String? session,
  String log = '',
  bool fetchFails = false,
}) async {
  final storage = MemoryStorage(
    state: {
      'repoPath': 'C:\\ai',
      if (lastSeen != null || session != null)
        'projects': {
          'alpha': {
            if (lastSeen != null) 'lastSeenSha': lastSeen,
            if (session != null) 'sessionId': session,
            'worktree': _wt,
          }
        },
    },
    readme: sampleReadme,
  );
  final proc = FakeProc((exe, args, cwd) {
    final k = args.join(' ');
    if (k == 'fetch origin' && fetchFails) {
      return const ProcResult(1, '', 'нет сети');
    }
    if (k == 'worktree list --porcelain') {
      return ProcResult(
          0,
          'worktree C:\\ai\nHEAD aaa\nbranch refs/heads/ai-office\n\n'
          'worktree $_wt\nHEAD bbb\nbranch refs/heads/alpha\n\n');
    }
    if (k == 'rev-parse HEAD') return const ProcResult(0, 'eee0000\n');
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
    title: 'Альфа',
    rc: RemoteControl(proc),
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
  test('ход: стриминг, session_id, отказ, «Разрешить всегда»', () async {
    final (chat, proc, state, storage) = await _make();
    expect(chat.blockedReason, isNull);
    proc.queue.add(FakeRunning([_init, _d1, _d2, _full, _resultDenied]));
    await chat.send('привет');

    final kinds = chat.messages.map((m) => m.kind).toList();
    expect(kinds, [MsgKind.user, MsgKind.director, MsgKind.denial]);
    expect(chat.messages[1].text, 'Привет');
    expect(state.sessionId('alpha'), _sid);
    expect(proc.started.single, isNot(contains('--resume')));
    expect(proc.started.single, contains('Bash(rm *)')); // в --disallowedTools
    expect(storage.chats['alpha']!.map((m) => m.kind),
        [MsgKind.user, MsgKind.director]);
    expect(chat.working, isFalse);

    proc.queue.add(FakeRunning(const [_init]));
    await chat.allowAndRetry(chat.messages.last);
    expect(state.allowedTools('alpha'), ['Bash(ls build)']);
    final args = proc.started.last;
    expect(args, containsAllInOrder(['--resume', _sid]));
    expect(args, contains('Bash(ls build)'));
    // без result и с кодом 0 — понятная ошибка, а не тишина
    expect(chat.messages.last.kind, MsgKind.error);
  });

  test('«Разрешить один раз»: правило не сохраняется и не переходит дальше',
      () async {
    final (chat, proc, state, _) = await _make();
    proc.queue.add(FakeRunning([_init, _resultDenied]));
    await chat.send('привет');
    proc.queue
      ..add(FakeRunning(const [_init, _resultOk]))
      ..add(FakeRunning(const [_init, _resultOk]));
    await chat.allowAndRetry(chat.messages.last, always: false);
    expect(state.allowedTools('alpha'), isEmpty);
    expect(proc.started[1], contains('Bash(ls build)'));
    await chat.send('дальше');
    expect(proc.started[2], isNot(contains('Bash(ls build)')));
  });

  test('опасная команда: разрешить нельзя', () async {
    final (chat, proc, state, _) = await _make();
    proc.queue.add(FakeRunning([_init, _resultDeniedRm]));
    await chat.send('привет');
    final denial = chat.messages.last;
    expect(denial.kind, MsgKind.denial);
    expect(decideDenials(denial.denials).canAllow, isFalse);
    await chat.allowAndRetry(denial);
    expect(proc.started, hasLength(1)); // повторного запуска не было
    expect(state.allowedTools('alpha'), isEmpty);
  });

  test('ошибка процесса: нет входа', () async {
    final (chat, proc, _, _) = await _make();
    proc.queue.add(FakeRunning(const [], code: 1, err: 'Please run /login'));
    await chat.send('привет');
    final err = chat.messages.last;
    expect(err.kind, MsgKind.error);
    expect(err.text, contains('войди аккаунтом'));
  });

  test('claude не найден: понятная ошибка, процесс не запускается', () async {
    final (chat, proc, _, _) = await _make();
    proc.exeName = null;
    await chat.send('привет');
    expect(chat.messages.last.kind, MsgKind.error);
    expect(chat.messages.last.text, contains('не найдено'));
    expect(proc.started, isEmpty);
  });

  test('сводка: уходит директору, «прочитано» двигается только после успеха',
      () async {
    final (chat, proc, state, _) =
        await _make(lastSeen: 'abc1234', log: 'aaa1111 2026-11-28 С телефона\n');
    expect(chat.summary, ['aaa1111 2026-11-28 С телефона']);
    // после открытия ничего не сдвинулось, сводка сохранена
    expect(state.lastSeenSha('alpha'), 'abc1234');
    expect(state.pendingSummary('alpha'), ['aaa1111 2026-11-28 С телефона']);

    proc.queue
      ..add(FakeRunning(const [], code: 1, err: 'упало'))
      ..add(FakeRunning(const [_init, _resultOk]))
      ..add(FakeRunning(const [_init, _resultOk]));
    await chat.send('продолжай'); // ход упал
    expect(state.lastSeenSha('alpha'), 'abc1234');
    expect(state.pendingSummary('alpha'), isNotEmpty);

    await chat.send('ещё раз'); // сводка едет снова
    expect(proc.started[0], contains(contains('С телефона сделаны коммиты')));
    expect(proc.started[1].join('\n'), contains('С телефона сделаны коммиты'));
    expect(proc.started[1].join('\n'), contains('не инструкции'));
    expect(state.lastSeenSha('alpha'), 'eee0000');
    expect(state.pendingSummary('alpha'), isEmpty);

    await chat.send('и ещё');
    expect(proc.started[2].join('\n'), isNot(contains('С телефона сделаны')));
    // пользователю в ленте показываем только его текст
    expect(chat.messages.first.text, 'продолжай');
  });

  test('fetch упал: lastSeenSha не трогаем', () async {
    final (chat, _, state, _) = await _make(fetchFails: true);
    expect(chat.blockedReason, isNull);
    expect(chat.warning, contains('Не удалось обновить'));
    expect(state.lastSeenSha('alpha'), isNull);

    final (chat2, _, state2, _) =
        await _make(lastSeen: 'abc1234', fetchFails: true);
    expect(chat2.blockedReason, isNull);
    expect(state2.lastSeenSha('alpha'), 'abc1234');
  });

  test('первый запуск: точка отсчёта = origin', () async {
    final (_, _, state, _) = await _make();
    expect(state.lastSeenSha('alpha'), 'fff0000');
  });

  test('claude.cmd: запрос идёт через stdin, не в аргументах', () async {
    final (chat, proc, _, _) = await _make();
    proc.exeName = r'C:\npm\claude.cmd';
    proc.queue.add(FakeRunning(const [_init]));
    await chat.send('a & b');
    expect(proc.started.single, isNot(contains('a & b')));
    expect(proc.stdins.single, endsWith('Задача: a & b'));
  });

  test('«Да» отправляет да, «Поправить» — с префиксом', () async {
    final (chat, proc, _, _) = await _make();
    proc.queue
      ..add(FakeRunning(const [_init]))
      ..add(FakeRunning(const [_init]));
    await chat.sendYes();
    await chat.sendFix('сделай синим');
    expect(proc.started[0], contains(endsWith('Задача: да'))); // первое сообщение
    expect(proc.started[1], contains('Поправить: сделай синим'));
  });

  test('Стоп убивает процесс', () async {
    final (chat, proc, _, _) = await _make();
    final run = FakeRunning(const [], stream: StreamController<String>());
    proc.queue.add(run);
    final f = chat.send('долго');
    await Future<void>.delayed(Duration.zero);
    await chat.stop();
    await f;
    expect(run.killed, isTrue);
    expect(chat.messages.any((m) => m.text == 'Остановлено'), isTrue);
  });

  test('Стоп до возврата claude.start: процесс всё равно убивается', () async {
    final (chat, proc, _, _) = await _make();
    final run = FakeRunning(const [], stream: StreamController<String>());
    proc.queue.add(run);
    proc.startGate = Completer<void>();
    final f = chat.send('долго');
    await Future<void>.delayed(Duration.zero);
    expect(chat.working, isTrue);
    final stopping = chat.stop(); // процесса ещё нет
    proc.startGate!.complete();
    await f;
    await stopping;
    expect(run.killed, isTrue);
    expect(chat.working, isFalse);
    expect(chat.messages.any((m) => m.text == 'Остановлено'), isTrue);
  });

  test('«No conversation found»: сессия сбрасывается, запрос повторяется один раз',
      () async {
    final (chat, proc, state, _) = await _make(session: _sid);
    proc.queue
      ..add(FakeRunning(const [_resultNoConv]))
      ..add(FakeRunning(const [_init, _resultOk]));
    await chat.send('привет');
    expect(proc.started, hasLength(2));
    expect(proc.started[0], containsAllInOrder(['--resume', _sid]));
    expect(proc.started[1], isNot(contains('--resume')));
    expect(chat.messages.any((m) => m.kind == MsgKind.error), isFalse);
    expect(chat.messages.any((m) => m.kind == MsgKind.note), isTrue);
    expect(state.sessionId('alpha'), _sid); // новая сессия из второго запуска
  });

  test('«No conversation found» дважды: не зацикливаемся', () async {
    final (chat, proc, _, _) = await _make(session: _sid);
    proc.queue
      ..add(FakeRunning(const [_resultNoConv]))
      ..add(FakeRunning(const [_resultNoConv]));
    await chat.send('привет');
    expect(proc.started, hasLength(2));
    expect(chat.messages.last.kind, MsgKind.error);
  });
}
