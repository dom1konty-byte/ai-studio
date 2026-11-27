import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../core/leftovers.dart';
import '../state/app_controller.dart';

/// Экран «Остатки»: папки, ярлыки и ключи реестра, оставшиеся после программы.
class LeftoversScreen extends StatelessWidget {
  const LeftoversScreen({super.key, required this.controller});
  final AppController controller;

  AppController get c => controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final prog = c.leftoverProgram!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Остатки: ${prog.name}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          c.leftoverForced
              ? 'Принудительное удаление: программа удаления не запускалась.'
              : 'Отмечено то, что точно относится к программе. Остальное проверьте сами.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Expanded(child: _body(cs)),
        if (c.leftoverBusy) const LinearProgressIndicator(),
        if (c.leftoverMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(c.leftoverMessage!, style: TextStyle(color: cs.primary)),
          ),
        Text('Файлы уйдут в Корзину, реестр — с резервной копией',
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              onPressed: c.leftoverBusy || c.leftoverSelected.isEmpty ? null : c.deleteLeftovers,
              child: Text(c.leftoverSelected.isEmpty
                  ? 'Удалить отмеченное'
                  : 'Удалить отмеченное (${formatSize(c.leftoverSelectedBytes)})'),
            ),
            OutlinedButton(
              onPressed: c.openBackupFolder,
              child: const Text('Открыть папку копий'),
            ),
            TextButton(
              onPressed: c.leftoverBusy ? null : c.closeLeftovers,
              child: const Text('Готово'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _body(ColorScheme cs) {
    switch (c.leftoverState) {
      case LoadState.idle:
      case LoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case LoadState.error:
        return const Center(child: Text('Не удалось найти остатки.'));
      case LoadState.loaded:
        if (c.leftovers.isEmpty) {
          return const Center(child: Text('Остатков не найдено'));
        }
        return ListView(
          children: [
            _group('Папки', LeftoverKind.folder, cs),
            _group('Ярлыки', LeftoverKind.shortcut, cs),
            _group('Реестр', LeftoverKind.registry, cs),
          ],
        );
    }
  }

  Widget _group(String title, LeftoverKind kind, ColorScheme cs) {
    final items = c.leftovers.where((l) => l.kind == kind).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        for (final l in items)
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: c.leftoverSelected.contains(l),
            onChanged: l.deletable && !c.leftoverBusy ? (v) => c.toggleLeftover(l, v == true) : null,
            title: Text(l.path, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                l.exact ? 'точно' : 'возможно',
                if (l.note != null) l.note!,
                if (!l.deletable && l.note == null) 'Нужны права администратора',
                if (c.leftoverResults[l] != null) c.leftoverResults[l]!,
              ].join(' · '),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            secondary: kind == LeftoverKind.registry
                ? null
                : Text(formatSize(l.bytes)),
          ),
      ],
    );
  }
}
