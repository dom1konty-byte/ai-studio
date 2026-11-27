import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../state/app_controller.dart';

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

    final list = <Widget>[];
    var programsHeader = false;
    for (final r in c.rows) {
      if (r.category.isProgram && !programsHeader) {
        programsHeader = true;
        list.add(const Padding(
          padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text('Программы', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ));
      }
      list.add(_CategoryTile(row: r, controller: c, enabled: ready));
    }
    list.add(const SizedBox(height: 8));
    list.add(_DownloadsTile(controller: c, enabled: !busy));

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
        Row(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: CircularProgressIndicator(value: ring, strokeWidth: 8),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(heroText, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w300)),
                Text(heroCaption, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: ListView(children: list)),
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
        size = Text(
          row.isEmpty ? 'Пусто' : formatSize(row.bytes ?? 0),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        );
    }
    if (cat.id == CategoryId.recycle && row.selected && row.active) {
      subtitle = 'Очищает Корзину на всех дисках';
    }
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: cardShape(),
      child: CheckboxListTile(
        shape: cardShape(),
        controlAffinity: ListTileControlAffinity.leading,
        value: row.selected,
        onChanged: enabled && row.active ? (v) => controller.toggleRow(row, v ?? false) : null,
        title: Row(
          children: [
            Icon(categoryIcon(cat.id), size: 20),
            const SizedBox(width: 8),
            Flexible(child: Text(cat.title)),
          ],
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
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
    return Card(
      elevation: 0,
      shape: cardShape(),
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
            Icon(Icons.download_outlined, size: 20),
            SizedBox(width: 8),
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
