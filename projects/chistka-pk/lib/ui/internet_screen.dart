import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/speed.dart';
import '../state/app_controller.dart';
import 'anim.dart';

/// Экран «Интернет»: тест скорости через speed.cloudflare.com.
class InternetScreen extends StatefulWidget {
  const InternetScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<InternetScreen> createState() => _InternetScreenState();
}

enum _Status { idle, running, done, offline, failed }

class _InternetScreenState extends State<InternetScreen> {
  _Status _status = _Status.idle;
  SpeedPhase _phase = SpeedPhase.idle;
  double _gauge = 0;
  double? _ping;
  double? _down;
  double? _up;
  List<SpeedResult> _history = [];
  SpeedCancel? _cancel;
  StreamSubscription<SpeedEvent>? _sub;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.speedStore?.load().then((h) {
      if (mounted) setState(() => _history = h);
    });
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _start() {
    _cancel?.cancel();
    _sub?.cancel();
    final cancel = _cancel = SpeedCancel();
    setState(() {
      _status = _Status.running;
      _phase = SpeedPhase.ping;
      _gauge = 0;
      _ping = _down = _up = null;
    });
    _sub = SpeedTester(c.speedNetwork).run(cancel).listen(
      (e) {
        if (!mounted || cancel.isCancelled) return;
        setState(() {
          _phase = e.phase;
          switch (e.phase) {
            case SpeedPhase.ping:
              if (e.value > 0) _ping = e.value;
              _gauge = 0;
            case SpeedPhase.download:
              _down = e.value;
              _gauge = e.value;
            case SpeedPhase.upload:
              _up = e.value;
              _gauge = e.value;
            case SpeedPhase.done:
              final r = e.result!;
              _ping = r.pingMs;
              _down = r.downMbps;
              _up = r.upMbps;
              _gauge = 0;
              _status = _Status.done;
              _history = addToHistory(_history, r);
              c.speedStore?.save(_history);
            case SpeedPhase.idle:
              break;
          }
        });
      },
      onError: (Object e) {
        if (!mounted || cancel.isCancelled) return;
        setState(() {
          _status = e is SpeedException && !e.offline ? _Status.failed : _Status.offline;
          _gauge = 0;
        });
      },
    );
  }

  void _stop() {
    _cancel?.cancel();
    _sub?.cancel();
    setState(() {
      _status = _Status.idle;
      _phase = SpeedPhase.idle;
      _gauge = 0;
    });
  }

  void _clearHistory() {
    setState(() => _history = []);
    c.speedStore?.save(const []);
  }

  String get _phaseText {
    if (_status == _Status.running) {
      return switch (_phase) {
        SpeedPhase.ping => 'Измеряю пинг…',
        SpeedPhase.download => 'Загрузка…',
        SpeedPhase.upload => 'Отдача…',
        _ => '',
      };
    }
    return switch (_status) {
      _Status.done => 'Готово',
      _Status.failed => 'Тест не удался, попробуйте ещё раз',
      _ => 'Нажмите «Начать»',
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final running = _status == _Status.running;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Интернет', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              if (_status == _Status.offline) _offline(cs) else ...[
                _gaugeView(context, cs),
                const SizedBox(height: 4),
                Text(_phaseText,
                    key: const Key('speed-phase'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16,
                        color: _status == _Status.failed ? cs.error : cs.onSurfaceVariant)),
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      key: const Key('speed-button'),
                      onPressed: running ? _stop : _start,
                      child: Text(running
                          ? 'Остановить'
                          : _status == _Status.failed
                              ? 'Повторить'
                              : 'Начать'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _card(cs, Icons.timer_outlined, 'Пинг', _ping, 'мс', 'speed-ping'),
                    _card(cs, Icons.download, 'Загрузка', _down, 'Мбит/с', 'speed-down'),
                    _card(cs, Icons.upload, 'Отдача', _up, 'Мбит/с', 'speed-up'),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              _historyView(cs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _offline(ColorScheme cs) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(Icons.wifi_off, size: 64, color: cs.error),
            const SizedBox(height: 12),
            const Text('Нет подключения к интернету', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('speed-retry'),
              onPressed: _start,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );

  Widget _gaugeView(BuildContext context, ColorScheme cs) {
    final shown = _status == _Status.running && _phase != SpeedPhase.ping ? _gauge : 0.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: gaugeFraction(shown)),
      duration: animDuration(context, const Duration(milliseconds: 300)),
      curve: Curves.easeOutCubic,
      builder: (context, f, _) => SizedBox(
        height: 260,
        child: CustomPaint(
          painter: _GaugePainter(f, cs.primary, cs.surfaceContainerHighest, cs.onSurface),
          child: Align(
            alignment: const Alignment(0, 0.45),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  shown > 0 ? shown.toStringAsFixed(shown < 100 ? 1 : 0) : '0',
                  key: const Key('speed-big'),
                  style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w300),
                ),
                Text('Мбит/с', style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(ColorScheme cs, IconData icon, String title, double? v, String unit, String key) {
    return SizedBox(
      width: 200,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: cs.onSurfaceVariant)),
                    Text(v == null ? '—' : _fmt(v),
                        key: Key(key),
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                    Text(unit, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(double v) => v < 100 ? v.toStringAsFixed(1) : v.toStringAsFixed(0);

  static String _date(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  Widget _historyView(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
                child: Text('История', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
            if (_history.isNotEmpty)
              TextButton(onPressed: _clearHistory, child: const Text('Очистить историю')),
          ],
        ),
        if (_history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Замеров пока нет', style: TextStyle(color: cs.onSurfaceVariant)),
          )
        else
          for (final r in _history)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(_date(r.time))),
                  Expanded(flex: 2, child: Text('${_fmt(r.pingMs)} мс')),
                  Expanded(flex: 2, child: Text('↓ ${_fmt(r.downMbps)}')),
                  Expanded(flex: 2, child: Text('↑ ${_fmt(r.upMbps)}')),
                ],
              ),
            ),
      ],
    );
  }
}

/// Дуга 240° с заливкой и стрелкой.
class _GaugePainter extends CustomPainter {
  _GaugePainter(this.fraction, this.color, this.track, this.needle);
  final double fraction;
  final Color color;
  final Color track;
  final Color needle;

  static const _sweep = 4 * math.pi / 3; // 240°
  static const _start = 5 * math.pi / 6; // 150°

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width / 2, size.height / 1.4) - 14;
    final center = Offset(size.width / 2, size.height / 2 + 10);
    final rect = Rect.fromCircle(center: center, radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, p..color = track);
    if (fraction > 0) {
      canvas.drawArc(rect, _start, _sweep * fraction, false, p..color = color);
    }
    final a = _start + _sweep * fraction;
    final tip = center + Offset(math.cos(a), math.sin(a)) * (r - 26);
    canvas.drawLine(
        center,
        tip,
        Paint()
          ..color = needle
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(center, 6, Paint()..color = needle);
  }

  @override
  bool shouldRepaint(_GaugePainter o) =>
      o.fraction != fraction || o.color != color || o.track != track || o.needle != needle;
}
