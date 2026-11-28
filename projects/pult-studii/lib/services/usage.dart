import 'app_storage.dart';

/// Целое из JSON: NaN, бесконечность, отрицательное и больше 1e12 — 0.
int _int(Object? v) =>
    v is num && v.isFinite && v >= 0 && v <= 1e12 ? v.round() : 0;

/// Расход одного хода: данные из события `result` потока Claude.
class TurnUsage {
  const TurnUsage({
    this.cost = 0,
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheCreate = 0,
  });

  final double cost;
  final int input;
  final int output;
  final int cacheRead;
  final int cacheCreate;

  /// Из `result`: `total_cost_usd` и `usage{input_tokens, output_tokens,
  /// cache_read_input_tokens, cache_creation_input_tokens}`. Нет ни того,
  /// ни другого — null.
  static TurnUsage? fromResult(Map<dynamic, dynamic> j) {
    final cost = j['total_cost_usd'];
    final u = j['usage'];
    if (cost is! num && u is! Map) return null;
    final m = u is Map ? u : const {};
    return TurnUsage(
      cost: cost is num && cost >= 0 ? cost.toDouble() : 0,
      input: _int(m['input_tokens']),
      output: _int(m['output_tokens']),
      cacheRead: _int(m['cache_read_input_tokens']),
      cacheCreate: _int(m['cache_creation_input_tokens']),
    );
  }
}

/// Сумма расходов (за день, неделю или всё время).
class UsageTotals {
  UsageTotals({
    this.cost = 0,
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheCreate = 0,
    this.turns = 0,
  });

  double cost;
  int input;
  int output;
  int cacheRead;
  int cacheCreate;
  int turns;

  /// Все токены вместе.
  int get tokens => input + output + cacheRead + cacheCreate;

  bool get isEmpty => turns == 0;

  void addTurn(TurnUsage u) {
    cost += u.cost;
    input += u.input;
    output += u.output;
    cacheRead += u.cacheRead;
    cacheCreate += u.cacheCreate;
    turns++;
  }

  void addTotals(UsageTotals o) {
    cost += o.cost;
    input += o.input;
    output += o.output;
    cacheRead += o.cacheRead;
    cacheCreate += o.cacheCreate;
    turns += o.turns;
  }

  Map<String, dynamic> toJson() => {
        'cost': cost,
        'in': input,
        'out': output,
        'cr': cacheRead,
        'cc': cacheCreate,
        'n': turns,
      };

  static UsageTotals fromJson(Object? j) {
    if (j is! Map) return UsageTotals();
    final c = j['cost'];
    return UsageTotals(
      cost: c is num && c.isFinite && c >= 0 && c <= 1e12 ? c.toDouble() : 0,
      input: _int(j['in']),
      output: _int(j['out']),
      cacheRead: _int(j['cr']),
      cacheCreate: _int(j['cc']),
      turns: _int(j['n']),
    );
  }
}

/// Ключ дня: `2026-11-28` (местная дата).
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Одна строка таблицы: сегодня / 7 дней / всего.
class UsageRow {
  UsageRow()
      : today = UsageTotals(),
        week = UsageTotals(),
        all = UsageTotals();

  final UsageTotals today;
  final UsageTotals week;
  final UsageTotals all;
}

class UsageSummary {
  UsageSummary(this.rows, this.total);

  /// По ключу чата (slug или `ai-office`).
  final Map<String, UsageRow> rows;
  final UsageRow total;

  bool get isEmpty => total.all.isEmpty;
}

/// Свёртка данных по дням. 7 дней — сегодня и 6 предыдущих.
UsageSummary summarizeUsage(
    Map<String, Map<String, UsageTotals>> data, DateTime now) {
  final todayKey = dayKey(now);
  final weekKeys = <String>{
    for (var i = 0; i < 7; i++)
      dayKey(DateTime(now.year, now.month, now.day - i)),
  };
  final rows = <String, UsageRow>{};
  final total = UsageRow();
  for (final e in data.entries) {
    final row = UsageRow();
    for (final d in e.value.entries) {
      row.all.addTotals(d.value);
      if (weekKeys.contains(d.key)) row.week.addTotals(d.value);
      if (d.key == todayKey) row.today.addTotals(d.value);
    }
    rows[e.key] = row;
    total.all.addTotals(row.all);
    total.week.addTotals(row.week);
    total.today.addTotals(row.today);
  }
  return UsageSummary(rows, total);
}

/// usage.json: `{ "<ключ чата>": { "2026-11-28": {cost, in, out, cr, cc, n} } }`.
class UsageRepo {
  UsageRepo(this._storage);

  final AppStorage _storage;
  final Map<String, Map<String, UsageTotals>> data = {};

  Future<void> load() async {
    data.clear();
    final raw = await _storage.loadUsage();
    for (final e in raw.entries) {
      final days = e.value;
      if (days is! Map) continue;
      final m = <String, UsageTotals>{};
      for (final d in days.entries) {
        if (d.key is String) m['${d.key}'] = UsageTotals.fromJson(d.value);
      }
      data[e.key] = m;
    }
  }

  /// Записать ход. Сразу обновляет память, потом пишет файл (очередь записей).
  Future<void> record(String key, TurnUsage u, DateTime now) {
    final day = (data[key] ??= {})[dayKey(now)] ??= UsageTotals();
    day.addTurn(u);
    return _storage.saveUsage({
      for (final e in data.entries)
        e.key: {for (final d in e.value.entries) d.key: d.value.toJson()},
    });
  }

  UsageSummary summary(DateTime now) => summarizeUsage(data, now);
}
