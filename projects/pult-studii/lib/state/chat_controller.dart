import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/models.dart';
import '../services/app_storage.dart';
import '../services/attachments.dart';
import '../services/claude_runner.dart';
import '../services/git_service.dart';
import '../services/process_runner.dart';
import '../services/remote_control.dart';
import '../services/stream_json.dart';
import '../services/usage.dart';

enum PendingState { copying, ready, error }

/// Файл, прикреплённый к ещё не отправленному сообщению (чип над полем ввода).
class PendingAttachment {
  PendingAttachment(this.name);

  /// Имя для показа (исходное).
  final String name;
  PendingState state = PendingState.copying;
  Attachment? file;
  String? error;
}

/// Чат одного проекта или «Офиса» (slug == officeKey).
class ChatController extends ChangeNotifier {
  ChatController({
    required this.slug,
    required this.title,
    this.rc,
    required this.git,
    required this.claude,
    required this.state,
    required this.storage,
    required this.onTurnDone,
    this.onUsage,
    this.onRateLimit,
    this.limitUntil,
    this.onReply,
    this.attachStore,
  });

  final String slug;

  /// Куда копируются вложения (null — вложения выключены).
  final AttachmentStore? attachStore;

  /// Имя для стартового текста («Проект: <Имя> …»).
  final String title;
  final RemoteControl? rc;
  final GitService git;
  final ClaudeRunner claude;
  final StateRepo state;
  final AppStorage storage;

  /// Вызывается после каждого хода (обновить этап проекта).
  final Future<void> Function() onTurnDone;

  /// Расход хода (событие `result`).
  final void Function(String slug, TurnUsage usage)? onUsage;

  /// Claude сообщил о лимите до этого времени.
  final void Function(DateTime until)? onRateLimit;

  /// До какого времени действует лимит (null — лимита нет).
  final DateTime? Function()? limitUntil;

  /// Ход закончился успешно (для уведомления «директор ответил»).
  final void Function()? onReply;

  /// Отправка заблокирована лимитом Claude.
  bool get limitBlocked => limitUntil?.call() != null;

  static const _maxShown = 300;

  final List<ChatMessage> messages = [];
  bool preparing = true;
  String? blockedReason;
  String? warning;
  List<String> summary = [];
  bool summaryDismissed = false;
  bool working = false;

  /// Последний ход закончился успешно.
  bool lastTurnOk = false;

  /// Папка, в которой работает директор (основная или worktree проекта).
  String workDir = '';

  /// Открыт терминал Remote Control: чат закрыт.
  bool rcOpen = false;

  /// Недописанный текст в поле ввода (переживает переключение чатов).
  String draft = '';

  bool get office => slug == officeKey;

  /// Стартовый текст сессии: первое сообщение нового разговора.
  String startText(String task) =>
      office ? officeStartText(task) : projectStartText(title, slug, task);

  String get phoneText => startText(continueTask);

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
  String? _lastRaw;
  bool _disposed = false;

  /// Вложения, ожидающие отправки.
  final List<PendingAttachment> pending = [];

  /// Хоть один файл ещё копируется.
  bool get copying => pending.any((x) => x.state == PendingState.copying);

  List<PendingAttachment> get readyAttachments =>
      pending.where((x) => x.state == PendingState.ready).toList();

  bool get hasReadyAttachments => readyAttachments.isNotEmpty;

  int get _activeCount =>
      pending.where((x) => x.state != PendingState.error).length;

  /// Добавить файлы с диска (кнопка, перетаскивание, буфер).
  Future<void> addFiles(List<String> paths) async {
    final store = attachStore;
    if (store == null) return;
    for (final src in paths) {
      final item = PendingAttachment(src.split(RegExp(r'[\\/]')).last);
      _addPending(item);
      if (_activeCount > maxAttachments) {
        item
          ..state = PendingState.error
          ..error = 'больше $maxAttachments файлов';
        notifyListeners();
        continue;
      }
      try {
        item.file = await store.addFile(slug, src);
        item.state = PendingState.ready;
      } on AttachmentException catch (e) {
        _fail(item, e.message);
      } catch (_) {
        _fail(item, 'не удалось скопировать');
      }
      notifyListeners();
    }
  }

