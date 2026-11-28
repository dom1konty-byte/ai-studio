// Разбор сообщений Claude о лимите. Форматы меняются, поэтому разбор
// терпимый: не поняли — null (лимит не ставим).

DateTime? _fromEpoch(num v) {
  if (v <= 0) return null;
  // секунды или миллисекунды
  final ms = v < 100000000000 ? (v * 1000).round() : v.round();
  return DateTime.fromMillisecondsSinceEpoch(ms);
}

/// Дальше этого срока вперёд время сброса считаем ошибкой разбора.
const maxLimitAhead = Duration(days: 8);

/// Разумное время сброса: в будущем, но не дальше [maxLimitAhead]. Иначе null.
DateTime? saneLimitUntil(DateTime at, DateTime now) =>
    at.isAfter(now) && !at.isAfter(now.add(maxLimitAhead)) ? at : null;

DateTime? _fromAny(Object? v) {
  if (v is num) return _fromEpoch(v);
  if (v is String) {
    final n = num.tryParse(v.trim());
    if (n != null) return _fromEpoch(n);
    return DateTime.tryParse(v.trim())?.toLocal();
  }
  return null;
}

/// События вида `{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","resetsAt":1730000000}}`
/// (то же поле может лежать в `system`). Блокируем только при отказе
/// (status не «allowed…»). Время сброса в прошлом или неизвестно — null.
DateTime? parseRateLimitEvent(Map<dynamic, dynamic> j, DateTime now) {
  Object? info = j['rate_limit_info'] ?? j['rateLimitInfo'];
  if (info is! Map) {
    final m = j['message'];
    info = m is Map ? (m['rate_limit_info'] ?? m['rateLimitInfo']) : null;
  }
  if (info is! Map) return null;
  final status = '${info['status']}'.toLowerCase();
  if (status.isEmpty || status == 'null' || status.startsWith('allowed')) {
    return null;
  }
  final at = _fromAny(info['resetsAt'] ??
      info['resets_at'] ??
      info['resetAt'] ??
      info['reset_at']);
  if (at == null) return null;
  return saneLimitUntil(at, now);
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

final _limitWord = RegExp(r'usage limit|limit reached|hit your limit|'
    r'limit exceeded|rate limit|limit will reset',
    caseSensitive: false);
final _epochAfterPipe = RegExp(r'limit[^|\n]*\|\s*(\d{9,13})\b',
    caseSensitive: false);
final _resetsAt = RegExp(
    r'resets?\s+(?:at\s+)?(?:([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(?:at\s+)?)?'
    r'(\d{1,2})(?::(\d{2}))?\s*([ap]\.?m\.?)?',
    caseSensitive: false);

/// Текст ошибки вида «Claude AI usage limit reached|1730000000»,
/// «5-hour limit reached ∙ resets 6pm», «You've hit your limit · resets 18:40
/// (Europe/Moscow)», «resets Dec 1 at 10am». Часовой пояс в скобках игнорируем
/// (считаем местным). Время не нашли — null.
/// Часовой пояс в скобках: Europe/Moscow (UTC+3), UTC, UTC±N учитываем,
/// остальное — местное время. Время в прошлом или дальше 8 суток — null.
DateTime? parseLimitText(String text, DateTime now) {
  final at = _parseLimitText(text, now);
  return at == null ? null : saneLimitUntil(at, now);
}

final _zoneInParens = RegExp(r'\(([^()]{1,40})\)');
final _utcOffset =
    RegExp(r'^(?:UTC|GMT)\s*([+-])\s*(\d{1,2})(?::?(\d{2}))?$', caseSensitive: false);

/// Смещение пояса от UTC; null — пояс незнакомый (берём местное время).
Duration? zoneOffset(String zone) {
  final z = zone.trim();
  if (z == 'Europe/Moscow') return const Duration(hours: 3);
  if (RegExp(r'^(?:UTC|GMT|Z)$', caseSensitive: false).hasMatch(z)) {
    return Duration.zero;
  }
  final m = _utcOffset.firstMatch(z);
  if (m == null) return null;
  final h = int.parse(m.group(2)!);
  final min = int.tryParse(m.group(3) ?? '0') ?? 0;
  if (h > 14 || min > 59) return null;
  final d = Duration(hours: h, minutes: min);
  return m.group(1) == '-' ? -d : d;
}

DateTime? _parseLimitText(String text, DateTime now) {
  if (text.isEmpty || !_limitWord.hasMatch(text)) return null;
  final e = _epochAfterPipe.firstMatch(text);
  if (e != null) {
    final at = _fromEpoch(int.parse(e.group(1)!));
    return at != null && at.isAfter(now) ? at : null;
  }
  final m = _resetsAt.firstMatch(text);
  if (m == null) return null;
  var hour = int.parse(m.group(3)!);
  final minute = int.tryParse(m.group(4) ?? '0') ?? 0;
  final ap = m.group(5)?.toLowerCase().replaceAll('.', '');
  if (ap != null) {
    if (hour < 1 || hour > 12) return null;
    if (ap == 'pm' && hour < 12) hour += 12;
    if (ap == 'am' && hour == 12) hour = 0;
  }
  if (hour > 23 || minute > 59) return null;
  final month = m.group(1) == null ? null : _months[m.group(1)!.toLowerCase()];
  if (m.group(1) != null && month == null) return null;
  final zm = _zoneInParens.firstMatch(text.substring(m.end));
  final off = zm == null ? null : zoneOffset(zm.group(1)!);
  if (off != null) {
    // время в чужом поясе: считаем «стенные» часы как UTC-поля, потом сдвигаем
    final wall = now.toUtc().add(off);
    DateTime build(int y) => month != null
        ? DateTime.utc(y, month, int.parse(m.group(2)!), hour, minute)
        : DateTime.utc(wall.year, wall.month, wall.day, hour, minute);
    var at = build(wall.year);
    if (!at.isAfter(wall)) {
      at = month != null
          ? build(wall.year + 1)
          : DateTime.utc(wall.year, wall.month, wall.day + 1, hour, minute);
    }
    return at.subtract(off).toLocal();
  }
  if (month != null) {
    final day = int.parse(m.group(2)!);
    var at = DateTime(now.year, month, day, hour, minute);
    if (!at.isAfter(now)) at = DateTime(now.year + 1, month, day, hour, minute);
    return at;
  }
  var at = DateTime(now.year, now.month, now.day, hour, minute);
  if (!at.isAfter(now)) at = DateTime(now.year, now.month, now.day + 1, hour, minute);
  return at;
}

/// «18:40».
String hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
