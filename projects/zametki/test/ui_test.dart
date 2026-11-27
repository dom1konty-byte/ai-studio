import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zametki/app.dart';
import 'package:zametki/models/note.dart';
import 'package:zametki/services/notes_service.dart';

import 'fakes.dart';

Future<(FakeNotesRepository, NotesService, RecordingWidgetSync)> pumpApp(
  WidgetTester tester, [
  List<Note> notes = const [],
]) async {
  final repo = FakeNotesRepository(notes);
  final sync = RecordingWidgetSync();
  final service = NotesService(repo, widgets: sync);
  await tester.pumpWidget(App(service: service));
  await tester.pumpAndSettle();
  return (repo, service, sync);
}

void main() {
  final t = DateTime(2026, 1, 1);

  testWidgets('пустой список: подсказка', (tester) async {
    await pumpApp(tester);
    expect(find.text('Пока нет заметок'), findsOneWidget);
    expect(find.text('Заметка'), findsOneWidget);
  });

  testWidgets('закреплённые сверху с заголовками секций', (tester) async {
    await pumpApp(tester, [
      Note(title: 'Обычная', body: 'x', updatedAt: DateTime(2026, 1, 5)),
      Note(title: 'Важная', body: 'y', pinned: true, updatedAt: t),
    ]);
    expect(find.text('Закреплённые'), findsOneWidget);
    expect(find.text('Остальные'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Важная')).dy < tester.getTopLeft(find.text('Обычная')).dy, isTrue);
  });

  testWidgets('поиск по тексту и «ничего не найдено»', (tester) async {
    await pumpApp(tester, [
      Note(title: 'Идеи', body: 'сайт для брата', updatedAt: t),
      Note(title: 'Звонок', body: 'маме', updatedAt: t),
    ]);
    await tester.enterText(find.byType(SearchBar), 'брата');
    await tester.pumpAndSettle();
    expect(find.text('Идеи'), findsOneWidget);
    expect(find.text('Звонок'), findsNothing);

    await tester.enterText(find.byType(SearchBar), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget);
  });

  testWidgets('новая заметка сохраняется при выходе, виджеты обновляются', (tester) async {
    final (repo, _, sync) = await pumpApp(tester);
    await tester.tap(find.text('Заметка'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('title_field')), 'Привет');
    await tester.enterText(find.byKey(const Key('body_field')), 'Мир');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final all = await repo.all();
    expect(all, hasLength(1));
    expect(all.single.title, 'Привет');
    expect(all.single.body, 'Мир');
    expect(find.text('Привет'), findsOneWidget);
    expect(sync.calls, 1);
  });

  testWidgets('пустая заметка не сохраняется', (tester) async {
    final (repo, _, _) = await pumpApp(tester);
    await tester.tap(find.text('Заметка'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(await repo.all(), isEmpty);
    expect(find.text('Пока нет заметок'), findsOneWidget);
  });

  testWidgets('чек-лист: пункты, галочка, сохранение', (tester) async {
    final (repo, _, _) = await pumpApp(tester);
    await tester.tap(find.text('Заметка'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('title_field')), 'Список');
    await tester.tap(find.text('Чек-лист'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Пункт').first, 'молоко');
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final n = (await repo.all()).single;
    expect(n.isChecklist, isTrue);
    expect(n.items, const [ChecklistItem(text: 'молоко', checked: true)]);
    expect(find.textContaining('☑ молоко'), findsOneWidget);
  });

  testWidgets('закрепить и цвет сохраняются', (tester) async {
    final (repo, _, _) = await pumpApp(tester, [Note(title: 'A', body: 'b', updatedAt: t)]);
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Закрепить'));
    await tester.tap(find.byTooltip('Цвет'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('color_3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    final n = (await repo.all()).single;
    expect(n.pinned, isTrue);
    expect(n.color, 3);
  });

  testWidgets('удаление: отмена оставляет, подтверждение удаляет', (tester) async {
    final (repo, _, sync) = await pumpApp(tester, [Note(title: 'A', body: 'b', updatedAt: t)]);
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Точно удалить? Вернуть будет нельзя.'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(await repo.all(), hasLength(1));

    await tester.tap(find.byTooltip('Удалить'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    expect(await repo.all(), isEmpty);
    expect(find.text('Заметка удалена'), findsOneWidget);
    expect(find.text('Пока нет заметок'), findsOneWidget);
    expect(sync.calls, 1);
  });

  test('разбор ссылок из виджета', () {
    expect(AppLink.parse(Uri.parse('zametki://new')), isA<NewNoteLink>());
    expect((AppLink.parse(Uri.parse('zametki://note/42')) as OpenNoteLink).id, 42);
    expect(AppLink.parse(Uri.parse('zametki://note/abc')), isNull);
    expect(AppLink.parse(Uri.parse('https://x.y/new')), isNull);
    expect(AppLink.parse(null), isNull);
  });
}
