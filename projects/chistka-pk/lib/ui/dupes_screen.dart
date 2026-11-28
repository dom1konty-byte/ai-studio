import 'package:material_ui/material_ui.dart';

import '../core/duplicates.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../state/app_controller.dart';
import 'main_screen.dart';
import 'anim.dart';
import 'pult_tile.dart';

/// Панель «Дубликаты»: группы одинаковых файлов, в каждой одна копия остаётся.
class DupesScreen extends StatelessWidget {
  const DupesScreen({super.key, required this.controller});
  final AppController controller;
  AppController get c => controller;

  Future<void> _confirm(BuildContext context) async {
    final n = c.dupSelectedFiles.length;
    final size = formatSize(c.dupSelectedBytes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('В Корзину'),
        content: Text('Переместить ${filesWord(n)} ($size) в Корзину?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('В Корзину')),
        ],
      ),
    );
    if (ok == true) await c.recycleDuplicates();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final groups = c.dupGroups;
    final selected = c.dupSelectedFiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Дубликаты', style: screenTitleStyle),
        Text(
          'Одинаковые файлы в ваших папках. Одна копия остаётся.',
          style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: groups.isEmpty
              ? const Center(child: Text('Дубликатов нет'))
              : ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (_, i) => _GroupCard(c: c, group: groups[i]),
                ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Выбрано: ${filesWord(selected.length)}, ${formatSize(c.dupSelectedBytes)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            FilledButton(
              key: const Key('dupes-recycle'),
              onPressed: selected.isEmpty ? null : () => _confirm(context),
              child: const Text('В Корзину'),
            ),
          ],
        ),
      ],
    );
  }
}

IconData dupIcon(String path) {
  final ext = path.toLowerCase().split('.').last;
  const img = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'tif', 'tiff'];
  const vid = ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'webm', 'm4v'];
  const doc = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'odt'];
  if (img.contains(ext)) return Icons.image_outlined;
  if (vid.contains(ext)) return Icons.movie_outlined;
  if (doc.contains(ext)) return Icons.description_outlined;
  if (fileKind(path) == FileKind.archive) return Icons.folder_zip_outlined;
  return Icons.insert_drive_file_outlined;
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.c, required this.group});
  final AppController c;
  final DupGroup group;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locked = lockedDupPath(group, c.dupSelected);
    final selBytes = group.files
        .where((f) => c.dupSelected.contains(f.path))
        .fold<int>(0, (a, f) => a + f.size);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: cardShape(),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconCircle(icon: dupIcon(group.keeper.path), color: const Color(0xFF7B5EA7)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.keeper.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      Text('${copiesWord(group.files.length)} · по ${formatSize(group.size)}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Text('Можно освободить ${formatSize(selBytes)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            for (final f in group.files)
              _CopyRow(c: c, group: group, file: f, locked: f.path == locked),
          ],
        ),
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.c, required this.group, required this.file, required this.locked});
  final AppController c;
  final DupGroup group;
  final FileInfo file;
  final bool locked;

  void _toggle(BuildContext context, bool on) {
    final ok = c.toggleDup(group, file.path, on);
    if (!ok) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Одна копия всегда остаётся')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final checked = c.dupSelected.contains(file.path);
    return InkWell(
      onTap: () => _toggle(context, !checked),
      child: Row(
        children: [
          Checkbox(
            key: ValueKey('dup-${file.path}'),
            value: checked,
            onChanged: locked ? null : (v) => _toggle(context, v ?? false),
          ),
          Expanded(
            child: Text('${file.folder} · ${formatDate(file.modified)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
          if (locked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_outline, size: 14),
                SizedBox(width: 4),
                Text('Оставить', style: TextStyle(fontSize: 12)),
              ]),
            ),
        ],
      ),
    );
  }
}
