import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zametki/models/note.dart';
import 'package:zametki/screens/note_editor_screen.dart';
import 'package:zametki/screens/notes_list_screen.dart';
import 'package:zametki/services/notes_service.dart';

import 'fakes.dart';

void main() {
  testWidgets('список обновляется, когда заметку сохранили не из списка', (tester) async {
    final service = NotesService(FakeNotesRepository());
    await tester.pumpWidget(MaterialApp(home: NotesListScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('Из виджета'), findsNothing);

    await service.save(Note(title: 'Из виджета', body: 'x', updatedAt: DateTime(2026)));
    await tester.pumpAndSettle();
    expect(find.text('Из виджета'), findsOneWidget);
  });

  testWidgets('автосохранение и выход не создают дубль новой заметки', (tester) async {
    final repo = FakeNotesRepository();
    final service = NotesService(repo);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => NoteEditorScreen(service: service),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('title_field')), 'Одна');

    // Автосохранение, потом уход приложения в фон и выход — всё подряд.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect((await repo.all()).length, 1);
    expect((await repo.all()).single.title, 'Одна');
  });

  testWidgets('flushEditors дожидается сохранения открытого редактора', (tester) async {
    final repo = FakeNotesRepository();
    final service = NotesService(repo);
    await tester.pumpWidget(MaterialApp(home: NoteEditorScreen(service: service)));
    await tester.enterText(find.byKey(const Key('title_field')), 'Быстро');
    await service.flushEditors();
    await service.flushEditors();
    expect((await repo.all()).length, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
