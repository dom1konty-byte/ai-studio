import 'package:material_ui/material_ui.dart';

import 'anim.dart';
import 'app.dart';
import 'clean_fx.dart';
import 'glass.dart';

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
    this.tint,
    this.wave = false,
    this.burst = false,
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

  /// Фон плитки (версия 1.4); без него — белая карточка.
  final Color? tint;

  /// Идёт удаление: по плитке бежит «волна».
  final bool wave;

  /// Только что очищено: галочка с кругами на воде вместо значка.
  final bool burst;

  /// Нажатие на всю плитку.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final grey = TextStyle(fontSize: 13, color: dark ? cs.onSurfaceVariant : const Color(0xFF3F4F4F));
    final Widget middle;
    final Widget bottom;
    switch (kind) {
      case TileKind.normal:
        middle = Text(caption, style: grey, maxLines: 1, overflow: TextOverflow.ellipsis);
        bottom = _tileButton(onAction, actionLabel);
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
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            ),
          ],
        );
        bottom = _tileButton(onAction, actionLabel);
      case TileKind.busy:
        middle = Text(caption, style: grey, maxLines: 1, overflow: TextOverflow.ellipsis);
        bottom = Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    color: const Color(0xFF3B78C2),
                    backgroundColor: dark ? null : const Color(0xB3FFFFFF),
                    borderRadius: BorderRadius.circular(4),
                  ),
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
            if (onAction != null) _tileButton(onAction, actionLabel),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 168 - 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (burst)
                    DoneBurst(size: 40, color: color)
                  else
                    IconCircle(icon: icon, color: color, size: 40, solid: tint != null, live: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              middle,
              const SizedBox(height: 14),
              bottom,
            ],
          ),
        ),
      );
    return HoverCard(
      tint: tint,
      child: WaveSweep(
        active: wave,
        radius: cardRadius,
        child: onTap == null
          ? body
          : InkWell(borderRadius: BorderRadius.circular(cardRadius), onTap: onTap, child: body),
      ),
    );
  }
}

/// Кнопка в плитке: белая 75 % с мягкой тенью, текст #1B2B2B.
Widget _tileButton(VoidCallback? onPressed, String label) => FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xBFFFFFFF),
        foregroundColor: const Color(0xFF1B2B2B),
        disabledBackgroundColor: const Color(0x80FFFFFF),
        disabledForegroundColor: const Color(0x991B2B2B),
        elevation: 2,
        shadowColor: const Color(0xFF143C46),
        minimumSize: const Size(96, 48),
      ),
      child: Text(label),
    );

/// Иконка в кружке: ровный круг. [solid] — насыщенный кружок с белой иконкой,
/// иначе цвет с прозрачностью 14 %. [live] — «оживает» при наведении на плитку.
class IconCircle extends StatelessWidget {
  const IconCircle(
      {super.key,
      required this.icon,
      required this.color,
      this.size = 40,
      this.solid = false,
      this.live = false});
  final IconData icon;
  final Color color;
  final double size;
  final bool solid;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final circle = SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: solid ? color : color.withValues(alpha: 0.14), shape: BoxShape.circle),
        child: Center(child: Icon(icon, size: size * 0.55, color: solid ? Colors.white : color)),
      ),
    );
    if (!live) return circle;
    final hover = _HoverScope.maybeOf(context);
    if (hover == null) return circle;
    final d = animDuration(context, const Duration(milliseconds: 250));
    return ValueListenableBuilder<bool>(
      valueListenable: hover,
      child: circle,
      builder: (_, on, child) => AnimatedRotation(
        turns: on ? 0.015 : 0,
        duration: d,
        curve: Curves.easeOutBack,
        child: AnimatedScale(
          scale: on ? 1.08 : 1,
          duration: d,
          curve: Curves.easeOutBack,
          child: child,
        ),
      ),
    );
  }
}

class _HoverScope extends InheritedWidget {
  const _HoverScope({required this.hover, required super.child});
  final ValueNotifier<bool> hover;

  static ValueNotifier<bool>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_HoverScope>()?.hover;

  // Уведомляет сам ValueNotifier, перестраивать подписчиков при смене виджета не нужно.
  @override
  bool updateShouldNotify(_HoverScope old) => false;
}

/// Карточка без рамки: мягкая тень, радиус 24. При наведении поднимается на 2 px,
/// тень глубже, иконка плитки «оживает». Перерисовывается только сама карточка.
class HoverCard extends StatefulWidget {
  const HoverCard({super.key, required this.child, this.tint});
  final Widget child;

  /// Цвет фона (в тёмной теме не используется).
  final Color? tint;

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  final ValueNotifier<bool> _hover = ValueNotifier(false);

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final radius = BorderRadius.circular(cardRadius);
    final d = animDuration(context, const Duration(milliseconds: 160));
    return MouseRegion(
      onEnter: (_) => _hover.value = true,
      onExit: (_) => _hover.value = false,
      child: ValueListenableBuilder<bool>(
        valueListenable: _hover,
        child: _HoverScope(
          hover: _hover,
          child: Material(type: MaterialType.transparency, borderRadius: radius, child: widget.child),
        ),
        builder: (_, on, child) => AnimatedContainer(
          duration: d,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, on ? -2 : 0, 0),
          decoration: BoxDecoration(
            color: light ? (widget.tint ?? Colors.white) : cs.surfaceContainerHigh,
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF143C46).withValues(alpha: on ? 0.18 : 0.09),
                blurRadius: on ? 28 : 20,
                offset: Offset(0, on ? 10 : 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Сетка плиток: 3 колонки при ширине от 720, 2 — от 480, иначе 1; отступ 24.
/// Плитки появляются по очереди снизу вверх (один раз при входе в раздел).
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final cols = w >= 720 ? 3 : (w >= 480 ? 2 : 1);
      final tileW = (w - blockGap * (cols - 1)) / cols;
      return Wrap(
        spacing: blockGap,
        runSpacing: blockGap,
        children: [
          for (var i = 0; i < children.length; i++)
            SizedBox(width: tileW, child: StaggerIn(index: i, child: children[i])),
        ],
      );
    });
  }
}

/// Оттенки плиток версии 1.4: фон плитки и насыщенный кружок.
class TileTint {
  const TileTint(this.bg, this.dot);
  final Color bg;
  final Color dot;
}

const tintDownloads = TileTint(Color(0xFFDCEBFA), Color(0xFF3B78C2)); // голубой
const tintBig = TileTint(Color(0xFFF6E9CF), Color(0xFFA9740A)); // песочный
const tintDupes = TileTint(Color(0xFFE8E0F6), Color(0xFF7B5EA7)); // сиреневый
const tintEmpty = TileTint(Color(0xFFFCE3D6), Color(0xFFC2552B)); // персиковый
const tintMap = TileTint(Color(0xFFD6F2E6), Color(0xFF1B8A5C)); // мятный
const tintDisk = tintDownloads; // Компьютер: диск — голубой
const tintProcs = TileTint(Color(0xFFFADCD8), Color(0xFFC8473A)); // коралловый
const tintBattery = TileTint(Color(0xFFDDEFD3), Color(0xFF3E8E3A)); // зелёный
