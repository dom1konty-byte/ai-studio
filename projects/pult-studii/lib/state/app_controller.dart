import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/app_storage.dart';
import '../services/claude_runner.dart';
import '../services/gh_service.dart';
import '../services/git_service.dart';
import '../services/process_runner.dart';
import '../services/tools_check.dart';
import 'chat_controller.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.proc,
    required this.storage,
    required this.downloadsDir,
  })  : state = StateRepo(storage),
        git = GitService(proc, storage),
        gh = GhService(proc),
        tools = ToolsCheck(proc, storage),
        claude = ClaudeRunner(proc);

  final ProcessRunner proc;
  final AppStorage storage;
  final String downloadsDir;
  final StateRepo state;
  final GitService git;
  final GhService gh;
  final ToolsCheck tools;
  final ClaudeRunner claude;

  final _toasts = StreamController<String>.broadcast();
  Stream<String> get toasts => _toasts.stream;

  bool starting = true;
  bool checking = false;
  bool _manualSetup = false;
  List<ToolStatus> setupItems = const [];
  bool get setupOk => setupItems.isNotEmpty && setupItems.every((t) => t.ok);
  bool get showSetup => !starting && (!setupOk || _manualSetup);
  String? get repoPath => state.repoPath;

  List<Project> projects = const [];
  bool boardLoading = false;
  String? boardError;
  final Map<String, BuildRun> builds = {};
  final Set<String> newMarks = {};
  final Set<String> downloading = {};

  ChatController? chat;
  Project? get selected {
    final c = chat;
    if (c == null) return null;
    for (final p in projects) {
      if (p.slug == c.slug) return p;
    }
    return null;
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    chat?.dispose();
    _toasts.close();
    super.dispose();
  }

  void toast(String m) {
    if (!_toasts.isClosed) _toasts.add(m);
  }

  Future<void> init() async {
    await state.load();
    git.repoPath = state.repoPath ?? '';
    await recheck();
    starting = false;
    notifyListeners();
  }

  Future<void> recheck() async {
    checking = true;
    notifyListeners();
    setupItems = await tools.check(state.repoPath);
    checking = false;
    notifyListeners();
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
    if (chat?.working ?? false) {
      toast('Дождись ответа директора, потом меняй папку.');
      return;
    }
    await state.setRepoPath(p);
    git.repoPath = p;
    chat?.dispose();
    chat = null;
    projects = const [];
    builds.clear();
    newMarks.clear();
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
    newMarks.clear();
    for (final p in projects) {
      final seen = state.lastSeenSha(p.slug);
      if (seen != null && p.branchExists) {
        try {
          if (await git.newCommitCount(p.slug, seen) > 0) newMarks.add(p.slug);
        } catch (_) {}
      }
    }
    final c = chat;
    if (c != null) await refreshStage(c.slug);
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

  /// Этап проекта из рабочей папки (свежее, чем origin).
  Future<void> refreshStage(String slug) async {
    final stage = await git.localStage(slug);
    if (stage == null) return;
    projects = [for (final p in projects) p.slug == slug ? p.withStage(stage) : p];
    notifyListeners();
  }

  /// Открыть чат проекта. Вернёт текст отказа, если открыть нельзя.
  String? select(Project p) {
    final cur = chat;
    if (cur != null && cur.slug == p.slug) return null;
    if (cur != null && cur.working) {
      return 'Директор ещё работает в «${selected?.name ?? cur.slug}». '
          'Дождись ответа и потом переключайся.';
    }
    cur?.dispose();
    final c = ChatController(
      slug: p.slug,
      git: git,
      claude: claude,
      state: state,
      storage: storage,
      onTurnDone: () => refreshStage(p.slug),
    );
    chat = c;
    newMarks.remove(p.slug);
    notifyListeners();
    unawaited(c.open());
    return null;
  }

  Future<void> download(Project p) async {
    final run = builds[p.slug];
    final id = run?.id;
    if (id == null || downloading.contains(p.slug)) return;
    downloading.add(p.slug);
    notifyListeners();
    try {
      final dir = await gh.download(id, p.slug, downloadsDir);
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
    if (href != null && RegExp(r'^https?://').hasMatch(href)) {
      unawaited(gh.openUrl(href));
    }
  }
}
