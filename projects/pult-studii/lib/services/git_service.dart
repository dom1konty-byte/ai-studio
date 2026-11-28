import 'package:path/path.dart' as p;

import '../models/models.dart';
import 'app_storage.dart';
import 'process_runner.dart';
import 'readme_parser.dart';

class GitException implements Exception {
  GitException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BoardResult {
  const BoardResult(this.projects, this.fetchError);
  final List<Project> projects;
  final String? fetchError;
}

class PrepareResult {
  const PrepareResult({
    this.blockedReason,
    this.warning,
    this.newCommits = const [],
    this.originSha,
  });

  /// Не удалось переключить ветку — чат закрыт.
  final String? blockedReason;

  /// Предупреждение (чат работает).
  final String? warning;

  /// Строки «sha дата сообщение» — сделано с телефона.
  final List<String> newCommits;
  final String? originSha;
}

class RepoRemote {
  const RepoRemote(this.owner, this.repo);
  final String owner;
  final String repo;
}

final _slugRe = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
bool isSafeSlug(String s) => _slugRe.hasMatch(s);

const _skipBranches = {'main', 'ai-office', 'HEAD', 'origin'};

List<String> parseCommitLog(String out) =>
    out.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

/// Текст, который добавляется к первому сообщению после перерыва.
String phoneSummaryPrompt(List<String> commits) =>
    'С телефона сделаны коммиты, продолжай с учётом них:\n${commits.join('\n')}';

/// owner/repo из `git remote get-url origin` (https, ssh и локальный прокси).
RepoRemote? parseRemote(String url) {
  final m = RegExp(r'[/:]([^/:]+)/([^/]+?)(?:\.git)?/?$').firstMatch(url.trim());
  if (m == null) return null;
  return RepoRemote(m.group(1)!, m.group(2)!);
}

class GitService {
  GitService(this._proc, this._storage);

  final ProcessRunner _proc;
  final AppStorage _storage;
  String repoPath = '';

  Future<ProcResult> _git(List<String> args) {
    if (repoPath.isEmpty) throw GitException('Папка ai-studio не выбрана.');
    return _proc.run('git', args, cwd: repoPath);
  }

  String _err(ProcResult r) {
    final t = r.stderr.trim().isNotEmpty ? r.stderr.trim() : r.stdout.trim();
    return t.isEmpty ? 'git завершился с кодом ${r.exitCode}' : t;
  }

  Future<RepoRemote?> remote() async {
    final r = await _git(['remote', 'get-url', 'origin']);
    return r.ok ? parseRemote(r.stdout) : null;
  }

  /// Порт scripts/status.py: README из main и из каждой ветки проекта.
  Future<BoardResult> loadProjects() async {
    String? fetchError;
    final f = await _git(['fetch', '--prune', 'origin']);
    if (!f.ok) fetchError = _err(f);

    final br = await _git(['branch', '-r', '--format=%(refname:short)']);
    if (!br.ok) throw GitException(_err(br));
    final branches = br.stdout
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((b) => b.startsWith('origin/') ? b.substring(7) : b)
        .where((b) =>
            !_skipBranches.contains(b) &&
            !b.startsWith('claude/') &&
            !b.contains('/'))
        .toList();

    var mainText = '';
    final m = await _git(['show', 'origin/main:projects/README.md']);
    if (m.ok) {
      mainText = m.stdout;
    } else {
      mainText =
          await _storage.readText(p.join(repoPath, 'projects', 'README.md')) ??
              '';
    }
    final texts = await Future.wait(branches.map((b) async {
      final r = await _git(['show', 'origin/$b:projects/README.md']);
      return r.ok ? r.stdout : '';
    }));

    final remote = branches.toSet();
    final projects = <String, Project>{};
    void add(String src, String text) {
      for (final r in parseReadmeRows(text)) {
        if (src == 'main') {
          if (projects.containsKey(r.slug)) continue;
        } else if (r.slug != src) {
          continue; // в ветке проекта верим только строке этого проекта
        }
        projects[r.slug] = Project(
          name: r.name,
          slug: r.slug,
          type: r.type,
          stage: r.stage,
          branch: r.branch,
          branchExists: remote.contains(r.branch),
        );
      }
    }

    add('main', mainText);
    for (var i = 0; i < branches.length; i++) {
      add(branches[i], texts[i]);
    }
    return BoardResult(projects.values.toList(), fetchError);
  }

