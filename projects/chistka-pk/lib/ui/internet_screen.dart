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

  static const _teal = Color(0xFF0B7C7A);
  static const _tealLight = Color(0xFF17B3AE);
  static const _border = Color(0xFFD5E6E6);

  SpeedResult? get _last => _history.isEmpty ? null : _history.first;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final running = _status == _Status.running;
    final offline = _status == _Status.offline;
    final String subtitle;
    subtitle = _last == null ? 'Замер ещё не делали' : 'Замер ${_date(_last!.time)}';
    final label = running
        ? 'Остановить'
        : (_status == _Status.done || _history.isNotEmpty || _status == _Status.failed)
            ? (_status == _Status.failed ? 'Повторить' : 'Повторить замер')
            : 'Начать';
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Интернет',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                    if (!offline)
                      Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              if (!offline)
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    key: const Key('speed-button'),
                    onPressed: running ? _stop : _start,
                    child: Text(label),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (offline)
            _offlineView(cs)
          else
            LayoutBuilder(builder: (context, box) {
              final gauge = _card(_gaugeView(context, cs), pad: 8);
              final metrics = _metrics(cs);
              if (box.maxWidth < 620) {
                return Column(children: [gauge, const SizedBox(height: 12), metrics]);
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: gauge),
                    const SizedBox(width: 12),
                    Expanded(flex: 4, child: metrics),
                  ],
                ),
              );
            }),
          if (_status == _Status.done || (_status == _Status.idle && _last != null)) ...[
            const SizedBox(height: 12),
            _tipsView(cs),
          ],
          const SizedBox(height: 12),
          _historyView(cs),
        ],
      ),
    );
  }

  Widget _card(Widget child, {double pad = 12, Color? color, Color? border}) => Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: color ?? Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border ?? _border),
        ),
        child: child,
      );

  Widget _offlineView(ColorScheme cs) => _card(
        Padding(
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
        ),
      );

  Widget _gaugeView(BuildContext context, ColorScheme cs) {
    final shown = _status == _Status.running && _phase != SpeedPhase.ping ? _gauge : 0.0;
    final big = _status == _Status.done ? (_down ?? 0) : shown;
    final f = gaugeFraction(_status == _Status.done ? (_down ?? 0) : shown);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: f),
      duration: animDuration(context, const Duration(milliseconds: 400)),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        height: 220,
        child: CustomPaint(
          painter: _GaugePainter(v, _border, cs.onSurface),
          child: Align(
            alignment: const Alignment(0, 0.2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  big > 0 ? _fmt(big) : '0',
                  key: const Key('speed-big'),
                  style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w300),
                ),
                Text('Мбит/с', style: TextStyle(color: cs.onSurfaceVariant)),
                Text(_phaseText,
                    key: const Key('speed-phase'),
                    style: TextStyle(
                        fontSize: 13,
                        color: _status == _Status.failed ? cs.error : cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metrics(ColorScheme cs) {
    final jitter = _status == _Status.done ? _last?.jitterMs : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _metric(cs, Icons.network_ping, const Color(0xFF0B7C7A), 'Пинг', _ping, 'мс', 'speed-ping'),
        const SizedBox(height: 8),
        _metric(cs, Icons.arrow_downward, const Color(0xFF3D5A80), 'Загрузка', _down, 'Мбит/с',
            'speed-down'),
        const SizedBox(height: 8),
        _metric(cs, Icons.arrow_upward, const Color(0xFF7B5EA7), 'Отдача', _up, 'Мбит/с',
            'speed-up'),
        const SizedBox(height: 8),
        Text(
          'Скачки пинга (джиттер): ${jitter == null ? '—' : '${_fmt(jitter)} мс'}',
          key: const Key('speed-jitter'),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _metric(ColorScheme cs, IconData icon, Color color, String title, double? v, String unit,
      String key) {
    return _card(
      Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.14),
            foregroundColor: color,
            child: Icon(icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v == null ? '—' : '${_fmt(v)} $unit',
                    key: Key(key),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                Text(title, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) => v < 100 ? v.toStringAsFixed(1) : v.toStringAsFixed(0);

  static String _date(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year}, ${two(t.hour)}:${two(t.minute)}';
  }

  Widget _tipsView(ColorScheme cs) {
    final tips = speedTips(_last);
    if (tips.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('speed-tips'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Советы', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, box) {
          final cards = [
            for (final t in tips)
              _card(
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          t.kind == TipKind.ok ? const Color(0xFFCDEBD6) : const Color(0xFFFFE9B3),
                      foregroundColor:
                          t.kind == TipKind.ok ? const Color(0xFF1B6B33) : const Color(0xFF8F5500),
                      child: Icon(t.kind == TipKind.ok ? Icons.check : Icons.warning_amber_rounded,
                          size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A1C1C))),
                          Text(t.text,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF3F4948))),
                        ],
                      ),
                    ),
                  ],
                ),
                color: t.kind == TipKind.ok ? const Color(0xFFE6F4EA) : const Color(0xFFFFF8E6),
                border: t.kind == TipKind.ok ? const Color(0xFFBFE0C8) : const Color(0xFFF2DFA8),
              ),
          ];
          if (box.maxWidth < 620 || cards.length == 1) {
            return Column(children: [
              for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 8), child: w),
            ]);
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: cards[i]),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _historyView(ColorScheme cs) {
    final rows = _history.take(3).toList();
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
          LayoutBuilder(builder: (context, box) {
            final chart = _card(
              SizedBox(
                height: 90,
                child: CustomPaint(
                  key: const Key('speed-chart'),
                  size: Size.infinite,
                  painter: _ChartPainter(
                      [for (final r in _history.take(10).toList().reversed) r.downMbps],
                      _tealLight),
                ),
              ),
            );
            final table = _card(
              Column(
                key: const Key('speed-history'),
                children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(flex: 4, child: Text(_date(r.time))),
                          Expanded(flex: 2, child: Text('${_fmt(r.pingMs)} мс')),
                          Expanded(flex: 2, child: Text('↓ ${_fmt(r.downMbps)}')),
                          Expanded(flex: 2, child: Text('↑ ${_fmt(r.upMbps)}')),
                        ],
                      ),
                    ),
                ],
              ),
            );
            if (box.maxWidth < 620) {
              return Column(children: [chart, const SizedBox(height: 12), table]);
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 4, child: chart),
                  const SizedBox(width: 12),
                  Expanded(flex: 6, child: table),
                ],
              ),
            );
          }),
      ],
    );
  }
}

