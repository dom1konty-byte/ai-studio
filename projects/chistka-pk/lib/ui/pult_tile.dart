import 'package:material_ui/material_ui.dart';

import 'anim.dart';
import 'app.dart';

/// Состояние плитки пульта.
enum TileKind { normal, busy, result, error, soon, summary }

/// Плитка пульта («Очистка», «Компьютер»): иконка в кружке, название, одна строка
/// и одно действие. Состояния: обычная / процесс / результат / ошибка / «Скоро».
class PultTile extends StatelessWidget {
  const PultTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.caption,
    this.kind = TileKind.normal,
    this.actionLabel = 'Открыть',
    this.onAction,
    this.progressText = '',
    this.resultText = '',
    this.onStop,
    this.onRetry,
    this.onAgain,
    this.summary = '',
    this.summaryIcon = Icons.check_circle,
    this.summaryColor = successColor,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String caption;
  final TileKind kind;
  final String actionLabel;
  final VoidCallback? onAction;
  final String progressText;
  final String resultText;
  final VoidCallback? onStop;
  final VoidCallback? onRetry;
  final VoidCallback? onAgain;

  /// Итог крупной строкой с иконкой состояния ([TileKind.summary]).
  final String summary;
  final IconData summaryIcon;
  final Color summaryColor;

  /// Нажатие на всю плитку.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grey = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final Widget middle;
    final Widget bottom;
    switch (kind) {
      case TileKind.normal:
        middle = Text(caption, style: grey, maxLines: 1, overflow: TextOverflow.ellipsis);
        bottom = FilledButton.tonal(onPressed: onAction, child: Text(actionLabel));
      case TileKind.soon:
        middle = Text(caption, style: grey, maxLines: 1, overflow: TextOverflow.ellipsis);
        bottom = const FilledButton.tonal(onPressed: null, child: Text('Скоро'));
      case TileKind.summary:
        middle = Row(
          children: [
            Icon(summaryIcon, size: 20, color: summaryColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
          ],
        );
        bottom = FilledButton.tonal(onPressed: onAction, child: Text(actionLabel));
      case TileKind.busy:
        middle = Text(caption, style: grey, maxLines: 1, overflow: TextOverflow.ellipsis);
        bottom = Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 4),
                  Text(progressText, style: grey, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (onStop != null) TextButton(onPressed: onStop, child: const Text('Стоп')),
          ],
        );
      case TileKind.result:
        middle = Row(
          children: [
            const Icon(Icons.check_circle, size: 18, color: successColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(resultText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ],
        );
        bottom = Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (onAction != null) FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
            if (onAgain != null) TextButton(onPressed: onAgain, child: const Text('Ещё раз')),
          ],
        );
      case TileKind.error:
        middle = Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: cs.error),
            const SizedBox(width: 6),
            Expanded(child: Text('Не удалось', style: TextStyle(fontSize: 14, color: cs.error))),
          ],
        );
        bottom = Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: onRetry, child: const Text('Повторить')),
        );
    }
    final body = Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 136),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconCircle(icon: icon, color: color, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              middle,
              const SizedBox(height: 12),
              bottom,
            ],
          ),
        ),
      );
    return HoverCard(
      child: onTap == null
          ? body
          : InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: body),
    );
  }
}

/// Иконка в цветном кружке (фон — цвет с прозрачностью 14 %).
class IconCircle extends StatelessWidget {
  const IconCircle({super.key, required this.icon, required this.color, this.size = 40});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.55, color: color),
      );
}

/// Карточка с рамкой 1 px; при наведении поднимается на 1 px, рамка — бирюзовая.
class HoverCard extends StatefulWidget {
  const HoverCard({super.key, required this.child});
  final Widget child;

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: animDuration(context, const Duration(milliseconds: 120)),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -1 : 0, 0),
        decoration: BoxDecoration(
          color: light ? Colors.white : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hover
                ? const Color(0xFF0F9D9A)
                : (light ? const Color(0xFFD5E6E6) : cs.outlineVariant),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(16),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Сетка плиток: 3 колонки при ширине от 720, 2 — от 480, иначе 1; отступ 16.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final cols = w >= 720 ? 3 : (w >= 480 ? 2 : 1);
      final tileW = (w - 16 * (cols - 1)) / cols;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [for (final t in children) SizedBox(width: tileW, child: t)],
      );
    });
  }
}
