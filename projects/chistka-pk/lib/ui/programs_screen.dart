import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../core/programs.dart';
import '../state/app_controller.dart';
import 'leftovers_screen.dart';

/// Экран «Программы»: список установленных программ, поиск, сортировка,
/// «Удалить» и «Принудительно удалить…».
class ProgramsScreen extends StatefulWidget {
  const ProgramsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  AppController get c => widget.controller;
  final _search = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _search.text = c.programQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (c.programsState == LoadState.idle) c.loadPrograms();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _confirmUninstall(Program p) async {
    final ok = await _ask(
      title: 'Удалить «${p.name}»?',
      text: 'Запустится программа удаления.',
      action: 'Удалить',
    );
    if (ok) await c.uninstall(p);
  }

  Future<void> _confirmForce(Program p) async {
    final ok = await _ask(
      title: 'Принудительно удалить «${p.name}»?',
      text: 'Программа удаления не будет запущена. Будут найдены и удалены остатки '
          'и запись в списке программ.',
      action: 'Продолжить',
    );
    if (ok) await c.forceRemove(p);
  }

  Future<bool> _ask({required String title, required String text, required String action}) async {
    final cs = Theme.of(context).colorScheme;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    if (c.leftoverProgram != null) return LeftoversScreen(controller: c);
    final cs = Theme.of(context).colorScheme;
    final list = c.visiblePrograms;
    final busy = c.uninstallBusy;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _focus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.f5): c.loadPrograms,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Программы', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _search,
                    focusNode: _focus,
                    onChanged: c.setProgramQuery,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Поиск по имени (Ctrl+F)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                SegmentedButton<ProgramSort>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ProgramSort.size, label: Text('Размер')),
                    ButtonSegment(value: ProgramSort.date, label: Text('Дата')),
                    ButtonSegment(value: ProgramSort.name, label: Text('Имя')),
                  ],
                  selected: {c.programSort},
                  onSelectionChanged: (s) => c.setProgramSort(s.first),
                ),
              ],
            ),
            if (c.programMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    Expanded(child: Text(c.programMessage!, style: TextStyle(color: cs.primary))),
                    if (c.uninstallWaiting)
                      OutlinedButton(
                        onPressed: c.cancelUninstallWait,
                        child: const Text('Отмена'),
                      ),
                    if (!busy && c.recheckProgram != null)
                      FilledButton(
                        onPressed: c.recheckAndFindLeftovers,
                        child: const Text('Проверить и найти остатки'),
                      ),
                    if (!busy && c.forceOffer != null)
                      OutlinedButton(
                        onPressed: () => _confirmForce(c.forceOffer!),
                        child: const Text('Принудительно удалить…'),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(child: _body(list, busy, cs)),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Всего программ: ${c.programs.length}',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(List<Program> list, bool busy, ColorScheme cs) {
    switch (c.programsState) {
      case LoadState.idle:
      case LoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case LoadState.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Не удалось прочитать список программ.'),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: c.loadPrograms, child: const Text('Повторить')),
            ],
          ),
        );
      case LoadState.loaded:
        if (list.isEmpty) return const Center(child: Text('Ничего не найдено'));
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) => _row(list[i], busy, cs),
        );
    }
  }

  Widget _row(Program p, bool busy, ColorScheme cs) {
    return ListTile(
      leading: const Icon(Icons.apps),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        p.publisher.isEmpty ? ' ' : p.publisher,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 80,
            child: Text(p.sizeKb > 0 ? formatSize(p.sizeBytes) : '—', textAlign: TextAlign.right),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 84,
            child: Text(p.installDate == null ? '—' : formatDate(p.installDate!),
                textAlign: TextAlign.right),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.error,
              side: BorderSide(color: cs.error),
              minimumSize: const Size(96, 40),
            ),
            onPressed: busy ? null : () => _confirmUninstall(p),
            child: const Text('Удалить'),
          ),
          PopupMenuButton<String>(
            enabled: !busy,
            tooltip: 'Ещё',
            onSelected: (v) {
              if (v == 'force') _confirmForce(p);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'force', child: Text('Принудительно удалить…')),
            ],
          ),
        ],
      ),
    );
  }
}
