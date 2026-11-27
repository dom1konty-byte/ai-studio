import 'package:material_ui/material_ui.dart';

import '../models/note.dart';
import '../services/notes_service.dart';
import '../widgets/note_card.dart';
import 'note_editor_screen.dart';

class NotesListScreen extends StatefulWidget {
  const NotesListScreen({super.key, required this.service});

  final NotesService service;

  @override
  State<NotesListScreen> createState() => NotesListScreenState();
}

class NotesListScreenState extends State<NotesListScreen> {
  final _search = TextEditingController();
  List<Note> _notes = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    try {
      final notes = await widget.service.all();
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      final cs = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: cs.errorContainer,
        content: Text('Не удалось сохранить. Попробуйте ещё раз',
            style: TextStyle(color: cs.onErrorContainer)),
      ));
    }
  }

  Future<void> _open(Note? note) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NoteEditorScreen(service: widget.service, initial: note),
    ));
    await reload();
  }

  int _columns(double width) => width >= 900 ? 4 : (width >= 600 ? 3 : 2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _search.text;
    final visible = _notes.where((n) => n.matches(query)).toList();
    final pinned = visible.where((n) => n.pinned).toList();
    final others = visible.where((n) => !n.pinned).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(null),
        icon: const Icon(Icons.add),
        label: const Text('Заметка'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(builder: (context, c) {
                final cols = _columns(c.maxWidth);
                final grid = SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: 160,
                );
                SliverPadding section(List<Note> list) => SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid.builder(
                        gridDelegate: grid,
                        itemCount: list.length,
                        itemBuilder: (context, i) =>
                            NoteCard(note: list[i], onTap: () => _open(list[i])),
                      ),
                    );
                SliverToBoxAdapter header(String text) => SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(text,
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ),
                    );
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SearchBar(
                          controller: _search,
                          hintText: 'Поиск по заметкам',
                          leading: const Icon(Icons.search),
                          onChanged: (_) => setState(() {}),
                          trailing: [
                            if (query.isNotEmpty)
                              IconButton(
                                tooltip: 'Очистить',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _search.clear();
                                  setState(() {});
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (visible.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _Empty(searching: _notes.isNotEmpty),
                      )
                    else ...[
                      if (pinned.isNotEmpty) ...[header('Закреплённые'), section(pinned)],
                      if (pinned.isNotEmpty && others.isNotEmpty) header('Остальные'),
                      if (others.isNotEmpty) section(others),
                      const SliverToBoxAdapter(child: SizedBox(height: 88)),
                    ],
                  ],
                );
              }),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(searching ? Icons.search_off : Icons.note_add_outlined,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(searching ? 'Ничего не найдено' : 'Пока нет заметок',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(searching ? 'Попробуйте другое слово' : 'Нажмите «+», чтобы записать первую',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
