import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

const splashMs = 1500;
const _fadeMs = 150;
const _splashBg = Color(0xFFEEF6F6);
const _teal = Color(0xFF0F9D9A);

/// Заставка ~1,5 с (логотип держится ~0,5 с): капля падает, расходятся круги, капля становится логотипом.
/// Щелчок — пропуск. [enabled] = false или «Убрать анимации» — заставки нет.
class Splash extends StatefulWidget {
  const Splash({super.key, required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: splashMs + _fadeMs),
  );
  bool _started = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ctl.addStatusListener((st) {
      if (st == AnimationStatus.completed && mounted) setState(() => _done = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final off = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!widget.enabled || off) {
      _done = true;
    } else {
      _ctl.forward();
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// Пропуск: сразу к концу заставки, остаётся только плавное исчезновение.
  void _skip() {
    if (_ctl.value * (splashMs + _fadeMs) < splashMs) {
      _ctl.forward(from: splashMs / (splashMs + _fadeMs));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Stack держим всегда: иначе при смене дерева состояние экрана потерялось бы.
    // Пока идёт заставка, ввод под ней (мышь и клавиатура) заблокирован.
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: !_done,
          child: AbsorbPointer(absorbing: !_done, child: widget.child),
        ),
        if (!_done)
        Positioned.fill(
          child: GestureDetector(
            key: const Key('splash'),
            behavior: HitTestBehavior.opaque,
            onTap: _skip,
            child: AnimatedBuilder(
              animation: _ctl,
              builder: (_, __) {
                final ms = _ctl.value * (splashMs + _fadeMs);
                final fade = ms <= splashMs ? 1.0 : 1 - (ms - splashMs) / _fadeMs;
                return Opacity(
                  opacity: fade.clamp(0.0, 1.0),
                  child: ColoredBox(
                    color: _splashBg,
                    child: _SplashArt(ms: ms.clamp(0, splashMs.toDouble())),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

double _seg(double ms, double a, double b, Curve c) =>
    c.transform(((ms - a) / (b - a)).clamp(0.0, 1.0));

class _SplashArt extends StatelessWidget {
  const _SplashArt({required this.ms});
  final double ms;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cx = box.maxWidth / 2, cy = box.maxHeight / 2;
      // 0–420: капля падает сверху в центр.
      final fall = _seg(ms, 0, 420, Curves.easeInQuad);
      final dropY = -40 + (cy + 40) * fall;
      // 600–1000 (потом логотип держится до конца): капля становится логотипом (чуть крупнее), подпись проявляется.
      final morph = _seg(ms, 600, 1000, Curves.easeOut);
      final dropSize = 28 + 20 * morph;
      return Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _RipplePainter(ms, Offset(cx, cy)))),
          Positioned(
            left: cx - dropSize,
            top: dropY - dropSize,
            child: Icon(Icons.water_drop, size: dropSize * 2, color: _teal),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: cy + 56,
            child: Opacity(
              opacity: morph,
              child: const Text(
                'ЧистоДиск',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w600, color: Color(0xFF0B3F3E)),
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// Три круга на воде: 380–800 мс, каждый следующий позже на 100 мс.
class _RipplePainter extends CustomPainter {
  _RipplePainter(this.ms, this.center);
  final double ms;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    final maxR = math.min(size.width, size.height) * 0.3;
    for (var i = 0; i < 3; i++) {
      final t = _seg(ms, 380.0 + i * 100, 800.0 + i * 100, Curves.easeOutCubic);
      if (t <= 0 || t >= 1) continue;
      final r = maxR * (0.2 + 0.8 * t);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _teal.withValues(alpha: 0.5 * (1 - t));
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.ms != ms;
}
