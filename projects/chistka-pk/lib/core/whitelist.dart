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
