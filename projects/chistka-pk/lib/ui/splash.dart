import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'frame_log.dart';
import 'glass.dart' show windowShown;

/// Заставка 2 с. Окно показано сразу непрозрачным с фоном заставки;
/// логотип проявляется внутри Flutter: 80–700 мс (easeOutCubic), дальше лёгкое «дыхание».
const splashMs = 2000;
const _fadeMs = 150;
const _splashBg = Color(0xFFEEF6F6);
const _teal = Color(0xFF0F9D9A);

/// Заставка 2 с: логотип плавно проявляется (капля + подпись), по воде расходятся круги.
/// Щелчок — пропуск. [enabled] = false или «Убрать анимации» — заставки нет.
/// Пока заставка идёт, волны фона и тяжёлая работа не запускаются;
/// [onDone] — заставка закончилась (или её нет).
class Splash extends StatefulWidget {
  const Splash({super.key, required this.enabled, required this.child, this.onDone});
  final bool enabled;
  final Widget child;
  final VoidCallback? onDone;

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: splashMs + _fadeMs),
  );
  final _log = FrameLog('splash');
  bool _started = false;
  bool _done = false;

  // Логотип строится один раз; в кадре меняются только opacity и transform.
  static const _logo = RepaintBoundary(child: _Logo());

  @override
  void initState() {
    super.initState();
    _ctl.addStatusListener((st) {
      if (st == AnimationStatus.completed && mounted) _finish();
    });
  }

  void _finish() {
    _log.stop();
    setState(() => _done = true);
    windowShown.value = true; // волны фона — только после заставки
    widget.onDone?.call();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final off = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!widget.enabled || off) {
      _done = true;
      if (widget.onDone != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone?.call());
      }
    } else {
      windowShown.value = false;
      _log.start();
      _ctl.forward();
    }
  }

  @override
  void dispose() {
    _log.stop();
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
                child: _logo,
                builder: (_, logo) {
                  final ms = _ctl.value * (splashMs + _fadeMs);
                  final fade = ms <= splashMs ? 1.0 : 1 - (ms - splashMs) / _fadeMs;
                  return Opacity(
                    opacity: fade.clamp(0.0, 1.0),
                    child: ColoredBox(
                      color: _splashBg,
                      child: _SplashArt(ms: ms.clamp(0, splashMs.toDouble()), logo: logo!),
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

/// Капля и подпись: статичная картинка, не перерисовывается в кадрах.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.water_drop, size: 96, color: _teal),
        SizedBox(height: 24),
        Text(
          'ЧистоДиск',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Color(0xFF0B3F3E)),
        ),
      ],
    );
  }
}

class _SplashArt extends StatelessWidget {
  const _SplashArt({required this.ms, required this.logo});
  final double ms;
  final Widget logo;

  @override
  Widget build(BuildContext context) {
    // 80–700: логотип проявляется (чуть растёт и поднимается, easeOutCubic);
    // потом медленное «дыхание» ±1,2 % (период 2 с), плавно включается.
    final appear = _seg(ms, 80, 700, Curves.easeOutCubic);
    final breathe = _seg(ms, 700, 1000, Curves.easeInOut) *
        math.sin((ms - 700) / 2000 * 2 * math.pi) *
        0.012;
    final scale = 0.92 + 0.08 * appear + breathe;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _RipplePainter(ms)),
          ),
        ),
        Center(
          child: Opacity(
            opacity: appear,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - appear)),
              child: Transform.scale(scale: scale, child: logo),
            ),
          ),
        ),
      ],
    );
  }
}

/// Три круга на воде: 450–900 мс, каждый следующий позже на 100 мс (простые линии, без размытия).
class _RipplePainter extends CustomPainter {
  _RipplePainter(this.ms);
  final double ms;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 20);
    final maxR = math.min(size.width, size.height) * 0.3;
    for (var i = 0; i < 3; i++) {
      final t = _seg(ms, 450.0 + i * 100, 900.0 + i * 100, Curves.easeOutCubic);
      if (t <= 0 || t >= 1) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _teal.withValues(alpha: 0.5 * (1 - t));
      canvas.drawCircle(center, maxR * (0.2 + 0.8 * t), paint);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.ms != ms;
}
