import 'package:material_ui/material_ui.dart';

import '../core/health.dart';
import '../state/app_controller.dart';
import '../state/computer_service.dart';
import 'app.dart';
import 'anim.dart';
import 'pult_tile.dart';

/// Экран «Компьютер» — пульт плиток с итогом в каждой. Подробности — слоем поверх.
class ComputerScreen extends StatefulWidget {
  const ComputerScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<ComputerScreen> createState() => _ComputerScreenState();
}

class _ComputerScreenState extends State<ComputerScreen> with WidgetsBindingObserver {
  ComputerService get s => widget.controller.computer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.startPolling();
    if (s.healthLoad == ComputerLoad.idle) s.loadHealth();
    if (s.batteryLoad == ComputerLoad.idle) s.loadBattery();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Окно свёрнуто или скрыто — опрос не нужен.
    if (state == AppLifecycleState.resumed) {
      s.startPolling();
    } else if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      s.stopPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Компьютер', style: screenTitleStyle),
            const SizedBox(height: 16),
            TileGrid(children: [
              _healthTile(c),
              _procsTile(c),
              if (s.battery != null) _batteryTile(c),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _healthTile(AppController c) {
    const icon = Icons.storage_outlined;
    const tt = tintDisk;
    const color = Color(0xFF3B78C2);
    const title = 'Здоровье диска';
    void open() => c.openComputerLayer(Layer.health);
    switch (s.healthLoad) {
      case ComputerLoad.idle:
      case ComputerLoad.loading:
        return PultTile(
            key: Key('tile-health'),
            icon: icon,
            color: color,
            tint: tt.bg,
            title: title,
            caption: 'Состояние, температура, износ',
            kind: TileKind.busy,
            progressText: 'Проверяю…');
      case ComputerLoad.error:
        return PultTile(
            key: const Key('tile-health'),
            icon: icon,
            color: color,
            tint: tt.bg,
            title: title,
            caption: '',
            kind: TileKind.error,
            onRetry: s.loadHealth);
      case ComputerLoad.done:
        final d = s.mainDisk!;
        final st = _stateLook(d.state);
        return PultTile(
          key: const Key('tile-health'),
          icon: icon,
          color: color,
          tint: tt.bg,
          title: title,
          caption: '',
          kind: TileKind.summary,
          summary: diskTileText(d),
          summaryIcon: st.icon,
          summaryColor: st.fg,
          onAction: open,
          onTap: open,
        );
    }
  }

  Widget _procsTile(AppController c) {
    const icon = Icons.speed_outlined;
    const tt = tintProcs;
    const color = Color(0xFFC8473A);
    const title = 'Что тормозит';
    if (s.cpuPercent == null && s.memTotal == 0) {
      return PultTile(
        key: const Key('tile-procs'),
        icon: icon,
        color: color,
        tint: tt.bg,
        title: title,
        caption: 'Нагрузка на процессор и память',
        kind: s.sampleFailed ? TileKind.error : TileKind.busy,
        progressText: 'Считаю…',
        onRetry: s.tick,
      );
    }
    void open() => c.openComputerLayer(Layer.procs);
    final cpu = s.cpuPercent == null ? '—' : '${s.cpuPercent!.round()}';
    return PultTile(
      key: const Key('tile-procs'),
      icon: icon,
      color: color,
      tint: tt.bg,
      title: title,
      caption: '',
      kind: TileKind.summary,
      summary: 'ЦП $cpu % · Память ${s.memPercent} %',
      summaryIcon: Icons.show_chart,
      summaryColor: color,
      onAction: open,
      onTap: open,
    );
  }

  Widget _batteryTile(AppController c) {
    final b = s.battery!;
    void open() => c.openComputerLayer(Layer.battery);
    return PultTile(
      key: const Key('tile-battery'),
      icon: Icons.battery_std_outlined,
      color: tintBattery.dot,
      tint: tintBattery.bg,
      title: 'Батарея',
      caption: '',
      kind: TileKind.summary,
      summary: b.noData ? 'Износ: нет данных' : 'Износ ${b.wearPercent} %',
      summaryIcon: !b.noData && b.wearPercent >= 40 ? Icons.warning_amber_rounded : Icons.check_circle,
      summaryColor: !b.noData && b.wearPercent >= 40 ? const Color(0xFF8F5500) : successColor,
      onAction: open,
      onTap: open,
    );
  }
}

/// Вид чипа состояния диска: иконка + слово + цвета (не только цвет).
({IconData icon, Color fg, Color bg}) _stateLook(DiskState st) => switch (st) {
      DiskState.healthy =>
        (icon: Icons.check_circle, fg: const Color(0xFF2E7D32), bg: const Color(0xFFE6F4EA)),
      DiskState.warning =>
        (icon: Icons.warning_amber_rounded, fg: const Color(0xFF8F5500), bg: const Color(0xFFFFF1D6)),
      DiskState.unhealthy =>
        (icon: Icons.error, fg: const Color(0xFFBA1A1A), bg: const Color(0xFFFDE7E7)),
    };

/// Публично для карточек подробностей.
({IconData icon, Color fg, Color bg}) diskStateLook(DiskState st) => _stateLook(st);
