import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../state/app_controller.dart';
import 'app.dart';
import 'main_screen.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.summary;
    final cs = Theme.of(context).colorScheme;

    if (c.failedAll || s == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 72, color: cs.error),
            const SizedBox(height: 16),
            const Text('Очистка прервана', style: TextStyle(fontSize: 28)),
            const SizedBox(height: 24),
            FilledButton(onPressed: c.reset, child: const Text('Назад')),
          ],
        ),
      );
    }

    final nothing = s.freedBytes == 0 && s.recycledBytes == 0;
    final before = s.freeBefore;
    final after = s.freeAfter;

    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                nothing ? Icons.info_outline : Icons.check_circle,
                size: 72,
                color: nothing ? cs.primary : successColor,
              ),
              const SizedBox(height: 16),
              Text(
                nothing ? 'Нечего было удалять' : 'Освобождено ${formatSize(s.freedBytes)}',
                style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w300),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text('Удалено файлов: ${s.deletedFiles}'),
              if (s.recycledBytes > 0)
                Text('Отправлено в Корзину: ${formatSize(s.recycledBytes)}'),
              if (before != null && after != null)
                Text('Было свободно ${formatSize(before)} → стало ${formatSize(after)}'),
              const SizedBox(height: 16),
              if (s.skippedFiles > 0)
                _Warn('Пропущено ${filesWord(s.skippedFiles)} — их используют другие программы'),
              if (s.browsersSkipped) const _Warn('Кэш браузеров не очищен'),
              if (s.logFailed)
                Text('Журнал не сохранён', style: TextStyle(color: cs.error, fontSize: 12)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(onPressed: c.openLog, child: const Text('Открыть журнал')),
                  const SizedBox(width: 16),
                  FilledButton(onPressed: c.reset, child: const Text('Готово')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Warn extends StatelessWidget {
  const _Warn(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: warningColor.withValues(alpha: 0.12),
      shape: cardShape(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: warningColor),
            const SizedBox(width: 8),
            Flexible(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
