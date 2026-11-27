import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../core/settings.dart';
import '../state/app_controller.dart';
import 'about_dialog.dart';
import 'anim.dart';

/// Ниже этой ширины панель показывает только иконки.
const navNarrowBelow = 120.0;

class _Item {
  const _Item(this.section, this.icon, this.label);
  final Section section;
  final IconData icon;
  final String label;
}

const _groupItems = [
  _Item(Section.main, Icons.cleaning_services_outlined, 'Очистка'),
  _Item(Section.downloads, Icons.download_outlined, 'Загрузки'),
  _Item(Section.big, Icons.data_usage, 'Большие файлы'),
  _Item(Section.map, Icons.pie_chart_outline, 'Карта диска'),
];
const _soloItems = [
  _Item(Section.programs, Icons.apps_outlined, 'Программы'),
  _Item(Section.startup, Icons.rocket_launch_outlined, 'Автозагрузка'),
  _Item(Section.internet, Icons.network_check, 'Интернет'),
];

/// Левая панель: логотип, группа «Очистка», остальные разделы, низ.
class NavPanel extends StatefulWidget {
  const NavPanel({
    super.key,
    required this.controller,
    required this.width,
    required this.onWidthChanged,
    required this.onWidthCommitted,
  });
  final AppController controller;
  final double width;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<double> onWidthCommitted;

  @override
  State<NavPanel> createState() => _NavPanelState();
}

class _NavPanelState extends State<NavPanel> {
  bool _expanded = true;
  bool _edgeHover = false;
  bool _edgeDrag = false;

  AppController get c => widget.controller;
  bool get _narrow => widget.width < navNarrowBelow;
  bool get _busy => c.phase == Phase.analyzing || c.phase == Phase.cleaning;

  Section? get _selected => c.phase == Phase.done ? Section.main : c.section;

  Widget _navTile(_Item it, {double indent = 0}) {
    final cs = Theme.of(context).colorScheme;
    final selected = _selected == it.section;
    final fg = selected ? const Color(0xFF0B3F3E) : cs.onSurface;
    final fgColor = selected && Theme.of(context).brightness == Brightness.dark
        ? cs.onSecondaryContainer
        : fg;
    final tile = Padding(
      padding: EdgeInsets.fromLTRB(8 + indent, 2, 8, 2),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          hoverColor: cs.primary.withValues(alpha: 0.08),
          onTap: _busy ? null : () => c.go(it.section),
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: _narrow ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                if (!_narrow) const SizedBox(width: 12),
                Icon(it.icon, size: 22, color: fgColor),
                if (!_narrow) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      it.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fgColor,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return _narrow ? Tooltip(message: it.label, waitDuration: const Duration(milliseconds: 400), child: tile) : tile;
  }

  Widget _group(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_narrow) {
      return Column(children: [for (final it in _groupItems) _navTile(it)]);
    }
    final d = animDuration(context, const Duration(milliseconds: 200));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            hoverColor: cs.primary.withValues(alpha: 0.08),
            onTap: () => setState(() => _expanded = !_expanded),
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.cleaning_services_outlined, size: 22, color: cs.onSurface),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Очистка',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: d,
                    child: const Icon(Icons.expand_more, size: 22),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: d,
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Column(children: [for (final it in _groupItems) _navTile(it, indent: 12)])
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _bottom(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final buttons = [
      Tooltip(
        message: 'Настройки',
        waitDuration: const Duration(milliseconds: 400),
        child: IconButton(
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          isSelected: c.section == Section.settings && c.phase != Phase.done,
          onPressed: _busy ? null : () => c.go(Section.settings),
          icon: const Icon(Icons.settings_outlined),
        ),
      ),
      Tooltip(
        message: 'Журнал',
        waitDuration: const Duration(milliseconds: 400),
        child: IconButton(
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: c.openLog,
          icon: const Icon(Icons.history),
        ),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_narrow)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('За всё время: ${formatSize(c.totalFreedEver)}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          if (c.adminMode)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _narrow
                  ? const Tooltip(
                      message: 'Режим администратора',
                      child: Icon(Icons.shield_outlined, color: Color(0xFF6B4300)),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1D6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.shield_outlined, size: 18, color: Color(0xFF6B4300)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('Режим администратора',
                                style: TextStyle(fontSize: 12, color: Color(0xFF6B4300))),
                          ),
                        ],
                      ),
                    ),
            ),
          _narrow ? Column(children: buttons) : Row(mainAxisAlignment: MainAxisAlignment.center, children: buttons),
        ],
      ),
    );
  }

  Widget _edge(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _edgeHover = true),
      onExit: (_) => setState(() => _edgeHover = false),
      child: GestureDetector(
        key: const Key('nav-edge'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _edgeDrag = true),
        // Ширина берётся из контроллера, а не из widget.width: между событиями
        // жеста кадр может не успеть перестроиться, и значение было бы устаревшим.
        onHorizontalDragUpdate: (d) =>
            widget.onWidthChanged(clampNavWidth(c.settings.navWidth + d.delta.dx)),
        onHorizontalDragEnd: (_) {
          setState(() => _edgeDrag = false);
          widget.onWidthCommitted(c.settings.navWidth);
        },
        onDoubleTap: () {
          final w = widget.width > 150 ? 72.0 : defaultNavWidth;
          widget.onWidthChanged(w);
          widget.onWidthCommitted(w);
        },
        child: SizedBox(
          width: 6,
          child: Center(
            child: Container(
              width: (_edgeHover || _edgeDrag) ? 2 : 1,
              color: (_edgeHover || _edgeDrag) ? cs.primary : cs.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final bg = light ? const Color(0xFFE3F1F1) : cs.surfaceContainer;
    final logo = InkWell(
      key: const Key('nav-logo'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => showAboutChisto(context),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisAlignment: _narrow ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            const Icon(Icons.water_drop, color: Color(0xFF0F9D9A), size: 32),
            if (!_narrow) ...[
              const SizedBox(width: 8),
              const Flexible(
                child: Text('ЧистоДиск',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
    return SizedBox(
      width: widget.width + 6,
      child: Row(
        children: [
          Expanded(
            child: Container(
              color: bg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                    child: Tooltip(
                      message: 'О программе',
                      waitDuration: const Duration(milliseconds: 400),
                      child: logo,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _group(context),
                          const SizedBox(height: 4),
                          for (final it in _soloItems) _navTile(it),
                        ],
                      ),
                    ),
                  ),
                  _bottom(context),
                ],
              ),
            ),
          ),
          _edge(context),
        ],
      ),
    );
  }
}
