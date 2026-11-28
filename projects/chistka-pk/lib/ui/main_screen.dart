import 'package:material_ui/material_ui.dart';

import '../core/clean_anim.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../state/app_controller.dart';
import 'anim.dart';
import 'app.dart';
import 'clean_fx.dart';
import 'pult_tile.dart';

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

/// «, пропущено N» (пусто, если ничего не пропущено).
String skippedText(int n) => n > 0 ? ', пропущено $n' : '';

RoundedRectangleBorder cardShape() =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius));


/// Экран «Очистка» — пульт: полоска диска, «Быстрая очистка» и плитки.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  AppController get c => widget.controller;
  bool _open = false; // выпадающая панель «Что чистить?»

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.autoAnalyzeOnce();
    });
  }

  Future<void> _quick() async {
    if (c.cleanBusy) return; // защита от двойного нажатия
    c.cleanBusy = true;
    try {
      // Перед очисткой — анализ, если его не было.
      if (c.phase == Phase.idle) await c.analyze();
      if (!mounted) return;
      if (c.canClean) await _confirmAndClean(context, c);
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

  void _toggleOpen() {
    setState(() => _open = !_open);
    // Размеры в списке появятся после анализа.
    if (_open && c.phase == Phase.idle && c.canAnalyze) c.analyze();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = c.phase == Phase.analyzing || c.phase == Phase.cleaning;
    final disk = c.disk;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Очистка', style: screenTitleStyle),
          const SizedBox(height: blockGap),
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
                        'Мало места: свободно ${formatSize(disk!.free)}. Нажмите «Очистить».',
                        style: TextStyle(color: theme.colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (disk != null && disk.total > 0) _DiskStrip(c: c),
          const SizedBox(height: blockGap),
          _QuickStrip(c: c, onClean: _quick, open: _open, onToggle: _toggleOpen),
          AnimatedSize(
            duration: animDuration(context, const Duration(milliseconds: 200)),
            alignment: Alignment.topCenter,
            child: _open ? _WhatToClean(c: c, enabled: !busy) : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: blockGap),
          TileGrid(children: [
            _FilesTile(c: c, downloads: true),
            _FilesTile(c: c, downloads: false),
            _DupTile(c: c),
            _EmptyDirsTile(c: c),
            PultTile(
              icon: Icons.pie_chart_outline,
              color: tintMap.dot,
              tint: tintMap.bg,
              title: 'Карта диска',
              caption: 'Что занимает место',
              actionLabel: 'Открыть',
              onAction: busy ? null : () => c.openLayer(Layer.map),
            ),
          ]),
        ],
      ),
    );
  }
}

class _DiskStrip extends StatelessWidget {
  const _DiskStrip({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final disk = c.disk!;
    final used = ((disk.total - disk.free) / disk.total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: used,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
          color: used > 0.9 ? warningColor : null,
        ),
        const SizedBox(height: 4),
        Text.rich(TextSpan(style: const TextStyle(fontSize: 14), children: [
          TextSpan(text: 'Диск ${c.systemDriveLabel} свободно '),
          TextSpan(
              text: formatSize(disk.free),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          TextSpan(text: ' из ${formatSize(disk.total)}'),
        ])),
      ],
    );
  }
}

/// «Быстрая очистка»: полоса 104 px (узко — в два ряда).
class _QuickStrip extends StatelessWidget {
  const _QuickStrip({required this.c, required this.onClean, required this.open, required this.onToggle});
  final AppController c;
  final VoidCallback onClean;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final phase = c.phase;
    final s = c.summary;
    final analyzing = phase == Phase.analyzing;
    final cleaning = phase == Phase.cleaning;
    final busy = analyzing || cleaning;
    final done = phase == Phase.done;
    final failed = done && (c.failedAll || s == null);

