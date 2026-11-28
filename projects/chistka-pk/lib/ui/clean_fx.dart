import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Мягкая «волна» поверх содержимого: светлый градиентный блик бежит слева
/// направо и повторяется, пока [active]. При отключённых анимациях — без блика.
class WaveSweep extends StatefulWidget {
  const WaveSweep({super.key, required this.active, required this.child, this.radius = 0});
  final bool active;
  final Widget child;
  final double radius;

  @override
  State<WaveSweep> createState() => _WaveSweepState();
}

class _WaveSweepState extends State<WaveSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  bool _off = false;

  void _sync() {
    final run = widget.active && !_off;
    if (run && !_ctl.isAnimating) {
      _ctl.repeat();
    } else if (!run && _ctl.isAnimating) {
      _ctl.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _off = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(WaveSweep old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || _off) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.radius),
              child: AnimatedBuilder(
                animation: _ctl,
                builder: (_, __) => CustomPaint(
                  key: const Key('wave-sweep'),
                  painter: _WavePainter(_ctl.value),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final band = size.width * 0.35;
    final x = -band + (size.width + band * 2) * t;
    final rect = Rect.fromLTWH(x - band / 2, 0, band, size.height);
    final shader = const LinearGradient(colors: [
      Color(0x00FFFFFF),
      Color(0x73FFFFFF),
      Color(0x00FFFFFF),
    ]).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.t != t;
}

const doneBurstMs = 900;

/// Кружок с галочкой: галочка «выпрыгивает» с масштабом, от кружка расходятся
/// 3 круга (как на воде) за ~900 мс. Проигрывается один раз при появлении.
/// Анимации отключены — сразу галочка.
class DoneBurst extends StatefulWidget {
  const DoneBurst({super.key, required this.size, required this.color, this.icon = Icons.check});
  final double size;
  final Color color;
  final IconData icon;

  @override
  State<DoneBurst> createState() => _DoneBurstState();
}

class _DoneBurstState extends State<DoneBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: doneBurstMs));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
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
    final s = widget.size;
    return SizedBox.square(
      dimension: s,
      child: AnimatedBuilder(
        animation: _ctl,
        builder: (_, __) {
          final check = Curves.elasticOut.transform((_ctl.value * 2).clamp(0.0, 1.0));
          return CustomPaint(
            key: const Key('done-burst'),
            painter: _RingsPainter(_ctl.value, widget.color),
            child: Center(
              child: Container(
                width: s,
                height: s,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                child: Transform.scale(
                  scale: check,
                  child: Icon(widget.icon, size: s * 0.6, color: Colors.white),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final p = ((t - i * 0.14) / 0.58).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final r = size.width / 2 * (1 + 0.9 * Curves.easeOut.transform(p));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, size.width * 0.04)
          ..color = color.withValues(alpha: 0.45 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t;
}
