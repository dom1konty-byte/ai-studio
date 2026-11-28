import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/app_storage.dart';
import '../services/claude_runner.dart';
import '../services/git_service.dart';
import '../services/stream_json.dart';

/// Чат одного проекта.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.slug,
    required this.git,
    required this.claude,
    required this.state,
    required this.storage,
    required this.onTurnDone,
  });

  final String slug;
  final GitService git;
  final ClaudeRunner claude;
  final StateRepo state;
  final AppStorage storage;

  /// Вызывается после каждого хода (обновить этап проекта).
  final Future<void> Function() onTurnDone;

  static const _maxShown = 300;

  final List<ChatMessage> messages = [];
  bool preparing = true;
  String? blockedReason;
  String? warning;
  List<String> summary = [];
  bool summaryDismissed = false;
  bool working = false;

  /// «Да»/«Поправить» уже нажаты — панель скрыта до следующей проверки.
  bool approvalHidden = false;

  ClaudeTurn? _turn;
  bool _stopRequested = false;
  bool _turnShowedText = false;
  bool _resultSeen = false;
  ChatMessage? _streaming;
  String? _pendingPrefix;
  String? _lastPrompt;
  bool _disposed = false;

  bool get canSend => !preparing && blockedReason == null && !working;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Загрузить историю и подготовить ветку.
  Future<void> open() async {
    preparing = true;
    blockedReason = null;
    warning = null;
    notifyListeners();
    try {
      if (messages.isEmpty) {
        final hist = await storage.loadChat(slug);
        messages.addAll(
            hist.length > _maxShown ? hist.sublist(hist.length - _maxShown) : hist);
        notifyListeners();
      }
      final res = await git.prepare(slug, lastSeenSha: state.lastSeenSha(slug));
      blockedReason = res.blockedReason;
      warning = res.warning;
      summary = res.newCommits;
      summaryDismissed = false;
      _pendingPrefix = summary.isEmpty ? null : phoneSummaryPrompt(summary);
      if (res.originSha != null) {
        await state.setLastSeenSha(slug, res.originSha!);
      }
    } catch (e) {
      blockedReason = '$e';
    }
    preparing = false;
    notifyListeners();
  }

  void dismissSummary() {
    summaryDismissed = true;
    notifyListeners();
  }

  void _add(ChatMessage m) {
    messages.add(m);
    if (m.persistent) storage.appendChat(slug, m);
    notifyListeners();
  }

  Future<void> send(String text, {bool approval = false}) async {
    final t = text.trim();
    if (t.isEmpty || !canSend) return;
    if (approval) approvalHidden = true;
    _add(ChatMessage(MsgKind.user, t));
    var prompt = t;
    final prefix = _pendingPrefix;
    if (prefix != null) {
      prompt = '$prefix\n\n$t';
      _pendingPrefix = null;
    }
    _lastPrompt = prompt;
    await _run(prompt);
  }

  Future<void> sendYes() => send('да', approval: true);

  Future<void> sendFix(String text) {
    final t = text.trim();
    if (t.isEmpty) return Future.value();
    return send('Поправить: $t', approval: true);
  }

  /// Повторить последний запрос после ошибки.
  Future<void> retry() async {
    final prompt = _lastPrompt;
    if (prompt == null || !canSend) return;
    messages.removeWhere((m) => m.kind == MsgKind.error);
    await _run(prompt);
  }

  /// «Разрешить и повторить»: правила уходят в allowedTools проекта.
  Future<void> allowAndRetry(ChatMessage denial) async {
    if (!canSend) return;
    denial.resolved = true;
    await state.addAllowedTools(slug, denial.denials.map((d) => d.allowRule));
    notifyListeners();
    await send('Разрешение выдано. Повтори то, что не удалось.');
  }

  Future<void> newChat() async {
    if (working) return;
    await state.setSessionId(slug, null);
    _pendingPrefix = null;
    _add(ChatMessage(MsgKind.note, 'Новый чат'));
  }

  void stop() {
    if (!working) return;
    _stopRequested = true;
    _turn?.stop();
  }

  Future<void> _run(String prompt) async {
    working = true;
    _stopRequested = false;
    _turnShowedText = false;
    _resultSeen = false;
    _streaming = null;
    notifyListeners();
    try {
      final turn = await claude.start(
        prompt: prompt,
        cwd: git.repoPath,
        sessionId: state.sessionId(slug),
        extraTools: state.allowedTools(slug),
      );
      _turn = turn;
      await for (final e in turn.events) {
        await _handle(e);
      }
      final code = await turn.exitCode;
      final err = (await turn.stderr).trim();
      _closeStreaming();
      if (_stopRequested) {
        _add(ChatMessage(MsgKind.note, 'Остановлено'));
      } else if (!_resultSeen) {
        final text = err.isNotEmpty
            ? err
            : 'Claude завершился с кодом $code без ответа.';
        _add(ChatMessage(MsgKind.error, friendlyError(text)));
      }
    } catch (e) {
      _closeStreaming();
      _add(ChatMessage(MsgKind.error, friendlyError('Не удалось запустить claude: $e')));
    } finally {
      _turn = null;
      working = false;
      try {
        final head = await git.headSha();
        if (head != null) await state.setLastSeenSha(slug, head);
        await onTurnDone();
      } catch (_) {}
      approvalHidden = false;
      notifyListeners();
    }
  }

  Future<void> _handle(ClaudeEvent e) async {
    switch (e) {
      case SessionInit(sessionId: final id):
        await state.setSessionId(slug, id);
      case TextDelta(text: final delta):
        var s = _streaming;
        if (s == null) {
          s = ChatMessage(MsgKind.director, '');
          _streaming = s;
          messages.add(s);
        }
        s.text += delta;
        _turnShowedText = true;
        notifyListeners();
      case AssistantText(text: final full):
        final s = _streaming;
        if (s != null) {
          s.text = full;
          _closeStreaming();
        } else {
          _add(ChatMessage(MsgKind.director, full));
        }
        _turnShowedText = true;
      case ToolUse(summary: final sum):
        _closeStreaming();
        _add(ChatMessage(MsgKind.action, 'агент запускает: $sum'));
      case ResultEvent r:
        _resultSeen = true;
        _closeStreaming();
        final sid = r.sessionId;
        if (sid != null) await state.setSessionId(slug, sid);
        if (r.isError) {
          final text = r.text.trim().isEmpty ? 'Claude вернул ошибку.' : r.text;
          _add(ChatMessage(MsgKind.error, friendlyError(text)));
        } else if (!_turnShowedText && r.text.trim().isNotEmpty) {
          _add(ChatMessage(MsgKind.director, r.text));
        }
        if (r.denials.isNotEmpty) {
          _add(ChatMessage(MsgKind.denial, '', denials: r.denials));
        }
    }
  }

  void _closeStreaming() {
    final s = _streaming;
    if (s == null) return;
    _streaming = null;
    if (s.text.trim().isEmpty) {
      messages.remove(s);
    } else {
      storage.appendChat(slug, s);
    }
    notifyListeners();
  }
}
