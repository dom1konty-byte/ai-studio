import 'package:flutter/foundation.dart';

import '../models/note.dart';
import 'notes_repository.dart';
import 'widget_sync.dart';

/// Работа с заметками для интерфейса: хранилище + обновление виджетов.
class NotesService extends ChangeNotifier {
  NotesService(this.repository, {this.widgets = const NoopWidgetSync(), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final NotesRepository repository;
  final WidgetSync widgets;
  final DateTime Function() _clock;

  final Set<Future<void> Function()> _flushers = {};

  /// Открытые редакторы регистрируют сохранение, чтобы его можно было дождаться.
  void registerFlusher(Future<void> Function() f) => _flushers.add(f);

  void unregisterFlusher(Future<void> Function() f) => _flushers.remove(f);

  /// Ждёт, пока открытые редакторы сохранят правки.
  Future<void> flushEditors() async {
    for (final f in [..._flushers]) {
      await f();
    }
  }

  Future<List<Note>> all() => repository.all();

  Future<Note?> byId(int id) => repository.byId(id);

  /// Сохраняет заметку, обновляет дату и виджеты.
  Future<Note> save(Note note) async {
    final saved = await repository.save(note.copyWith(updatedAt: _clock()));
    await refreshWidgets();
    notifyListeners();
    return saved;
  }

  Future<void> delete(int id) async {
    await repository.delete(id);
    await refreshWidgets();
    notifyListeners();
  }

  Future<void> refreshWidgets() async {
    await widgets.refresh(await repository.all());
  }
}
