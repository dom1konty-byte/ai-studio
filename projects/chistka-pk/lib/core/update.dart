import 'dart:convert';

/// Версия программы (совпадает с version в pubspec.yaml; проверяется тестом).
const appVersion = '1.3.0';

/// Префикс тега релиза ЧистоДиск в общем репозитории студии.
const releaseTagPrefix = 'chistka-pk-v';
const installerAssetName = 'ChistoDisk-setup.exe';
const checksumAssetName = 'ChistoDisk-setup.exe.sha256';
final releasesApiUrl =
    Uri.parse('https://api.github.com/repos/dom1konty-byte/ai-studio/releases?per_page=30');

/// Разбор «1.10.0» / «1.3.0+4» в [major, minor, patch]; мусор — null.
List<int>? parseVersion(String v) {
  final core = v.trim().split('+').first.split('-').first;
  final parts = core.split('.');
  if (parts.isEmpty || parts.length > 3) return null;
  final nums = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0) return null;
    nums.add(n);
  }
  while (nums.length < 3) {
    nums.add(0);
  }
  return nums;
}

/// Сравнение версий: <0, 0, >0. Непонятная версия считается самой старой (0.0.0).
int compareVersions(String a, String b) {
  final x = parseVersion(a) ?? const [0, 0, 0];
  final y = parseVersion(b) ?? const [0, 0, 0];
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return 0;
}

bool isNewerVersion(String candidate, String current) =>
    parseVersion(candidate) != null && compareVersions(candidate, current) > 0;

/// Найденный релиз с установщиком.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.installerUrl,
    required this.checksumUrl,
  });
  final String version;
  final Uri installerUrl;
  final Uri checksumUrl;
}

/// Выбор самого свежего подходящего релиза из JSON GitHub API:
/// тег `chistka-pk-v…`, не draft, не prerelease, есть установщик и .sha256
/// с безопасными адресами. Иначе null.
UpdateInfo? pickLatestRelease(Object? json) {
  if (json is! List) return null;
  UpdateInfo? best;
  for (final r in json) {
    if (r is! Map) continue;
    if (r['draft'] == true || r['prerelease'] == true) continue;
    final tag = r['tag_name'];
    if (tag is! String || !tag.startsWith(releaseTagPrefix)) continue;
    final version = tag.substring(releaseTagPrefix.length);
    if (parseVersion(version) == null) continue;
    final assets = r['assets'];
    if (assets is! List) continue;
    final exe = _assetUrl(assets, installerAssetName);
    final sum = _assetUrl(assets, checksumAssetName);
    if (exe == null || sum == null) continue;
    if (best == null || compareVersions(version, best.version) > 0) {
      best = UpdateInfo(version: version, installerUrl: exe, checksumUrl: sum);
    }
  }
  return best;
}

Uri? _assetUrl(List assets, String name) {
  for (final a in assets) {
    if (a is Map && a['name'] == name && a['browser_download_url'] is String) {
      final u = Uri.tryParse(a['browser_download_url'] as String);
      if (u != null && isSafeDownloadUrl(u)) return u;
    }
  }
  return null;
}

/// Скачивать можно только по https с github.com или *.githubusercontent.com.
bool isSafeDownloadUrl(Uri u) {
  if (u.scheme != 'https') return false;
  final h = u.host.toLowerCase();
  return h == 'github.com' || h.endsWith('.githubusercontent.com');
}

/// Первый sha256 (64 hex) из файла «<хеш>  имя»; нет — null. Приводится к нижнему регистру.
String? parseSha256(String text) {
  final m = RegExp(r'^\s*([0-9a-fA-F]{64})(?:\s|$)').firstMatch(text);
  return m?.group(1)!.toLowerCase();
}

/// Разбор тела ответа API (JSON-текст); ошибка разбора — null.
UpdateInfo? pickLatestFromBody(String body) {
  try {
    return pickLatestRelease(jsonDecode(body));
  } catch (_) {
    return null;
  }
}

/// Пора ли проверять: раз в сутки (нет отметки или время ушло назад — пора).
bool isUpdateCheckDue(DateTime? last, DateTime now) =>
    last == null || now.isBefore(last) || now.difference(last) >= const Duration(hours: 24);
