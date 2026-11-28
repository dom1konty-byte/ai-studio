import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../state/app_controller.dart';

/// Полоса «Есть новая версия» над всем окном.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (!c.updateVisible) return const SizedBox.shrink();
    final Widget label;
    final List<Widget> actions;
    switch (c.updateStatus) {
      case UpdateStatus.downloading:
      case UpdateStatus.installing:
        label = Text(
            c.updateStatus == UpdateStatus.downloading
                ? 'Скачиваю…'
                : 'Ставлю…',
            style: Rubka.body(size: 14, color: Rubka.onAmber));
        actions = const [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ];
      case UpdateStatus.error:
        label = Text('Не обновилось: ${c.updateError ?? 'ошибка'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Rubka.body(size: 14, color: Rubka.error));
        actions = [
          FilledButton(
              onPressed: c.applyUpdate, child: const Text('Повторить')),
          IconButton(
              tooltip: 'Закрыть',
              onPressed: c.dismissUpdate,
              icon: const Icon(Icons.close)),
        ];
      case UpdateStatus.none:
        label = Text('Есть новая версия AI Studio',
            style: Rubka.body(size: 14, color: Rubka.onAmber));
        actions = [
          FilledButton(
              onPressed: c.applyUpdate, child: const Text('Обновить')),
          IconButton(
              tooltip: 'Закрыть',
              onPressed: c.dismissUpdate,
              icon: const Icon(Icons.close)),
        ];
    }
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Rubka.summaryBg,
        border: Border(bottom: BorderSide(color: Rubka.amber)),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_alt, size: 20, color: Rubka.onAmber),
          const SizedBox(width: 8),
          Expanded(child: label),
          for (final a in actions) ...[const SizedBox(width: 8), a],
        ],
      ),
    );
  }
}
