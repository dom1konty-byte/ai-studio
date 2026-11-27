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

  Future<void> add(String category, String path, int size, String result, {DateTime? now}) async {
    _buf.add('${stamp(now ?? DateTime.now())}\t$category\t$path\t$size\t$result');
    if (_buf.length >= 500) await flush();
  }

  Future<void> note(String text, {DateTime? now}) async {
    _buf.add('${stamp(now ?? DateTime.now())}\t# $text');
  }

  Future<void> flush() async {
    if (_buf.isEmpty) return;
    final text = '${_buf.join('\n')}\n';
    _buf.clear();
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(text, mode: FileMode.append, flush: true);
    } catch (_) {
      failed = true;
    }
  }
}
