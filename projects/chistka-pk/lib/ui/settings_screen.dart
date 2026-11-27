import 'package:material_ui/material_ui.dart';

import '../state/app_controller.dart';

/// Экран «Настройки».
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Настройки',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Запускать вместе с Windows (в трее)'),
              value: c.autostartOn,
              onChanged: (v) async {
                final ok = await c.setAutostart(v);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Не удалось изменить настройку.')),
                  );
                }
              },
            ),
            SwitchListTile(
              title: const Text('Сворачивать в трей при закрытии'),
              value: c.settings.minimizeToTray,
              onChanged: c.setMinimizeToTray,
            ),
          ],
        );
      },
    );
  }
}
