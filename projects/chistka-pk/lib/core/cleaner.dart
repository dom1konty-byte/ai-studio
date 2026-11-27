import 'dart:io';

import '../platform/platform_api.dart';
import 'fs_walk.dart';
import 'journal.dart';
import 'models.dart';
import 'scanner.dart';
import 'whitelist.dart';

typedef ProgressCallback = void Function(String text, double fraction);

class Cleaner {
  Cleaner(this.platform, this.log);
  final PlatformApi platform;
  final CleanLog log;

  /// Очищает одну цель. Удаляет только внутри белого списка (папка цели).
  Future<void> cleanTarget(Category cat, CleanTarget t, CleanSummary s) async {
    final dir = Directory(t.dir);
    try {
      if (!dir.existsSync() || FileSystemEntity.isLinkSync(t.dir)) return;
    } catch (_) {
      return;
    }
    final roots = [t.dir];

    Future<void> delFile(File f) async {
      var size = 0;
      try {
        if (!isInsideAllowedRoot(f.path, roots)) {
          s.skippedFiles++;
          await log.add(cat.title, f.path, 0, 'пропущено (вне белого списка)');
          return;
        }
        size = await f.length();
        await f.delete();
        s.deletedFiles++;
        s.freedBytes += size;
        await log.add(cat.title, f.path, size, 'удалено');
      } catch (_) {
        s.skippedFiles++;
        await log.add(cat.title, f.path, size, 'пропущено');
      }
    }

    if (t.filePattern != null) {
      try {
        await for (final e in dir.list(followLinks: false)) {
          if (e is File && targetMatchesName(t, e.path.split(RegExp(r'[\\/]')).last)) {
            await delFile(e);
          }
        }
      } catch (_) {}
      return;
    }

    final dirs = <Directory>[];
    await walkTree(dir, onFile: delFile, onDir: dirs.add);
    // пустые подпапки — от самых глубоких; саму корневую папку не трогаем
    for (final d in dirs.reversed) {
      if (!isInsideAllowedRoot(d.path, roots)) continue;
      try {
        await d.delete(); // не рекурсивно: непустая не удалится
      } catch (_) {}
    }
  }

  /// Полная очистка. Порядок важен: сначала опустошаем Корзину, и только потом
  /// отправляем в неё файлы — иначе они удалились бы насовсем.
  Future<CleanSummary> run({
    required List<Category> categories,
    required List<FileInfo> filesToRecycle,
    required List<String> userRoots,
    required bool skipBrowsers,
    ProgressCallback? onProgress,
  }) async {
    final s = CleanSummary();
    final cats = categories
        .where((c) => !(skipBrowsers && c.id == CategoryId.browsers))
        .toList()
      ..sort((a, b) {
        int rank(Category c) => c.id == CategoryId.recycle ? 0 : 1;
        return rank(a).compareTo(rank(b));
      });
    s.browsersSkipped =
        skipBrowsers && categories.any((c) => c.id == CategoryId.browsers);
    final total = cats.length + (filesToRecycle.isEmpty ? 0 : 1);
    var step = 0;

    final disk = await platform.diskSpace(r'C:\');
    s.freeBefore = disk?.free;

    for (final c in cats) {
      step++;
      onProgress?.call('Очищаю: ${c.title}… ($step из $total)', 1 - (step - 1) / total);
      if (c.id == CategoryId.recycle) {
        final info = await platform.recycleBinInfo();
        if (info != null && info.items > 0) {
          if (await platform.emptyRecycleBin()) {
            s.freedBytes += info.bytes;
            s.deletedFiles += info.items;
            await log.add(c.title, 'Корзина', info.bytes, 'удалено');
          } else {
            s.skippedFiles += info.items;
            await log.add(c.title, 'Корзина', info.bytes, 'пропущено');
          }
        }
      } else {
        for (final t in c.targets) {
          await cleanTarget(c, t, s);
        }
      }
    }

    if (filesToRecycle.isNotEmpty) {
      step++;
      onProgress?.call('Очищаю: файлы в Корзину… ($step из $total)', 1 - (step - 1) / total);
      for (final f in filesToRecycle) {
        var ok = false;
        if (isInsideAllowedRoot(f.path, userRoots) &&
            FileSystemEntity.typeSync(f.path, followLinks: false) == FileSystemEntityType.file) {
          ok = await platform.moveToRecycleBin(f.path);
        }
        if (ok) {
          s.recycledBytes += f.size;
          s.deletedFiles++;
          await log.add('Файлы', f.path, f.size, 'в Корзину');
        } else {
          s.skippedFiles++;
          await log.add('Файлы', f.path, f.size, 'пропущено');
        }
      }
    }

    onProgress?.call('Готово', 0);
    final after = await platform.diskSpace(r'C:\');
    s.freeAfter = after?.free;
    await log.flush();
    s.logFailed = log.failed;
    return s;
  }
}
