import 'dart:io';

import 'package:path/path.dart' as p;

import '../platform/platform_api.dart';
import 'hidden.dart';
import 'journal.dart';
import 'leftovers.dart' show PathGuard, realPathGuardAsync;
import 'whitelist.dart';

/// Папка пуста, если в ней (рекурсивно) нет файлов. Ссылки/junction, скрытые и
/// системные папки, недоступные папки считаются «не пустыми» и не обходятся.
/// Найденные пустые папки добавляются в [out] (дети раньше родителей).
bool _visit(String path, HiddenCheck hidden, List<String>? out, bool Function()? cancelled) {
  if (cancelled?.call() ?? false) return false;
  List<FileSystemEntity> list;
  try {
    list = Directory(path).listSync(followLinks: false);
  } catch (_) {
    return false;
  }
  var empty = true;
  for (final e in list) {
    if (e is Link || e is! Directory) {
      empty = false; // файл, ссылка или что-то необычное
      continue;
    }
    if (hidden(e.path)) {
      empty = false;
      continue;
    }
    if (!_visit(e.path, hidden, out, cancelled)) empty = false;
  }
  if (empty) out?.add(path);
  return empty;
}

int _depth(String path) => p.windows.split(p.windows.normalize(path.replaceAll('/', r'\'))).length;

/// Пустые папки внутри [roots] (вызывать из Isolate). Сами корни и их предки
/// не попадают в результат никогда. Порядок: самые глубокие первыми.
List<String> findEmptyDirsSync(
  List<String> roots, {
  HiddenCheck hidden = isHiddenOrSystem,
  bool Function()? cancelled,
}) {
  final found = <String>[];
  for (final r in roots) {
    if (!Directory(r).existsSync()) continue;
    if (FileSystemEntity.typeSync(r, followLinks: false) == FileSystemEntityType.link) continue;
    _visit(r, hidden, found, cancelled);
  }
  final ctx = p.context;
  final res = <String>{};
  for (final d in found) {
    final isRootOrAncestor = roots.any((r) => ctx.equals(d, r) || ctx.isWithin(d, r));
    if (!isRootOrAncestor) res.add(d);
  }
  final list = res.toList();
  list.sort((a, b) => _depth(b).compareTo(_depth(a)));
  return list;
}

/// Пуста ли папка прямо сейчас (для перепроверки перед удалением).
bool isDirEmptyNow(String path, {HiddenCheck hidden = isHiddenOrSystem}) {
  try {
    if (FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.directory) {
      return false;
    }
  } catch (_) {
    return false;
  }
  return _visit(path, hidden, null, null);
}

class EmptyDirResult {
  int recycled = 0;
  int skipped = 0;
  final List<String> recycledPaths = [];
}

/// Удаление пустых папок: только в Корзину (по одной, самые глубокие первыми),
/// только внутри [userRoots] (сами корни — никогда), с перепроверкой «пуста».
class EmptyDirCleaner {
  EmptyDirCleaner({
    required this.platform,
    required this.log,
    required this.userRoots,
    PathGuard? guard,
    bool Function(String path)? isEmpty,
  })  : guard = guard ?? realPathGuardAsync,
        isEmpty = isEmpty ?? isDirEmptyNow;

  final PlatformApi platform;
  final CleanLog log;
  final List<String> userRoots;
  final PathGuard guard;
  final bool Function(String path) isEmpty;

  static const category = 'Пустые папки';

  Future<EmptyDirResult> run(List<String> paths) async {
    final res = EmptyDirResult();
    final order = List.of(paths)..sort((a, b) => _depth(b).compareTo(_depth(a)));
    final win = p.windows;
    for (final path in order) {
      Future<void> skip(String why) async {
        res.skipped++;
        await log.add(category, path, 0, 'пропущено: $why');
      }

      final n = normalizeWinPath(path);
      if (n == null || userRoots.any((r) => normalizeWinPath(r) != null && win.equals(normalizeWinPath(r)!, n))) {
        await skip('корневая папка');
        continue;
      }
      if (!isInsideAllowedRoot(path, userRoots) || !isSafeCleanTarget(path, minSegments: 3)) {
        await skip('вне папок пользователя');
        continue;
      }
      final bad = recycleSkipReason(path);
      if (bad != null) {
        await skip(bad);
        continue;
      }
      final root = userRoots.firstWhere((r) => isInsideAllowedRoot(path, [r]), orElse: () => '');
      final why = await guard(path, root, true);
      if (why != null) {
        await skip(why);
        continue;
      }
      if (!isEmpty(path)) {
        await skip('папка уже не пуста');
        continue;
      }
      Map<String, String?> r;
      try {
        r = await platform.moveToRecycleBin([path]);
      } catch (_) {
        r = {path: 'ошибка вызова Windows'};
      }
      if (r.containsKey(path) && r[path] == null) {
        res.recycled++;
        res.recycledPaths.add(path);
        await log.add(category, path, 0, 'в Корзину');
      } else {
        await skip(r[path] ?? 'нет ответа');
      }
      await Future<void>.delayed(Duration.zero);
    }
    await log.flush();
    return res;
  }
}

/// Выбор в списке пустых папок: отметка родителя отмечает вложенные пустые,
/// снятие отметки с вложенной снимает её с родителей (родитель унёс бы её с собой).
void toggleEmptyDir(List<String> all, Set<String> selected, String path, bool on) {
  final win = p.windows;
  bool inside(String child, String parent) => win.isWithin(parent, child);
  if (on) {
    selected.add(path);
    for (final d in all) {
      if (inside(d, path)) selected.add(d);
    }
  } else {
    selected.remove(path);
    for (final d in all) {
      if (inside(path, d)) selected.remove(d);
    }
  }
}

/// Папка внутри OneDrive (по переменной OneDrive или по имени сегмента).
bool isInOneDrive(String path, String? oneDriveEnv) {
  final win = p.windows;
  if (oneDriveEnv != null && oneDriveEnv.isNotEmpty && win.isWithin(oneDriveEnv, path)) {
    return true;
  }
  return win.split(path).any((s) => s.toLowerCase().startsWith('onedrive'));
}
