/// Файл с размером и датой (для Загрузок и Больших файлов).
class FileInfo {
  const FileInfo(this.path, this.size, this.modified);
  final String path;
  final int size;
  final DateTime modified;

  String get name {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i < 0 ? path : path.substring(i + 1);
  }

  String get folder {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i < 0 ? '' : path.substring(0, i);
  }
}

enum FileKind { installer, archive, other }

FileKind fileKind(String path) {
  final lower = path.toLowerCase();
  const inst = ['.exe', '.msi'];
  const arch = ['.zip', '.rar', '.7z'];
  if (inst.any(lower.endsWith)) return FileKind.installer;
  if (arch.any(lower.endsWith)) return FileKind.archive;
  return FileKind.other;
}

/// Цель очистки: содержимое папки [dir] (саму папку не трогаем)
/// или файлы верхнего уровня, подходящие под [filePattern].
class CleanTarget {
  const CleanTarget(
    this.dir, {
    this.filePattern,
    this.base,
    this.minSegments = 4,
    this.protectedPaths = const [],
  });
  final String dir;
  final RegExp? filePattern;

  /// Базовая папка (%LOCALAPPDATA%, %APPDATA%, SystemRoot, Steam): все компоненты
  /// пути от неё до [dir] не должны быть ссылками.
  final String? base;

  /// Минимум сегментов пути (диск считается сегментом).
  final int minSegments;

  /// Папки, которые цель не может ни совпадать, ни быть их предком.
  final List<String> protectedPaths;
}

enum CategoryId {
  temp,
  browsers,
  recycle,
  thumbs,
  logs,
  telegram,
  discord,
  steam,
  spotify,
  vscode,
  gpu,
}

class Category {
  const Category({
    required this.id,
    required this.title,
    required this.hint,
    required this.targets,
    this.isProgram = false,
  });
  final CategoryId id;
  final String title;
  final String hint;
  final List<CleanTarget> targets;
  final bool isProgram;
}

/// Итог очистки.
class CleanSummary {
  int freedBytes = 0; // реально освобождено (кэш + опустошённая Корзина)
  int recycledBytes = 0; // отправлено в Корзину (Загрузки, большие файлы)
  int deletedFiles = 0;
  int skippedFiles = 0;
  bool browsersSkipped = false;
  bool logFailed = false;
  int? freeBefore;
  int? freeAfter;
}
