import 'dart:io';

import 'fs_walk.dart';

/// Размер одной подпапки. [denied] — не удалось прочитать (размер может быть частичным).
class FolderSize {
  const FolderSize(this.name, this.path, this.bytes, {this.denied = false});
  final String name;
  final String path;
  final int bytes;
  final bool denied;
}

String _baseName(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}

/// Подпапки [dir] (без ссылок/junction). Нет доступа — пустой список.
List<Directory> listSubdirs(String dir) {
  try {
    return [
      for (final e in Directory(dir).listSync(followLinks: false))
        if (e is Directory) e,
    ];
  } catch (_) {
    return const [];
  }
}

/// Размер одной папки: сумма файлов внутри, ссылки не обходятся, ошибки доступа не роняют.
FolderSize measureFolderSync(String path) {
  var denied = false;
  try {
    Directory(path).listSync(followLinks: false);
  } catch (_) {
    denied = true;
  }
  var total = 0;
  walkTreeSync(Directory(path), (f) {
    try {
      total += f.lengthSync();
    } catch (_) {}
  });
  return FolderSize(_baseName(path), path, total, denied: denied);
}

/// Сортировка по размеру по убыванию (при равенстве — по имени).
List<FolderSize> sortBySize(List<FolderSize> items) {
  final r = [...items];
  r.sort((a, b) {
    final c = b.bytes.compareTo(a.bytes);
    return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return r;
}

/// Размеры подпапок [dir], по убыванию. Синхронно (вызывать в Isolate).
List<FolderSize> scanSubfoldersSync(String dir) =>
    sortBySize([for (final d in listSubdirs(dir)) measureFolderSync(d.path)]);

/// Хлебные крошки: от [root] до [path] (например C:\ › Users › Me).
List<({String label, String path})> breadcrumbs(String root, String path) {
  final res = <({String label, String path})>[(label: root, path: root)];
  final rootClean = root.replaceAll(RegExp(r'[\\/]+$'), '');
  if (!path.toLowerCase().startsWith(rootClean.toLowerCase())) return res;
  final rest = path
      .substring(rootClean.length)
      .split(RegExp(r'[\\/]'))
      .where((s) => s.isNotEmpty);
  var cur = rootClean;
  for (final s in rest) {
    cur = '$cur\\$s';
    res.add((label: s, path: cur));
  }
  return res;
}
