/// Список установленных программ (реестр Uninstall): модель, фильтр, разбор
/// строки удаления, поиск и сортировка. Чистые функции — без обращения к системе.
library;

/// Запись раздела Uninstall «как есть»: [hive] — `HKCU`, `HKLM` или `HKLM32`
/// (HKLM\WOW6432Node), [keyPath] — полный путь ключа для reg.exe,
/// [values] — значения (DWORD уже переведены в десятичную строку).
class RawUninstall {
  const RawUninstall(this.hive, this.keyPath, this.values);
  final String hive;
  final String keyPath;
  final Map<String, String> values;

  String get keyName => keyPath.split(r'\').last;
}

class Program {
  const Program({
    required this.name,
    required this.publisher,
    required this.sizeKb,
    required this.installDate,
    required this.displayIcon,
    required this.installLocation,
    required this.uninstallString,
    required this.quietUninstallString,
    required this.hive,
    required this.keyPath,
  });

  final String name;
  final String publisher;

  /// EstimatedSize в КБ (0 — не указан).
  final int sizeKb;
  final DateTime? installDate;
  final String displayIcon;
  final String installLocation;
  final String uninstallString;
  final String quietUninstallString;
  final String hive;
  final String keyPath;

  int get sizeBytes => sizeKb * 1024;
  bool get isUserHive => hive == 'HKCU';
}

final RegExp _kbName = RegExp(r'^KB\d+$', caseSensitive: false);
final RegExp _kbInName = RegExp(r'\(KB\d+\)', caseSensitive: false);

/// Скрывать ли запись: без имени, системный компонент, дочерний компонент,
/// обновление/исправление, имя вида KB1234567.
bool isHiddenEntry(Map<String, String> v, String keyName) {
  final name = (v['DisplayName'] ?? '').trim();
  if (name.isEmpty) return true;
  if ((v['SystemComponent'] ?? '').trim() == '1') return true;
  if ((v['ParentKeyName'] ?? '').trim().isNotEmpty) return true;
  final rt = (v['ReleaseType'] ?? '').toLowerCase();
  if (rt.contains('update') || rt.contains('hotfix')) return true;
  if (_kbName.hasMatch(name) || _kbName.hasMatch(keyName) || _kbInName.hasMatch(name)) {
    return true;
  }
  return false;
}

/// yyyymmdd → дата (null, если не разобралась).
DateTime? parseInstallDate(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (y < 1990 || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d);
}

/// Из сырых записей — список программ для показа. Системные скрыты,
/// повторы (одно имя + издатель в разных ветках) схлопнуты.
List<Program> buildPrograms(List<RawUninstall> raw) {
  final seen = <String>{};
  final res = <Program>[];
  for (final r in raw) {
    final v = r.values;
    if (isHiddenEntry(v, r.keyName)) continue;
    final name = v['DisplayName']!.trim();
    final publisher = (v['Publisher'] ?? '').trim();
    final key = '${name.toLowerCase()}\u0000${publisher.toLowerCase()}';
    if (!seen.add(key)) continue;
    res.add(Program(
      name: name,
      publisher: publisher,
      sizeKb: int.tryParse((v['EstimatedSize'] ?? '').trim()) ?? 0,
      installDate: parseInstallDate(v['InstallDate']),
      displayIcon: (v['DisplayIcon'] ?? '').trim(),
      installLocation: (v['InstallLocation'] ?? '').trim(),
      uninstallString: (v['UninstallString'] ?? '').trim(),
      quietUninstallString: (v['QuietUninstallString'] ?? '').trim(),
      hive: r.hive,
      keyPath: r.keyPath,
    ));
  }
  return res;
}

enum ProgramSort { size, date, name }

/// Поиск по имени и издателю (без учёта регистра) и сортировка.
/// Размер/дата — по убыванию (без значения — в конец), имя — по алфавиту.
List<Program> filterAndSort(List<Program> all, String query, ProgramSort sort) {
  final q = query.trim().toLowerCase();
  final res = q.isEmpty
      ? [...all]
      : all
          .where((p) =>
              p.name.toLowerCase().contains(q) || p.publisher.toLowerCase().contains(q))
          .toList();
  int byName(Program a, Program b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
  res.sort((a, b) {
    switch (sort) {
      case ProgramSort.size:
        final c = b.sizeKb.compareTo(a.sizeKb);
        return c != 0 ? c : byName(a, b);
      case ProgramSort.date:
        final da = a.installDate, db = b.installDate;
        if (da == null && db == null) return byName(a, b);
        if (da == null) return 1;
        if (db == null) return -1;
        final c = db.compareTo(da);
        return c != 0 ? c : byName(a, b);
      case ProgramSort.name:
        return byName(a, b);
    }
  });
  return res;
}

/// Команда запуска: программа и строка аргументов.
class UninstallCommand {
  const UninstallCommand(this.exe, this.args);
  final String exe;
  final String args;

  @override
  String toString() => '$exe $args';
}

String _expandEnv(String s, Map<String, String> env) {
  final lower = {for (final e in env.entries) e.key.toLowerCase(): e.value};
  return s.replaceAllMapped(RegExp(r'%([^%]+)%'), (m) => lower[m.group(1)!.toLowerCase()] ?? m.group(0)!);
}

/// Разбирает UninstallString на exe и аргументы. Понимает кавычки, пути с
/// пробелами без кавычек (`C:\Program Files\X\unins000.exe /SILENT`),
/// `MsiExec.exe /I{GUID}` → `/X{GUID}`. Пустая или негодная строка → null.
UninstallCommand? parseUninstallString(String raw, {Map<String, String> env = const {}}) {
  final s = _expandEnv(raw.trim(), env);
  if (s.isEmpty) return null;
  String exe;
  String args;
  if (s.startsWith('"')) {
    final end = s.indexOf('"', 1);
    if (end < 0) return null;
    exe = s.substring(1, end);
    args = s.substring(end + 1).trim();
  } else {
    final m = RegExp(r'\.(exe|msi|bat|cmd|com)(?=\s|$)', caseSensitive: false).firstMatch(s);
    if (m != null) {
      exe = s.substring(0, m.end);
      args = s.substring(m.end).trim();
    } else {
      final sp = s.indexOf(RegExp(r'\s'));
      exe = sp < 0 ? s : s.substring(0, sp);
      args = sp < 0 ? '' : s.substring(sp).trim();
    }
  }
  exe = exe.trim();
  if (exe.isEmpty || RegExp(r'[\x00-\x1f]').hasMatch(exe)) return null;

  final base = exe.split(RegExp(r'[\\/]')).last.toLowerCase();
  if (base == 'msiexec.exe' || base == 'msiexec') {
    args = args.replaceAllMapped(
      RegExp(r'/[iI]\s*(\{[0-9A-Fa-f-]+\})'),
      (m) => '/X${m.group(1)}',
    );
    if (!RegExp(r'[\\/]').hasMatch(exe)) {
      final root = env['SystemRoot'] ?? env['SYSTEMROOT'] ?? env['windir'] ?? r'C:\Windows';
      exe = '$root\\System32\\msiexec.exe';
    }
  }
  return UninstallCommand(exe, args);
}
