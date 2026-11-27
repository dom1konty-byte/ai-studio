import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zametki/app.dart';
import 'package:zametki/models/note.dart';
import 'package:zametki/services/notes_repository.dart';
import 'package:zametki/services/notes_service.dart';
import 'package:zametki/services/widget_sync.dart';

import 'fakes.dart';
import 'ui_test.dart' show pumpApp;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final t = DateTime(2026, 1, 1);

  group('перезапуск: данные в файле базы', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('zametki_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('после закрытия и повторного открытия всё на месте', () async {
      final path = '${dir.path}/z.db';
      var repo = await SqliteNotesRepository.open(path);
      final a = await repo.save(
        Note(
          title: 'Список',
          isChecklist: true,
          items: const [ChecklistItem(text: 'x', checked: true)],
          color: 6,
          pinned: true,
          updatedAt: DateTime(2026, 3, 4, 5, 6),
        ),
      );
      final b = await repo.save(Note(title: 'Удалю', body: 'z', updatedAt: t));
      await repo.delete(b.id!);
      await repo.close();

      repo = await SqliteNotesRepository.open(path);
      final all = await repo.all();
      expect(all, hasLength(1));
      expect(all.single.id, a.id);
      expect(all.single.sameContent(a), isTrue);
      expect(all.single.updatedAt, DateTime(2026, 3, 4, 5, 6));
      await repo.close();
    });
  });

  group('репозиторий: границы', () {
    late SqliteNotesRepository repo;
    setUp(
      () async => repo = await SqliteNotesRepository.open(inMemoryDatabasePath),
    );
    tearDown(() => repo.close());

    test(
      'byId несуществующей = null, delete несуществующей не падает',
      () async {
        expect(await repo.byId(999), isNull);
        await repo.delete(999);
      },
    );

    test('кавычки, переводы строк и эмодзи сохраняются как есть', () async {
      const s = 'Он сказал "привет"\n\'ок\' 😀 \\ %';
      final n = await repo.save(
        Note(
          title: s,
          isChecklist: true,
          items: const [ChecklistItem(text: s)],
          updatedAt: t,
        ),
      );
      final back = (await repo.byId(n.id!))!;
      expect(back.title, s);
      expect(back.items.single.text, s);
    });

    test('изменение одной заметки не трогает другие', () async {
      final a = await repo.save(Note(title: 'a', updatedAt: t));
      final b = await repo.save(Note(title: 'b', updatedAt: t));
      await repo.save(a.copyWith(title: 'a2'));
      expect((await repo.byId(b.id!))!.title, 'b');
      expect(await repo.all(), hasLength(2));
    });

    test('сервис обновляет дату изменения при сохранении', () async {
      final service = NotesService(repo, clock: () => DateTime(2030, 5, 5));
      final n = await service.save(Note(title: 'a', updatedAt: t));
      expect(n.updatedAt, DateTime(2030, 5, 5));
      expect((await repo.byId(n.id!))!.updatedAt, DateTime(2030, 5, 5));
    });
  });

  group('Note: чек-лист и текст', () {
    test('конвертация туда-обратно сохраняет строки, пустые отбрасывает', () {
      const text = 'молоко\n\n  хлеб  \n';
      final items = Note.itemsFromText(text);
      expect(items.every((e) => !e.checked), isTrue);
      expect(Note.textFromItems(items), 'молоко\nхлеб');
      expect(Note.itemsFromText(''), isEmpty);
      expect(Note.textFromItems(const []), '');
    });

    test('fromMap: битые/пустые поля не роняют разбор', () {
      final n = Note.fromMap({'id': 1, 'updated_at': 0});
      expect(n.title, '');
      expect(n.items, isEmpty);
      expect(n.color, 0);
      expect(n.pinned, isFalse);
    });

    test('displayTitle: пустой заголовок = «Без названия»', () {
      expect(Note(updatedAt: t).displayTitle, 'Без названия');
      expect(Note(title: '  X ', updatedAt: t).displayTitle, 'X');
    });

    test('sameContent замечает смену галочки', () {
      final a = Note(
        id: 1,
        isChecklist: true,
        items: const [ChecklistItem(text: 'a')],
        updatedAt: t,
      );
      final b = a.copyWith(
        items: const [ChecklistItem(text: 'a', checked: true)],
      );
      expect(a.sameContent(b), isFalse);
    });

    test(
      'matches: пробелы вокруг запроса, текст чек-листа не ищется в body',
      () {
        final n = Note(title: 'Идеи', updatedAt: t);
        expect(n.matches('  идеи  '), isTrue);
        expect(n.matches('   '), isTrue);
      },
    );

    test('цвет и заметка с цветом по границам 0 и 7 сохраняются', () {
      for (final c in [0, 7]) {
        expect(Note.fromMap(Note(color: c, updatedAt: t).toMap()).color, c);
      }
    });
  });

  group('WidgetPayload (данные для home_widget)', () {
    test(
      'recent: пусто -> [], без id не попадают, порядок от новых к старым',
      () {
        expect(WidgetPayload.recent(const []), '[]');
        final notes = [
          Note(title: 'без id', updatedAt: DateTime(2030)),
          Note(id: 1, title: 'старая', updatedAt: DateTime(2026, 1, 1)),
          Note(id: 2, title: 'новая', updatedAt: DateTime(2026, 1, 2)),
        ];
        final list = jsonDecode(WidgetPayload.recent(notes)) as List;
        expect(list.map((e) => e['title']), ['новая', 'старая']);
      },
    );

    test(
      'recent: меньше 5 заметок отдаёт все, поля id/title/preview/color',
      () {
        final notes = [
          Note(
            id: 7,
            title: '',
            body: '\nпервая\nвторая',
            color: 3,
            updatedAt: t,
          ),
          Note(
            id: 8,
            title: 'Л',
            isChecklist: true,
            items: const [ChecklistItem(text: 'a', checked: true)],
            updatedAt: DateTime(2025),
          ),
        ];
        final list = jsonDecode(WidgetPayload.recent(notes)) as List;
        expect(list, hasLength(2));
        expect(list[0], {
          'id': 7,
          'title': 'Без названия',
          'preview': 'первая',
          'color': 3,
        });
        expect(list[1]['preview'], '☑ a');
      },
    );

    test('recent: ровно 5 из 10, закреплённость на выборку не влияет', () {
      final notes = [
        for (var i = 1; i <= 10; i++)
          Note(
            id: i,
            title: 'n$i',
            pinned: i == 1,
            updatedAt: DateTime(2026, 1, i),
          ),
      ];
      final list = jsonDecode(WidgetPayload.recent(notes)) as List;
      expect(list.map((e) => e['id']), [10, 9, 8, 7, 6]);
    });

    test('pinned: самая свежая закреплённая, полный текст', () {
      final notes = [
        Note(
          id: 1,
          title: 'старая',
          body: 'a',
          pinned: true,
          updatedAt: DateTime(2026, 1, 1),
        ),
        Note(
          id: 2,
          title: 'свежая',
          body: 'l1\nl2',
          pinned: true,
          color: 2,
          updatedAt: DateTime(2026, 1, 2),
        ),
        Note(
          id: 3,
          title: 'не закреплена',
          pinned: false,
          updatedAt: DateTime(2030),
        ),
      ];
      final m = jsonDecode(WidgetPayload.pinned(notes)) as Map;
      expect(m, {'id': 2, 'title': 'свежая', 'text': 'l1\nl2', 'color': 2});
    });

    test('pinned: чек-лист отдаётся с галочками', () {
      final n = Note(
        id: 1,
        pinned: true,
        isChecklist: true,
        items: const [
          ChecklistItem(text: 'a', checked: true),
          ChecklistItem(text: 'b'),
        ],
        updatedAt: t,
      );
      expect(
        (jsonDecode(WidgetPayload.pinned([n])) as Map)['text'],
        '☑ a\n☐ b',
      );
    });

    test('pinned: нет заметок / нет закреплённых -> пустая строка', () {
      expect(WidgetPayload.pinned(const []), '');
      expect(WidgetPayload.pinned([Note(id: 1, updatedAt: t)]), '');
    });

    test('после удаления закреплённой виджет получает пусто', () async {
      final sync = RecordingWidgetSync();
      final service = NotesService(FakeNotesRepository(), widgets: sync);
      final n = await service.save(
        Note(title: 'p', pinned: true, updatedAt: t),
      );
      expect(WidgetPayload.pinned(sync.last), isNot(''));
      await service.delete(n.id!);
      expect(WidgetPayload.pinned(sync.last), '');
      expect(WidgetPayload.recent(sync.last), '[]');
    });
  });

  group('AppLink', () {
    test('граничные ссылки', () {
      expect(AppLink.parse(Uri.parse('zametki://note/0')), isA<OpenNoteLink>());
      expect(
        AppLink.parse(Uri.parse('zametki://note/-5')),
        isA<OpenNoteLink>(),
      );
      expect(AppLink.parse(Uri.parse('zametki://note')), isNull);
      expect(AppLink.parse(Uri.parse('zametki://note/')), isNull);
      expect(
        AppLink.parse(Uri.parse('zametki://note/1/extra')),
        isA<OpenNoteLink>(),
      );
      expect(AppLink.parse(Uri.parse('zametki://unknown')), isNull);
      expect(AppLink.parse(Uri.parse('zametki:new')), isNull);
      expect(AppLink.parse(Uri.parse('other://new')), isNull);
    });
  });

  group('редактор', () {
    testWidgets('текст -> чек-лист -> текст: строки сохраняются', (
      tester,
    ) async {
      final (repo, _, _) = await pumpApp(tester);
      await tester.tap(find.text('Заметка'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('body_field')), 'a\nb');
      await tester.tap(find.text('Чек-лист'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'a'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'b'), findsOneWidget);
      await tester.tap(find.text('Текст'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final n = (await repo.all()).single;
      expect(n.isChecklist, isFalse);
      expect(n.body, 'a\nb');
    });

    testWidgets(
      'открыть чек-лист из списка: галочка сохраняется после повторного входа',
      (tester) async {
        final (repo, _, _) = await pumpApp(tester, [
          Note(
            title: 'L',
            isChecklist: true,
            items: const [ChecklistItem(text: 'x')],
            updatedAt: t,
          ),
        ]);
        await tester.tap(find.text('L'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect((await repo.all()).single.items.single.checked, isTrue);

        await tester.tap(find.text('L'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Checkbox>(find.byType(Checkbox).first).value,
          isTrue,
        );
      },
    );

    testWidgets('очистка существующей заметки удаляет её', (tester) async {
      final (repo, _, _) = await pumpApp(tester, [
        Note(title: 'A', body: 'b', updatedAt: t),
      ]);
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('title_field')), '');
      await tester.enterText(find.byKey(const Key('body_field')), '');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(await repo.all(), isEmpty);
    });

    testWidgets('заметка из пробелов не сохраняется', (tester) async {
      final (repo, _, _) = await pumpApp(tester);
      await tester.tap(find.text('Заметка'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('title_field')), '   ');
      await tester.enterText(find.byKey(const Key('body_field')), '\n  ');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(await repo.all(), isEmpty);
    });

    testWidgets('открытие без правок не обновляет виджеты и дату', (
      tester,
    ) async {
      final (repo, _, sync) = await pumpApp(tester, [
        Note(title: 'A', body: 'b', updatedAt: t),
      ]);
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(sync.calls, 0);
      expect((await repo.all()).single.updatedAt, t);
    });

    testWidgets(
      'поиск по заголовку и по пункту чек-листа; закреплённая выше при поиске',
      (tester) async {
        await pumpApp(tester, [
          Note(title: 'Работа', body: 'x', updatedAt: DateTime(2026, 1, 9)),
          Note(
            title: 'Дом',
            isChecklist: true,
            items: const [ChecklistItem(text: 'работа по дому')],
            pinned: true,
            updatedAt: t,
          ),
          Note(title: 'Другое', body: 'y', updatedAt: t),
        ]);
        await tester.enterText(find.byType(SearchBar), 'РАБОТ');
        await tester.pumpAndSettle();
        expect(find.text('Работа'), findsOneWidget);
        expect(find.text('Дом'), findsOneWidget);
        expect(find.text('Другое'), findsNothing);
        expect(
          tester.getTopLeft(find.text('Дом')).dy <
              tester.getTopLeft(find.text('Работа')).dy,
          isTrue,
        );
      },
    );
  });
}