    const base = TextStyle(fontSize: 14);
    const bold = TextStyle(fontSize: 28, fontWeight: FontWeight.w700);
    Widget sub;
    if (busy) {
      sub = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cleaning && c.cleanTotalBytes > 0)
            Text.rich(
              key: const Key('countdown'),
              TextSpan(style: base, children: [
                const TextSpan(text: 'Можно освободить '),
                TextSpan(
                    text: formatSize(countdownBytes(c.cleanTotalBytes, c.progressFraction)),
                    style: bold),
              ]),
            ),
          LinearProgressIndicator(value: cleaning ? (1 - c.progressFraction).clamp(0.0, 1.0) : null),
          const SizedBox(height: 2),
          Text(c.progressText, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      );
    } else if (failed) {
      sub = Text('Очистка прервана', style: base.copyWith(color: cs.error));
    } else if (done) {
      final freed = s!.freedBytes;
      final recycled = s.recycledBytes;
      sub = Text.rich(
        TextSpan(style: base, children: [
          if (freed == 0 && recycled == 0)
            const TextSpan(text: 'Нечего было удалять')
          else if (freed > 0) ...[
            const TextSpan(text: 'Освобождено '),
            TextSpan(text: formatSize(freed), style: bold),
          ] else ...[
            const TextSpan(text: 'В Корзине '),
            TextSpan(text: formatSize(recycled), style: bold),
          ],
        ]),
      );
    } else if (phase == Phase.ready) {
      sub = c.selectedBytes > 0
          ? Text.rich(TextSpan(style: base, children: [
              const TextSpan(text: 'Можно освободить '),
              TextSpan(text: formatSize(c.selectedBytes), style: bold),
            ]))
          : const Text('Нечего очищать', style: base);
    } else {
      sub = Text('Сначала посчитаю, что можно убрать',
          style: base.copyWith(color: cs.onSurfaceVariant));
    }

    final info = Row(
      children: [
        if (done && !failed && (s!.freedBytes > 0 || s.recycledBytes > 0))
          const DoneBurst(size: 56, color: Color(0xFF0F9D9A))
        else
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(color: Color(0xFF0F9D9A), shape: BoxShape.circle),
            child: const Icon(Icons.auto_fix_high, color: Colors.white, size: 28),
          ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Быстрая очистка',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              sub,
            ],
          ),
        ),
      ],
    );

    final List<Widget> actions;
    if (done) {
      actions = [
        TextButton(onPressed: c.openDetails, child: const Text('Подробнее')),
        FilledButton(onPressed: c.reset, child: Text(failed ? 'Назад' : 'Готово')),
      ];
    } else {
      actions = [
        TextButton(
          key: const Key('what-to-clean'),
          onPressed: busy ? null : onToggle,
          child: Text(open ? 'Скрыть' : 'Что чистить?'),
        ),
        FilledButton(
          key: const Key('quick-clean'),
          onPressed: (c.phase == Phase.idle || c.canClean) && !c.quickBusy ? onClean : null,
          child: const Text('Очистить'),
        ),
      ];
    }

    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 560;
      return WaveSweep(
        active: cleaning,
        radius: cardRadius,
        child: Container(
        constraints: const BoxConstraints(minHeight: 104),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(cardRadius),
          boxShadow: const [
            BoxShadow(color: Color(0x17143C46), blurRadius: 20, offset: Offset(0, 6)),
          ],
          gradient: light
              ? const LinearGradient(colors: [Color(0xFFDDF2F1), Color(0xFFC6EAE8)])
              : null,
          color: light ? null : cs.surfaceContainerHigh,
        ),
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  info,
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    for (final a in actions) ...[a, const SizedBox(width: 8)],
                  ]),
                ],
              )
            : Row(
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 8),
                  for (final a in actions) ...[const SizedBox(width: 8), a],
                ],
              ),
        ),
      );
    });
  }
}

