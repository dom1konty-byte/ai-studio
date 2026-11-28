/// Имя процесса → название браузера.
const browserProcesses = <String, String>{
  'chrome.exe': 'Chrome',
  'msedge.exe': 'Edge',
  'firefox.exe': 'Firefox',
  'browser.exe': 'Яндекс',
};

/// Разбор вывода `tasklist /fo csv /nh`: список названий запущенных браузеров.
List<String> parseRunningBrowsers(String tasklistCsv) {
  final found = <String>{};
  for (final line in tasklistCsv.split(RegExp(r'\r?\n'))) {
    final t = line.trim();
    if (!t.startsWith('"')) continue;
    final end = t.indexOf('"', 1);
    if (end < 0) continue;
    final name = t.substring(1, end).toLowerCase();
    final title = browserProcesses[name];
    if (title != null) found.add(title);
  }
  return found.toList();
}
