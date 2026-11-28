import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../services/rate_limit.dart';
import '../state/app_controller.dart';

/// Янтарная плашка «Лимит до HH:MM. Чаты ждут» (пусто, если лимита нет).
class LimitBanner extends StatelessWidget {
  const LimitBanner({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final until = controller.activeLimit;
        if (until == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          decoration: BoxDecoration(
            color: Rubka.summaryBg,
            border: Border.all(color: Rubka.amber),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.hourglass_top, size: 18, color: Rubka.onAmber),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Лимит до ${hhmm(until)}. Чаты ждут',
                    style: Rubka.body(size: 14, color: Rubka.onAmber)),
              ),
              TextButton(
                  onPressed: controller.clearLimit,
                  child: const Text('Всё равно отправить')),
            ],
          ),
        );
      },
    );
  }
}
