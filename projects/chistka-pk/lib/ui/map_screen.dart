import 'package:material_ui/material_ui.dart';

import '../core/disk_map.dart';
import '../core/format.dart';
import '../state/app_controller.dart';
import 'anim.dart';

/// «Карта диска»: размеры подпапок. Только просмотр, ничего не удаляется.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final cs = Theme.of(context).colorScheme;
    final crumbs = breadcrumbs(c.systemDrive, c.mapPath);
    final loading = c.mapState == LoadState.loading;
    final maxBytes = c.mapEntries.isEmpty
        ? 1
        : c.mapEntries.map((e) => e.bytes).reduce((a, b) => a > b ? a : b).clamp(1, 1 << 62);

    Widget body;
    switch (c.mapState) {
      case LoadState.idle:
        body = const Center(child: Text('Посмотрите, что занимает место'));
      case LoadState.loading:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 4),
            Text(c.mapProgress, style: const TextStyle(fontSize: 12)),
          ],
        );
      case LoadState.error:
        body = const Center(child: Text('Не удалось прочитать папку'));
      case LoadState.loaded:
        body = c.mapEntries.isEmpty
            ? const Center(child: Text('Вложенных папок нет'))
            : ListView(
                children: [
                  for (final e in c.mapEntries)
                    ListTile(
                      enabled: !e.denied,
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(e.name),
                      subtitle: e.denied
                          ? const Text('Нет доступа')
                          : Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: LinearProgressIndicator(value: e.bytes / maxBytes),
                            ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(e.denied && e.bytes == 0 ? '—' : formatSize(e.bytes)),
                          IconButton(
                            tooltip: 'Открыть в Проводнике',
                            icon: const Icon(Icons.open_in_new),
                            onPressed: () => c.openInExplorer(e.path),
                          ),
                        ],
                      ),
                      onTap: e.denied ? null : () => c.openMapFolder(e.path),
                    ),
                ],
              );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Карта диска', style: screenTitleStyle),
        Text('Только просмотр, ничего не удаляется',
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: c.mapCanGoBack && !loading ? c.mapBack : null,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Назад'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < crumbs.length; i++) ...[
                    if (i > 0) const Icon(Icons.chevron_right, size: 16),
                    TextButton(
                      onPressed: loading || i == crumbs.length - 1
                          ? null
                          : () => c.openMapFolder(crumbs[i].path),
                      child: Text(crumbs[i].label),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Открыть в Проводнике',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => c.openInExplorer(c.mapPath),
            ),
            FilledButton(
              onPressed: loading ? null : () => c.openMapFolder(c.mapPath, force: true),
              child: const Text('Сканировать'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: body),
      ],
    );
  }
}
