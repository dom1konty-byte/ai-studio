// Уборка старых временных папок, оставшихся после сбоев.
import 'dart:io';

import 'package:path/path.dart' as p;

/// Удаляет папки `<prefix>*` в [root] (по умолчанию системная temp),
/// изменённые раньше чем [maxAge] назад. Ссылки не трогаем. Ошибки глушим.
Future<void> cleanOldTempDirs(String prefix,
    {Directory? root,
    Duration maxAge = const Duration(hours: 1),
    DateTime? now}) async {
  try {
    final base = root ?? Directory.systemTemp;
    final limit = (now ?? DateTime.now()).subtract(maxAge);
    await for (final e in base.list(followLinks: false)) {
      if (e is! Directory || !p.basename(e.path).startsWith(prefix)) continue;
      try {
        if ((await e.stat()).modified.isBefore(limit)) {
          await e.delete(recursive: true);
        }
      } catch (_) {}
    }
  } catch (_) {}
}
