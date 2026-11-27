import 'package:flutter_test/flutter_test.dart';
import 'package:zametki/models/note.dart';

void main() {
  final t = DateTime(2026, 1, 1);

  test('toMap/fromMap сохраняет все поля, включая чек-лист', () {
    final n = Note(
      id: 3,
      title: 'Покупки',
      isChecklist: true,
      items: const [ChecklistItem(text: 'молоко'), ChecklistItem(text: 'хлеб', checked: true)],
      color: 5,
      pinned: true,
      updatedAt: t,
    );
    final back = Note.fromMap(n.toMap());
    expect(back.sameContent(n), isTrue);
    expect(back.updatedAt, t);
  });

  test('isEmpty: пустая и из пробелов', () {
    expect(Note(updatedAt: t).isEmpty, isTrue);
    expect(Note(title: '  ', body: '\n', updatedAt: t).isEmpty, isTrue);
    expect(Note(title: 'a', updatedAt: t).isEmpty, isFalse);
    expect(Note(isChecklist: true, items: const [ChecklistItem(text: ' ')], updatedAt: t).isEmpty, isTrue);
  });

  test('matches ищет по заголовку, тексту и пунктам без учёта регистра', () {
    final text = Note(title: 'Идеи', body: 'Сайт для брата', updatedAt: t);
    expect(text.matches('идеи'), isTrue);
    expect(text.matches('БРАТА'), isTrue);
    expect(text.matches('молоко'), isFalse);
    expect(text.matches(''), isTrue);
    final list = Note(isChecklist: true, items: const [ChecklistItem(text: 'Молоко')], updatedAt: t);
    expect(list.matches('молок'), isTrue);
  });

  test('previewLines: чек-лист с ☐/☑, лимит строк', () {
    final n = Note(
      isChecklist: true,
      items: const [
        ChecklistItem(text: 'a'),
        ChecklistItem(text: 'b', checked: true),
        ChecklistItem(text: 'c'),
        ChecklistItem(text: 'd'),
      ],
      updatedAt: t,
    );
    expect(n.previewLines(3), ['☐ a', '☑ b', '☐ c']);
    expect(Note(body: 'x\n\ny', updatedAt: t).previewLines(5), ['x', 'y']);
  });

  test('преобразование текст <-> пункты', () {
    final items = Note.itemsFromText('a\n\n b \nc');
    expect(items.map((e) => e.text), ['a', 'b', 'c']);
    expect(Note.textFromItems(items), 'a\nb\nc');
  });
}
