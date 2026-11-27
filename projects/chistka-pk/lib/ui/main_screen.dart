import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../state/app_controller.dart';
import 'anim.dart';

IconData categoryIcon(CategoryId id) {
  switch (id) {
    case CategoryId.temp:
      return Icons.folder_delete_outlined;
    case CategoryId.browsers:
      return Icons.public;
    case CategoryId.recycle:
      return Icons.delete_outline;
    case CategoryId.thumbs:
      return Icons.image_outlined;
    case CategoryId.logs:
      return Icons.description_outlined;
    case CategoryId.gpu:
      return Icons.memory;
    case CategoryId.winUpdate:
      return Icons.system_update_alt;
    case CategoryId.prefetch:
      return Icons.speed;
    case CategoryId.telegram:
    case CategoryId.discord:
    case CategoryId.steam:
    case CategoryId.spotify:
    case CategoryId.vscode:
      return Icons.apps;
  }
}

RoundedRectangleBorder cardShape() =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

class MainScreen extends StatelessWidget {
  const MainScreen({super.key, required this.controller});
  final AppController controller;

  Future<void> _onClean(BuildContext context) async {
    final c = controller;
    if (c.cleanBusy) return; // защита от двойного нажатия
    c.cleanBusy = true;
    try {
      await _confirmAndClean(context, c);
    } finally {
      c.cleanBusy = false;
    }
  }

  Future<void> _confirmAndClean(BuildContext context, AppController c) async {
    var skip = false;
    while (true) {
      final running = await c.browsersToClose();
      if (running.isEmpty) break;
      if (!context.mounted) return;
      final res = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Закройте браузер'),
          content: Text('Запущены: ${running.join(', ')}. Закройте их, чтобы очистить кэш.\n'
              'Проверьте, что браузер закрыт полностью (и значок у часов тоже).'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Пропустить кэш браузеров'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Я закрыл, продолжить'),
            ),
          ],
        ),
      );
      if (res == null) return;
      if (res == false) {
        skip = true;
        break;
      }
    }
    await c.clean(skipBrowsers: skip);
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final analyzing = c.phase == Phase.analyzing;
    final cleaning = c.phase == Phase.cleaning;
    final ready = c.phase == Phase.ready;
    final busy = analyzing || cleaning;
    final totalActive =
        c.rows.where((r) => r.active).fold<int>(0, (a, r) => a + (r.bytes ?? 0));

    double? ring;
    if (analyzing) {
      ring = null;
    } else if (cleaning) {
      ring = c.progressFraction;
    } else if (ready && totalActive > 0) {
      ring = (c.selectedBytes / totalActive).clamp(0.0, 1.0);
    } else {
      ring = 0;
    }

    final String heroText;
    final String heroCaption;
    if (cleaning) {
      heroText = '…';
      heroCaption = c.progressText;
    } else if (analyzing) {
      heroText = '…';
      heroCaption = c.progressText;
    } else if (ready) {
      heroText = formatSize(c.selectedBytes);
      heroCaption = 'Можно освободить';
    } else {
      heroText = '—';
      heroCaption = 'Нажмите «Анализ»';
    }

    final general = <Widget>[];
    final programs = <Widget>[];
    for (final r in c.rows) {
      (r.category.isProgram ? programs : general)
          .add(_CategoryTile(row: r, controller: c, enabled: ready));
    }

    final disk = c.disk;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Очистка', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
        Text('Выберите, что убрать',
            style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        if (busy)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: cleaning ? (1 - c.progressFraction).clamp(0.0, 1.0) : null,
                ),
                const SizedBox(height: 4),
                Text(c.progressText, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        if (c.lowSpace)
          Card(
            elevation: 0,
            color: theme.colorScheme.errorContainer,
            shape: cardShape(),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Мало места: свободно ${formatSize(disk!.free)}. Нажмите «Анализ».',
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (disk != null && disk.total > 0) ...[
          LinearProgressIndicator(
            value: ((disk.total - disk.free) / disk.total).clamp(0.0, 1.0),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 4),
          Text(
            'Диск ${c.systemDriveLabel} свободно ${formatSize(disk.free)} из ${formatSize(disk.total)}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
        const SizedBox(height: 8),
        _Hero(
          ring: ring,
          indeterminate: analyzing,
          bytes: ready ? c.selectedBytes : null,
          text: heroText,
          caption: heroCaption,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final twoCols = box.maxWidth >= 600;
              Widget grid(List<Widget> items) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final w in items)
                        SizedBox(
                          width: twoCols ? (box.maxWidth - 12 - 16) / 2 : box.maxWidth - 16,
                          child: w,
                        ),
                    ],
                  );
              return ListView(
                padding: const EdgeInsets.only(right: 16, top: 4, bottom: 4),
                children: [
                  grid(general),
                  if (programs.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
                      child: Text('Программы',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    ),
                    grid(programs),
                  ],
                  const SizedBox(height: 12),
                  _DownloadsTile(controller: c, enabled: !busy),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.tonal(
              onPressed: c.canAnalyze ? c.analyze : null,
              child: const Text('Анализ'),
            ),
            const SizedBox(width: 16),
            FilledButton(
              onPressed: c.canClean ? () => _onClean(context) : null,
              child: const Text('Очистить'),
            ),
          ],
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.row, required this.controller, required this.enabled});
  final CategoryRow row;
  final AppController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cat = row.category;
    final cs = Theme.of(context).colorScheme;
    Widget size;
    String subtitle = cat.hint;
    switch (row.status) {
      case RowStatus.pending:
        size = const Text('—');
      case RowStatus.scanning:
        size = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case RowStatus.error:
        size = Icon(Icons.error_outline, color: cs.error);
        subtitle = 'Не удалось посчитать';
      case RowStatus.done:
        size = row.isEmpty
            ? const Text('Пусто', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))
            : CountSize(row.bytes ?? 0, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600));
    }
    if (cat.id == CategoryId.recycle && row.selected && row.active) {
      subtitle = 'Очищает Корзину на всех дисках';
    }
    return _HoverCard(
      child: CheckboxListTile(
        shape: cardShape(),
        controlAffinity: ListTileControlAffinity.leading,
        value: row.selected,
        onChanged: enabled && row.active ? (v) => controller.toggleRow(row, v ?? false) : null,
        title: Row(
          children: [
            _IconCircle(icon: categoryIcon(cat.id), color: categoryColor(cat.id)),
            const SizedBox(width: 12),
            Flexible(child: Text(cat.title)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(left: 52),
          child: Text(subtitle, style: const TextStyle(fontSize: 12)),
        ),
        secondary: size,
      ),
    );
  }
}

