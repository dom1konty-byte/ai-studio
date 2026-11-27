import 'dart:io';

/// Журнал удалённого: дата, категория, путь, размер, результат.
class CleanLog {
  CleanLog(this.file);
  final File file;
  final List<String> _buf = [];
  bool failed = false;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String stamp(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

  /// Табуляции и переводы строк в именах не должны ломать формат журнала.
  static String clean(String s) => s.replaceAll(RegExp(r'[\t\r\n]'), ' ');

  static const maxBytes = 2 * 1024 * 1024;
  bool _rotated = false;

  /// Если log.txt больше 2 МБ — переименовать в log.old.txt (старый old затирается).
  Future<void> _rotate() async {
    if (_rotated) return;
    _rotated = true;
    try {
      if (file.existsSync() && file.lengthSync() > maxBytes) {
        final old = File('${file.parent.path}${Platform.pathSeparator}log.old.txt');
        if (old.existsSync()) old.deleteSync();
        file.renameSync(old.path);
      }
    } catch (_) {}
  }

  Future<void> add(String category, String path, int size, String result, {DateTime? now}) async {
    _buf.add(
        '${stamp(now ?? DateTime.now())}\t${clean(category)}\t${clean(path)}\t$size\t${clean(result)}');
    if (_buf.length >= 500) await flush();
  }

  Future<void> note(String text, {DateTime? now}) async {
    _buf.add('${stamp(now ?? DateTime.now())}\t# ${clean(text)}');
  }

  Future<void> flush() async {
    if (_buf.isEmpty) return;
    final text = '${_buf.join('\n')}\n';
    _buf.clear();
    try {
      await file.parent.create(recursive: true);
      await _rotate();
      await file.writeAsString(text, mode: FileMode.append, flush: true);
    } catch (_) {
      failed = true;
    }
  }
}