  /// Добавить картинку из буфера обмена.
  Future<void> addImageBytes(Uint8List bytes) async {
    final store = attachStore;
    if (store == null) return;
    final item = PendingAttachment('image.${imageExtension(bytes)}');
    _addPending(item);
    if (_activeCount > maxAttachments) {
      _fail(item, 'больше $maxAttachments файлов');
      notifyListeners();
      return;
    }
    try {
      item.file = await store.addBytes(slug, item.name, bytes);
      item.state = PendingState.ready;
    } on AttachmentException catch (e) {
      _fail(item, e.message);
    } catch (_) {
      _fail(item, 'не удалось сохранить');
    }
    notifyListeners();
  }

  void _addPending(PendingAttachment item) {
    pending.add(item);
    // Красных чипов не копим больше пяти.
    final errors = pending.where((x) => x.state == PendingState.error).toList();
    for (var i = 0; i < errors.length - 5; i++) {
      pending.remove(errors[i]);
    }
    notifyListeners();
  }

  void _fail(PendingAttachment item, String text) {
    item
      ..state = PendingState.error
      ..error = text;
  }

  void removePending(PendingAttachment item) {
    pending.remove(item);
    notifyListeners();
  }

  /// Папка вложений передаётся claude, если в чате были вложения.
  List<String> _addDirs() {
    final s = attachStore;
    if (s == null || !messages.any((m) => m.attachments.isNotEmpty)) {
      return const [];
    }
    return [s.dirFor(slug)];
  }

  bool get canSend =>
      !preparing && blockedReason == null && !working && !rcOpen;

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

  Future<void>? _opening;

  /// Завершится, когда чат открыт (история и папка готовы).
  Future<void> ready() => _opening ?? Future<void>.value();

  /// Загрузить историю и подготовить папку.
  Future<void> open() => _opening = _open();

