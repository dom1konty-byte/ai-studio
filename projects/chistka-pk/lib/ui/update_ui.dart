import 'package:material_ui/material_ui.dart';

import '../core/update.dart';
import '../state/app_controller.dart';

/// Баннер вверху контента: «Доступна версия X · Обновить» / «Позже».
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final u = controller.showUpdateBanner ? controller.availableUpdate : null;
        if (u == null) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        return Material(
          key: const Key('update-banner'),
          color: cs.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.system_update_alt, color: cs.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Доступна версия ${u.version}',
                      style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
                ),
                FilledButton(
                  key: const Key('update-now'),
                  onPressed: () => showUpdateDialog(context, controller),
                  child: const Text('Обновить'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const Key('update-later'),
                  onPressed: controller.hideUpdateBanner,
                  child: const Text('Позже'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Ручная проверка из «О программе»: итог — в сообщении снизу.
Future<void> checkUpdatesManually(BuildContext context, AppController c) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final r = await c.checkForUpdates();
  final text = switch (r) {
    UpdateCheck.upToDate => 'У вас последняя версия.',
    UpdateCheck.available => 'Доступна версия ${c.availableUpdate?.version}. Баннер вверху окна.',
    UpdateCheck.error => 'Не удалось проверить обновления. Проверьте интернет.',
  };
  messenger?.showSnackBar(SnackBar(content: Text(text)));
}

/// Диалог скачивания и установки: этапы, «Отмена», при ошибке — «Повторить».
Future<void> showUpdateDialog(BuildContext context, AppController c) async {
  final done = c.installUpdate();
  final err = await showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      done.then((e) {
        if (ctx.mounted) Navigator.of(ctx).pop(e ?? '');
      });
      return ListenableBuilder(
        listenable: c,
        builder: (_, __) => AlertDialog(
          title: const Text('Обновление'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(updateStageText(c.updateStage, c.updateReceived, c.updateTotal),
                  key: const Key('update-stage')),
              const SizedBox(height: 12),
              LinearProgressIndicator(key: const Key('update-progress'), value: c.updateProgress),
            ],
          ),
          actions: [
            if (c.updateStage == UpdateStage.downloading)
              TextButton(
                key: const Key('update-cancel'),
                onPressed: c.cancelUpdate,
                child: const Text('Отмена'),
              ),
          ],
        ),
      );
    },
  );
  if (err != null && err.isNotEmpty && context.mounted) {
    final retry = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Не получилось обновить'),
        content: Text(err),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Закрыть')),
          FilledButton(
              key: const Key('update-retry'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Повторить')),
        ],
      ),
    );
    if (retry == true && context.mounted) await showUpdateDialog(context, c);
  }
}
