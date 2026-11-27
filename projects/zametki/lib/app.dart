import 'dart:async';

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
  StreamSubscription<Uri?>? _clicks;
  bool _busy = false;
  bool _initPhase = true;

  /// Стартовая ссылка обрабатывается один раз за процесс (не при пересоздании экрана).
  static bool _initialHandled = false;

  @override
  void initState() {
    super.initState();
    if (widget.listenLinks) _initLinks();
  }

  @override
  void dispose() {
    _clicks?.cancel();
    super.dispose();
  }

  void _handleInitial(AppLink? link) {
    if (_initialHandled) return;
    _initialHandled = true;
    _handle(link);
  }

  Future<void> _initLinks() async {
    try {
      const QuickActions().initialize((type) {
        if (type != 'new_note') return;
        // Пока идёт запуск — это ярлык, которым открыли приложение.
        if (_initPhase) {
          _handleInitial(const NewNoteLink());
        } else {
          _handle(const NewNoteLink());
        }
      });
      await const QuickActions().setShortcutItems(const [
        ShortcutItem(type: 'new_note', localizedTitle: 'Новая заметка', icon: 'ic_shortcut_add'),
      ]);
      _clicks = HomeWidget.widgetClicked.listen((uri) => _handle(AppLink.parse(uri)));
      final initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
      _handleInitial(AppLink.parse(initial));
    } catch (e) {
      debugPrint('Ссылки из виджетов недоступны: $e');
    } finally {
      _initPhase = false;
    }
  }

  /// Навигатор появляется после первого кадра (холодный старт).
  Future<NavigatorState?> _navigator() {
    final nav = _navKey.currentState;
    if (nav != null) return Future.value(nav);
    final c = Completer<NavigatorState?>();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.complete(_navKey.currentState));
    WidgetsBinding.instance.ensureVisualUpdate();
    return c.future;
  }

  Future<void> _handle(AppLink? link) async {
    if (link == null || _busy) return;
    _busy = true;
    NavigatorState? nav;
    Note? note;
    try {
      nav = await _navigator();
      if (nav == null) return;
      // Не терять правки открытого редактора (и читать заметку уже после них).
      await widget.service.flushEditors();
      nav.popUntil((r) => r.isFirst);
      if (link is OpenNoteLink) {
        note = await widget.service.byId(link.id);
        if (note == null) return;
      }
    } catch (e) {
      debugPrint('Не удалось открыть по ссылке: $e');
      return;
    } finally {
      _busy = false;
    }
    unawaited(nav.push(MaterialPageRoute<void>(
      builder: (_) => NoteEditorScreen(service: widget.service, initial: note),
    )));
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
