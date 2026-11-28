import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as pth;

import '../models/models.dart';
import '../services/app_storage.dart';
import '../services/attachments.dart';
import '../services/rate_limit.dart';
import '../services/claude_runner.dart';
import '../services/gh_service.dart';
import '../services/git_service.dart';
import '../services/notifications.dart';
import '../services/process_runner.dart';
import '../services/project_docs.dart';
import '../services/remote_control.dart';
import '../services/tools_check.dart';
import '../services/updater.dart';
import '../services/usage.dart';
import 'chat_controller.dart';
import 'phone_share_controller.dart';

/// Состояние автообновления.
enum UpdateStatus { none, downloading, installing, error }

class AppController extends ChangeNotifier {
  AppController({
    required this.proc,
    required this.storage,
    required this.downloadsDir,
    this.homeDir = '',
    this.autoRefresh = const Duration(minutes: 3),
    RemoteControl? remote,
    Future<void> Function(String text)? copyText,
    this.updater,
    this.updateEvery = const Duration(hours: 6),
    this.build = buildNumber,
    this.notifier,
    this.isWindowFocused,
    this.showWindow,
    this.quitApp,
    this.attachments,
    DateTime Function()? clock,
  })  : state = StateRepo(storage),
        usage = UsageRepo(storage),
        _now = clock ?? DateTime.now,
        rc = remote ?? RemoteControl(proc),
        _copy = copyText ?? _systemCopy,
        git = GitService(proc, storage),
        gh = GhService(proc),
        tools = ToolsCheck(proc, storage),
        claude = ClaudeRunner(proc) {
    // Основную папку нельзя уводить с ветки Офиса, пока Офис работает.
    git.officeBusy = () {
      final c = chats[officeKey];
      return c != null && (c.working || c.preparing);
    };
  }

  final ProcessRunner proc;
  final AppStorage storage;

  /// Вложения чатов (null — выключены, например в тестах).
  final AttachmentStore? attachments;

  /// Документы проектов (docs/*.md).
  late final ProjectDocs docs = ProjectDocs(proc, storage);

  /// Идущая раздача APK на телефон (одна за раз).
  PhoneShareController? activeShare;

  /// Автообновление (null — выключено, например в тестах).
  final UpdateService? updater;
  final Duration? updateEvery;

  /// Номер этой сборки (0 — dev, обновление не предлагаем).
  final int build;

  /// Уведомления Windows (null — выключены).
  final AppNotifier? notifier;
  final Future<bool> Function()? isWindowFocused;
  final Future<void> Function()? showWindow;

  /// Закрыть программу после запуска установщика (stopAll уже сделан).
  final Future<void> Function()? quitApp;
  final DateTime Function() _now;
  final UsageRepo usage;
  final NotifyTracker _tracker = NotifyTracker();
  final String downloadsDir;

  /// Домашняя папка пользователя (для папки студии по умолчанию).
  final String homeDir;

  /// Как часто обновлять доску сама (null — не обновлять; для тестов).
  final Duration? autoRefresh;
  Timer? _boardTimer;
  final StateRepo state;
  final GitService git;
  final GhService gh;
  final ToolsCheck tools;
  final ClaudeRunner claude;
  final RemoteControl rc;
  final Future<void> Function(String text) _copy;

  static Future<void> _systemCopy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  final _toasts = StreamController<String>.broadcast();
  Stream<String> get toasts => _toasts.stream;

  bool starting = true;
  bool checking = false;
  bool _manualSetup = false;
  List<ToolStatus> setupItems = const [];
  bool get setupOk => setupItems.isNotEmpty && setupItems.every((t) => t.ok || !t.blocking);
  bool get showSetup => !starting && (!setupOk || _manualSetup);
  String? get repoPath => state.repoPath;

  List<Project> projects = const [];
  bool boardLoading = false;
  String? boardError;
  final Map<String, BuildRun> builds = {};

