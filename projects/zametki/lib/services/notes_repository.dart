import 'package:sqflite/sqflite.dart';

import '../models/note.dart';

/// Хранилище заметок.
abstract class NotesRepository {
  /// Все заметки, новые (по дате изменения) сверху.
  Future<List<Note>> all();
  Future<Note?> byId(int id);

  /// Вставляет (id == null) или обновляет; возвращает заметку с id.
  Future<Note> save(Note note);
  Future<void> delete(int id);
}

/// Хранилище на SQLite (sqflite).
class SqliteNotesRepository implements NotesRepository {
  SqliteNotesRepository(this._db);

  final Database _db;

  static const _table = 'notes';

  /// [path] — файл базы или [inMemoryDatabasePath] для тестов.
  static Future<SqliteNotesRepository> open(String path) async {
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE $_table (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL DEFAULT '',
          body TEXT NOT NULL DEFAULT '',
          is_checklist INTEGER NOT NULL DEFAULT 0,
          items TEXT NOT NULL DEFAULT '[]',
          color INTEGER NOT NULL DEFAULT 0,
          pinned INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL
        )
      '''),
    );
    return SqliteNotesRepository(db);
  }

  @override
  Future<List<Note>> all() async {
    final rows = await _db.query(_table, orderBy: 'updated_at DESC, id DESC');
    return rows.map(Note.fromMap).toList();
  }

  @override
  Future<Note?> byId(int id) async {
    final rows = await _db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Note.fromMap(rows.first);
  }

  @override
  Future<Note> save(Note note) async {
    if (note.id == null) {
      final id = await _db.insert(_table, note.toMap());
      return note.copyWith(id: id);
    }
    await _db.update(_table, note.toMap(), where: 'id = ?', whereArgs: [note.id]);
    return note;
  }

  @override
  Future<void> delete(int id) => _db.delete(_table, where: 'id = ?', whereArgs: [id]);

  Future<void> close() => _db.close();
}
