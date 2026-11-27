import 'dart:convert';
import 'dart:io';

/// Статистика «за всё время освобождено» в stats.json.
class StatsStore {
  StatsStore(this.file);
  final File file;

  Future<int> load() async {
    try {
      if (!file.existsSync()) return 0;
      final m = jsonDecode(await file.readAsString());
      final v = m is Map ? m['totalFreedBytes'] : null;
      return v is int && v >= 0 ? v : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Добавляет [bytes] и возвращает новую сумму.
  Future<int> add(int bytes) async {
    final total = (await load()) + (bytes < 0 ? 0 : bytes);
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'totalFreedBytes': total}), flush: true);
    } catch (_) {}
    return total;
  }
}
