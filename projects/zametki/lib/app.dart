import 'package:material_ui/material_ui.dart';
import 'package:home_widget/home_widget.dart';
import 'package:quick_actions/quick_actions.dart';

import 'models/note.dart';

import 'screens/note_editor_screen.dart';
import 'screens/notes_list_screen.dart';
import 'services/notes_service.dart';

const _seed = Color(0xFF2F6F5E);

ThemeData _theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: b),
      useMaterial3: true,
    );

/// Куда вести по ссылке: `zametki://new` или `zametki://note/<id>`.
sealed class AppLink {
  const AppLink();

  static AppLink? parse(Uri? uri) {
    if (uri == null || uri.scheme != 'zametki') return null;
    if (uri.host == 'new') return const NewNoteLink();
    if (uri.host == 'note') {
      final id = int.tryParse(uri.pathSegments.isEmpty ? '' : uri.pathSegments.first);
      if (id != null) return OpenNoteLink(id);
    }
    return null;
  }
}

class NewNoteLink extends AppLink {
  const NewNoteLink();
}

class OpenNoteLink extends AppLink {
  const OpenNoteLink(this.id);
  final int id;
}

class App extends StatefulWidget {
  /// [listenLinks] — слушать ярлык и виджеты (в тестах выключаем).
  const App({super.key, required this.service, this.listenLinks = false});

  final NotesService service;
  final bool listenLinks;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    if (widget.listenLinks) _initLinks();
  }

  Future<void> _initLinks() async {
    const QuickActions().initialize((type) {
      if (type == 'new_note') _handle(const NewNoteLink());
    });
    await const QuickActions().setShortcutItems(const [
      ShortcutItem(type: 'new_note', localizedTitle: 'Новая заметка', icon: 'ic_shortcut_add'),
    ]);
    try {
      HomeWidget.widgetClicked.listen((uri) => _handle(AppLink.parse(uri)));
      final initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
      _handle(AppLink.parse(initial));
    } catch (e) {
      debugPrint('Ссылки из виджетов недоступны: $e');
    }
  }

  Future<void> _handle(AppLink? link) async {
    if (link == null) return;
    Note? note;
    if (link is OpenNoteLink) {
      note = await widget.service.byId(link.id);
      if (note == null) return;
    }
    // Ждём, пока навигатор появится (холодный старт).
    var nav = _navKey.currentState;
    for (var i = 0; nav == null && i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      nav = _navKey.currentState;
    }
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    await nav.push(MaterialPageRoute<void>(
      builder: (_) => NoteEditorScreen(service: widget.service, initial: note),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      title: 'Заметки',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: NotesListScreen(service: widget.service),
    );
  }
}
