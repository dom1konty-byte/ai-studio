import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../state/app_controller.dart';

/// Панель «Пустые папки»: список с галочками, удаление в Корзину.
class EmptyDirsScreen extends StatelessWidget {
  const EmptyDirsScreen({super.key, required this.controller});
  final AppController controller;
  AppController get c => controller;

  Future<void> _confirm(BuildContext context) async {
    final n = c.emptySelected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('В Корзину'),
        content: Text('Переместить ${emptyDirsWord(n)} в Корзину?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('В Корзину')),
        ],
      ),
    );
    if (ok == true) await c.recycleEmptyDirs();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dirs = c.emptyDirs;
    final sel = c.emptySelected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Пустые папки', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
        Text(
          'Системные и скрытые папки не показываются. Папки в OneDrive не отмечены заранее.',
          style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (dirs.isNotEmpty)
          Row(
            children: [
              Checkbox(
                value: sel.isEmpty ? false : (sel.length == dirs.length ? true : null),
                tristate: true,
                onChanged: c.emptyBusy ? null : (v) => c.setAllEmptyDirs(v == true),
              ),
              const Text('Выбрать все'),
            ],
          ),
        Expanded(
          child: dirs.isEmpty
              ? const Center(child: Text('Пустых папок нет'))
              : ListView.builder(
                  itemCount: dirs.length,
                  itemBuilder: (_, i) {
                    final d = dirs[i];
                    return CheckboxListTile(
                      key: ValueKey('empty-$d'),
                      controlAffinity: ListTileControlAffinity.leading,
                      secondary: const Icon(Icons.folder_off_outlined),
                      value: sel.contains(d),
                      onChanged: c.emptyBusy ? null : (v) => c.toggleEmptyDirPath(d, v ?? false),
                      title: Text(d, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: const Text('0 файлов', style: TextStyle(fontSize: 12)),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: Text('Выбрано: ${emptyDirsWord(sel.length)}')),
            FilledButton(
              key: const Key('empty-recycle'),
              onPressed: sel.isEmpty || c.emptyBusy ? null : () => _confirm(context),
              child: const Text('В Корзину'),
            ),
          ],
        ),
      ],
    );
  }
}
