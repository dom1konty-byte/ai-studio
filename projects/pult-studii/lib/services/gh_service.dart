import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/models.dart';
import 'git_service.dart';
import 'process_runner.dart';

class GhService {
  GhService(this._proc);

  final ProcessRunner _proc;

  /// Последняя сборка workflow `<slug>.yml` в ветке `<slug>`.
  /// Нет workflow / нет запусков → [BuildRun.none]. Ошибка gh → [BuildRun.unknown].
  Future<BuildRun> latestRun(RepoRemote r, String slug) async {
    if (!isSafeSlug(slug)) return BuildRun.none;
    final res = await _proc.run('gh', [
      'api',
      'repos/${r.owner}/${r.repo}/actions/workflows/$slug.yml/runs?branch=$slug&per_page=1',
    ]);
    if (!res.ok) {
      final all = '${res.stdout}${res.stderr}';
      return all.contains('404') || all.contains('Not Found')
          ? BuildRun.none
          : BuildRun.unknown;
    }
    return parseLatestRun(res.stdout);
  }

  /// Скачать артефакты запуска в `<downloads>\<slug>\<runId>`; вернуть папку.
  Future<String> download(
      RepoRemote r, int runId, String slug, String downloadsDir,
      {String? cwd}) async {
    if (!isSafeSlug(slug)) throw GitException('Недопустимое имя проекта: $slug');
    final dir = p.join(downloadsDir, slug, '$runId');
    await downloadInto(r, runId, dir, cwd: cwd);
    return dir;
  }

  /// Скачать артефакты запуска прямо в папку [dir].
  Future<void> downloadInto(RepoRemote r, int runId, String dir,
      {String? cwd}) async {
    if (!_repoPartRe.hasMatch(r.owner) || !_repoPartRe.hasMatch(r.repo)) {
      throw GitException('Недопустимый адрес репозитория.');
    }
    final res = await _proc.run(
        'gh', ['run', 'download', '$runId', '-R', '${r.owner}/${r.repo}', '-D', dir],
        cwd: cwd, timeout: const Duration(minutes: 10));
    if (!res.ok) {
      final t = res.stderr.trim().isNotEmpty ? res.stderr.trim() : res.stdout.trim();
      throw GitException('gh run download: $t');
    }
  }

  Future<void> openFolder(String dir) => _proc.run(explorerPath(), [dir]);

  /// Открыть https-ссылку в браузере без оболочки (rundll32).
  Future<void> openUrl(String url) =>
      _proc.run(sys32('rundll32.exe'), ['url.dll,FileProtocolHandler', url]);
}

final _repoPartRe = RegExp(r'^[A-Za-z0-9._-]+$');

/// Домен, если ссылка безопасна для открытия (https, есть host, без
/// пробелов, кавычек и управляющих символов); иначе null.
String? safeHttpsHost(String? href) {
  if (href == null || href.isEmpty) return null;
  if (RegExp(r'''[\s"'`<>^|\\\x00-\x1f\x7f]''').hasMatch(href)) return null;
  final u = Uri.tryParse(href);
  if (u == null || u.scheme != 'https' || u.host.isEmpty) return null;
  return u.host;
}

BuildRun parseLatestRun(String json) {
  try {
    final j = jsonDecode(json);
    final runs = j is Map ? j['workflow_runs'] : null;
    if (runs is List && runs.isNotEmpty && runs.first is Map) {
      return BuildRun.fromApi(Map<String, dynamic>.from(runs.first as Map));
    }
    return BuildRun.none;
  } catch (_) {
    return BuildRun.unknown;
  }
}
