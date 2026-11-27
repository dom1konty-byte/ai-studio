/// «512 Б», «48,3 МБ», «2,1 ГБ» — один знак после запятой, порог 1024.
String formatSize(int bytes) {
  if (bytes < 0) bytes = 0;
  if (bytes < 1024) return '$bytes Б';
  const units = ['КБ', 'МБ', 'ГБ', 'ТБ'];
  double v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(1).replaceAll('.', ',')} ${units[i]}';
}

/// Дата вида «12.08.2026».
String formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

/// «1 файл», «3 файла», «17 файлов».
String filesWord(int n) {
  final m100 = n % 100;
  final m10 = n % 10;
  if (m100 >= 11 && m100 <= 14) return '$n файлов';
  if (m10 == 1) return '$n файл';
  if (m10 >= 2 && m10 <= 4) return '$n файла';
  return '$n файлов';
}
