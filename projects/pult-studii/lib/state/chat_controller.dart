import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/app_storage.dart';
import '../services/claude_runner.dart';
import '../services/git_service.dart';
import '../services/process_runner.dart';
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
  Completer<void>? _runDone;
  bool _stopRequested = false;
  bool _resultError = false;
  bool _sessionLost = false;
  bool _canRetrySession = true;
  Object? _handleError;
  Timer? _deltaTimer;
  DateTime _lastDeltaNotify = DateTime.fromMillisecondsSinceEpoch(0);
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
    _deltaTimer?.cancel();
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
        try {
          final hist = await storage.loadChat(slug);
          messages.addAll(hist.length > _maxShown
              ? hist.sublist(hist.length - _maxShown)
              : hist);
        } catch (_) {
          warning = 'История чата не прочиталась, начинаю с чистого листа.';
        }
        notifyListeners();
      }
      final seen = state.lastSeenSha(slug);
      final res = await git.prepare(slug, lastSeenSha: seen);
      blockedReason = res.blockedReason;
      if (res.warning != null) {
        warning = warning == null ? res.warning : '$warning\n${res.warning}';
      }
      if (res.blockedReason == null) {
        // Непрочитанная сводка переживает переключение и перезапуск.
        var commits = res.newCommits;
        if (commits.isEmpty) commits = state.pendingSummary(slug);
        summary = commits;
        summaryDismissed = false;
        if (commits.isEmpty) {
          _pendingPrefix = null;
        } else {
          _pendingPrefix = phoneSummaryPrompt(commits, pulled: res.pulled);
          await _safe(() => state.setPendingSummary(slug, commits));
        }
        // Первый запуск: запоминаем точку отсчёта (только если fetch прошёл).
        if (seen == null && res.fetchOk && res.originSha != null) {
          await _safe(() => state.setLastSeenSha(slug, res.originSha!));
        }
      }
    } catch (e) {
      blockedReason = '$e';
    }
    preparing = false;
    notifyListeners();
  }

  /// Запись состояния не должна ронять чат.
  Future<void> _safe(Future<void> Function() job) async {
    try {
      await job();
    } catch (_) {}
  }

  void dismissSummary() {
    summaryDismissed = true;
    notifyListeners();
  }

  void _add(ChatMessage m) {
    messages.add(m);
    if (m.persistent) _persist(m);
    notifyListeners();
  }

  void _persist(ChatMessage m) {
    unawaited(_safe(() => storage.appendChat(slug, m)));
  }

  Future<void> send(String text,
      {bool approval = false, List<String> onceTools = const []}) async {
    final t = text.trim();
    if (t.isEmpty || !canSend) return;
    if (approval) approvalHidden = true;
    _add(ChatMessage(MsgKind.user, t));
    var prompt = t;
    final prefix = _pendingPrefix;
    // Префикс снимается только после успешного хода (см. _run).
    if (prefix != null) prompt = '$prefix\n\n$t';
    _lastPrompt = prompt;
    await _run(prompt, onceTools);
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
    await _run(prompt, const []);
  }

  /// «Разрешить один раз» ([always] false: правило не сохраняется)
  /// или «Разрешить всегда» ([always] true: сохраняется в state.json).
  Future<void> allowAndRetry(ChatMessage denial, {bool always = true}) async {
    if (!canSend) return;
    final decision = decideDenials(denial.denials);
    if (!decision.canAllow) return;
    denial.resolved = true;
    if (always) {
      await _safe(() => state.addAllowedTools(slug, decision.rules));
    }
    notifyListeners();
    await send('Разрешение выдано. Повтори то, что не удалось.',
        onceTools: always ? const [] : decision.rules);
  }

  Future<void> newChat() async {
    if (working) return;
    await _safe(() => state.setSessionId(slug, null));
    _pendingPrefix = null;
    _add(ChatMessage(MsgKind.note, 'Новый чат'));
  }

  /// Остановить ход: убить процесс и дождаться конца хода (до 3 с).
  Future<void> stop() async {
    if (!working) return;
    _stopRequested = true;
    final t = _turn;
    if (t != null) {
      try {
        await t.stop();
      } catch (_) {}
    }
    final done = _runDone;
    if (done != null && !done.isCompleted) {
      await done.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    }
  }

  Future<void> _run(String prompt, List<String> onceTools) async {
    working = true;
    _stopRequested = false;
    _canRetrySession = true;
    _runDone = Completer<void>();
    notifyListeners();
    var ok = false;
    try {
      ok = await _attempt(prompt, onceTools);
      if (_sessionLost && !_stopRequested) {
        // «No conversation found»: сбросить сессию и повторить один раз.
        _canRetrySession = false;
        await _safe(() => state.setSessionId(slug, null));
        _add(ChatMessage(MsgKind.note,
            'Прежний разговор не найден — начинаю новый и повторяю запрос.'));
        ok = await _attempt(prompt, onceTools);
      }
    } finally {
      _turn = null;
      working = false;
      if (ok) {
        // Сводка ушла директору — только теперь двигаем «прочитано».
        _pendingPrefix = null;
        summaryDismissed = true;
        try {
          await state.setPendingSummary(slug, const []);
          final head = await git.headSha();
          if (head != null) await state.setLastSeenSha(slug, head);
        } catch (_) {}
      }
      try {
        await onTurnDone();
      } catch (_) {}
      approvalHidden = false;
      notifyListeners();
      final d = _runDone;
      if (d != null && !d.isCompleted) d.complete();
    }
  }

  /// Один запуск claude. true — ход закончился успешно.
  Future<bool> _attempt(String prompt, List<String> onceTools) async {
    _turnShowedText = false;
    _resultSeen = false;
    _resultError = false;
    _sessionLost = false;
    _handleError = null;
    _streaming = null;
    try {
      final turn = await claude.start(
        prompt: prompt,
        cwd: git.repoPath,
        sessionId: state.sessionId(slug),
        extraTools: [...state.allowedTools(slug), ...onceTools],
      );
      _turn = turn;
      // Стоп нажали, пока процесс запускался.
      if (_stopRequested) unawaited(turn.stop());
      await for (final e in turn.events) {
        try {
          await _handle(e);
        } catch (err) {
          _handleError = err;
          unawaited(turn.stop());
          break;
        }
      }
      final code = await turn.exitCode;
      final err = (await turn.stderr).trim();
      _closeStreaming();
      if (_handleError != null) {
        _add(ChatMessage(MsgKind.error,
            'Ошибка Рубки при разборе ответа Claude: $_handleError. '
            'Ход остановлен — нажми «Повторить».'));
        return false;
      }
      if (_stopRequested) {
        _add(ChatMessage(MsgKind.note, 'Остановлено'));
        return false;
      }
      if (_sessionLost) return false;
      if (!_resultSeen) {
        final text = err.isNotEmpty
            ? err
            : 'Claude завершился с кодом $code без ответа.';
        if (_canRetrySession && _isNoConversation(text)) {
          _sessionLost = true;
          return false;
        }
        _add(ChatMessage(MsgKind.error, friendlyError(text)));
        return false;
      }
      return !_resultError;
    } on ToolNotFound catch (e) {
      _closeStreaming();
      _add(ChatMessage(MsgKind.error, e.message));
      return false;
    } catch (e) {
      _closeStreaming();
      _add(ChatMessage(
          MsgKind.error, friendlyError('Не удалось запустить claude: $e')));
      return false;
    }
  }

  static bool _isNoConversation(String t) =>
      RegExp(r'no conversation found', caseSensitive: false).hasMatch(t);

  Future<void> _handle(ClaudeEvent e) async {
    switch (e) {
      case SessionInit(sessionId: final id):
        await _safe(() => state.setSessionId(slug, id));
      case TextDelta(text: final delta):
        var s = _streaming;
        if (s == null) {
          s = ChatMessage(MsgKind.director, '');
          _streaming = s;
          messages.add(s);
        }
        s.text += delta;
        _turnShowedText = true;
        _notifyDelta();
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
        if (sid != null) await _safe(() => state.setSessionId(slug, sid));
        if (r.isError) {
          final text = r.text.trim().isEmpty ? 'Claude вернул ошибку.' : r.text;
          if (_canRetrySession && _isNoConversation(text)) {
            _sessionLost = true;
          } else {
            _resultError = true;
            _add(ChatMessage(MsgKind.error, friendlyError(text)));
          }
        } else if (!_turnShowedText && r.text.trim().isNotEmpty) {
          _add(ChatMessage(MsgKind.director, r.text));
        }
        if (r.denials.isNotEmpty) {
          _add(ChatMessage(MsgKind.denial, '', denials: r.denials));
        }
    }
  }

  /// Обновление ленты при стриминге — не чаще раза в 50 мс.
  void _notifyDelta() {
    const gap = Duration(milliseconds: 50);
    if (DateTime.now().difference(_lastDeltaNotify) >= gap) {
      _lastDeltaNotify = DateTime.now();
      notifyListeners();
    } else {
      _deltaTimer ??= Timer(gap, () {
        _deltaTimer = null;
        _lastDeltaNotify = DateTime.now();
        notifyListeners();
      });
    }
  }

  void _closeStreaming() {
    final s = _streaming;
    if (s == null) return;
    _streaming = null;
    _deltaTimer?.cancel();
    _deltaTimer = null;
    if (s.text.trim().isEmpty) {
      messages.remove(s);
    } else {
      _persist(s);
    }
    notifyListeners();
  }
}
