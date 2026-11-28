import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/models.dart';
import 'git_service.dart';
import 'process_runner.dart';

class GhService {
  GhService(this._proc);

  final ProcessRunner _proc;

  /// Последняя сборка workflow `<slug>.yml` в ветке `<slug>`: только push
  /// (и workflow_dispatch) из самого репозитория, без запросов на слияние.
  /// Нет workflow / нет запусков → [BuildRun.none]. Ошибка gh → [BuildRun.unknown].
  Future<BuildRun> latestRun(RepoRemote r, String slug) async {
    if (!isSafeSlug(slug)) return BuildRun.none;
    final res = await _proc.run('gh', [
      'api',
      'repos/${r.owner}/${r.repo}/actions/workflows/$slug.yml/runs?branch=$slug&event=push&exclude_pull_requests=true&per_page=5',
    ]);
    if (!res.ok) {
      final all = '${res.stdout}${res.stderr}';
      return all.contains('404') || all.contains('Not Found')
          ? BuildRun.none
          : BuildRun.unknown;
    }
    return parseLatestRun(res.stdout, '${r.owner}/${r.repo}');
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

  /// Имя артефакта с APK в запуске [runId]: имя с «apk», иначе первый
  /// неустаревший. Не нашли или ошибка gh — null (тогда качаем всё).
  Future<String?> apkArtifactName(RepoRemote r, int runId, {String? cwd}) async {
    if (!_repoPartRe.hasMatch(r.owner) || !_repoPartRe.hasMatch(r.repo)) {
      return null;
    }
    try {
      final res = await _proc.run(
          'gh', ['api', 'repos/${r.owner}/${r.repo}/actions/runs/$runId/artifacts'],
          cwd: cwd);
      if (!res.ok) return null;
      return pickApkArtifact(res.stdout);
    } catch (_) {
      return null;
    }
  }

  /// Скачать артефакты запуска прямо в папку [dir]
  /// (только артефакт [artifact], если имя задано).
  Future<void> downloadInto(RepoRemote r, int runId, String dir,
      {String? cwd, String? artifact}) async {
    if (!_repoPartRe.hasMatch(r.owner) || !_repoPartRe.hasMatch(r.repo)) {
      throw GitException('Недопустимый адрес репозитория.');
    }
    if (artifact != null && !_artifactRe.hasMatch(artifact)) {
      throw GitException('Недопустимое имя артефакта.');
    }
    final res = await _proc.run(
        'gh',
        [
          'run',
          'download',
          '$runId',
          '-R',
          '${r.owner}/${r.repo}',
          if (artifact != null) ...['-n', artifact],
          '-D',
          dir,
        ],
        cwd: cwd,
        timeout: const Duration(minutes: 10));
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
final _artifactRe = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

/// Из ответа `actions/runs/<id>/artifacts`: имя артефакта с «apk»,
/// иначе первое безопасное имя. Нет подходящих — null.
String? pickApkArtifact(String json) {
  try {
    final j = jsonDecode(json);
    final list = j is Map ? j['artifacts'] : null;
    if (list is! List) return null;
    final names = <String>[];
    for (final a in list) {
      if (a is! Map || a['expired'] == true) continue;
      final n = a['name'];
      if (n is String && _artifactRe.hasMatch(n)) names.add(n);
    }
    if (names.isEmpty) return null;
    return names.firstWhere((n) => n.toLowerCase().contains('apk'),
        orElse: () => names.first);
  } catch (_) {
    return null;
  }
}

/// События, сборкам которых доверяем (не pull_request).
const trustedRunEvents = {'push', 'workflow_dispatch'};

/// Запуск можно показывать и раздавать: событие push / workflow_dispatch,
/// код из самого репозитория [repoFullName] (`owner/repo`), не из форка,
/// и без привязанных запросов на слияние.
bool isTrustedRun(Map<dynamic, dynamic> run, String repoFullName) {
  if (!trustedRunEvents.contains(run['event'])) return false;
  final head = run['head_repository'];
  final name = head is Map ? head['full_name'] : null;
  if (name is! String || name.toLowerCase() != repoFullName.toLowerCase()) {
    return false;
  }
  final prs = run['pull_requests'];
  if (prs is List && prs.isNotEmpty) return false;
  return true;
}

/// Домен, если ссылка безопасна для открытия (https, есть host, без
/// пробелов, кавычек и управляющих символов); иначе null.
String? safeHttpsHost(String? href) {
  if (href == null || href.isEmpty) return null;
  if (RegExp(r'''[\s"'`<>^|\\\x00-\x1f\x7f]''').hasMatch(href)) return null;
  final u = Uri.tryParse(href);
  if (u == null || u.scheme != 'https' || u.host.isEmpty) return null;
  return u.host;
}

/// Самый свежий доверенный запуск ([isTrustedRun]) из ответа `.../runs`.
BuildRun parseLatestRun(String json, String repoFullName) {
  try {
    final j = jsonDecode(json);
    final runs = j is Map ? j['workflow_runs'] : null;
    if (runs is List) {
      for (final r in runs) {
        if (r is Map && isTrustedRun(r, repoFullName)) {
          return BuildRun.fromApi(Map<String, dynamic>.from(r));
        }
      }
    }
    return BuildRun.none;
  } catch (_) {
    return BuildRun.unknown;
  }
}
