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
  Future<String> download(int runId, String slug, String downloadsDir) async {
    final dir = p.join(downloadsDir, slug, '$runId');
    final res = await _proc.run('gh', ['run', 'download', '$runId', '-D', dir]);
    if (!res.ok) {
      final t = res.stderr.trim().isNotEmpty ? res.stderr.trim() : res.stdout.trim();
      throw GitException('gh run download: $t');
    }
    return dir;
  }

  Future<void> openFolder(String dir) => _proc.run('explorer', [dir]);

  Future<void> openUrl(String url) => _proc.run('explorer', [url]);
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