/// Выпадающая панель «Что чистить?»: галочки категорий с размерами.
class _WhatToClean extends StatelessWidget {
  const _WhatToClean({required this.c, required this.enabled});
  final AppController c;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: HoverCard(
        child: Column(
          key: const Key('what-to-clean-panel'),
          children: [
            for (final r in c.rows) _row(r, cs),
          ],
        ),
      ),
    );
  }

  Widget _row(CategoryRow row, ColorScheme cs) {
    final cat = row.category;
    Widget size;
    switch (row.status) {
      case RowStatus.pending:
        size = const Text('—');
      case RowStatus.scanning:
        size = const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
      case RowStatus.error:
        size = Icon(Icons.error_outline, color: cs.error);
      case RowStatus.done:
        size = row.isEmpty
            ? const Text('Пусто', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))
            : Text(formatSize(row.bytes ?? 0),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600));
    }
    final ready = c.phase == Phase.ready;
    return CheckboxListTile(
      key: ValueKey('cat-${cat.id.name}'),
      controlAffinity: ListTileControlAffinity.leading,
      value: row.selected,
      onChanged: enabled && ready && row.active ? (v) => c.toggleRow(row, v ?? false) : null,
      title: Row(
        children: [
          IconCircle(icon: categoryIcon(cat.id), color: categoryColor(cat.id), size: 32),
          const SizedBox(width: 12),
          Flexible(child: Text(cat.title)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(left: 44),
        child: Text(
          row.status == RowStatus.error
              ? 'Не удалось посчитать'
              : (cat.id == CategoryId.recycle && row.selected && row.active
                  ? 'Очищает Корзину на всех дисках'
                  : cat.hint),
          style: const TextStyle(fontSize: 12),
        ),
      ),
      secondary: size,
    );
  }
}

/// Плитки «Загрузки» и «Большие файлы»: «Найти» → поиск → «Найдено N, X» + «Выбрать».
class _FilesTile extends StatelessWidget {
  const _FilesTile({required this.c, required this.downloads});
  final AppController c;
  final bool downloads;

  @override
  Widget build(BuildContext context) {
    final state = downloads ? c.downloadsState : c.bigState;
    final recycled = downloads ? c.downloadsRecycled : c.bigRecycled;
    final busyApp = c.anyBusy;
    final find = downloads ? c.loadDownloads : c.loadBig;
    final layer = downloads ? Layer.downloads : Layer.big;
    final title = downloads ? 'Загрузки' : 'Большие файлы';
    final icon = downloads ? Icons.download_outlined : Icons.data_usage;
    final tt = downloads ? tintDownloads : tintBig;
    final color = tt.dot;
    final caption = downloads ? 'Что давно лежит в Загрузках' : 'Самые тяжёлые файлы';

    if (recycled != null) {
      return PultTile(
        icon: icon,
        color: color,
        tint: tt.bg,
        title: title,
        caption: caption,
        kind: TileKind.result,
        resultText: 'В Корзину ${formatSize(recycled)}',
        burst: true,
        onAgain: find,
      );
    }
    switch (state) {
      case LoadState.idle:
        return PultTile(
          icon: icon,
          color: color,
          tint: tt.bg,
          title: title,
          caption: caption,
          actionLabel: 'Найти',
          onAction: busyApp ? null : find,
        );
      case LoadState.loading:
        return PultTile(
          icon: icon,
          color: color,
          tint: tt.bg,
          title: title,
          caption: caption,
          kind: TileKind.busy,
          progressText: 'Ищу…',
          onStop: downloads ? c.cancelDownloads : c.cancelBig,
        );
      case LoadState.error:
        return PultTile(
          icon: icon,
          color: color,
          tint: tt.bg,
          title: title,
          caption: caption,
          kind: TileKind.error,
          onRetry: find,
        );
      case LoadState.loaded:
        final files = downloads ? c.visibleDownloads : c.big;
        final bytes = files.fold<int>(0, (a, f) => a + f.size);
        return PultTile(
          icon: icon,
          color: color,
          tint: tt.bg,
          title: title,
          caption: caption,
          kind: TileKind.result,
          wave: c.tileBusy && (downloads ? c.downloadsSelected : c.bigSelected).isNotEmpty,
          resultText: files.isEmpty ? 'Пусто ✓' : 'Найдено ${files.length}, ${formatSize(bytes)}',
          actionLabel: 'Выбрать',
          onAction: files.isEmpty || busyApp ? null : () => c.openLayer(layer),
          onAgain: find,
        );
    }
  }
}

