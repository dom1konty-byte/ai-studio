import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Заставка 2 с. Окно при запуске проявляется первые ~300 мс (WindowAnimator),
/// поэтому логотип начинает проявляться в 250 мс и виден целиком с 700 мс (≥ 1200 мс до конца).
const splashMs = 2000;
const _fadeMs = 150;
const _splashBg = Color(0xFFEEF6F6);
const _teal = Color(0xFF0F9D9A);

/// Заставка 2 с: логотип плавно проявляется (капля + подпись), по воде расходятся круги.
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
      // 250–700: логотип проявляется целиком (капля чуть опускается и растёт, подпись — следом).
      final logo = _seg(ms, 250, 700, Curves.easeOutCubic);
      final text = _seg(ms, 400, 750, Curves.easeOut);
      final dropSize = 40 + 8 * logo;
      final dropY = cy - 24 * (1 - logo);
      return Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _RipplePainter(ms, Offset(cx, cy)))),
          Positioned(
            left: cx - dropSize,
            top: dropY - dropSize,
            child: Opacity(
              opacity: logo,
              child: Icon(Icons.water_drop, size: dropSize * 2, color: _teal),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: cy + 56,
            child: Opacity(
              opacity: text,
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

/// Три круга на воде: 450–900 мс, каждый следующий позже на 100 мс.
class _RipplePainter extends CustomPainter {
  _RipplePainter(this.ms, this.center);
  final double ms;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    final maxR = math.min(size.width, size.height) * 0.3;
    for (var i = 0; i < 3; i++) {
      final t = _seg(ms, 450.0 + i * 100, 900.0 + i * 100, Curves.easeOutCubic);
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
