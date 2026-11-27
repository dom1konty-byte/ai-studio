import 'package:material_ui/material_ui.dart';

import '../state/app_controller.dart';
import 'anim.dart';
import 'files_screen.dart';
import 'internet_screen.dart';
import 'nav_panel.dart';
import 'main_screen.dart';
import 'programs_screen.dart';
import 'map_screen.dart';
import 'result_screen.dart';
import 'settings_screen.dart';
import 'startup_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key, required this.controller});
  final AppController controller;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  AppController get c => widget.controller;

  Widget _content() {
    if (c.phase == Phase.done) return ResultScreen(key: const ValueKey('done'), controller: c);
    switch (c.section) {
      case Section.main:
        return MainScreen(key: const ValueKey('main'), controller: c);
      case Section.downloads:
        return FilesScreen(key: const ValueKey('downloads'), controller: c, isDownloads: true);
      case Section.big:
        return FilesScreen(key: const ValueKey('big'), controller: c, isDownloads: false);
      case Section.map:
        return MapScreen(key: const ValueKey('map'), controller: c);
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavPanel(
                  controller: c,
                  width: c.settings.navWidth,
                  onWidthChanged: c.previewNavWidth,
                  onWidthCommitted: c.setNavWidth,
                ),
                Expanded(
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
              ],
            ),
          ),
        );
      },
    );
  }
}
