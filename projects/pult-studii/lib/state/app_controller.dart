import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/app_storage.dart';
import '../services/claude_runner.dart';
import '../services/gh_service.dart';
import '../services/git_service.dart';
import '../services/process_runner.dart';
import '../services/remote_control.dart';
import '../services/tools_check.dart';
import 'chat_controller.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.proc,
    required this.storage,
    required this.downloadsDir,
    this.homeDir = '',
    this.autoRefresh = const Duration(minutes: 3),
    RemoteControl? remote,
    Future<void> Function(String text)? copyText,
  })  : state = StateRepo(storage),
        rc = remote ?? RemoteControl(proc),
        _copy = copyText ?? _systemCopy,
        git = GitService(proc, storage),
        gh = GhService(proc),
        tools = ToolsCheck(proc, storage),
        claude = ClaudeRunner(proc);

  final ProcessRunner proc;
  final AppStorage storage;
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

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _boardTimer?.cancel();
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
  }

  void _autoRefreshBoard() {
    if (_disposed || boardLoading || git.repoPath.isEmpty || !setupOk) return;
    unawaited(refreshBoard());
  }

  /// Закрытие окна: остановить все процессы директоров.
  Future<void> stopAll() async {
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
    await recheck();
  }

  Future<void> refreshBoard() async {
    if (git.repoPath.isEmpty || boardLoading) return;
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
      builds[p.slug] = await gh.latestRun(r, p.slug);
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
    if (git.repoPath.isEmpty) return 'Папка ai-studio не выбрана.';
    if (_creatingProject) return 'Другой проект ещё создаётся.';
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
      final known = projects.map((p) => p.slug).toSet();
      await office.send('Новый проект: $n, тип: $type ($label). Идея: $i. '
          'Создай через /new-project, сессию проекта не запускай — '
          'Рубка откроет его сама.');
      while (boardLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await refreshBoard();
      final fresh = projects.where((p) => !known.contains(p.slug)).toList();
      if (fresh.isEmpty) {
        toast('Офис пока не создал проект — посмотри ответ в «Офисе».');
        return null;
      }
      final proj = fresh.firstWhere(
          (p) => p.name.toLowerCase() == n.toLowerCase(),
          orElse: () => fresh.first);
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
}
