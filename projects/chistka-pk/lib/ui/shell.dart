import 'dart:math' as math;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../state/app_controller.dart';
import 'anim.dart';
import 'computer_details.dart';
import 'computer_screen.dart';
import 'empty_dirs_screen.dart';
import 'dupes_screen.dart';
import 'files_screen.dart';
import 'internet_screen.dart';
import 'nav_panel.dart';
import 'main_screen.dart';
import 'programs_screen.dart';
import 'map_screen.dart';
import 'result_screen.dart';
import 'settings_screen.dart';
import 'startup_screen.dart';
import 'update_ui.dart';

class Shell extends StatefulWidget {
  const Shell({super.key, required this.controller});
  final AppController controller;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  AppController get c => widget.controller;

  // Ширина панели живёт здесь: при перетаскивании перестраивается только панель,
  // в настройки она пишется в конце жеста.
  late final ValueNotifier<double> _navWidth = ValueNotifier(c.settings.navWidth);
  bool _resizing = false;

  void _syncNav() {
    if (!_resizing && _navWidth.value != c.settings.navWidth) _navWidth.value = c.settings.navWidth;
  }

  @override
  void initState() {
    super.initState();
    c.addListener(_syncNav);
  }

  @override
  void dispose() {
    c.removeListener(_syncNav);
    _navWidth.dispose();
    super.dispose();
  }

  Widget _content() {
    if (c.phase == Phase.done && c.showDetails) {
      return ResultScreen(key: const ValueKey('done'), controller: c);
    }
    switch (c.section) {
      case Section.main:
        return MainScreen(key: const ValueKey('main'), controller: c);
      case Section.computer:
        return ComputerScreen(key: const ValueKey('computer'), controller: c);
      case Section.programs:
        return ProgramsScreen(key: const ValueKey('programs'), controller: c);
      case Section.startup:
        return StartupScreen(key: const ValueKey('startup'), controller: c);
      case Section.settings:
        return SettingsScreen(key: const ValueKey('settings'), controller: c);
      case Section.internet:
        return InternetScreen(key: const ValueKey('internet'), controller: c);
    }
  }

  /// Экран поверх «Очистки»: справа панель 60 % ширины (узко — на весь экран),
  /// вверху «Назад»; закрывается кнопкой, щелчком по затемнению и Esc.
  Widget _layer(BuildContext context, BoxConstraints box) {
    final l = c.layer;
    final full = box.maxWidth < 720 || l == Layer.map;
    final Widget screen;
    switch (l) {
      case Layer.downloads:
        screen = FilesScreen(key: const ValueKey('downloads'), controller: c, isDownloads: true);
      case Layer.big:
        screen = FilesScreen(key: const ValueKey('big'), controller: c, isDownloads: false);
      case Layer.dupes:
        screen = DupesScreen(key: const ValueKey('dupes'), controller: c);
      case Layer.emptyDirs:
        screen = EmptyDirsScreen(key: const ValueKey('empty-dirs'), controller: c);
      case Layer.map:
        screen = MapScreen(key: const ValueKey('map'), controller: c);
      case Layer.health:
        screen = HealthDetails(key: const ValueKey('health'), controller: c);
      case Layer.procs:
        screen = ProcsDetails(key: const ValueKey('procs'), controller: c);
      case Layer.battery:
        screen = BatteryDetails(key: const ValueKey('battery'), controller: c);
      case Layer.none:
        return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): c.closeLayer},
      child: Focus(
        autofocus: true,
        child: Stack(
          key: ValueKey('layer-${l.name}'),
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: c.closeLayer,
                child: const ColoredBox(color: Color(0x33000000)),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: full
                    ? box.maxWidth
                    // Таблице процессов нужно не меньше ~680 px.
                    : math.min(box.maxWidth,
                        math.max(box.maxWidth * 0.6, l == Layer.procs ? 680.0 : 0.0)),
                height: box.maxHeight,
                child: Material(
                  elevation: 8,
                  color: cs.surface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextButton.icon(
                          key: const Key('layer-back'),
                          onPressed: c.closeLayer,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Назад'),
                        ),
                        Expanded(child: screen),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: _navWidth,
                  builder: (_, w, __) => NavPanel(
                    controller: c,
                    width: w,
                    onWidthChanged: (v) {
                      _resizing = true;
                      _navWidth.value = v;
                    },
                    onWidthCommitted: (v) {
                      _resizing = false;
                      _navWidth.value = v;
                      c.setNavWidth(v);
                    },
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      UpdateBanner(controller: c),
                      Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => Stack(
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: AnimatedSwitcher(
                      duration: animDuration(context, const Duration(milliseconds: 200)),
                      switchInCurve: Curves.easeOutCubic,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
                              .animate(anim),
                          child: child,
                        ),
                      ),
                      child: _content(),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: AnimatedSwitcher(
                            duration: animDuration(context, const Duration(milliseconds: 200)),
                            transitionBuilder: (child, anim) => SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0.1, 0), end: Offset.zero)
                                  .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                              child: FadeTransition(opacity: anim, child: child),
                            ),
                            child: _layer(context, box),
                          ),
                        ),
                      ],
                    ),
                  ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