class _DownloadsTile extends StatelessWidget {
  const _DownloadsTile({required this.controller, required this.enabled});
  final AppController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return _HoverCard(
      child: CheckboxListTile(
        shape: cardShape(),
        controlAffinity: ListTileControlAffinity.leading,
        value: c.downloadsOn,
        onChanged: enabled
            ? (v) {
                if (v == true) {
                  c.go(Section.downloads);
                } else {
                  c.setAllDownloads(false);
                }
              }
            : null,
        title: const Row(
          children: [
            _IconCircle(icon: Icons.download_outlined, color: Color(0xFF0F9D9A)),
            SizedBox(width: 12),
            Flexible(child: Text('Загрузки')),
          ],
        ),
        subtitle: Text(
          c.downloadsOn
              ? 'Выбрано: ${filesWord(c.downloadsSelected.length)}, ${formatSize(c.downloadsSelectedBytes)}'
              : 'Файлы старше 30 дней',
          style: const TextStyle(fontSize: 12),
        ),
        secondary: TextButton(
          onPressed: enabled ? () => c.go(Section.downloads) : null,
          child: const Text('Выбрать файлы →'),
        ),
      ),
    );
  }
}

Color categoryColor(CategoryId id) {
  switch (id) {
    case CategoryId.temp:
      return const Color(0xFF0F9D9A);
    case CategoryId.browsers:
    case CategoryId.gpu:
      return const Color(0xFF3D5A80);
    case CategoryId.recycle:
      return const Color(0xFFB26A00);
    case CategoryId.thumbs:
      return const Color(0xFF7B5EA7);
    case CategoryId.logs:
    case CategoryId.winUpdate:
    case CategoryId.prefetch:
      return const Color(0xFF566B6B);
    case CategoryId.telegram:
    case CategoryId.discord:
    case CategoryId.steam:
    case CategoryId.spotify:
    case CategoryId.vscode:
      return const Color(0xFF2E7D32);
  }
}

/// Иконка в цветном кружке (фон — цвет с прозрачностью 14 %).
class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
        child: Icon(icon, size: 22, color: color),
      );
}

/// Карточка с рамкой 1 px; при наведении поднимается на 1 px, рамка — бирюзовая.
class _HoverCard extends StatefulWidget {
  const _HoverCard({required this.child});
  final Widget child;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: animDuration(context, const Duration(milliseconds: 120)),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -1 : 0, 0),
        decoration: BoxDecoration(
          color: light ? Colors.white : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hover ? const Color(0xFF0F9D9A) : (light ? const Color(0xFFD5E6E6) : cs.outlineVariant),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(16),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Размер, который «считает» от нуля (или от прошлого значения) до нового.
class CountSize extends StatelessWidget {
  const CountSize(this.bytes, {super.key, this.style});
  final int bytes;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: bytes.toDouble()),
      duration: animDuration(context, const Duration(milliseconds: 500)),
      curve: Curves.easeOut,
      builder: (_, v, __) => Text(formatSize(v.round()), style: style),
    );
  }
}

/// Герой: градиентная карточка с кольцом и крупной цифрой.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.ring,
    required this.indeterminate,
    required this.bytes,
    required this.text,
    required this.caption,
  });
  final double? ring;
  final bool indeterminate;
  final int? bytes;
  final String text;
  final String caption;

  @override
  Widget build(BuildContext context) {
    const big = TextStyle(fontSize: 56, fontWeight: FontWeight.w300, color: Colors.white);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B7C7A), Color(0xFF17B3AE)],
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: indeterminate || ring == null
                ? const CircularProgressIndicator(
                    strokeWidth: 12,
                    strokeCap: StrokeCap.round,
                    color: Colors.white,
                    backgroundColor: Color(0x33FFFFFF),
                  )
                : TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: ring),
                    duration: animDuration(context, const Duration(milliseconds: 800)),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: 12,
                      strokeCap: StrokeCap.round,
                      color: Colors.white,
                      backgroundColor: const Color(0x33FFFFFF),
                    ),
                  ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bytes != null)
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: bytes!.toDouble()),
                    duration: animDuration(context, const Duration(milliseconds: 600)),
                    curve: Curves.easeOut,
                    builder: (_, v, __) => Text(formatSize(v.round()), style: big),
                  )
                else
                  Text(text, style: big),
                Text(caption, style: const TextStyle(fontSize: 14, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
