import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';
import 'whitelist.dart';

String _stripExtended(String s) => s.startsWith(r'\\?\') ? s.substring(4) : s;

/// Причина, по которой цель нельзя сканировать/чистить, или null, если можно.
/// Проверяет безопасность пути, ссылки/junction во всех родителях от [CleanTarget.base]
/// и совпадение реального пути (resolveSymbolicLinks) с ожидаемым.
String? targetRejectReason(CleanTarget t) {
  if (!isSafeCleanTarget(t.dir, protectedPaths: t.protectedPaths, minSegments: t.minSegments)) {
    return 'небезопасный путь цели';
  }
  final n = normalizeWinPath(t.dir)!;
  final base = t.base;
  try {
    if (base == null) {
      return FileSystemEntity.typeSync(n, followLinks: false) == FileSystemEntityType.link
          ? 'цель — ссылка'
          : null;
    }
    final nb = normalizeWinPath(base);
    final win = p.windows;
    if (nb == null || !(win.equals(nb, n) || win.isWithin(nb, n))) {
      return 'цель вне базовой папки';
    }
    var cur = nb;
    if (!win.equals(nb, n)) {
      for (final seg in win.split(win.relative(n, from: nb))) {
        cur = win.join(cur, seg);
        if (FileSystemEntity.typeSync(cur, followLinks: false) == FileSystemEntityType.link) {
          return 'ссылка в пути: $cur';
        }
      }
    }
    final real = _stripExtended(Directory(n).resolveSymbolicLinksSync());
    final nr = normalizeWinPath(real);
    if (nr == null || !win.equals(nr, n)) return 'реальный путь не совпадает';
  } catch (e) {
    return 'не удалось проверить путь';
  }
  return null;
}
