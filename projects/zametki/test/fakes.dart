import 'package:zametki/models/note.dart';
import 'package:zametki/services/notes_repository.dart';
import 'package:zametki/services/widget_sync.dart';

/// Хранилище в памяти для widget-тестов.
class FakeNotesRepository implements NotesRepository {
  FakeNotesRepository([List<Note> initial = const []]) {
    for (final n in initial) {
      _notes[_next] = n.copyWith(id: _next);
      _next++;
    }
  }

  final Map<int, Note> _notes = {};
  int _next = 1;

  @override
  Future<List<Note>> all() async {
    final list = _notes.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<Note?> byId(int id) async => _notes[id];

  @override
  Future<Note> save(Note note) async {
    final id = note.id ?? _next++;
    final saved = note.copyWith(id: id);
    _notes[id] = saved;
    return saved;
  }

  @override
  Future<void> delete(int id) async => _notes.remove(id);
}

/// Запоминает, сколько раз обновляли виджеты.
class RecordingWidgetSync implements WidgetSync {
  int calls = 0;
  List<Note> last = const [];

  @override
  Future<void> refresh(List<Note> notes) async {
    calls++;
    last = notes;
  }
}
