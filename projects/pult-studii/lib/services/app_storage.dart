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

  /// usage.json: расходы по чатам и дням.
  Future<Map<String, dynamic>> loadUsage();
  Future<void> saveUsage(Map<String, dynamic> usage);
  Future<List<ChatMessage>> loadChat(String slug);
  Future<void> appendChat(String slug, ChatMessage message);
  Future<String?> readText(String path);

  /// В папке есть .claude/agents и projects/README.md.
  Future<bool> repoLooksValid(String path);

  /// Нет папки / пустая / в ней что-то есть.
  Future<FolderKind> folderKind(String path);

  /// Удалить пустую папку (не пустую — не трогать). true — папки больше нет.
  Future<bool> deleteEmptyDir(String path);
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
  File get _usageFile => File(p.join(dir, 'usage.json'));

  File _chatFile(String slug) => File(p.join(
      dir, 'chats', '${slug.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}.jsonl'));

  @override
  Future<Map<String, dynamic>> loadState() async {
    try {
      if (!await _stateFile.exists()) return {};
      final text = await _stateFile.readAsString();
      try {
        final j = jsonDecode(text);
        if (j is Map) return Map<String, dynamic>.from(j);
      } catch (_) {}
      await _keepBadCopy();
      return {};
    } catch (_) {
      await _keepBadCopy();
      return {};
    }
  }

  /// Битый state.json: сохранить копию, чтобы не потерять при перезаписи.
  Future<void> _keepBadCopy() async {
    try {
      if (await _stateFile.exists()) {
        await _stateFile.copy(p.join(dir, 'state.json.bad'));
      }
    } catch (_) {}
  }

  @override
  Future<void> saveState(Map<String, dynamic> state) =>
      _writeJson(_stateFile, jsonEncode(state));

  /// Запись через временный файл и переименование (одна очередь на всё).
  Future<void> _writeJson(File target, String text) {
    return _enqueue(() async {
      await Directory(dir).create(recursive: true);
      final tmp = File(
          '${target.path}.${pid}_${_tmpCounter++}_${DateTime.now().microsecondsSinceEpoch}.tmp');
      try {
        await tmp.writeAsString(text, flush: true);
        await tmp.rename(target.path);
      } catch (_) {
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
        rethrow;
      }
    });
  }

  @override
  Future<Map<String, dynamic>> loadUsage() async {
    try {
      if (!await _usageFile.exists()) return {};
      final j = jsonDecode(await _usageFile.readAsString());
      return j is Map ? Map<String, dynamic>.from(j) : {};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> saveUsage(Map<String, dynamic> usage) =>
      _writeJson(_usageFile, jsonEncode(usage));

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
  Future<bool> deleteEmptyDir(String path) async {
    try {
      final d = Directory(path);
      if (!await d.exists()) return true;
      if (!await d.list().isEmpty) return false;
      await d.delete(); // не рекурсивно
      return true;
    } catch (_) {
      return false;
    }
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
  /// Запись из state.json принимаем, только если это основная папка студии
  /// или папка внутри `<родитель основной>\ai-studio-wt\` (файл могли подменить).
  String? worktree(String slug) {
    final v = _proj(slug)['worktree'];
    final repo = repoPath;
    if (v is! String || v.isEmpty || repo == null) return null;
    if (p.equals(v, repo)) return v;
    final root = p.join(p.dirname(repo), 'ai-studio-wt');
    return p.isWithin(root, v) ? v : null;
  }

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

  /// Уведомления Windows: по умолчанию все включены.
  bool notifyEnabled(NotifyKind k) {
    final v = _data['notify'];
    return v is Map ? v[k.name] != false : true;
  }

  Future<void> setNotifyEnabled(NotifyKind k, bool on) {
    final v = _data['notify'];
    final m = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    m[k.name] = on;
    _data['notify'] = m;
    return _save();
  }

  /// Компактный режим (плотный интерфейс).
  bool get compact => _data['compact'] == true;

  Future<void> setCompact(bool on) {
    _data['compact'] = on;
    return _save();
  }

  /// Предложение компактного режима уже показывали.
  bool get compactAsked => _data['compactAsked'] == true;

  Future<void> setCompactAsked() {
    _data['compactAsked'] = true;
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

  /// «Задачи на ночь» (сообщения директору по расписанию).
  List<Map<String, dynamic>> nightTasks() {
    final v = _data['nightTasks'];
    return v is List
        ? [
            for (final x in v.take(200))
              if (x is Map) Map<String, dynamic>.from(x),
          ]
        : <Map<String, dynamic>>[];
  }

  Future<void> setNightTasks(List<Map<String, dynamic>> tasks) {
    if (tasks.isEmpty) {
      if (!_data.containsKey('nightTasks')) return Future.value();
      _data.remove('nightTasks');
    } else {
      _data['nightTasks'] = tasks;
    }
    return _save();
  }
}
