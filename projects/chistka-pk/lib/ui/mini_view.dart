import 'dart:math' as math;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../state/app_controller.dart';
import 'clean_fx.dart';
import 'glass.dart';

/// «сегодня 14:32» / «вчера 14:32» / «12.08 14:32».
String speedWhen(DateTime t, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hm = '${two(t.hour)}:${two(t.minute)}';
  final d0 = DateTime(now.year, now.month, now.day);
  final days = d0.difference(DateTime(t.year, t.month, t.day)).inDays;
  if (days == 0) return 'сегодня $hm';
  if (days == 1) return 'вчера $hm';
  return '${two(t.day)}.${two(t.month)} $hm';
}

/// Мини-окно 360×480 у часов: свободное место, «Быстрая очистка», последний
/// замер скорости и «Открыть ЧистоДиск». Esc и потеря фокуса — прячут окно.
class MiniView extends StatelessWidget {
  const MiniView({super.key, required this.controller});
  final AppController controller;

  AppController get c => controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): c.hideMini},
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Scaffold(
            key: const Key('mini-view'),
            backgroundColor:
                light ? const Color(0xFFEAF5F5) : glassScaffoldColor(Theme.of(context).brightness),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Icon(Icons.water_drop, color: Color(0xFF0F9D9A), size: 24),
                      const SizedBox(width: 8),
                      Text('ЧистоДиск',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    ]),
                    const SizedBox(height: 8),
                    _ring(cs),
                    const SizedBox(height: 14),
                    _quick(context),
                    const SizedBox(height: 10),
                    _speed(cs),
                    const SizedBox(height: 4),
                    TextButton(
                      key: const Key('mini-open'),
                      style: TextButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                      onPressed: () => c.setMiniMode(false),
                      child: const Text('Открыть ЧистоДиск'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ring(ColorScheme cs) {
    final d = c.disk;
    final has = d != null && d.total > 0;
    final free = has ? (d.free / d.total).clamp(0.0, 1.0) : 0.0;
    return Center(
      child: SizedBox.square(
        dimension: 168,
        child: CustomPaint(
          key: const Key('mini-ring'),
          painter: _RingPainter(free, track: const Color(0xFF0F9D9A).withValues(alpha: 0.2)),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(has ? formatSize(d.free) : '—',
                    key: const Key('mini-free'),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                Text(has ? 'свободно из ${formatSize(d.total)}' : 'нет данных',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quick(BuildContext context) {
    final busy = c.quickBusy;
    final freed = c.quickFreedBytes;
    final can = c.selectedBytes > 0;
    final label = busy
        ? 'Очищаю…'
        : can
            ? 'Быстрая очистка · ${formatSize(c.selectedBytes)}'
            : 'Быстрая очистка';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WaveSweep(
          active: busy,
          radius: 24,
          child: FilledButton(
            key: const Key('mini-quick'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0B7C7A),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: c.anyBusy ? null : () => c.quickClean(),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        if (!busy && freed != null)
          Padding(
            key: const Key('mini-freed'),
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const DoneBurst(size: 24, color: Color(0xFF2E7D32)),
                const SizedBox(width: 10),
                Text('Освобождено ${formatSize(freed)}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _speed(ColorScheme cs) {
    final r = c.lastSpeed;
    final busy = c.speedBusy;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: cs.brightness == Brightness.light ? Colors.white : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x17143C46), blurRadius: 20, offset: Offset(0, 6))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r == null ? 'Ещё не замеряли' : '${r.downMbps.round()} Мбит/с',
                    key: const Key('mini-speed'),
                    style: TextStyle(
                        fontSize: r == null ? 14 : 22, fontWeight: FontWeight.w600)),
                if (r != null)
                  Text('Скорость, ${speedWhen(r.time, DateTime.now())}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          FilledButton.tonal(
            key: const Key('mini-measure'),
            style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
            onPressed: busy || c.anyBusy ? null : c.quickSpeedTest,
            child: busy
                ? const Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Замеряю…'),
                  ])
                : const Text('Замерить'),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, {required this.track});
  final double fraction;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const w = 16.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(w / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, 2 * math.pi, false, p..color = track);
    if (fraction > 0) {
      canvas.drawArc(r, -math.pi / 2, 2 * math.pi * fraction, false,
          p..color = const Color(0xFF0F9D9A));
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction;
}
