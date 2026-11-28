// Документы проекта (docs/*.md): читаем из папки worktree или из git.
import 'package:path/path.dart' as p;

import 'app_storage.dart';
import 'git_service.dart';
import 'process_runner.dart';

/// Один документ из списка: подпись и имя файла.
class DocSpec {
  const DocSpec(this.title, this.file);

  final String title;
  final String file;
}

const projectDocSpecs = [
  DocSpec('Бриф', 'brief.md'),
  DocSpec('ТЗ', 'tz.md'),
  DocSpec('Дизайн', 'design.md'),
  DocSpec('Архитектура', 'architecture.md'),
  DocSpec('Отчёт', 'report.md'),
  DocSpec('Уроки', 'lessons.md'),
];

/// Документ и его текст (null — файла нет).
class DocEntry {
  const DocEntry(this.spec, this.text);

  final DocSpec spec;
  final String? text;

  bool get exists => text != null;
}

class ProjectDocs {
  ProjectDocs(this._proc, this._storage);

  final ProcessRunner _proc;
  final AppStorage _storage;

  /// Все шесть документов. [workDir] — папка worktree проекта (пусто —
  /// папки ещё нет, читаем `git show origin/<slug>:…` в [repoPath]).
  Future<List<DocEntry>> load({
    required String slug,
    required String repoPath,
    String? workDir,
  }) async {
    final res = <DocEntry>[];
    for (final spec in projectDocSpecs) {
      res.add(DocEntry(
          spec,
          isSafeSlug(slug)
              ? await _read(slug, spec, repoPath, workDir)
              : null));
    }
    return res;
  }

  Future<String?> _read(
      String slug, DocSpec spec, String repoPath, String? workDir) async {
    if (workDir != null && workDir.isNotEmpty) {
      final t = await _storage
          .readText(p.join(workDir, 'projects', slug, 'docs', spec.file));
      if (t != null) return t;
    }
    if (repoPath.isEmpty) return null;
    try {
      final r = await _proc.run(
          'git', ['show', 'origin/$slug:projects/$slug/docs/${spec.file}'],
          cwd: repoPath);
      return r.ok ? r.stdout : null;
    } catch (_) {
      return null;
    }
  }
}
