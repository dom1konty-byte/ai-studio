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
          key: const Key('limit-banner'),
          height: 32,
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          decoration: const BoxDecoration(
            color: Rubka.summaryBg,
            border: Border(bottom: BorderSide(color: Rubka.amber)),
          ),
          child: Row(
            children: [
              const Icon(Icons.hourglass_top, size: 16, color: Rubka.onAmber),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Лимит до ${hhmm(until)}. Чаты ждут',
                    style: Rubka.body(size: 13, color: Rubka.onAmber)),
              ),
              TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: controller.clearLimit,
                  child: const Text('Всё равно отправить')),
            ],
          ),
        );
      },
    );
  }
}