  /// Этап проекта из README в рабочей папке (там свежее).
  Future<String?> localStage(String slug) async {
    final t = await _storage.readText(p.join(repoPath, 'projects', 'README.md'));
    if (t == null) return null;
    for (final r in parseReadmeRows(t)) {
      if (r.slug == slug) return r.stage;
    }
    return null;
  }

  Future<String?> originSha(String slug) async {
    if (!isSafeSlug(slug)) return null;
    final r = await _git(['rev-parse', '--verify', '--quiet', 'origin/$slug']);
    final s = r.stdout.trim();
    return r.ok && s.isNotEmpty ? s : null;
  }

  Future<String?> headSha() async {
    final r = await _git(['rev-parse', 'HEAD']);
    final s = r.stdout.trim();
    return r.ok && s.isNotEmpty ? s : null;
  }

  Future<List<String>> commitsSince(String lastSeen, String slug) async {
    if (!isSafeSlug(slug) || !RegExp(r'^[0-9a-fA-F]{4,64}$').hasMatch(lastSeen)) {
      return [];
    }
    final r = await _git(
        ['log', '--format=%h %cs %s', '$lastSeen..origin/$slug']);
    return r.ok ? parseCommitLog(r.stdout) : [];
  }

  /// Открытие чата проекта: fetch, проверка правок, checkout, pull --ff-only.
  Future<PrepareResult> prepare(String slug, {String? lastSeenSha}) async {
    if (!isSafeSlug(slug)) {
      return PrepareResult(blockedReason: 'Недопустимое имя ветки: $slug');
    }
    final f = await _git(['fetch', 'origin']);
    String? warning;
    if (!f.ok) warning = 'Не удалось обновить из GitHub: ${_err(f)}';

    final st = await _git(['status', '--porcelain']);
    if (!st.ok) throw GitException(_err(st));
    final dirty = st.stdout.trim().isNotEmpty;

    final cur = (await _git(['branch', '--show-current'])).stdout.trim();
    final origin = await originSha(slug);

    if (cur != slug) {
      if (dirty) {
        return const PrepareResult(
            blockedReason:
                'В папке ai-studio есть незакоммиченные правки, ветку не переключаю. '
                'Сохрани или убери их, потом открой проект снова.');
      }
      final local =
          await _git(['rev-parse', '--verify', '--quiet', 'refs/heads/$slug']);
      final ProcResult co;
      if (local.ok) {
        co = await _git(['checkout', slug]);
      } else if (origin != null) {
        co = await _git(['checkout', '-b', slug, 'origin/$slug']);
      } else {
        return PrepareResult(
            blockedReason: 'Ветки $slug нет ни на компьютере, ни на GitHub.');
      }
      if (!co.ok) {
        return PrepareResult(blockedReason: 'Не удалось переключить ветку: ${_err(co)}');
      }
    }

    if (dirty) {
      warning = 'В папке есть незакоммиченные правки — обновление (pull) пропущено.';
    } else {
      final pull = await _git(['pull', '--ff-only']);
      if (!pull.ok) warning = 'git pull --ff-only не удался: ${_err(pull)}';
    }

    var commits = <String>[];
    if (lastSeenSha != null && origin != null && lastSeenSha != origin) {
      commits = await commitsSince(lastSeenSha, slug);
    }
    return PrepareResult(warning: warning, newCommits: commits, originSha: origin);
  }

  /// Число коммитов с телефона для значка «новое».
  Future<int> newCommitCount(String slug, String lastSeen) async =>
      (await commitsSince(lastSeen, slug)).length;
}
