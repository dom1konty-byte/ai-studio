import 'package:path/path.dart' as p;

final p.Context _win = p.windows;

/// Нормализует путь Windows: `..`, `.`, `/` → `\`. Не абсолютный путь → null.
String? normalizeWinPath(String path) {
  if (path.isEmpty || !_win.isAbsolute(path)) return null;
  return _win.normalize(path);
}

/// true, только если [path] после нормализации лежит СТРОГО внутри одного из
/// [roots] (сам корень не считается). Регистр не важен (Windows).
/// Символические ссылки здесь не разворачиваются: за них отвечает обход
/// (ссылки и junction не открываются и не удаляются).
bool isInsideAllowedRoot(String path, Iterable<String> roots) {
  final n = normalizeWinPath(path);
  if (n == null) return false;
  for (final r in roots) {
    final nr = normalizeWinPath(r);
    if (nr == null) continue;
    // корень диска или пустой корень не допускаем
    if (_win.dirname(nr) == nr) continue;
    if (_win.isWithin(nr, n)) return true;
  }
  return false;
}

final RegExp _driveAbs = RegExp(r'^[A-Za-z]:[\\/]');

/// Безопасна ли цель очистки [path]. Отклоняет: UNC, `\\?\`, `\\.\`, ':' не на
/// позиции 2, символы `*?"<>|`, сегменты с хвостовой точкой/пробелом, путь короче
/// [minSegments] сегментов (диск считается сегментом), корень диска, а также цель,
/// которая равна [protectedPaths] или является их предком. Без учёта регистра.
bool isSafeCleanTarget(
  String path, {
  Iterable<String> protectedPaths = const [],
  int minSegments = 4,
}) {
  if (path.isEmpty) return false;
  if (!_driveAbs.hasMatch(path)) return false; // UNC, \\?\, \\.\, относительные
  if (path.indexOf(':') != 1 || path.lastIndexOf(':') != 1) return false;
  if (RegExp(r'[*?"<>|\x00-\x1f]').hasMatch(path)) return false;
  final raw = path.split(RegExp(r'[\\/]')).skip(1);
  for (final seg in raw) {
    if (seg == '.' || seg == '..' || seg.isEmpty) continue;
    if (seg.endsWith('.') || seg.endsWith(' ')) return false;
  }
  final n = normalizeWinPath(path);
  if (n == null) return false;
  final parts = _win.split(n);
  if (parts.length < minSegments || parts.length < 2) return false;
  for (final seg in parts.skip(1)) {
    if (seg.isEmpty || seg.endsWith('.') || seg.endsWith(' ')) return false;
  }
  for (final prot in protectedPaths) {
    final np = normalizeWinPath(prot);
    if (np == null) continue;
    if (_win.equals(np, n) || _win.isWithin(n, np)) return false;
  }
  return true;
}

/// Причина, по которой файл нельзя отправлять в Корзину, или null.
String? recycleSkipReason(String path) {
  if (path.length > 259) return 'путь длиннее 259 символов';
  if (path.startsWith(r'\\') || path.startsWith('//')) {
    return 'сетевой или служебный путь';
  }
  if (!_driveAbs.hasMatch(path)) return 'не локальный путь';
  if (path.indexOf(':') != 1 || path.lastIndexOf(':') != 1) return 'недопустимый путь';
  if (RegExp(r'[*?\x00]').hasMatch(path)) return 'недопустимые символы в имени';
  return null;
}

/// Список путей для pFrom (SHFileOperation): каждый путь оканчивается \0,
/// в конце ещё один \0.
List<int> buildDoubleNullList(List<String> paths) {
  final res = <int>[];
  for (final p in paths) {
    res
      ..addAll(p.codeUnits)
      ..add(0);
  }
  res.add(0);
  return res;
}
