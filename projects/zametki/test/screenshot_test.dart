// Скриншот главного экрана для сообщения в Telegram (сборка на GitHub).
// Запуск: flutter test --update-goldens --dart-define=SCREENSHOTS=true test/screenshot_test.dart
// Обычный `flutter test` его пропускает. Картинка: build/telegram/screenshot.png
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zametki/app.dart';
import 'package:zametki/models/note.dart';
import 'package:zametki/services/notes_service.dart';

import 'fakes.dart';

const _enabled = bool.fromEnvironment('SCREENSHOTS');

Future<void> _loadFonts() async {
  final dir = Directory('${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  Future<void> load(String family, Iterable<File> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await loader.load();
  }

  final files = dir.listSync().whereType<File>();
  await load('Roboto', files.where((f) => f.path.contains('Roboto-')));
  await load('MaterialIcons', files.where((f) => f.path.endsWith('MaterialIcons-Regular.otf')));
}

void main() {
  testWidgets('скриншот главного экрана', skip: !_enabled, (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repo = FakeNotesRepository([
      Note(title: 'Покупки', isChecklist: true, items: const [
        ChecklistItem(text: 'молоко'),
        ChecklistItem(text: 'хлеб', checked: true),
      ], pinned: true, color: 4, updatedAt: DateTime(2026, 1, 3)),
      Note(title: 'Идеи', body: 'Сайт для брата, приложение для заметок', pinned: true, color: 3, updatedAt: DateTime(2026, 1, 2)),
      Note(title: 'Звонок', body: 'Позвонить маме вечером', color: 6, updatedAt: DateTime(2026, 1, 1)),
      Note(title: 'План недели', body: 'Тренировка, встреча, уборка', updatedAt: DateTime(2026, 1, 1)),
    ]);
    await tester.pumpWidget(App(service: NotesService(repo)));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('../build/telegram/screenshot.png'));
  });
}
