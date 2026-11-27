import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'services/notes_repository.dart';
import 'services/notes_service.dart';
import 'services/widget_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await SqliteNotesRepository.open(p.join(await getDatabasesPath(), 'zametki.db'));
  // Виджеты главного экрана есть только на Android.
  final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  final service = NotesService(
    repo,
    widgets: isAndroid ? const HomeWidgetSync() : const NoopWidgetSync(),
  );
  runApp(App(service: service, listenLinks: isAndroid));
  // Виджеты показывают актуальное и после обновления приложения.
  try {
    await service.refreshWidgets();
  } catch (e) {
    debugPrint('Не удалось обновить виджеты: $e');
  }
}
