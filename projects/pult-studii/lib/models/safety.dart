// Проверки безопасности: правила разрешений, id сессии, маскировка секретов.

/// Первое слово команды, которое можно разрешить.
const allowedCommandWords = {
  'git', 'gh', 'flutter', 'dart', 'python', 'python3', 'py', 'npm', 'node', //
  'ls', 'dir', 'cat', 'type', 'findstr', 'where',
};

/// Эти команды Рубка не разрешает никогда (в нижнем регистре).
const forbiddenCommandWords = {
  'rm', 'del', 'erase', 'rmdir', 'rd', 'remove-item', 'powershell', 'pwsh', //
  'cmd', 'curl', 'wget', 'iwr', 'invoke-webrequest', 'reg', 'format',
  'taskkill', 'schtasks', 'icacls', 'takeown',
};

const dangerousText = 'Это опасная команда — Рубка её не разрешает';
const notAllowedText =
    'Рубка не может разрешить такую команду: её нет в белом списке '
    'или в ней есть кавычки, перенаправление или другие спецсимволы.';

final _ruleRe = RegExp(r'^Bash\([A-Za-z0-9._-]+( [A-Za-z0-9._:/\\ *-]*)?\)$');
final _badChars = RegExp('[&|<>^%"\'`\r\n]');
final _splitRe = RegExp(r'&&|\|\||[;&|\r\n]');
final _dangerousPatterns = [
  RegExp(r'^git\s+push\b.*(--force|\s-f\b)', caseSensitive: false),
  RegExp(r'^gh\s+repo\s+delete\b', caseSensitive: false),
  RegExp(r'^gh\s+(auth|secret)\b', caseSensitive: false),
];

/// Синтаксис правила `Bash(...)` и отсутствие запрещённых символов.
bool isValidRule(String rule) =>
    !_badChars.hasMatch(rule) && _ruleRe.hasMatch(rule);

String _firstWord(String part) {
  var w = part.trim().split(RegExp(r'\s+')).first.toLowerCase();
  w = w.split(RegExp(r'[\\/]')).last;
  return w.replaceFirst(RegExp(r'\.(exe|cmd|bat|com)$'), '');
}

/// Результат проверки: либо правила, либо причина отказа.
class RuleDecision {
  const RuleDecision.allowed(this.rules)
      : refusal = null,
        dangerous = false;
  const RuleDecision.refused(this.refusal, {this.dangerous = false})
      : rules = const [];

  /// Точные правила `Bash(...)` — по одному на каждую часть команды.
  final List<String> rules;
  final String? refusal;
  final bool dangerous;

  bool get canAllow => refusal == null && rules.isNotEmpty;
}

/// Части составной команды (`&&`, `||`, `;`, `|`, `&`, перевод строки).
List<String> splitCompound(String cmd) => cmd
    .split(_splitRe)
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

/// Можно ли разрешить команду. Каждая часть составной команды должна пройти.
RuleDecision decideCommand(String cmd) {
  final parts = splitCompound(cmd);
  if (parts.isEmpty) return const RuleDecision.refused(notAllowedText);
  for (final part in parts) {
    if (forbiddenCommandWords.contains(_firstWord(part)) ||
        _dangerousPatterns.any((re) => re.hasMatch(part))) {
      return const RuleDecision.refused(dangerousText, dangerous: true);
    }
  }
  final rules = <String>[];
  for (final part in parts) {
    final first = part.split(RegExp(r'\s+')).first.toLowerCase();
    final rule = 'Bash($part)';
    if (!allowedCommandWords.contains(first) || !isValidRule(rule)) {
      return const RuleDecision.refused(notAllowedText);
    }
    if (!rules.contains(rule)) rules.add(rule);
  }
  return RuleDecision.allowed(rules);
}

/// Правило можно сохранить и передать в `--allowedTools`.
bool isSafeRule(String rule) {
  if (!isValidRule(rule)) return false;
  final inner = rule.substring(5, rule.length - 1);
  final d = decideCommand(inner);
  return d.canAllow && d.rules.length == 1 && d.rules.single == rule;
}

final _sessionRe = RegExp(r'^[0-9a-fA-F-]{36}$');
bool isValidSessionId(String? id) => id != null && _sessionRe.hasMatch(id);

final _secretRe = RegExp(
  r'(ghp_|gho_|ghu_|ghs_|ghr_|github_pat_|sk-ant-)[A-Za-z0-9_-]*'
  r'|Bearer\s+[^\s"' "'" r']+'
  r'|token=[^\s&"' "'" r']*',
  caseSensitive: false,
);

/// Заменяет токены и ключи на `***` (перед записью истории на диск).
String maskSecrets(String text) => text.replaceAll(_secretRe, '***');
