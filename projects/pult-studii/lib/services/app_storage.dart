import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/models.dart';
import '../models/safety.dart';

/// Что лежит по пути папки студии.
enum FolderKind { missing, empty, notEmpty }

/// Хранилище на диске (подменяется в тестах).
abstract class AppStorage {
  Future<Map<String, dynamic>> loadState();
  Future<void> saveState(Map<String, dynamic> state);
  Future<List<ChatMessage>> loadChat(String slug);
  Future<void> appendChat(String slug, ChatMessage message);
  Future<String?> readText(String path);

  /// В папке есть .claude/agents и projects/README.md.
  Future<bool> repoLooksValid(String path);

  /// Нет папки / пустая / в ней что-то есть.
  Future<FolderKind> folderKind(String path);
}

class FileStorage implements AppStorage {
  FileStorage(this.dir);

  /// %APPDATA%\pult-studii
  final String dir;

  /// Очередь записей: одна за другой, чтобы строки не перемешивались.
  Future<void> _tail = Future.value();
  int _tmpCounter = 0;

  Future<T> _enqueue<T>(Future<T> Function() job) {
    final c = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        c.complete(await job());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  File get _stateFile => File(p.join(dir, 'state.json'));

  File _chatFile(String slug) => File(p.join(
      dir, 'chats', '${slug.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}.jsonl'));

  @override
  Future<Map<String, dynamic>> loadState() async {
    try {
      if (!await _stateFile.exists()) return {};
      final j = jsonDecode(await _stateFile.readAsString());
      return j is Map ? Map<String, dynamic>.from(j) : {};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> saveState(Map<String, dynamic> state) {
    final text = jsonEncode(state);
    return _enqueue(() async {
      await Directory(dir).create(recursive: true);
      final tmp = File(
          '${_stateFile.path}.${pid}_${_tmpCounter++}_${DateTime.now().microsecondsSinceEpoch}.tmp');
      try {
        await tmp.writeAsString(text, flush: true);
        await tmp.rename(_stateFile.path);
      } catch (_) {
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
        rethrow;
      }
    });
  }

  @override
  Future<List<ChatMessage>> loadChat(String slug) async {
    final f = _chatFile(slug);
    if (!await f.exists()) return [];
    final bytes = await f.readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    return const LineSplitter()
        .convert(text)
        .map(ChatMessage.fromJsonLine)
        .whereType<ChatMessage>()
        .toList();
  }

  @override
  Future<void> appendChat(String slug, ChatMessage message) {
    final line = '${message.toJsonLine()}\n';
    return _enqueue(() async {
      final f = _chatFile(slug);
      await f.parent.create(recursive: true);
      await f.writeAsString(line, mode: FileMode.append, flush: true);
    });
  }

  @override
  Future<String?> readText(String path) async {
    try {
      final f = File(path);
      return await f.exists() ? await f.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> repoLooksValid(String path) async {
    if (path.trim().isEmpty) return false;
    return await Directory(p.join(path, '.claude', 'agents')).exists() &&
        await File(p.join(path, 'projects', 'README.md')).exists();
  }

  @override
  Future<FolderKind> folderKind(String path) async {
    try {
      final d = Directory(path);
      if (!await d.exists()) {
        return await File(path).exists() ? FolderKind.notEmpty : FolderKind.missing;
      }
      return await d.list().isEmpty ? FolderKind.empty : FolderKind.notEmpty;
    } catch (_) {
      return FolderKind.notEmpty;
    }
  }
}

/// state.json: {repoPath, projects: {slug: {sessionId, worktree, lastSeenSha, allowedTools, rcOpen}}}
class StateRepo {
  StateRepo(this._storage);

  final AppStorage _storage;
  Map<String, dynamic> _data = {};

  Future<void> load() async => _data = await _storage.loadState();

  Future<void> _save() => _storage.saveState(_data);

  String? get repoPath {
    final v = _data['repoPath'];
    return v is String && v.isNotEmpty ? v : null;
  }

  Future<void> setRepoPath(String path) {
    _data['repoPath'] = path;
    return _save();
  }

  Map<String, dynamic> _proj(String slug) {
    // Копия с типом <String, dynamic>: иначе запись списка в карту
    // с узким типом (например Map<String, String>) упадёт.
    final raw = _data['projects'];
    final all = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    _data['projects'] = all;
    final p = all[slug];
    final m = p is Map ? Map<String, dynamic>.from(p) : <String, dynamic>{};
    all[slug] = m;
    return m;
  }

  /// Только корректный id (иначе не передаём в `--resume`).
  String? sessionId(String slug) {
    final v = _proj(slug)['sessionId'];
    return v is String && isValidSessionId(v) ? v : null;
  }

  Future<void> setSessionId(String slug, String? id) {
    final m = _proj(slug);
    if (id == null) {
      m.remove('sessionId');
    } else if (isValidSessionId(id)) {
      m['sessionId'] = id;
    } else {
      return Future.value();
    }
    return _save();
  }

  /// Папка, в которой начат разговор (сессия Claude привязана к папке).
  String? worktree(String slug) => _proj(slug)['worktree'] as String?;

  Future<void> setWorktree(String slug, String path) {
    _proj(slug)['worktree'] = path;
    return _save();
  }

  /// Открыт терминал Remote Control — чат закрыт, пока Дамир не вернётся.
  bool rcOpen(String slug) => _proj(slug)['rcOpen'] == true;

  Future<void> setRcOpen(String slug, bool open) {
    final m = _proj(slug);
    if (open) {
      m['rcOpen'] = true;
    } else {
      if (!m.containsKey('rcOpen')) return Future.value();
      m.remove('rcOpen');
    }
    return _save();
  }

  String? lastSeenSha(String slug) => _proj(slug)['lastSeenSha'] as String?;

  Future<void> setLastSeenSha(String slug, String sha) {
    _proj(slug)['lastSeenSha'] = sha;
    return _save();
  }

  /// Прочитанные из файла правила тоже проверяем.
  List<String> allowedTools(String slug) {
    final v = _proj(slug)['allowedTools'];
    return v is List
        ? v.whereType<String>().where(isSafeRule).toSet().toList()
        : <String>[];
  }

  Future<void> addAllowedTools(String slug, Iterable<String> rules) {
    final set = allowedTools(slug).toSet()..addAll(rules.where(isSafeRule));
    _proj(slug)['allowedTools'] = set.toList();
    return _save();
  }

  /// Сводка «с телефона», которую ещё не отправили директору.
  List<String> pendingSummary(String slug) {
    final v = _proj(slug)['pendingSummary'];
    return v is List ? v.whereType<String>().take(100).toList() : <String>[];
  }

  Future<void> setPendingSummary(String slug, List<String> lines) {
    final m = _proj(slug);
    if (lines.isEmpty) {
      if (!m.containsKey('pendingSummary')) return Future.value();
      m.remove('pendingSummary');
    } else {
      m['pendingSummary'] = lines;
    }
    return _save();
  }
}
