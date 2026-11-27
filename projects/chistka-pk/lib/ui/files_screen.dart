import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/scanner.dart';
import '../state/app_controller.dart';
import 'main_screen.dart';

/// Экран «Загрузки» ([isDownloads] = true) или «Большие файлы».
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key, required this.controller, required this.isDownloads});
  final AppController controller;
  final bool isDownloads;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  AppController get c => widget.controller;
  bool get dl => widget.isDownloads;

  LoadState get _state => dl ? c.downloadsState : c.bigState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_state == LoadState.idle) _load();
    });
  }

  void _load() => dl ? c.loadDownloads() : c.loadBig();

  Future<void> _confirmRecycle() async {
    final n = dl ? c.downloadsSelected.length : c.bigSelected.length;
    final size = formatSize(dl ? c.downloadsSelectedBytes : c.bigSelectedBytes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('В Корзину'),
        content: Text('Переместить ${filesWord(n)} ($size) в Корзину?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('В Корзину'),
          ),
        ],
      ),
    );
    if (ok == true) await (dl ? c.recycleDownloads() : c.recycleBig());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final files = dl ? c.visibleDownloads : c.big;
    final selected = dl ? c.downloadsSelected : c.bigSelected;
    final selBytes = dl ? c.downloadsSelectedBytes : c.bigSelectedBytes;

    Widget body;
    switch (_state) {
      case LoadState.idle:
      case LoadState.loading:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(dl ? 'Ищу старые файлы…' : 'Ищу большие файлы…'),
          ],
        );
      case LoadState.error:
        body = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 8),
              const Text('Не удалось прочитать папку'),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        );
      case LoadState.loaded:
        if (files.isEmpty) {
          body = Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, size: 48),
                const SizedBox(height: 8),
                Text(dl ? 'В этом списке файлов нет' : 'Файлов нет'),
              ],
            ),
          );
        } else {
          body = Column(
            children: [
              Row(
                children: [
                  Checkbox(
                    value: selected.isEmpty
                        ? false
                        : (selected.length == files.length ? true : null),
                    tristate: true,
                    onChanged: dl
                        ? (v) => c.setAllDownloads(v == true)
                        : (v) {
                            for (final f in files) {
                              c.toggleBig(f.path, v == true);
                            }
                          },
                  ),
                  const Text('Выбрать все'),
                  const Spacer(),
                  Text('Выбрано: ${filesWord(selected.length)}, ${formatSize(selBytes)}'),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (_, i) => _FileTile(
                    file: files[i],
                    isDownloads: dl,
                    checked: selected.contains(files[i].path),
                    onChanged: (v) =>
                        dl ? c.toggleDownload(files[i].path, v) : c.toggleBig(files[i].path, v),
                  ),
                ),
              ),
            ],
          );
        }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(dl ? 'Загрузки' : 'Большие файлы',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
        Text(
          dl
              ? 'Удаляются в Корзину. Ничего не отмечено заранее.'
              : 'Только показ. Отмеченные уйдут в Корзину.',
          style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
        ),
        if (dl) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<DownloadsFilter>(
            key: const Key('downloads-filter'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: DownloadsFilter.all, label: Text('Все')),
              ButtonSegment(value: DownloadsFilter.recent, label: Text('Новые (≤ 7 дней)')),
              ButtonSegment(value: DownloadsFilter.old, label: Text('Старше 30 дней')),
            ],
            selected: {c.downloadsFilter},
            onSelectionChanged: (v) => c.setDownloadsFilter(v.first),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Expanded(child: body),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton(
              onPressed: selected.isEmpty ? null : _confirmRecycle,
              child: const Text('В Корзину'),
            ),
          ],
        ),
      ],
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.isDownloads,
    required this.checked,
    required this.onChanged,
  });
  final FileInfo file;
  final bool isDownloads;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kind = fileKind(file.path);
    final IconData icon;
    String? chip;
    final age = isDownloads ? ageLabel(file.modified, DateTime.now()) : null;
    switch (kind) {
      case FileKind.installer:
        icon = Icons.install_desktop;
        chip = 'Установщик';
      case FileKind.archive:
        icon = Icons.folder_zip_outlined;
        chip = 'Архив';
      case FileKind.other:
        icon = Icons.insert_drive_file_outlined;
    }
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 4),
      shape: cardShape(),
      child: ListTile(
        shape: cardShape(),
        onTap: () => onChanged(!checked),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(value: checked, onChanged: (v) => onChanged(v ?? false)),
            Icon(icon),
          ],
        ),
        title: Row(
          children: [
            Flexible(child: Text(file.name, overflow: TextOverflow.ellipsis)),
            for (final t in [?chip, ?age]) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(t, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
        subtitle: Text(
          isDownloads ? formatDate(file.modified) : file.folder,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(formatSize(file.size),
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Чип возраста файла: «Сегодня», «12 дн.», «5 мес.», «2 г.».
String ageLabel(DateTime modified, DateTime now) {
  final d = now.difference(modified).inDays;
  if (d < 1) return 'Сегодня';
  if (d < 60) return '$d дн.';
  if (d < 730) return '${d ~/ 30} мес.';
  return '${d ~/ 365} г.';
}
