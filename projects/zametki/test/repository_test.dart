import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zametki/models/note.dart';
import 'package:zametki/services/notes_repository.dart';
import 'package:zametki/services/notes_service.dart';
import 'package:zametki/services/widget_sync.dart';

import 'fakes.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late SqliteNotesRepository repo;

  setUp(() async {
    repo = await SqliteNotesRepository.open(inMemoryDatabasePath);
  });
  tearDown(() => repo.close());

  test('создать, прочитать, изменить, удалить', () async {
    final saved = await repo.save(Note(title: 'A', body: 'b', updatedAt: DateTime(2026, 1, 1)));
    expect(saved.id, isNotNull);
    expect((await repo.byId(saved.id!))!.title, 'A');

    await repo.save(saved.copyWith(title: 'B', pinned: true, color: 4));
    final changed = (await repo.byId(saved.id!))!;
    expect(changed.title, 'B');
    expect(changed.pinned, isTrue);
    expect(changed.color, 4);
    expect(await repo.all(), hasLength(1));

    await repo.delete(saved.id!);
    expect(await repo.all(), isEmpty);
    expect(await repo.byId(saved.id!), isNull);
  });

  test('чек-лист сохраняется вместе с галочками', () async {
    final saved = await repo.save(Note(
      isChecklist: true,
      items: const [ChecklistItem(text: 'x', checked: true), ChecklistItem(text: 'y')],
      updatedAt: DateTime(2026, 1, 1),
    ));
    final back = (await repo.byId(saved.id!))!;
    expect(back.isChecklist, isTrue);
    expect(back.items, const [ChecklistItem(text: 'x', checked: true), ChecklistItem(text: 'y')]);
  });

  test('all: новые по дате изменения сверху', () async {
    await repo.save(Note(title: 'старая', updatedAt: DateTime(2026, 1, 1)));
    await repo.save(Note(title: 'новая', updatedAt: DateTime(2026, 1, 5)));
    expect((await repo.all()).map((e) => e.title), ['новая', 'старая']);
  });

  test('сервис обновляет виджеты при сохранении и удалении', () async {
    final sync = RecordingWidgetSync();
    final service = NotesService(repo, widgets: sync);
    final n = await service.save(Note(title: 'A', updatedAt: DateTime(2020)));
    expect(sync.calls, 1);
    expect(sync.last, hasLength(1));
    await service.delete(n.id!);
    expect(sync.calls, 2);
    expect(sync.last, isEmpty);
  });

  test('WidgetPayload: последние (макс. 5) и самая свежая закреплённая', () {
    final notes = [
      for (var i = 1; i <= 7; i++)
        Note(id: i, title: 'n$i', body: 'текст $i', pinned: i == 2 || i == 4, updatedAt: DateTime(2026, 1, i)),
    ];
    final recent = WidgetPayload.recent(notes);
    expect(recent, contains('"title":"n7"'));
    expect(recent, isNot(contains('"title":"n2"')));
    expect('"id"'.allMatches(recent), hasLength(5));
    final pinned = WidgetPayload.pinned(notes);
    expect(pinned, contains('"title":"n4"'));
    expect(WidgetPayload.pinned([Note(id: 1, updatedAt: DateTime(2026))]), '');
  });

  test('FakeNotesRepository ведёт себя как настоящий', () async {
    final f = FakeNotesRepository();
    final s = await f.save(Note(title: 'x', updatedAt: DateTime(2026)));
    expect(s.id, 1);
  });
}
