import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../state/app_controller.dart';

/// Полоса «Есть новая версия» над всем окном.
final _thin = FilledButton.styleFrom(
  minimumSize: const Size(0, 24),
  padding: const EdgeInsets.symmetric(horizontal: 12),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  textStyle: const TextStyle(fontSize: 13),
);

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
            style: Rubka.body(size: 13, color: Rubka.onAmber));
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
            style: Rubka.body(size: 13, color: Rubka.error));
        actions = [
          FilledButton(
              style: _thin,
              onPressed: c.applyUpdate,
              child: const Text('Повторить')),
          IconButton(
              tooltip: 'Закрыть',
              iconSize: 16,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              onPressed: c.dismissUpdate,
              icon: const Icon(Icons.close)),
        ];
      case UpdateStatus.none:
        label = Text('Есть новая версия AI Studio',
            style: Rubka.body(size: 13, color: Rubka.onAmber));
        actions = [
          FilledButton(
              style: _thin.merge(accentButtonStyle),
              onPressed: c.applyUpdate,
              child: const Text('Обновить')),
          IconButton(
              tooltip: 'Закрыть',
              iconSize: 16,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              onPressed: c.dismissUpdate,
              icon: const Icon(Icons.close)),
        ];
    }
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Rubka.summaryBg,
        border: Border(bottom: BorderSide(color: Rubka.amber)),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_alt, size: 16, color: Rubka.onAmber),
          const SizedBox(width: 8),
          Expanded(child: label),
          for (final a in actions) ...[const SizedBox(width: 8), a],
        ],
      ),
    );
  }
}