/// Плитка «Дубликаты»: «Найти» → прогресс + «Стоп» → «Найдено N групп, X лишнего» + «Выбрать».
class _DupTile extends StatelessWidget {
  const _DupTile({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    const icon = Icons.file_copy_outlined;
    const tt = tintDupes;
    const color = Color(0xFF7B5EA7);
    const title = 'Дубликаты';
    const caption = 'Одинаковые файлы';
    final busyApp = c.anyBusy;
    final recycled = c.dupRecycled;
    if (recycled != null) {
      return PultTile(
        icon: icon,
        color: color,
        tint: tt.bg,
        title: title,
        caption: caption,
        kind: TileKind.result,
        resultText: 'В Корзину ${formatSize(recycled)}${skippedText(c.dupSkipped)}',
        burst: true,
        onAgain: c.loadDuplicates,
      );
    }
    switch (c.dupState) {
      case LoadState.idle:
        return PultTile(
          icon: icon,
          color: color,
          tint: tt.bg,
          title: title,
          caption: caption,
          actionLabel: 'Найти',
          onAction: busyApp ? null : c.loadDuplicates,
        );
      case LoadState.loading:
        return PultTile(
          icon: icon,
          color: color,
          tint: tt.bg,
          title: title,
          caption: caption,
          kind: TileKind.busy,
          progressText: c.dupProgress,
          onStop: c.cancelDuplicates,
        );
      case LoadState.error:
        return PultTile(
          icon: icon,
          color: color,
          tint: tt.bg,
          title: title,
          caption: caption,
          kind: TileKind.error,
          onRetry: c.loadDuplicates,
        );
      case LoadState.loaded:
        final n = c.dupGroups.length;
        return PultTile(
          icon: icon,
          color: color,
          tint: tt.bg,
          title: title,
          caption: caption,
          kind: TileKind.result,
          wave: c.tileBusy && c.dupSelected.isNotEmpty,
          resultText: n == 0 ? 'Пусто ✓' : 'Найдено ${groupsWord(n)}, ${formatSize(c.dupWasted)} лишнего',
          actionLabel: 'Выбрать',
          onAction: n == 0 || busyApp ? null : () => c.openLayer(Layer.dupes),
          onAgain: c.loadDuplicates,
        );
    }
  }
}

/// Плитка «Пустые папки»: «Найти» → «Найдено N пустых папок» + «Выбрать».
class _EmptyDirsTile extends StatelessWidget {
  const _EmptyDirsTile({required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    const icon = Icons.folder_off_outlined;
    const tt = tintEmpty;
    const color = Color(0xFFC2552B);
    const title = 'Пустые папки';
    const caption = 'Папки без файлов';
    final busyApp = c.anyBusy;
    final recycled = c.emptyRecycled;
    if (recycled != null) {
      return PultTile(
        icon: icon,
        color: color,
        tint: tt.bg,
        title: title,
        caption: caption,
        kind: TileKind.result,
        resultText: 'В Корзину ${emptyDirsWord(recycled)}${skippedText(c.emptySkipped)}',
        burst: true,
        onAgain: c.loadEmptyDirs,
      );
    }
    switch (c.emptyState) {
      case LoadState.idle:
        return PultTile(
          icon: icon,
          color: color,
          tint: tt.bg,
          title: title,
          caption: caption,
          actionLabel: 'Найти',
          onAction: busyApp ? null : c.loadEmptyDirs,
        );
      case LoadState.loading:
        return PultTile(
          icon: icon,
          color: color,
          tint: tt.bg,
          title: title,
          caption: caption,
          kind: TileKind.busy,
          progressText: 'Ищу…',
          onStop: c.cancelEmptyDirs,
        );
      case LoadState.error:
        return PultTile(
          icon: icon,
          color: color,
          tint: tt.bg,
          title: title,
          caption: caption,
          kind: TileKind.error,
          onRetry: c.loadEmptyDirs,
        );
      case LoadState.loaded:
        final n = c.emptyDirs.length;
        return PultTile(
          icon: icon,
          color: color,
          tint: tt.bg,
          title: title,
          caption: caption,
          kind: TileKind.result,
          resultText: n == 0 ? 'Пусто ✓' : 'Найдено ${emptyDirsWord(n)}',
          actionLabel: 'Выбрать',
          onAction: n == 0 || busyApp ? null : () => c.openLayer(Layer.emptyDirs),
          onAgain: c.loadEmptyDirs,
        );
    }
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

