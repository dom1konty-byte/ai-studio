import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/battery.dart';
import '../core/format.dart';
import '../core/health.dart';
import '../core/procs.dart';
import '../state/app_controller.dart';
import '../state/computer_service.dart';
import 'computer_screen.dart';
import 'pult_tile.dart';
import 'settings_screen.dart';

const _border = Color(0xFFD5E6E6);

/// Число с узкими пробелами между тысячами: 50000 -> «50 000».
String groupDigits(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return (n < 0 ? '-' : '') + b.toString();
}

Color _loadColor(BuildContext context, double pct) {
  if (pct > 92) return const Color(0xFFBA1A1A);
  if (pct > 80) return const Color(0xFFB26A00);
  return Theme.of(context).colorScheme.primary;
}

Widget _title(String t) =>
    Text(t, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600));

/// «Нужен режим администратора» + «Включить» (если ещё не включён).
class AdminHint extends StatelessWidget {
  const AdminHint({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(controller.adminMode ? 'Нет данных' : 'Нужен режим администратора',
            key: const Key('admin-hint-text'),
            style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        if (!controller.adminMode)
          TextButton(
            key: const Key('admin-enable'),
            onPressed: controller.canToggleAdmin
                ? () => toggleAdminWithDialog(context, controller, true)
                : null,
            child: const Text('Включить'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- диск

class HealthDetails extends StatelessWidget {
  const HealthDetails({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.computer;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        return ListView(
          children: [
            _title('Здоровье диска'),
            const SizedBox(height: 12),
            if (s.healthLoad == ComputerLoad.loading || s.healthLoad == ComputerLoad.idle)
              const LinearProgressIndicator()
            else if (s.healthLoad == ComputerLoad.error) ...[
              const Text('Не удалось получить данные о дисках.'),
              TextButton(onPressed: s.loadHealth, child: const Text('Повторить')),
            ] else
              for (final d in s.disks) ...[
                _DiskCard(disk: d, controller: controller),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }
}

class _DiskCard extends StatelessWidget {
  const _DiskCard({required this.disk, required this.controller});
  final DiskHealth disk;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final d = disk;
    final look = diskStateLook(d.state);
    final grey = TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final head = [
      d.name,
      if (d.mediaType.isNotEmpty) d.mediaType,
      if (d.size != null) formatSize(d.size!),
    ].join(' · ');
    return Container(
      key: const Key('disk-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconCircle(
                  icon: d.mediaType == 'HDD' ? Icons.album_outlined : Icons.memory,
                  color: const Color(0xFF0F9D9A)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(head,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: look.bg, borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(look.icon, size: 16, color: look.fg),
                  const SizedBox(width: 4),
                  Text(d.state.label,
                      style: TextStyle(color: look.fg, fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Тип: ${d.mediaType.isEmpty ? 'не определён' : d.mediaType}', style: grey),
          if (d.temperature != null) Text('Температура: ${d.temperature} °C', style: grey),
          if (d.powerOnHours != null)
            Text('Часов работы: ${groupDigits(d.powerOnHours!)}', style: grey),
          if (d.readErrors != null && d.readErrors! > 0)
            Text('Ошибок чтения: ${groupDigits(d.readErrors!)}', style: grey),
          if (d.wear != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              key: const Key('wear-bar'),
              value: d.wear! / 100,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 4),
            Text('Износ ${d.wear} %', style: grey),
          ],
          if (d.needsAdmin) ...[
            const SizedBox(height: 8),
            AdminHint(controller: controller),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- процессы

class ProcsDetails extends StatelessWidget {
  const ProcsDetails({super.key, required this.controller});
  final AppController controller;

  Future<void> _kill(BuildContext context, ProcGroup g) async {
    final s = controller.computer;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Завершить «${g.name}»?'),
        content: Text(g.count > 1
            ? 'Будут завершены все процессы «${g.name}» (${g.count}). Несохранённые данные пропадут.'
            : 'Несохранённые данные пропадут.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(
              key: const Key('kill-confirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Завершить')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await s.terminateGroup(g);
    if (!context.mounted) return;
    final msg = switch (r) {
      KillResult.ok => null,
      KillResult.denied => 'Нужен режим администратора',
      KillResult.failed => 'Не удалось завершить «${g.name}»',
    };
    if (msg != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final s = controller.computer;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final rows = s.sortedGroups.take(80).toList();
        final cpu = s.cpuPercent ?? 0;
        return ListView(
          children: [
            _title('Что тормозит'),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: [
              _Meter(
                key: const Key('meter-cpu'),
                label: s.cpuPercent == null ? 'Процессор' : 'Процессор ${cpu.round()} %',
                value: cpu,
              ),
              _Meter(
                key: const Key('meter-mem'),
                label: s.memTotal == 0
                    ? 'Память'
                    : 'Память ${_gb(s.memUsed)} из ${_gb(s.memTotal)} ГБ',
                value: s.memPercent.toDouble(),
              ),
            ]),
            const SizedBox(height: 12),
            if (s.sampleFailed && rows.isEmpty) const Text('Не удалось получить список процессов.'),
            MouseRegion(
              onEnter: (_) => s.setHoverFreeze(true),
              onExit: (_) => s.setHoverFreeze(false),
              child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 24,
                horizontalMargin: 8,
                sortColumnIndex: s.sort == ProcSort.cpu ? 1 : 2,
                sortAscending: s.sortAscending,
                columns: [
                  const DataColumn(label: Text('Процесс')),
                  DataColumn(
                      label: const Text('ЦП %'),
                      numeric: true,
                      onSort: (_, __) => s.setSort(ProcSort.cpu)),
                  DataColumn(
                      label: const Text('Память'),
                      numeric: true,
                      onSort: (_, __) => s.setSort(ProcSort.memory)),
                  const DataColumn(label: Text('')),
                ],
                rows: [
                  for (final g in rows)
                    DataRow(key: ValueKey(g.name.toLowerCase()), cells: [
                      DataCell(Text(g.count > 1 ? '${g.name} (${g.count})' : g.name)),
                      DataCell(Text(g.cpu.toStringAsFixed(1))),
                      DataCell(Text(formatSize(g.memory))),
                      DataCell(g.isProtected
                          ? const Tooltip(
                              message: 'Системный процесс',
                              child: TextButton(onPressed: null, child: Text('Завершить')),
                            )
                          : TextButton(
                              key: Key('kill-${g.name.toLowerCase()}'),
                              style: TextButton.styleFrom(
                                  foregroundColor: Theme.of(context).colorScheme.error),
                              onPressed: () => _kill(context, g),
                              child: const Text('Завершить'),
                            )),
                    ]),
                ],
              ),
            )),
          ],
        );
      },
    );
  }

  static String _gb(int b) => (b / (1024 * 1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',');
}

class _Meter extends StatelessWidget {
  const _Meter({super.key, required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (value / 100).clamp(0.0, 1.0),
            minHeight: 12,
            color: _loadColor(context, value),
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- батарея

class BatteryDetails extends StatelessWidget {
  const BatteryDetails({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.computer;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final b = s.battery;
        final grey = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
        return ListView(
          children: [
            _title('Батарея'),
            const SizedBox(height: 12),
            if (b == null)
              const Text('Батарея не найдена.')
            else
              Wrap(
                spacing: 32,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _WearRing(info: b),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Новая ёмкость ${groupDigits(b.design)} мВт·ч',
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(b.noData ? 'Сейчас: нет данных' : 'Сейчас ${groupDigits(b.full)} мВт·ч',
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(
                          b.cycles == null
                              ? 'Циклов зарядки: нет данных'
                              : 'Циклов зарядки: ${groupDigits(b.cycles!)}',
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 10),
                      Text('Данные из отчёта Windows', style: grey),
                    ],
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _WearRing extends StatelessWidget {
  const _WearRing({required this.info});
  final BatteryInfo info;

  @override
  Widget build(BuildContext context) {
    final high = !info.noData && info.wearPercent >= 40;
    final color = high ? const Color(0xFF8F5500) : const Color(0xFF0F9D9A);
    return SizedBox(
      key: const Key('wear-ring'),
      width: 140,
      height: 140,
      child: CustomPaint(
        painter: _RingPainter(info.noData ? 0 : info.wear, color, _border),
        child: Center(
          child: Text(info.noData ? 'Износ:\nнет данных' : 'Износ\n${info.wearPercent} %',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track);
  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const w = 12.0;
    final rect = Rect.fromLTWH(w / 2, w / 2, size.width - w, size.height - w);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, p..color = track);
    if (value > 0) canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.value != value || o.color != color;
}
