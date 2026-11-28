import 'dart:io';

import 'fs_walk.dart';
import 'models.dart';
import 'target_guard.dart';

class ScanResult {
  const ScanResult(this.bytes, this.files);
  final int bytes;
  final int files;
}

bool _matches(CleanTarget t, File f) {
  final pat = t.filePattern;
  if (pat == null) return true;
  final name = f.path.split(RegExp(r'[\\/]')).last;
  return pat.hasMatch(name);
}

/// Считает размер того, что будет удалено для цели [t].
Future<ScanResult> scanTarget(CleanTarget t) async {
  var bytes = 0;
  var files = 0;
  final dir = Directory(t.dir);
  if (!dir.existsSync()) return const ScanResult(0, 0);
  if (targetRejectReason(t) != null) return const ScanResult(0, 0);

  Future<void> count(File f) async {
    try {
      bytes += await f.length();
      files++;
    } catch (_) {}
  }

  if (t.filePattern != null) {
    try {
      await for (final e in dir.list(followLinks: false)) {
        if (e is File && _matches(t, e)) await count(e);
      }
    } catch (_) {}
  } else {
    await walkTree(dir, onFile: count);
  }
  return ScanResult(bytes, files);
}

Future<ScanResult> scanTargets(List<CleanTarget> targets) async {
  var b = 0;
  var f = 0;
  for (final t in targets) {
    final r = await scanTarget(t);
    b += r.bytes;
    f += r.files;
  }
  return ScanResult(b, f);
}

/// Подходит ли файл [name] под шаблон цели.
bool targetMatchesName(CleanTarget t, String name) =>
    t.filePattern == null || t.filePattern!.hasMatch(name);

// ---------- Загрузки и большие файлы (запускаются в Isolate) ----------

/// Файлы старше [days] дней по дате изменения.
bool isOldEnough(DateTime modified, DateTime now, {int days = 30}) =>
    now.difference(modified) > Duration(days: days);

/// Фильтр Загрузок: старше 30 дней, по размеру по убыванию.
List<FileInfo> filterOldDownloads(List<FileInfo> all, DateTime now, {int days = 30}) {
  final res = all.where((f) => isOldEnough(f.modified, now, days: days)).toList()
    ..sort((a, b) => b.size.compareTo(a.size));
  return res;
}

/// Топ-[n] самых больших файлов, по убыванию размера.
List<FileInfo> topLargest(Iterable<FileInfo> all, int n) {
  final res = all.toList()..sort((a, b) => b.size.compareTo(a.size));
  return res.length > n ? res.sublist(0, n) : res;
}

/// Синхронное сканирование Загрузок (вызывать из Isolate).
List<FileInfo> scanOldDownloadsSync(String dir, DateTime now, {int days = 30}) {
  final res = <FileInfo>[];
  walkTreeSync(Directory(dir), (f) {
    try {
      final st = f.statSync();
      if (isOldEnough(st.modified, now, days: days)) {
        res.add(FileInfo(f.path, st.size, st.modified));
      }
    } catch (_) {}
  });
  res.sort((a, b) => b.size.compareTo(a.size));
  return res;
}

/// Синхронный поиск больших файлов (вызывать из Isolate).
List<FileInfo> scanLargestSync(List<String> dirs, int n) {
  var best = <FileInfo>[];
  for (final d in dirs) {
    walkTreeSync(Directory(d), (f) {
      try {
        final st = f.statSync();
        best.add(FileInfo(f.path, st.size, st.modified));
        if (best.length > n * 4) best = topLargest(best, n);
      } catch (_) {}
    });
  }
  return topLargest(best, n);
}