  /// Сколько коммитов с телефона на карточке (ключ — slug или officeKey).
  final Map<String, int> newCounts = {};
  final Set<String> downloading = {};

  /// Все открытые чаты (проекты и офис) работают параллельно.
  final Map<String, ChatController> chats = {};
  final Map<String, int> _busySig = {};
  String? activeKey;

  static const officeProject = Project(
      name: 'Офис студии',
      slug: officeKey,
      type: 'Офис',
      stage: 'ветка $officeKey',
      branch: officeKey,
      branchExists: true);

  ChatController? get chat => activeKey == null ? null : chats[activeKey];

  Project? get selected {
    final k = activeKey;
    if (k == null) return null;
    if (k == officeKey) return officeProject;
    for (final p in projects) {
      if (p.slug == k) return p;
    }
    return null;
  }

  /// Директор этого чата сейчас работает.
  bool isWorking(String key) => chats[key]?.working ?? false;

  bool get anyBusy =>
      chats.values.any((c) => c.working || c.preparing);

  bool _disposed = false;

  /// Отмена идущего входа в GitHub (ставит мастер настройки).
  Future<void> Function()? cancelLogin;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _boardTimer?.cancel();
    _updateTimer?.cancel();
    _limitTimer?.cancel();
    for (final c in chats.values) {
      c.dispose();
    }
    _toasts.close();
    super.dispose();
  }

  void toast(String m) {
    if (!_toasts.isClosed) _toasts.add(m);
  }

  Future<void> init() async {
    try {
      await state.load();
      try {
        await usage.load();
      } catch (_) {}
      try {
        await notifier?.init(openFromNotification);
      } catch (_) {}
      await git.setRepoPath(state.repoPath ?? '');
      await recheck();
    } catch (e) {
      toast('Не удалось проверить установку: $e');
    } finally {
      starting = false;
      notifyListeners();
    }
    final every = autoRefresh;
    if (every != null) {
      _boardTimer?.cancel();
      _boardTimer = Timer.periodic(every, (_) => _autoRefreshBoard());
    }
    final upd = updateEvery;
    if (updater != null && upd != null) {
      unawaited(checkUpdate());
      _updateTimer?.cancel();
      _updateTimer = Timer.periodic(upd, (_) => unawaited(checkUpdate()));
    }
  }

  // ---------- Автообновление ----------

  Timer? _updateTimer;
  UpdateInfo? update;
  UpdateStatus updateStatus = UpdateStatus.none;
  String? updateError;
  bool updateDismissed = false;

  /// Показывать ли плашку «Есть новая версия».
  bool get updateVisible =>
      update != null && (!updateDismissed || updateBusy || updateError != null);

  bool get updateBusy =>
      updateStatus == UpdateStatus.downloading ||
      updateStatus == UpdateStatus.installing;

  /// Спросить GitHub про свежую сборку (при запуске и раз в 6 ч).
  Future<void> checkUpdate() async {
    final u = updater;
    if (u == null || _disposed || build <= 0 || updateBusy) return;
    RepoRemote? remote;
    try {
      remote = await git.remote();
    } catch (_) {}
    if (remote == null) return;
    final info = await u.check(remote, build, cwd: git.repoPath);
    if (info == null || _disposed || updateBusy) return;
    update = info;
    updateDismissed = false;
    if (updateStatus == UpdateStatus.error) updateStatus = UpdateStatus.none;
    notifyListeners();
  }

  void dismissUpdate() {
    updateDismissed = true;
    updateError = null;
    if (updateStatus == UpdateStatus.error) updateStatus = UpdateStatus.none;
    notifyListeners();
  }

  /// «Обновить»: скачать установщик, запустить тихую установку, закрыться.
  Future<void> applyUpdate() async {
    final info = update;
    final u = updater;
    if (info == null || u == null || updateBusy) return;
    if (anyBusy) {
      updateStatus = UpdateStatus.error;
      updateError = 'Директор ещё работает. Дождись конца хода и повтори.';
      notifyListeners();
      return;
    }
    updateStatus = UpdateStatus.downloading;
    updateError = null;
    notifyListeners();
    try {
      final remote = await git.remote();
      if (remote == null) {
        throw UpdateException('не удалось определить репозиторий');
      }
      final exe = await u.download(remote, info, cwd: git.repoPath);
      updateStatus = UpdateStatus.installing;
      notifyListeners();
      await u.install(exe);
      await stopAll();
      await quitApp?.call();
    } catch (e) {
      updateStatus = UpdateStatus.error;
      updateError = '$e';
      notifyListeners();
    }
  }

  // ---------- Расходы и лимит ----------

  bool usageOpen = false;

  void toggleUsage([bool? open]) {
    usageOpen = open ?? !usageOpen;
    notifyListeners();
  }

  UsageSummary get usageSummary => usage.summary(_now());

  DateTime? limitUntil;
  Timer? _limitTimer;

  bool get limited {
    final u = limitUntil;
    return u != null && _now().isBefore(u);
  }

  /// Лимит, если он ещё действует.
  DateTime? get activeLimit => limited ? limitUntil : null;

  void setLimit(DateTime until) {
    final now = _now();
    if (saneLimitUntil(until, now) == null) return;
    limitUntil = until;
    _limitTimer?.cancel();
    _limitTimer = Timer(until.difference(now) + const Duration(seconds: 1), () {
      limitUntil = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// «Всё равно отправить»: снять ожидание (если лимит ещё есть, Claude ответит снова).
  void clearLimit() {
    limitUntil = null;
    _limitTimer?.cancel();
    notifyListeners();
  }

  void _recordUsage(String key, TurnUsage u) {
    unawaited(usage.record(key, u, _now()).catchError((Object _) {}));
    notifyListeners();
  }

  // ---------- Уведомления ----------

  Future<void> _emit(NotifyKind kind, String slug, {String stage = ''}) async {
    final n = notifier;
    if (n == null || _disposed || !state.notifyEnabled(kind)) return;
    if (kind == NotifyKind.directorReply) {
      var focused = false;
      try {
        focused = await (isWindowFocused?.call() ?? Future.value(false));
      } catch (_) {}
      if (focused) return;
    }
    var name = slug;
    if (slug == officeKey) {
      name = officeProject.name;
    } else {
      for (final p in projects) {
        if (p.slug == slug) name = p.name;
      }
    }
    try {
      await n.show(
          title: notifyTitle,
          body: notifyBody(kind, name, stage: stage),
          key: slug);
    } catch (_) {}
  }

  void _checkWaits() {
    for (final p in _tracker.newlyWaiting(projects)) {
      unawaited(_emit(NotifyKind.waitsYes, p.slug, stage: p.stage));
    }
  }

  void _checkBuild(String slug, BuildRun run) {
    final s = _tracker.buildChanged(slug, run);
    if (s == BuildState.success) {
      unawaited(_emit(NotifyKind.buildOk, slug));
    } else if (s == BuildState.failed) {
      unawaited(_emit(NotifyKind.buildFailed, slug));
    }
  }

  /// Клик по уведомлению: показать окно и открыть чат.
  Future<void> openFromNotification(String key) async {
    try {
      await showWindow?.call();
    } catch (_) {}
    if (_disposed) return;
    if (key == officeKey) {
      openOffice();
      return;
    }
    for (final p in projects) {
      if (p.slug == key) {
        select(p);
        return;
      }
    }
  }

  Future<void> setNotifyEnabled(NotifyKind k, bool on) async {
    try {
      await state.setNotifyEnabled(k, on);
    } catch (_) {}
    notifyListeners();
  }

  void _autoRefreshBoard() {
    if (_disposed || boardLoading || git.repoPath.isEmpty || !setupOk) return;
    unawaited(refreshBoard());
  }

  /// Закрытие окна: остановить все процессы директоров.
  Future<void> stopAll() async {
    try {
      await cancelLogin?.call();
    } catch (_) {}
    try {
      await activeShare?.stop();
    } catch (_) {}
    await Future.wait(chats.values.map((c) async {
      try {
        await c.stop();
      } catch (_) {}
    }));
  }

  Future<void> recheck() async {
    checking = true;
    notifyListeners();
    try {
      await proc.refreshEnvironment();
      setupItems = await tools.check(state.repoPath);
    } finally {
      checking = false;
      notifyListeners();
    }
    if (setupOk && projects.isEmpty && !boardLoading) {
      unawaited(refreshBoard());
    }
  }

  void openSetup() {
    _manualSetup = true;
    notifyListeners();
  }

  void closeSetup() {
    _manualSetup = false;
    notifyListeners();
  }

  Future<void> setRepoPath(String path) async {
    final p = path.trim();
    if (anyBusy) {
      toast('Дождись ответа директоров, потом меняй папку.');
      return;
    }
    await state.setRepoPath(p);
    await git.setRepoPath(p);
    for (final c in chats.values) {
      c.dispose();
    }
    chats.clear();
    _busySig.clear();
    activeKey = null;
    projects = const [];
    builds.clear();
    newCounts.clear();
    _tracker.reset();
    await recheck();
  }

  Future<void>? _refreshing;

  /// Обновить доску. Уже идёт обновление — вернёт его Future (дождаться конца).
  Future<void> refreshBoard() {
    if (git.repoPath.isEmpty) return Future.value();
    return _refreshing ??=
        _refreshBoard().whenComplete(() => _refreshing = null);
  }

  Future<void> _refreshBoard() async {
    boardLoading = true;
    boardError = null;
    notifyListeners();
    try {
      final res = await git.loadProjects();
      projects = res.projects;
      boardError = res.fetchError;
    } catch (e) {
      boardError = '$e';
    }
    newCounts.clear();
    final keys = [
      officeKey,
      for (final p in projects)
        if (p.branchExists) p.slug,
    ];
    for (final k in keys) {
      final seen = state.lastSeenSha(k);
      if (seen == null || k == activeKey) continue;
      try {
        final n = await git.newCommitCount(k, seen);
        if (n > 0) newCounts[k] = n;
      } catch (_) {}
    }
    for (final k in chats.keys.toList()) {
      try {
        await refreshStageGuarded(k);
      } catch (_) {}
    }
    _checkWaits();
    boardLoading = false;
    notifyListeners();
    unawaited(_loadBuilds());
  }

  Future<void> _loadBuilds() async {
    RepoRemote? remote;
    try {
      remote = await git.remote();
    } catch (_) {}
    final list = projects.toList();
    for (final p in list) {
      builds[p.slug] = remote == null ? BuildRun.unknown : BuildRun.loading;
    }
    notifyListeners();
    if (remote == null) return;
    final r = remote;
    await Future.wait(list.map((p) async {
      final run = await gh.latestRun(r, p.slug);
      builds[p.slug] = run;
      _checkBuild(p.slug, run);
      notifyListeners();
    }));
  }

  /// Этап из папки проекта — только если там ветка этого проекта
  /// и чат открыт (иначе README в папке чужой).
  Future<void> refreshStageGuarded(String? slug) async {
    final c = slug == null ? null : chats[slug];
    if (slug == null || slug == officeKey || c == null) return;
    if (c.blockedReason != null || c.preparing || c.workDir.isEmpty) return;
    if (await git.currentBranch(dir: c.workDir) != slug) return;
    await refreshStage(slug);
  }

  /// Этап проекта из его папки (свежее, чем origin).
  Future<void> refreshStage(String slug) async {
    final dir = chats[slug]?.workDir;
    final stage = await git.localStage(slug, dir: dir);
    if (stage == null) return;
    projects = [for (final p in projects) p.slug == slug ? p.withStage(stage) : p];
    if (!boardLoading) _checkWaits();
    notifyListeners();
  }

  ChatController _create(String key, String title) {
    final c = ChatController(
      slug: key,
      title: title,
      rc: rc,
      git: git,
      claude: claude,
      state: state,
      storage: storage,
      onTurnDone: () => refreshStageGuarded(key),
      onUsage: _recordUsage,
      onRateLimit: setLimit,
      limitUntil: () => activeLimit,
      onReply: () => unawaited(_emit(NotifyKind.directorReply, key)),
      attachStore: attachments,
    );
    int sig() =>
        (c.working ? 1 : 0) + (c.preparing ? 2 : 0) + (c.rcOpen ? 4 : 0);
    _busySig[key] = sig();
    c.addListener(() {
      final n = sig();
      if (_busySig[key] != n) {
        _busySig[key] = n;
        notifyListeners();
      }
    });
    chats[key] = c;
    unawaited(c.open());
    return c;
  }

  /// Открыть чат проекта (своя папка, свой процесс). Переключение
  /// никогда не блокируется: другие чаты продолжают работать.
  /// Вернёт текст отказа или null.
  String? select(Project p) {
    if (!isSafeSlug(p.slug)) return 'Недопустимое имя проекта.';
    if (chats[p.slug] == null) _create(p.slug, p.name);
    activeKey = p.slug;
    newCounts.remove(p.slug);
    notifyListeners();
    return null;
  }

  /// Вкладка «Офис»: основная папка, ветка ai-office.
  void openOffice() {
    if (chats[officeKey] == null) _create(officeKey, officeProject.name);
    activeKey = officeKey;
    newCounts.remove(officeKey);
    notifyListeners();
  }

  /// «Продолжить на телефоне»: копирует стартовый текст. Есть незапушенное —
  /// вернёт описание (UI предложит «Закоммить и запушь всё»), текст не копируется,
  /// пока не вызвано с [force].
  Future<PendingWork?> continueOnPhone(ChatController c,
      {bool force = false}) async {
    if (c.preparing || c.blockedReason != null || c.workDir.isEmpty) {
      toast('Чат ещё не открыт — подожди пару секунд.');
      return null;
    }
    if (c.working) {
      toast('Дождись ответа директора и повтори.');
      return null;
    }
    if (!force) {
      final w = await c.pendingWork();
      if (!w.clean) return w;
    }
    await _copy(c.phoneText);
    toast('Скопировано — вставь в новую сессию Claude Code на телефоне');
    return null;
  }

  bool _creatingProject = false;

  /// «+ Новый проект»: просим Офис создать проект, потом открываем его чат.
  /// Вернёт текст ошибки или null.
  Future<String?> startNewProject(
      {required String name, required String type, required String idea}) async {
    final n = name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
    final i = idea.trim();
    final label = newProjectTypes[type];
    if (n.isEmpty || n.length > 80) return 'Имя проекта: от 1 до 80 символов.';
    if (label == null) return 'Выбери тип проекта.';
    if (i.isEmpty) return 'Напиши идею проекта.';
    if (i.length > 2000) return 'Идея слишком длинная: не больше 2000 символов.';
    if (git.repoPath.isEmpty) return 'Папка ai-studio не выбрана.';
    if (_creatingProject) return 'Другой проект ещё создаётся.';
    final expected = projectSlug(n);
    if (expected.isEmpty) {
      return 'Из имени не получился адрес проекта. Используй буквы или цифры.';
    }
    _creatingProject = true;
    try {
      openOffice();
      final office = chats[officeKey]!;
      await office.ready();
      if (!office.canSend) {
        return office.blockedReason != null
            ? 'Офис не открыт: ${office.blockedReason}'
            : 'Офис сейчас занят. Дождись ответа и повтори.';
      }
      // Доска должна быть загружена: иначе «уже известные» проекты неизвестны.
      await refreshBoard();
      if (boardError != null) {
        return 'Доска проектов не обновилась (${boardError!}). '
            'Проверь интернет и повтори.';
      }
      final known = projects.map((p) => p.slug).toSet();
      if (known.contains(expected)) {
        return 'Проект «$expected» уже есть. Выбери другое имя.';
      }
      office.lastTurnOk = false;
      await office.send('Новый проект: $n, тип: $type ($label). Идея: $i. '
          'Создай через /new-project, сессию проекта не запускай — '
          'AI Studio откроет его. Потом запушь ветку $expected '
          '(git push -u origin $expected).');
      if (!office.lastTurnOk) {
        toast('Офис не закончил ход — проект не открываю. '
            'Посмотри ответ в «Офисе».');
        return null;
      }
      await refreshBoard();
      final fresh = projects
          .where((p) =>
              !known.contains(p.slug) &&
              (p.slug == expected ||
                  p.name.toLowerCase() == n.toLowerCase()))
          .toList();
      if (fresh.isEmpty) {
        toast('Офис пока не создал проект «$expected» — '
            'посмотри ответ в «Офисе».');
        return null;
      }
      // Сначала точный slug, потом совпадение имени (fresh уже отфильтрован).
      final proj = [
        ...fresh.where((p) => p.slug == expected),
        ...fresh,
      ].first;
      final c = chats[proj.slug] ?? _create(proj.slug, proj.name);
      activeKey = proj.slug;
      newCounts.remove(proj.slug);
      notifyListeners();
      await c.ready();
      await c.send(
          'Начни с этапа Бриф: задай мне 1–2 вопроса. О проекте: $i');
      return null;
    } finally {
      _creatingProject = false;
    }
  }

  Future<void> download(Project p) async {
    final run = builds[p.slug];
    final id = run?.id;
    if (id == null || downloading.contains(p.slug)) return;
    downloading.add(p.slug);
    notifyListeners();
    try {
      final remote = await git.remote();
      if (remote == null) throw GitException('не удалось определить репозиторий');
      final dir = await gh.download(remote, id, p.slug, downloadsDir,
          cwd: git.repoPath);
      await gh.openFolder(dir);
      toast('Скачано: $dir');
    } catch (e) {
      toast('Не удалось скачать: $e');
    } finally {
      downloading.remove(p.slug);
      notifyListeners();
    }
  }

  void openLink(String? href) {
    final host = safeHttpsHost(href);
    if (host == null) {
      toast('Ссылка не открыта: разрешены только https-ссылки.');
      return;
    }
    toast('Открываю: $host');
    unawaited(gh.openUrl(href!));
  }

  /// Документы проекта для окна «Документы».
  Future<List<DocEntry>> loadDocs(ChatController c) => docs.load(
      slug: c.slug, repoPath: git.repoPath, workDir: c.workDir);

  /// Открыть вложение: безопасный тип — самим файлом, остальное — папкой
  /// (чтобы случайно не запустить программу).
  Future<void> openAttachment(String path) async {
    final store = attachments;
    if (store == null || !pth.isWithin(store.root, path)) return;
    try {
      await proc.run(
          explorerPath(), [isOpenableAttachment(path) ? path : pth.dirname(path)]);
    } catch (_) {
      toast('Не удалось открыть файл.');
    }
  }

  /// «На телефон»: скачать APK последней успешной сборки и раздать.
  /// null — раздавать нечего.
  PhoneShareController? startPhoneShare(Project pr) {
    final run = builds[pr.slug];
    final id = run?.id;
    if (!isSafeSlug(pr.slug) || id == null || run?.state != BuildState.success) {
      return null;
    }
    unawaited(activeShare?.stop());
    final share = PhoneShareController(
      slug: pr.slug,
      downloadTo: (dir) async {
        final remote = await git.remote();
        if (remote == null) {
          throw GitException('не удалось определить репозиторий');
        }
        // качаем только артефакт с APK, а не всю сборку
        final name = await gh.apkArtifactName(remote, id, cwd: git.repoPath);
        await gh.downloadInto(remote, id, dir,
            cwd: git.repoPath, artifact: name);
      },
    );
    activeShare = share;
    unawaited(share.start());
    return share;
  }
}
