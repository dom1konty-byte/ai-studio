import '../models/models.dart';
import 'readme_parser.dart';

/// Заголовок всех уведомлений.
const notifyTitle = 'AI Studio';

/// Показ уведомлений Windows (в тестах подменяется фейком).
abstract class AppNotifier {
  /// [onClick] получает ключ чата (slug проекта или `ai-office`).
  Future<void> init(void Function(String key) onClick);

  Future<void> show({
    required String title,
    required String body,
    required String key,
  });
}

/// Название этапа без пометки «ждёт «да»» и галочки: `Дизайн ✅ ждёт «да»` → `Дизайн`.
String stageName(String stage) {
  final t = stage
      .replaceAll(RegExp('ждёт\\s*[«"]?да[»"]?', caseSensitive: false), '')
      .replaceAll('✅', '')
      .trim();
  return t.isEmpty ? stage.trim() : t;
}

String notifyBody(NotifyKind kind, String projectName, {String stage = ''}) =>
    switch (kind) {
      NotifyKind.directorReply => 'Директор ответил: $projectName',
      NotifyKind.waitsYes => stage.isEmpty
          ? '$projectName ждёт «да»'
          : '$projectName ждёт «да» — ${stageName(stage)}',
      NotifyKind.buildOk => '$projectName: сборка готова',
      NotifyKind.buildFailed => '$projectName: сборка упала',
    };

/// Помнит прошлое состояние доски и сборок: уведомляет только об изменениях.
/// Первое наблюдение ничего не шлёт.
class NotifyTracker {
  bool _stagesInit = false;
  Set<String> _waiting = {};
  final Map<String, (int?, BuildState)> _builds = {};

  void reset() {
    _stagesInit = false;
    _waiting = {};
    _builds.clear();
  }

  /// Проекты, которые только что стали «ждёт «да»».
  List<Project> newlyWaiting(List<Project> projects) {
    if (projects.isEmpty) return const [];
    final now = {
      for (final p in projects)
        if (stageWaitsYes(p.stage)) p.slug,
    };
    final fresh = _stagesInit
        ? [
            for (final p in projects)
              if (now.contains(p.slug) && !_waiting.contains(p.slug)) p,
          ]
        : <Project>[];
    _stagesInit = true;
    _waiting = now;
    return fresh;
  }

  /// success / failed, если у проекта сменился статус последнего запуска.
  BuildState? buildChanged(String slug, BuildRun run) {
    if (run.state == BuildState.loading || run.state == BuildState.unknown) {
      return null;
    }
    final prev = _builds[slug];
    _builds[slug] = (run.id, run.state);
    if (prev == null) return null;
    final done =
        run.state == BuildState.success || run.state == BuildState.failed;
    if (done && (prev.$2 != run.state || prev.$1 != run.id)) return run.state;
    return null;
  }
}
