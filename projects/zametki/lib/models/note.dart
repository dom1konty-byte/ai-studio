import 'dart:convert';

/// Пункт чек-листа.
class ChecklistItem {
  const ChecklistItem({required this.text, this.checked = false});

  final String text;
  final bool checked;

  ChecklistItem copyWith({String? text, bool? checked}) =>
      ChecklistItem(text: text ?? this.text, checked: checked ?? this.checked);

  Map<String, Object?> toJson() => {'text': text, 'checked': checked};

  factory ChecklistItem.fromJson(Map<String, Object?> json) => ChecklistItem(
        text: (json['text'] as String?) ?? '',
        checked: (json['checked'] as bool?) ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is ChecklistItem && other.text == text && other.checked == checked;

  @override
  int get hashCode => Object.hash(text, checked);
}

/// Заметка: обычный текст или чек-лист.
class Note {
  const Note({
    this.id,
    this.title = '',
    this.body = '',
    this.isChecklist = false,
    this.items = const [],
    this.color = 0,
    this.pinned = false,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final String body;
  final bool isChecklist;
  final List<ChecklistItem> items;

  /// Индекс цвета 0–7 (см. note_colors.dart).
  final int color;
  final bool pinned;
  final DateTime updatedAt;

  Note copyWith({
    int? id,
    String? title,
    String? body,
    bool? isChecklist,
    List<ChecklistItem>? items,
    int? color,
    bool? pinned,
    DateTime? updatedAt,
  }) =>
      Note(
        id: id ?? this.id,
        title: title ?? this.title,
        body: body ?? this.body,
        isChecklist: isChecklist ?? this.isChecklist,
        items: items ?? this.items,
        color: color ?? this.color,
        pinned: pinned ?? this.pinned,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'body': body,
        'is_checklist': isChecklist ? 1 : 0,
        'items': jsonEncode(items.map((e) => e.toJson()).toList()),
        'color': color,
        'pinned': pinned ? 1 : 0,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Note.fromMap(Map<String, Object?> map) {
    final rawItems = jsonDecode((map['items'] as String?) ?? '[]') as List;
    return Note(
      id: map['id'] as int?,
      title: (map['title'] as String?) ?? '',
      body: (map['body'] as String?) ?? '',
      isChecklist: (map['is_checklist'] as int? ?? 0) == 1,
      items: rawItems
          .map((e) => ChecklistItem.fromJson(Map<String, Object?>.from(e as Map)))
          .toList(),
      color: map['color'] as int? ?? 0,
      pinned: (map['pinned'] as int? ?? 0) == 1,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int? ?? 0),
    );
  }

  /// Нет ни заголовка, ни содержимого — такую заметку не сохраняем.
  bool get isEmpty =>
      title.trim().isEmpty &&
      (isChecklist ? items.every((e) => e.text.trim().isEmpty) : body.trim().isEmpty);

  String get displayTitle => title.trim().isEmpty ? 'Без названия' : title.trim();

  /// Поиск по заголовку и тексту (без учёта регистра).
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (title.toLowerCase().contains(q)) return true;
    if (isChecklist) {
      return items.any((e) => e.text.toLowerCase().contains(q));
    }
    return body.toLowerCase().contains(q);
  }

  /// Первые [max] строк содержимого; у чек-листа с «☐/☑».
  List<String> previewLines(int max) {
    final lines = isChecklist
        ? items
            .where((e) => e.text.trim().isNotEmpty)
            .map((e) => '${e.checked ? '☑' : '☐'} ${e.text.trim()}')
        : body.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty);
    return lines.take(max).toList();
  }

  /// Содержимое для виджета «Закреплённая» (строки через перевод строки).
  String get fullText => previewLines(1000).join('\n');

  /// Сравнение содержимого без даты (нужно, чтобы не пересохранять без правок).
  bool sameContent(Note o) =>
      o.id == id &&
      o.title == title &&
      o.body == body &&
      o.isChecklist == isChecklist &&
      o.color == color &&
      o.pinned == pinned &&
      _listEq(o.items, items);

  static bool _listEq(List<ChecklistItem> a, List<ChecklistItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Текст → пункты: каждая непустая строка становится пунктом.
  static List<ChecklistItem> itemsFromText(String text) => text
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .map((e) => ChecklistItem(text: e))
      .toList();

  /// Пункты → текст: каждый пункт — строка.
  static String textFromItems(List<ChecklistItem> items) =>
      items.map((e) => e.text.trim()).where((e) => e.isNotEmpty).join('\n');
}
