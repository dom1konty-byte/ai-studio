import 'dart:convert';

enum MsgKind { user, director, action, error, denial, note }

/// Отказ в разрешении из `result.permission_denials`.
class PermissionDenial {
  const PermissionDenial({required this.toolName, required this.input});

  final String toolName;
  final Map<String, dynamic> input;

  /// Что показать Дамиру.
  String get display {
    final cmd = input['command'];
    if (cmd is String && cmd.isNotEmpty) return cmd;
    final path = input['file_path'] ?? input['path'];
    if (path is String && path.isNotEmpty) return '$toolName $path';
    return toolName;
  }

  /// Правило для `--allowedTools`.
  String get allowRule {
    if (toolName == 'Bash') {
      final cmd = input['command'];
      if (cmd is String && cmd.trim().isNotEmpty) {
        final first = cmd.trim().split(RegExp(r'\s+')).first;
        return 'Bash($first *)';
      }
    }
    return toolName;
  }
}

class ChatMessage {
  ChatMessage(this.kind, this.text,
      {this.denials = const [], DateTime? time})
      : time = time ?? DateTime.now();

  final MsgKind kind;
  String text;
  final List<PermissionDenial> denials;
  final DateTime time;
  bool resolved = false;

  /// Что сохраняем в chats/<slug>.jsonl.
  bool get persistent =>
      kind == MsgKind.user ||
      kind == MsgKind.director ||
      kind == MsgKind.action ||
      kind == MsgKind.note;

  String toJsonLine() =>
      jsonEncode({'k': kind.name, 't': text, 'ts': time.toIso8601String()});

  static ChatMessage? fromJsonLine(String line) {
    try {
      final j = jsonDecode(line);
      if (j is! Map) return null;
      final kind = MsgKind.values.where((k) => k.name == j['k']).firstOrNull;
      final text = j['t'];
      if (kind == null || text is! String) return null;
      return ChatMessage(kind, text,
          time: DateTime.tryParse('${j['ts']}') ?? DateTime.now());
    } catch (_) {
      return null;
    }
  }
}

class Project {
  const Project({
    required this.name,
    required this.slug,
    required this.type,
    required this.stage,
    required this.branch,
    required this.branchExists,
  });

  final String name;
  final String slug;
  final String type;
  final String stage;
  final String branch;
  final bool branchExists;

  Project withStage(String s) => Project(
      name: name,
      slug: slug,
      type: type,
      stage: s,
      branch: branch,
      branchExists: branchExists);
}

enum BuildState { loading, none, running, success, failed, unknown }

class BuildRun {
  const BuildRun(this.state, {this.id, this.url, this.updatedAt});

  static const loading = BuildRun(BuildState.loading);
  static const none = BuildRun(BuildState.none);
  static const unknown = BuildRun(BuildState.unknown);

  final BuildState state;
  final int? id;
  final String? url;
  final DateTime? updatedAt;

  factory BuildRun.fromApi(Map<String, dynamic> run) {
    final status = run['status'] as String?;
    final conclusion = run['conclusion'] as String?;
    final BuildState s;
    if (status != 'completed') {
      s = BuildState.running;
    } else if (conclusion == 'success') {
      s = BuildState.success;
    } else {
      s = BuildState.failed;
    }
    final id = run['id'];
    return BuildRun(
      s,
      id: id is int ? id : null,
      url: run['html_url'] as String?,
      updatedAt: DateTime.tryParse('${run['updated_at']}'),
    );
  }

  /// Артефакты GitHub хранятся 30 дней.
  bool isExpired(DateTime now) =>
      updatedAt != null && now.difference(updatedAt!).inDays >= 30;
}
