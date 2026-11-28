import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'gh_service.dart';
import 'git_service.dart';
import 'process_runner.dart';
import 'temp_cleanup.dart';

/// Номер сборки, зашитый CI (`--dart-define=BUILD_NUMBER=<run_number>`).
/// 0 — сборка из исходников (dev): обновление не предлагаем.
const buildNumber = int.fromEnvironment('BUILD_NUMBER');

const updateWorkflow = 'pult-studii.yml';

/// Ветки, сборки которых считаем «релизом»: только main.
const updateBranches = {'main'};

/// Имена артефакта с установщиком: новое и прежнее («Рубка»).
const setupArtifacts = ['AI-Studio-setup', 'Rubka-setup'];

final _repoPart = RegExp(r'^[A-Za-z0-9._-]+$');

class UpdateInfo {
  const UpdateInfo(
      {required this.runId, required this.runNumber, required this.branch});

  final int runId;
  final int runNumber;
  final String branch;
}

/// Из ответа `actions/workflows/.../runs`: самый свежий успешный запуск
/// на ветке main (push / workflow_dispatch из репозитория [repoFullName],
/// `owner/repo`), если его номер больше [current].
/// [current] <= 0 (dev-сборка) — всегда null.
UpdateInfo? pickUpdate(String json, int current, String repoFullName) {
  if (current <= 0) return null;
  final Object? j;
  try {
    j = jsonDecode(json);
  } catch (_) {
    return null;
  }
  final runs = j is Map ? j['workflow_runs'] : null;
  if (runs is! List) return null;
  UpdateInfo? best;
  for (final r in runs) {
    if (r is! Map) continue;
    final id = r['id'];
    final number = r['run_number'];
    final branch = r['head_branch'];
    if (id is! int || number is! int || branch is! String) continue;
    if (!updateBranches.contains(branch)) continue;
    if (!isTrustedRun(r, repoFullName)) continue;
    if (r['conclusion'] != 'success') continue;
    if (best == null || number > best.runNumber) {
      best = UpdateInfo(runId: id, runNumber: number, branch: branch);
    }
  }
  return best != null && best.runNumber > current ? best : null;
}

/// Установщик внутри скачанной папки: обычный файл `*setup*.exe`,
/// лежащий именно внутри [dir] (ссылки не берём).
Future<String?> findSetupExe(String dir) async {
  final d = Directory(dir);
  try {
    if (!await d.exists()) return null;
    final found = <String>[];
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path).toLowerCase();
      if (!name.endsWith('.exe') || !name.contains('setup')) continue;
      if (!p.isWithin(dir, e.path)) continue;
      found.add(e.path);
    }
    found.sort();
    return found.isEmpty ? null : found.first;
  } catch (_) {
    return null;
  }
}

class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateService {
  UpdateService(this._proc, {Future<String> Function()? makeTempDir})
      : _makeTempDir = makeTempDir ?? _systemTempDir;

  final ProcessRunner _proc;
  final Future<String> Function() _makeTempDir;

  static Future<String> _systemTempDir() async =>
      (await Directory.systemTemp.createTemp('ai-studio-update-')).path;

  /// Есть ли сборка новее [current]. Любая ошибка (нет сети, gh не вошёл) — null.
  Future<UpdateInfo?> check(RepoRemote r, int current, {String? cwd}) async {
    if (current <= 0) return null;
    if (!_repoPart.hasMatch(r.owner) || !_repoPart.hasMatch(r.repo)) {
      return null;
    }
    try {
      final res = await _proc.run(
          'gh',
          [
            'api',
            'repos/${r.owner}/${r.repo}/actions/workflows/$updateWorkflow/runs'
                '?branch=main&status=success&per_page=5&exclude_pull_requests=true',
          ],
          cwd: cwd);
      if (!res.ok) return null;
      return pickUpdate(res.stdout, current, '${r.owner}/${r.repo}');
    } catch (_) {
      return null;
    }
  }

  /// Скачать установщик запуска [u] в новую пустую папку; вернуть путь к .exe.
  Future<String> download(RepoRemote r, UpdateInfo u, {String? cwd}) async {
    if (!_repoPart.hasMatch(r.owner) || !_repoPart.hasMatch(r.repo)) {
      throw UpdateException('Недопустимый адрес репозитория.');
    }
    final dir = await _makeTempDir();
    try {
      return await _downloadInto(r, u, dir, cwd);
    } catch (_) {
      await _removeDir(dir);
      rethrow;
    }
  }

  Future<String> _downloadInto(
      RepoRemote r, UpdateInfo u, String dir, String? cwd) async {
    String? lastError;
    for (final name in setupArtifacts) {
      final res = await _proc.run(
          'gh',
          [
            'run',
            'download',
            '${u.runId}',
            '-R',
            '${r.owner}/${r.repo}',
            '-n',
            name,
            '-D',
            dir,
          ],
          cwd: cwd,
          timeout: const Duration(minutes: 10));
      if (!res.ok) {
        final t =
            res.stderr.trim().isNotEmpty ? res.stderr.trim() : res.stdout.trim();
        lastError = t;
        continue;
      }
      final exe = await findSetupExe(dir);
      if (exe != null) return exe;
      lastError = 'в артефакте $name нет установщика';
    }
    throw UpdateException('Не удалось скачать обновление: ${lastError ?? '?'}');
  }

  /// Тихая установка отдельным процессом (переживает закрытие программы).
  /// Файл проверяем прямо перед запуском.
  Future<void> install(String exePath) async {
    if (await FileSystemEntity.type(exePath, followLinks: false) !=
        FileSystemEntityType.file) {
      throw UpdateException('Установщик пропал: $exePath');
    }
    await _proc.startDetached(
        exePath, const ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART']);
  }

  static Future<void> _removeDir(String dir) async {
    // Удаляем только свою временную папку, никогда — общую temp.
    if (!p.basename(dir).startsWith('ai-studio-update-')) return;
    try {
      final d = Directory(dir);
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  /// При запуске: убрать старые (больше часа) папки `ai-studio-update-*`.
  static Future<void> cleanOld({Directory? root, DateTime? now}) =>
      cleanOldTempDirs('ai-studio-update-', root: root, now: now);
}
