import '../models/note.dart';
import 'notes_repository.dart';
import 'widget_sync.dart';

/// Работа с заметками для интерфейса: хранилище + обновление виджетов.
class NotesService {
  NotesService(this.repository, {this.widgets = const NoopWidgetSync(), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final NotesRepository repository;
  final WidgetSync widgets;
  final DateTime Function() _clock;

  Future<List<Note>> all() => repository.all();

  Future<Note?> byId(int id) => repository.byId(id);

  /// Сохраняет заметку, обновляет дату и виджеты.
  Future<Note> save(Note note) async {
    final saved = await repository.save(note.copyWith(updatedAt: _clock()));
    await refreshWidgets();
    return saved;
  }

  Future<void> delete(int id) async {
    await repository.delete(id);
    await refreshWidgets();
  }

  Future<void> refreshWidgets() async {
    await widgets.refresh(await repository.all());
  }
}
