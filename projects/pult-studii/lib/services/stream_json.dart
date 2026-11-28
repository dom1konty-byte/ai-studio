import 'dart:convert';

import '../models/models.dart';

/// События потока `claude -p --output-format stream-json`.
sealed class ClaudeEvent {
  const ClaudeEvent();
}

class SessionInit extends ClaudeEvent {
  const SessionInit(this.sessionId);
  final String sessionId;
}

/// Кусок текста по ходу (partial messages).
class TextDelta extends ClaudeEvent {
  const TextDelta(this.text);
  final String text;
}

/// Законченный текстовый блок ответа.
class AssistantText extends ClaudeEvent {
  const AssistantText(this.text);
  final String text;
}

class ToolUse extends ClaudeEvent {
  const ToolUse(this.name, this.summary);
  final String name;
  final String summary;
}

class ResultEvent extends ClaudeEvent {
  const ResultEvent({
    required this.sessionId,
    required this.isError,
    required this.text,
    required this.costUsd,
    required this.denials,
  });

  final String? sessionId;
  final bool isError;
  final String text;
  final double? costUsd;
  final List<PermissionDenial> denials;
}

/// Разбор одной строки потока. Неизвестное и битое — пропускаем (пустой список).
List<ClaudeEvent> parseStreamLine(String line) {
  final s = line.trim();
  if (s.isEmpty) return const [];
  final Object? j;
  try {
    j = jsonDecode(s);
  } catch (_) {
    return const [];
  }
  if (j is! Map) return const [];
  // События субагентов не показываем.
  if (j['parent_tool_use_id'] != null) return const [];

  switch (j['type']) {
    case 'system':
      final id = j['session_id'];
      if (j['subtype'] == 'init' && id is String && id.isNotEmpty) {
        return [SessionInit(id)];
      }
      return const [];
    case 'stream_event':
      final ev = j['event'];
      if (ev is Map && ev['type'] == 'content_block_delta') {
        final d = ev['delta'];
        if (d is Map && d['type'] == 'text_delta' && d['text'] is String) {
          return [TextDelta(d['text'] as String)];
        }
      }
      return const [];
    case 'assistant':
      final msg = j['message'];
      final content = msg is Map ? msg['content'] : null;
      if (content is! List) return const [];
      final out = <ClaudeEvent>[];
      for (final b in content) {
        if (b is! Map) continue;
        if (b['type'] == 'text') {
          final t = b['text'];
          if (t is String && t.trim().isNotEmpty) out.add(AssistantText(t));
        } else if (b['type'] == 'tool_use') {
          final name = '${b['name']}';
          final input = b['input'];
          out.add(ToolUse(
              name, _summary(name, input is Map ? input : const {})));
        }
      }
      return out;
    case 'result':
      final denials = <PermissionDenial>[];
      final raw = j['permission_denials'];
      if (raw is List) {
        for (final d in raw) {
          if (d is! Map) continue;
          final input = d['tool_input'];
          denials.add(PermissionDenial(
            toolName: '${d['tool_name']}',
            input: input is Map ? Map<String, dynamic>.from(input) : const {},
          ));
        }
      }
      final cost = j['total_cost_usd'];
      final sub = '${j['subtype']}';
      return [
        ResultEvent(
          sessionId: j['session_id'] is String ? j['session_id'] as String : null,
          isError: j['is_error'] == true || sub.startsWith('error'),
          text: j['result'] is String ? j['result'] as String : '',
          costUsd: cost is num ? cost.toDouble() : null,
          denials: denials,
        )
      ];
  }
  return const [];
}

String _summary(String name, Map input) {
  final cmd = input['command'];
  if (cmd is String && cmd.isNotEmpty) return cmd;
  final path = input['file_path'] ?? input['path'];
  if (path is String && path.isNotEmpty) return '$name $path';
  return name;
}
