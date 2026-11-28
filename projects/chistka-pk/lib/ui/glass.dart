import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'anim.dart';

/// Включён ли вид «Стекло» (настройка + эффект реально применён).
class GlassScope extends InheritedWidget {
  const GlassScope({super.key, required this.on, required super.child});
  final bool on;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassScope>()?.on ?? false;

  @override
  bool updateShouldNotify(GlassScope old) => old.on != on;
}

/// Фон окна: белый-мятный 72 % поверх Mica (тёмная тема — тёмный 72 %).
Color glassScaffoldColor(Brightness b) =>
    b == Brightness.light ? const Color(0xB8F4FAFA) : const Color(0xB8101818);

/// Левая панель: белый 38 % (стекло) или сплошной #E3F1F1.
Color navPanelColor(BuildContext context, {required bool glass}) {
  final light = Theme.of(context).brightness == Brightness.light;
  if (glass) return light ? const Color(0x61FFFFFF) : const Color(0x14FFFFFF);
  return light ? const Color(0xFFE3F1F1) : Theme.of(context).colorScheme.surfaceContainer;
}

/// Живой фон левой панели: медленные волны (период 10 с, прозрачность 5 %).
/// Стоит под RepaintBoundary; кадры не идут, если окно скрыто/свёрнуто
/// или в Windows включено «Убрать анимации».
/// Окно сейчас на экране. Ставят TrayService и WindowAnimator: при скрытии волны
/// останавливаются явно, не дожидаясь AppLifecycleState.
final ValueNotifier<bool> windowShown = ValueNotifier<bool>(true);

class WavesBackground extends StatefulWidget {
  const WavesBackground({super.key});

  @override
  State<WavesBackground> createState() => _WavesBackgroundState();
}

class _WavesBackgroundState extends State<WavesBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ctl =
      AnimationController(vsync: this, duration: const Duration(seconds: 10));
  bool _visible = true;
  bool _off = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final st = WidgetsBinding.instance.lifecycleState;
    _visible = st == null || st == AppLifecycleState.resumed || st == AppLifecycleState.inactive;
    windowShown.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _off = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    _sync();
  }

  void _sync() {
    final run = _visible && windowShown.value && !_off;
    if (run && !_ctl.isAnimating) {
      _ctl.repeat();
    } else if (!run && _ctl.isAnimating) {
      _ctl.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    windowShown.removeListener(_sync);
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        key: const Key('waves'),
        painter: _WavesPainter(_ctl),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _WavesPainter extends CustomPainter {
  _WavesPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final phase = t.value * 2 * math.pi;
    for (var i = 0; i < 3; i++) {
      final base = size.height * (0.55 + 0.17 * i);
      final amp = 10.0 + 4 * i; // низкая амплитуда
      final path = Path()..moveTo(0, size.height);
      for (var x = 0.0; x <= size.width + 8; x += 8) {
        final y = base +
            amp * math.sin(x / size.width * 2 * math.pi * (1 + i * 0.4) + phase * (i.isEven ? 1 : -1));
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0xFF0F9D9A).withValues(alpha: 0.05));
    }
  }

  @override
  bool shouldRepaint(_WavesPainter old) => old.t != t;
}

/// Появление снизу вверх: сдвиг 12 px + проявление за 260 мс, с задержкой 40 мс
/// на каждый следующий [index]. Один раз при появлении в дереве.
class StaggerIn extends StatefulWidget {
  const StaggerIn({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn> with SingleTickerProviderStateMixin {
  static const _itemMs = 260;
  static const _stepMs = 40;
  late final int _delay = _stepMs * math.min(widget.index, 8);
  late final AnimationController _ctl = AnimationController(
      vsync: this, duration: Duration(milliseconds: _delay + _itemMs));
  late final Animation<double> _a = CurvedAnimation(
    parent: _ctl,
    curve: Interval(_delay / (_delay + _itemMs), 1, curve: Curves.easeOutCubic),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (animDuration(context, const Duration(milliseconds: 1)) == Duration.zero) {
      _ctl.value = 1;
    } else {
      _ctl.forward();
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _a,
      child: AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (_, child) =>
            Transform.translate(offset: Offset(0, 12 * (1 - _a.value)), child: child),
      ),
    );
  }
}