/// Мини-график загрузки: линия, заливка, точки.
class _ChartPainter extends CustomPainter {
  _ChartPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.reduce(math.max).clamp(1.0, double.infinity);
    const pad = 6.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    Offset pt(int i) => Offset(
        pad + (values.length == 1 ? w / 2 : w * i / (values.length - 1)),
        pad + h * (1 - values[i] / maxV));
    final pts = [for (var i = 0; i < values.length; i++) pt(i)];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(line)
      ..lineTo(pts.last.dx, size.height - pad)
      ..lineTo(pts.first.dx, size.height - pad)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = color);
    for (final p in pts) {
      canvas.drawCircle(p, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter o) => o.values != values || o.color != color;
}

/// Дуга 240° с градиентом, стрелкой и «бусиной» на конце.
class _GaugePainter extends CustomPainter {
  _GaugePainter(this.fraction, this.track, this.needle);
  final double fraction;
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
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, p..color = track);
    if (fraction > 0) {
      p.shader = const SweepGradient(
        startAngle: 0,
        endAngle: _sweep,
        colors: [_InternetScreenState._teal, _InternetScreenState._tealLight],
        transform: GradientRotation(_start),
      ).createShader(rect);
      canvas.drawArc(rect, _start, _sweep * fraction, false, p);
    }
    final a = _start + _sweep * fraction;
    final dir = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(
        center,
        center + dir * (r - 30),
        Paint()
          ..color = needle
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(center, 6, Paint()..color = needle);
    final bead = center + dir * r;
    canvas.drawCircle(bead, 8, Paint()..color = Colors.white);
    canvas.drawCircle(
        bead,
        8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _InternetScreenState._teal);
  }

  @override
  bool shouldRepaint(_GaugePainter o) =>
      o.fraction != fraction || o.track != track || o.needle != needle;
}
