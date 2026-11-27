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
  final service = NotesService(repo, widgets: const HomeWidgetSync());
  runApp(App(service: service, listenLinks: true));
  // Виджеты показывают актуальное и после обновления приложения.
  await service.refreshWidgets();
}
