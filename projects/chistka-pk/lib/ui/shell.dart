import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../state/app_controller.dart';
import 'files_screen.dart';
import 'main_screen.dart';
import 'map_screen.dart';
import 'result_screen.dart';

class Shell extends StatelessWidget {
  const Shell({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final busy = c.phase == Phase.analyzing || c.phase == Phase.cleaning;
        final Widget content;
        if (c.phase == Phase.done) {
          content = ResultScreen(controller: c);
        } else {
          switch (c.section) {
            case Section.main:
              content = MainScreen(controller: c);
            case Section.downloads:
              content = FilesScreen(controller: c, isDownloads: true);
            case Section.big:
              content = FilesScreen(controller: c, isDownloads: false);
            case Section.map:
              content = MapScreen(controller: c);
          }
        }
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  extended: true,
                  minExtendedWidth: 240,
                  selectedIndex: c.phase == Phase.done ? 0 : c.section.index,
                  onDestinationSelected: busy ? null : (i) => c.go(Section.values[i]),
                  leading: const Padding(
                    padding: EdgeInsets.fromLTRB(8, 16, 8, 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.water_drop, color: Color(0xFF0F9D9A), size: 32),
                        SizedBox(width: 8),
                        Text('ЧистоДиск',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.cleaning_services_outlined),
                      selectedIcon: Icon(Icons.cleaning_services),
                      label: Text('Главный'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.download_outlined),
                      selectedIcon: Icon(Icons.download),
                      label: Text('Загрузки'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.data_usage),
                      label: Text('Большие файлы'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.pie_chart_outline),
                      label: Text('Карта диска'),
                    ),
                  ],
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'За всё время: ${formatSize(c.totalFreedEver)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            TextButton.icon(
                              onPressed: c.openLog,
                              icon: const Icon(Icons.description_outlined),
                              label: const Text('Открыть журнал'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Padding(padding: const EdgeInsets.all(24), child: content),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
