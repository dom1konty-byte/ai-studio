/// Разбор строк таблицы projects/README.md (порт scripts/status.py).
class ReadmeRow {
  const ReadmeRow({
    required this.name,
    required this.slug,
    required this.type,
    required this.stage,
    required this.branch,
  });

  final String name;
  final String slug;
  final String type;
  final String stage;
  final String branch;
}

List<ReadmeRow> parseReadmeRows(String text) {
  final out = <ReadmeRow>[];
  for (final raw in text.split('\n')) {
    final line = raw.trimRight();
    if (!line.startsWith('|')) continue;
    final inner = line.trim().replaceAll(RegExp(r'^\|+|\|+$'), '');
    final cells = inner.split('|').map((c) => c.trim()).toList();
    if (cells.length < 5) continue;
    final first = cells[0];
    if (first.isEmpty || first.split('').every((c) => '-: '.contains(c))) {
      continue;
    }
    if (first == 'Имя') continue;
    final folder = cells[1];
    final parts = folder.split('`');
    final slug = parts.length > 1 ? parts[1] : folder;
    out.add(ReadmeRow(
      name: first,
      slug: slug,
      type: cells[2],
      stage: cells[3],
      branch: cells[4].replaceAll('`', ''),
    ));
  }
  return out;
}

/// Этап содержит «ждёт «да»» (допускаем е/ё и разные кавычки).
bool stageWaitsYes(String stage) {
  final s = stage.toLowerCase().replaceAll('ё', 'е');
  return RegExp(r'ждет\s*[«"“„]?\s*да(?![а-я])').hasMatch(s);
}
