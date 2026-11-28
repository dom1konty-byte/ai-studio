// Лёгкая анимация и плотность интерфейса. Всё отключается через
// MediaQuery.disableAnimations.
import 'package:material_ui/material_ui.dart';

const Duration kMotion = Duration(milliseconds: 220);
const Curve kCurve = Curves.easeOutCubic;

/// true — анимации выключены (системная настройка или тест).
bool motionOff(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// Компактный режим для всего дерева.
class Density extends InheritedWidget {
  const Density({super.key, required this.compact, required super.child});

  final bool compact;

  static bool compactOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Density>()?.compact ?? false;

  @override
  bool updateShouldNotify(Density oldWidget) => compact != oldWidget.compact;
}

/// Появление: fade + сдвиг снизу на [dy] px, с задержкой [delay].
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.dy = 8,
    this.duration = kMotion,
  });

  final Widget child;
  final Duration delay;
  final double dy;
  final Duration duration;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final total = widget.delay + widget.duration;
    _c = AnimationController(vsync: this, duration: total);
    _t = CurvedAnimation(
      parent: _c,
      curve: Interval(widget.delay.inMilliseconds / total.inMilliseconds, 1,
          curve: kCurve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (motionOff(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _t,
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, child) => Transform.translate(
              offset: Offset(0, (1 - _t.value) * widget.dy), child: child),
          child: widget.child,
        ),
      );
}

/// Число, которое «докручивается» к новому значению.
/// [format] получает текущие (промежуточные) значения.
class CountText extends StatefulWidget {
  const CountText({
    super.key,
    this.textKey,
    required this.values,
    required this.format,
    required this.style,
  });

  final Key? textKey;
  final List<double> values;
  final String Function(List<double> v) format;
  final TextStyle style;

  @override
  State<CountText> createState() => _CountTextState();
}

class _CountTextState extends State<CountText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300), value: 1);
  late List<double> _from = widget.values;
  late List<double> _to = widget.values;

  List<double> _now() {
    final t = kCurve.transform(_c.value);
    if (t >= 1) return _to;
    return [for (var i = 0; i < _to.length; i++) _from[i] + (_to[i] - _from[i]) * t];
  }

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(CountText old) {
    super.didUpdateWidget(old);
    if (_same(widget.values, _to)) return;
    if (motionOff(context)) {
      _from = _to = widget.values;
      _c.value = 1;
    } else {
      _from = _now();
      _to = widget.values;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Text(widget.format(_now()),
            key: widget.textKey, style: widget.style),
      );
}

/// Лёгкий подъём при наведении мыши: тень + scale 1.01.
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.child, this.radius = 22});

  final Widget child;
  final double radius;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final d = motionOff(context) ? Duration.zero : const Duration(milliseconds: 150);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.01 : 1,
        duration: d,
        curve: kCurve,
        child: AnimatedContainer(
          duration: d,
          curve: kCurve,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: _hover
                ? const [
                    BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 14,
                        offset: Offset(0, 4)),
                  ]
                : const [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
