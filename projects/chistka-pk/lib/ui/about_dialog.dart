import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/update.dart';
import '../state/app_controller.dart';
import 'anim.dart';
import 'update_ui.dart';

export '../core/update.dart' show appVersion;

const publisherName = 'Дамир';
final ideaUrl = Uri.parse('https://t.me/dmrzhvm');

/// Окно «О программе»: появляется с масштабом 0,92→1 и прозрачностью.
Future<void> showAboutChisto(BuildContext context, AppController controller) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Закрыть',
    barrierColor: Colors.black54,
    transitionDuration: animDuration(context, const Duration(milliseconds: 200)),
    pageBuilder: (ctx, _, __) => _AboutDialog(controller),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _AboutDialog extends StatelessWidget {
  const _AboutDialog(this.controller);
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                child: Icon(Icons.water_drop, size: 40, color: cs.onPrimary),
              ),
              const SizedBox(height: 16),
              const Text('ЧистоДиск',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Версия $appVersion'),
              const SizedBox(height: 4),
              const Text('Издатель: $publisherName'),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () =>
                    launchUrl(ideaUrl, mode: LaunchMode.externalApplication).catchError((_) => false),
                icon: const Icon(Icons.send),
                label: const Text('Предложить идею / связь'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('check-updates'),
                onPressed: () => checkUpdatesManually(context, controller),
                icon: const Icon(Icons.system_update_alt),
                label: const Text('Проверить обновления'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
