import 'dart:io';

import '../platform/platform_api.dart';
import 'fs_walk.dart';
import 'journal.dart';
import 'models.dart';
import 'scanner.dart';
import 'target_guard.dart';
import 'whitelist.dart';

typedef ProgressCallback = void Function(String text, double fraction);

class Cleaner {
  Cleaner(
    this.platform,
    this.log, {
    this.systemDrive = r'C:\',
    this.systemRoot = r'C:\Windows',
    this.admin = false,
  });
  final PlatformApi platform;
  final CleanLog log;

  /// Папка Windows (SystemRoot): для проверки админ-категорий и пути к net.exe.
  final String systemRoot;

  /// Программа запущена с правами администратора: только тогда чистятся
  /// админ-категории (Кэш обновлений Windows, Prefetch).
  final bool admin;

  /// Диск системы (из SystemRoot) — для подсчёта свободного места.
  final String systemDrive;

  /// Очищает одну цель. Удаляет только внутри белого списка (папка цели).
  Future<void> cleanTarget(Category cat, CleanTarget t, CleanSummary s) async {
    if (cat.adminOnly && !isAdminCleanTarget(cat.id, t, systemRoot)) {
      await log.note('Цель пропущена: ${t.dir} (не входит в список системных папок)');
      return;
    }
    final dir = Directory(t.dir);
    try {
      if (!dir.existsSync()) return;
    } catch (_) {
      return;
    }
    final reason = targetRejectReason(t);
    if (reason != null) {
      await log.note('Цель пропущена: ${t.dir} ($reason)');
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
    // в Temp подпапки не удаляем — только файлы (папки могут быть заняты программами)
    if (cat.id == CategoryId.temp) return;
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
  /// [into] — итог, который наполняется по ходу (при исключении сохраняется).
  Future<CleanSummary> run({
    required List<Category> categories,
    required List<FileInfo> filesToRecycle,
    required List<String> userRoots,
    required bool skipBrowsers,
    ProgressCallback? onProgress,
    CleanSummary? into,
  }) async {
    final s = into ?? CleanSummary();
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

    try {
      final disk = await platform.diskSpace(systemDrive);
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
              await log.add(c.title, 'Корзина (все диски)', info.bytes, 'удалено');
            } else {
              s.skippedFiles += info.items;
              await log.add(c.title, 'Корзина (все диски)', info.bytes, 'пропущено');
            }
          }
        } else if (c.adminOnly && !admin) {
          await log.note('Категория пропущена (нужны права администратора): ${c.title}');
        } else if (c.id == CategoryId.winUpdate) {
          await _cleanWithUpdateService(c, s);
        } else {
          for (final t in c.targets) {
            await cleanTarget(c, t, s);
          }
        }
        await log.flush();
      }

      if (filesToRecycle.isNotEmpty) {
        step++;
        onProgress?.call('Очищаю: файлы в Корзину… ($step из $total)', 1 - (step - 1) / total);
        await _recycleFiles(filesToRecycle, userRoots, s);
        await log.flush();
      }

      onProgress?.call('Готово', 0);
      final after = await platform.diskSpace(systemDrive);
      s.freeAfter = after?.free;
    } finally {
      await log.flush();
      s.logFailed = log.failed;
    }
    return s;
  }

  /// Кэш обновлений: служба wuauserv держит файлы, поэтому перед очисткой её
  /// останавливаем, а после (в том числе при ошибке) запускаем обратно.
  Future<void> _cleanWithUpdateService(Category c, CleanSummary s) async {
    final net = '$systemRoot\\System32\\net.exe';
    try {
      int? code;
      try {
        code = await platform.runTool(net, const ['stop', 'wuauserv']);
      } catch (_) {}
      await log.note('Служба wuauserv: остановка, код ${code ?? 'нет'}');
      for (final t in c.targets) {
        await cleanTarget(c, t, s);
      }
    } finally {
      int? code;
      try {
        code = await platform.runTool(net, const ['start', 'wuauserv']);
      } catch (_) {}
      await log.note('Служба wuauserv: запуск, код ${code ?? 'нет'}');
    }
  }

  Future<void> _recycleFiles(
      List<FileInfo> files, List<String> userRoots, CleanSummary s) async {
    final ok = <FileInfo>[];
    for (final f in files) {
      String? reason;
      if (!isInsideAllowedRoot(f.path, userRoots)) {
        reason = 'вне папок пользователя';
      } else {
        reason = recycleSkipReason(f.path);
      }
      if (reason == null) {
        try {
          if (FileSystemEntity.typeSync(f.path, followLinks: false) !=
              FileSystemEntityType.file) {
            reason = 'не обычный файл';
          }
        } catch (_) {
          reason = 'не удалось проверить файл';
        }
      }
      if (reason == null) {
        ok.add(f);
      } else {
        s.skippedFiles++;
        await log.add('Файлы', f.path, f.size, 'пропущено: $reason');
      }
    }
    if (ok.isEmpty) return;
    Map<String, String?> res;
    try {
      res = await platform.moveToRecycleBin(ok.map((f) => f.path).toList());
    } catch (_) {
      res = {for (final f in ok) f.path: 'ошибка вызова Windows'};
    }
    for (final f in ok) {
      if (res.containsKey(f.path) && res[f.path] == null) {
        s.recycledBytes += f.size;
        s.deletedFiles++;
        await log.add('Файлы', f.path, f.size, 'в Корзину');
      } else {
        s.skippedFiles++;
        await log.add('Файлы', f.path, f.size, 'пропущено: ${res[f.path] ?? 'нет ответа'}');
      }
    }
  }
}
