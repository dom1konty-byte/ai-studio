import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/models.dart';

/// Хранилище на диске (подменяется в тестах).
abstract class AppStorage {
  Future<Map<String, dynamic>> loadState();
  Future<void> saveState(Map<String, dynamic> state);
  Future<List<ChatMessage>> loadChat(String slug);
  Future<void> appendChat(String slug, ChatMessage message);
  Future<String?> readText(String path);

  /// В папке есть .claude/agents и projects/README.md.
  Future<bool> repoLooksValid(String path);
}

class FileStorage implements AppStorage {
  FileStorage(this.dir);

  /// %APPDATA%\pult-studii
  final String dir;

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
  Future<void> saveState(Map<String, dynamic> state) async {
    await Directory(dir).create(recursive: true);
    final tmp = File('${_stateFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(state), flush: true);
    await tmp.rename(_stateFile.path);
  }

  @override
  Future<List<ChatMessage>> loadChat(String slug) async {
    final f = _chatFile(slug);
    if (!await f.exists()) return [];
    final lines = await f.readAsLines();
    return lines.map(ChatMessage.fromJsonLine).whereType<ChatMessage>().toList();
  }

  @override
  Future<void> appendChat(String slug, ChatMessage message) async {
    final f = _chatFile(slug);
    await f.parent.create(recursive: true);
    await f.writeAsString('${message.toJsonLine()}\n',
        mode: FileMode.append, flush: true);
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
}

/// state.json: {repoPath, projects: {slug: {sessionId, lastSeenSha, allowedTools}}}
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
    final all = (_data['projects'] ??= <String, dynamic>{}) as Map<String, dynamic>;
    return (all[slug] ??= <String, dynamic>{}) as Map<String, dynamic>;
  }

  String? sessionId(String slug) => _proj(slug)['sessionId'] as String?;

  Future<void> setSessionId(String slug, String? id) {
    final m = _proj(slug);
    if (id == null) {
      m.remove('sessionId');
    } else {
      m['sessionId'] = id;
    }
    return _save();
  }

  String? lastSeenSha(String slug) => _proj(slug)['lastSeenSha'] as String?;

  Future<void> setLastSeenSha(String slug, String sha) {
    _proj(slug)['lastSeenSha'] = sha;
    return _save();
  }

  List<String> allowedTools(String slug) {
    final v = _proj(slug)['allowedTools'];
    return v is List ? v.whereType<String>().toList() : <String>[];
  }

  Future<void> addAllowedTools(String slug, Iterable<String> rules) {
    final set = allowedTools(slug).toSet()..addAll(rules);
    _proj(slug)['allowedTools'] = set.toList();
    return _save();
  }
}
