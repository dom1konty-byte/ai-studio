import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../state/app_controller.dart';

/// Ключи пунктов левой панели, на которые указывают подсказки.
final Map<Section, GlobalKey> onboardKeys = {
  Section.main: GlobalKey(debugLabel: 'onboard-main'),
  Section.computer: GlobalKey(debugLabel: 'onboard-computer'),
  Section.programs: GlobalKey(debugLabel: 'onboard-programs'),
};

class OnboardStep {
  const OnboardStep(this.title, this.text, this.target);
  final String title;
  final String text;

  /// Пункт панели; null — подсказка по центру без подсветки.
  final Section? target;
}

const onboardSteps = [
  OnboardStep('Здесь очистка', 'Быстрая очистка и поиск лишнего на диске.', Section.main),
  OnboardStep('Компьютер', 'Диск, процессы, батарея.', Section.computer),
  OnboardStep('Программы', 'Удаление программ полностью, вместе с остатками.', Section.programs),
  OnboardStep('Значок у часов', 'Щелчок по значку у часов — мини-окно.', null),
];

/// Подсказки первого запуска («coach marks»): затемнение с «окошком» вокруг
/// нужного элемента и пузырь с текстом. Показываются один раз (флаг
/// onboardingDone в настройках) или по кнопке в Настройках.
class Onboarding extends StatefulWidget {
  const Onboarding({
    super.key,
    required this.controller,
    required this.enabled,
    required this.child,
    this.delay = Duration.zero,
  });
  final AppController controller;
  final bool enabled;
  final Widget child;

  /// Пауза перед первым показом (пока идёт заставка).
  final Duration delay;

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  int _step = 0;
  late bool _ready = widget.delay == Duration.zero;
  Timer? _timer;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (!_ready) {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _ready = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _next() {
    if (_step >= onboardSteps.length - 1) {
      _finish();
    } else {
      setState(() => _step++);
    }
  }

  void _finish() {
    _step = 0;
    c.finishOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final show = widget.enabled &&
            _ready &&
            c.settingsLoaded &&
            !c.settings.onboardingDone &&
            !c.miniMode;
        // Всегда Stack: так основное дерево не пересоздаётся при показе подсказок.
        return Stack(
          children: [
            Positioned.fill(child: widget.child),
            if (show)
              Positioned.fill(
              child: _Coach(
                key: const Key('onboarding'),
                step: _step,
                onNext: _next,
                onSkip: _finish,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Coach extends StatefulWidget {
  const _Coach({super.key, required this.step, required this.onNext, required this.onSkip});
  final int step;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  State<_Coach> createState() => _CoachState();
}

class _CoachState extends State<_Coach> {
  Rect? _rect() {
    final t = onboardSteps[widget.step].target;
    final ctx = t == null ? null : onboardKeys[t]?.currentContext;
    final box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final me = context.findRenderObject();
    if (me is! RenderBox) return null;
    final topLeft = me.globalToLocal(box.localToGlobal(Offset.zero));
    return (topLeft & box.size).inflate(4);
  }

  @override
  Widget build(BuildContext context) {
    final step = onboardSteps[widget.step];
    final last = widget.step == onboardSteps.length - 1;
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final rect = _rect();
      const w = 360.0;
      const h = 190.0;
      final double left;
      final double top;
      if (rect == null) {
        left = (box.maxWidth - w) / 2;
        top = (box.maxHeight - h) / 2;
      } else {
        left = (rect.right + 16).clamp(8.0, (box.maxWidth - w - 8).clamp(8.0, double.infinity));
        top = (rect.center.dy - h / 2).clamp(8.0, (box.maxHeight - h - 8).clamp(8.0, double.infinity));
      }
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(painter: _DimPainter(rect)),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: w,
            child: Material(
              key: const Key('onboarding-bubble'),
              color: cs.surface,
              elevation: 8,
              shadowColor: const Color(0xFF143C46),
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Шаг ${widget.step + 1} из ${onboardSteps.length}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(step.title,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(step.text, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          key: const Key('onboarding-skip'),
                          onPressed: widget.onSkip,
                          child: const Text('Пропустить'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const Key('onboarding-next'),
                          onPressed: widget.onNext,
                          style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
                          child: Text(last ? 'Понятно' : 'Далее'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// Затемнение с «окошком» вокруг целевого элемента.
class _DimPainter extends CustomPainter {
  _DimPainter(this.hole);
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Path()..addRect(Offset.zero & size);
    final path = hole == null
        ? all
        : Path.combine(PathOperation.difference, all,
            Path()..addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(24))));
    canvas.drawPath(path, Paint()..color = const Color(0x8C000000));
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole;
}