  Future<void> _open() async {
    preparing = true;
    rcOpen = state.rcOpen(slug);
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
      final res = office
          ? await git.prepareOffice(lastSeenSha: seen)
          : await git.prepareProject(slug, lastSeenSha: seen);
      workDir = res.dir ?? workDir;
      blockedReason = res.blockedReason;
      if (res.warning != null) {
        warning = warning == null ? res.warning : '$warning\n${res.warning}';
      }
      if (res.blockedReason == null) {
        await _checkFolder();
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

  /// Сессия Claude привязана к папке: папка сменилась — разговор новый.
  Future<void> _checkFolder() async {
    final prev = state.worktree(slug);
    if (prev != null && p.equals(prev, workDir)) return;
    // Офис работает в основной папке: старых записей о ней нет — сессию не трогаем.
    if (prev == null && p.equals(workDir, git.repoPath)) {
      await _safe(() => state.setWorktree(slug, workDir));
      return;
    }
    final had = state.sessionId(slug) != null;
    await _safe(() => state.setWorktree(slug, workDir));
    if (had) {
      await _safe(() => state.setSessionId(slug, null));
      _add(ChatMessage(MsgKind.note, 'Новая папка — начинаю новый разговор'));
    }
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
      {bool approval = false,
      List<String> onceTools = const [],
      bool withAttachments = false}) async {
    final t = text.trim();
    if (!canSend || limitBlocked) return;
    if (withAttachments && copying) return;
    var files = <String>[];
    final store = attachStore;
    if (withAttachments && store != null) {
      final dir = store.dirFor(slug);
      files = readyAttachments
          .map((x) => x.file!.path)
          .where((f) => p.isWithin(dir, f))
          .toList();
    }
    if (t.isEmpty && files.isEmpty) return;
    if (withAttachments) pending.clear();
    if (approval) approvalHidden = true;
    _add(ChatMessage(MsgKind.user, t, attachments: files));
    final body = t.isEmpty ? 'Посмотри вложения.' : t;
    final raw = files.isEmpty ? body : '$body\n\n${attachmentsBlock(files)}';
    _lastRaw = raw;
    await _run(raw, onceTools);
  }

  /// Итоговый запрос по ТЕКУЩЕЙ сессии: в новом разговоре — со стартовым
  /// текстом, в существующем — без него. Сводка с телефона снимается только
  /// после успешного хода (см. _run).
  String _compose(String raw) {
    final fresh = state.sessionId(slug) == null;
    final base = fresh ? startText(raw) : raw;
    final prefix = _pendingPrefix;
    if (prefix == null) return base;
    return fresh ? '$base\n\n$prefix' : '$prefix\n\n$base';
  }

  Future<void> sendYes() => send('да', approval: true);

  Future<void> sendFix(String text) {
    final t = text.trim();
    if (t.isEmpty) return Future.value();
    return send('Поправить: $t', approval: true);
  }

  /// Повторить последний запрос после ошибки.
  Future<void> retry() async {
    final raw = _lastRaw;
    if (raw == null || !canSend || limitBlocked) return;
    messages.removeWhere((m) => m.kind == MsgKind.error);
    await _run(raw, const []);
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
    if (working || rcOpen) return;
    await _safe(() => state.setSessionId(slug, null));
    _pendingPrefix = null;
    _add(ChatMessage(MsgKind.note, 'Новый чат'));
  }

  /// Почему нельзя открыть терминал для телефона (null — можно).
  String? get rcDisabledReason {
    if (state.sessionId(slug) == null) {
      return 'Сначала напиши директору — пока нет разговора';
    }
    if (rcOpen) return 'Терминал уже открыт';
    if (working || preparing) return 'Дождись конца хода директора';
    if (blockedReason != null || workDir.isEmpty) return 'Чат закрыт';
    return null;
  }

  /// Открыть терминал с Remote Control. Вернёт текст ошибки или null.
  Future<String?> openRemoteControl() async {
    final why = rcDisabledReason;
    if (why != null) return why;
    final r = rc;
    if (r == null) return 'Remote Control недоступен';
    final err = await r.open(dir: workDir, sessionId: state.sessionId(slug));
    if (err != null) return err;
    rcOpen = true;
    await _safe(() => state.setRcOpen(slug, true));
    _add(ChatMessage(MsgKind.note,
        'Открыт терминал для телефона — чат в AI Studio закрыт, пока он открыт'));
    return null;
  }

  /// «Я закрыл терминал — вернуться»: разблокировать чат и подтянуть изменения.
  Future<void> returnFromRc() async {
    if (!rcOpen) return;
    rcOpen = false;
    await _safe(() => state.setRcOpen(slug, false));
    _add(ChatMessage(MsgKind.note, 'Терминал закрыт — чат снова работает'));
    await open();
  }

  /// Незакоммиченное и неотправленное в папке (для «Продолжить на телефоне»).
  Future<PendingWork> pendingWork() => workDir.isEmpty
      ? Future.value(const PendingWork(unknown: true))
      : git.pendingWork(workDir, slug);

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

  Future<void> _run(String raw, List<String> onceTools) async {
    working = true;
    _stopRequested = false;
    _canRetrySession = true;
    _runDone = Completer<void>();
    notifyListeners();
    var ok = false;
    try {
      ok = await _attempt(raw, onceTools);
      if (_sessionLost && !_stopRequested) {
        // «No conversation found»: сбросить сессию и повторить один раз.
        _canRetrySession = false;
        await _safe(() => state.setSessionId(slug, null));
        _add(ChatMessage(MsgKind.note,
            'Прежний разговор не найден — начинаю новый и повторяю запрос.'));
        ok = await _attempt(raw, onceTools);
      }
    } finally {
      _turn = null;
      working = false;
      lastTurnOk = ok;
      notifyListeners();
      if (ok) {
        try {
          onReply?.call();
        } catch (_) {}
        // Сводка ушла директору — только теперь двигаем «прочитано».
        _pendingPrefix = null;
        summaryDismissed = true;
        try {
          await state.setPendingSummary(slug, const []);
          final head = await git.headSha(dir: workDir);
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
  Future<bool> _attempt(String raw, List<String> onceTools) async {
    _turnShowedText = false;
    _resultSeen = false;
    _resultError = false;
    _sessionLost = false;
    _handleError = null;
    _streaming = null;
    try {
      final turn = await claude.start(
        prompt: _compose(raw),
        cwd: workDir,
        sessionId: state.sessionId(slug),
        extraTools: [...state.allowedTools(slug), ...onceTools],
        addDirs: _addDirs(),
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
            'Ошибка AI Studio при разборе ответа Claude: $_handleError. '
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
      case RateLimitEvent(resetsAt: final until):
        onRateLimit?.call(until);
      case ResultEvent r:
        _resultSeen = true;
        _closeStreaming();
        final usage = r.usage;
        if (usage != null) onUsage?.call(slug, usage);
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
