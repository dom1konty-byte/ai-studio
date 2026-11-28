/// Статус запланированной задачи («Задача на ночь»).
enum TaskStatus { waiting, done, error, cancelled }

/// Сообщение директору, которое уйдёт в заданное время.
class ScheduledTask {
  ScheduledTask({
    required this.id,
    required this.key,
    required this.text,
    required this.when,
    this.keepAwake = false,
    this.status = TaskStatus.waiting,
    this.result = '',
  });

  final String id;

  /// Ключ чата: slug проекта или `ai-office`.
  final String key;
  final String text;
  DateTime when;

  /// Не давать компьютеру уснуть до выполнения.
  final bool keepAwake;
  TaskStatus status;

  /// Результат кратко (ответ директора или ошибка).
  String result;

  bool get waiting => status == TaskStatus.waiting;

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'text': text,
        'when': when.toIso8601String(),
        'keepAwake': keepAwake,
        'status': status.name,
        'result': result,
      };

  static ScheduledTask? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final key = j['key'];
    final text = j['text'];
    final when = DateTime.tryParse('${j['when']}');
    if (id is! String || key is! String || text is! String || when == null) {
      return null;
    }
    if (id.isEmpty || key.isEmpty || text.trim().isEmpty) return null;
    final status = TaskStatus.values
            .where((s) => s.name == j['status'])
            .firstOrNull ??
        TaskStatus.waiting;
    final res = j['result'];
    return ScheduledTask(
      id: id,
      key: key,
      text: text,
      when: when,
      keepAwake: j['keepAwake'] == true,
      status: status,
      result: res is String ? res : '',
    );
  }
}

/// Ближайшее наступление часов:минут: сегодня, а если уже прошло — завтра.
DateTime nextOccurrence(DateTime now, int hour, int minute) {
  final today = DateTime(now.year, now.month, now.day, hour, minute);
  return today.isAfter(now)
      ? today
      : DateTime(now.year, now.month, now.day + 1, hour, minute);
}
