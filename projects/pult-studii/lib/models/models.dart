import 'dart:convert';

import 'safety.dart';

/// Ключ чата и ветка «Офиса» студии.
const officeKey = 'ai-office';

/// Первое сообщение нового разговора с офисом.
String officeStartText(String task) =>
    'Офис студии. Ветка: $officeKey. Задача: $task';

/// Первое сообщение нового разговора с директором проекта.
String projectStartText(String name, String slug, String task) =>
    'Проект: $name ($slug). Ветка: $slug. Задача: $task';

/// Задача для «Продолжить на телефоне».
const continueTask = 'продолжи с текущего этапа';

/// Что отправить директору, если в папке есть незапушенное.
const commitAndPushText = 'Закоммить и запушь всё';

/// Типы нового проекта: значения `scripts/new_project.py` → подпись.
const newProjectTypes = {
  'app': 'Android-приложение',
  'site': 'Сайт',
  'bot': 'Telegram-бот',
  'windows': 'Программа Windows',
};

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

  /// Можно ли разрешить: точные правила или причина отказа.
  RuleDecision get decision {
    if (toolName != 'Bash') {
      return const RuleDecision.refused(
          'Рубка разрешает только команды из белого списка, '
          'это действие разрешить нельзя.');
    }
    final cmd = input['command'];
    if (cmd is! String || cmd.trim().isEmpty) {
      return const RuleDecision.refused(notAllowedText);
    }
    return decideCommand(cmd);
  }
}

/// Решение по всем отказам одного сообщения.
RuleDecision decideDenials(List<PermissionDenial> denials) {
  final rules = <String>[];
  for (final d in denials) {
    final r = d.decision;
    if (!r.canAllow) return r;
    for (final x in r.rules) {
      if (!rules.contains(x)) rules.add(x);
    }
  }
  return rules.isEmpty
      ? const RuleDecision.refused(notAllowedText)
      : RuleDecision.allowed(rules);
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

  /// Что сохраняем в `chats/<slug>.jsonl`.
  bool get persistent =>
      kind == MsgKind.user ||
      kind == MsgKind.director ||
      kind == MsgKind.action ||
      kind == MsgKind.note;

  /// Строка для истории: секреты замаскированы, действия обрезаны до 200 символов.
  String toJsonLine() {
    var t = maskSecrets(text);
    if (kind == MsgKind.action && t.length > 200) {
      t = '${t.substring(0, 199)}…';
    }
    return jsonEncode({'k': kind.name, 't': t, 'ts': time.toIso8601String()});
  }

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
