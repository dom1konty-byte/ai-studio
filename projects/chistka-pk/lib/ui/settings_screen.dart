import 'package:material_ui/material_ui.dart';

import '../platform/platform_api.dart';
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
              key: const Key('admin-switch'),
              title: const Text('Режим администратора'),
              subtitle: const Text(
                  'Нужен, чтобы чистить системные папки и менять автозагрузку для всех. '
                  'Программа перезапустится и попросит разрешение Windows (UAC).'),
              value: c.adminMode,
              onChanged: c.canToggleAdmin ? (v) => toggleAdminWithDialog(context, controller, v) : null,
            ),
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

/// Спрашивает подтверждение и перезапускает программу с другими правами.
Future<void> toggleAdminWithDialog(BuildContext context, AppController controller, bool on) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(on
          ? 'Перезапустить с правами администратора?'
          : 'Перезапустить без прав администратора?'),
      content: Text(on
          ? 'Windows спросит разрешение (UAC). Окно программы закроется и откроется снова.'
          : 'Окно программы закроется и откроется снова.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Перезапустить')),
      ],
    ),
  );
  if (ok != true) return;
  final r = await controller.setAdminMode(on);
  if (!context.mounted) return;
  final msg = switch (r) {
    RelaunchResult.started => null,
    RelaunchResult.cancelled => 'Разрешение не получено',
    RelaunchResult.failed => 'Не удалось перезапустить программу.',
  };
  if (msg != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
