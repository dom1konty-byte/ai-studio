import 'dart:io';

/// Обход папки без перехода по ссылкам/junction. Ошибки доступа игнорируются.
/// [onFile] получает файл; [onDir] — каждую найденную подпапку (родитель раньше детей).
Future<void> walkTree(
  Directory root, {
  required Future<void> Function(File f) onFile,
  void Function(Directory d)? onDir,
}) async {
  final stack = <Directory>[root];
  var counter = 0;
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    try {
      await for (final e in dir.list(followLinks: false)) {
        if (e is Link) continue; // ссылки и junction не обходим
        if (e is File) {
          await onFile(e);
        } else if (e is Directory) {
          onDir?.call(e);
          stack.add(e);
        }
      }
    } catch (_) {
      // нет доступа — пропускаем папку
    }
    if (++counter % 50 == 0) await Future<void>.delayed(Duration.zero);
  }
}

/// Синхронный обход для Isolate.
void walkTreeSync(Directory root, void Function(File f) onFile) {
  final stack = <Directory>[root];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    try {
      for (final e in dir.listSync(followLinks: false)) {
        if (e is Link) continue;
        if (e is File) {
          onFile(e);
        } else if (e is Directory) {
          stack.add(e);
        }
      }
    } catch (_) {
      // нет доступа
    }
  }
}
