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
    this.installerDigest,
  });

  /// Нормализованная версия x.y.z (по ней собирается имя файла).
  final String version;
  final Uri installerUrl;
  final Uri checksumUrl;

  /// sha256 из поля `digest` ассета GitHub (если есть), нижний регистр.
  final String? installerDigest;
}

/// Репозиторий релизов: только отсюда берём установщик.
const releaseDownloadPrefix = 'https://github.com/dom1konty-byte/ai-studio/releases/download/';

/// Установщик больше этого размера не качаем (300 МБ).
const maxInstallerBytes = 300 * 1024 * 1024;

/// Файл .sha256 больше этого размера не читаем (1 КБ).
const maxChecksumBytes = 1024;

/// Часть тега после префикса → нормализованная версия x.y.z.
/// Мусор после версии (`-beta`, `+4`, пробелы, буквы) — null: такой релиз отбрасывается.
String? normalizeReleaseVersion(String tagSuffix) {
  if (!RegExp(r'^\d{1,6}(\.\d{1,6}){0,2}$').hasMatch(tagSuffix)) return null;
  final v = parseVersion(tagSuffix);
  return v?.join('.');
}

/// Выбор самого свежего подходящего релиза из JSON GitHub API:
/// тег `chistka-pk-v…`, не draft, не prerelease, есть установщик и .sha256
/// с адресами именно этого релиза. Иначе null.
UpdateInfo? pickLatestRelease(Object? json) {
  if (json is! List) return null;
  UpdateInfo? best;
  for (final r in json) {
    if (r is! Map) continue;
    if (r['draft'] == true || r['prerelease'] == true) continue;
    final tag = r['tag_name'];
    if (tag is! String || !tag.startsWith(releaseTagPrefix)) continue;
    final tagVersion = tag.substring(releaseTagPrefix.length);
    final version = normalizeReleaseVersion(tagVersion);
    if (version == null) continue;
    final assets = r['assets'];
    if (assets is! List) continue;
    final exe = _asset(assets, installerAssetName, tagVersion);
    final sum = _asset(assets, checksumAssetName, tagVersion);
    if (exe == null || sum == null) continue;
    // digest у установщика: есть, но непонятный — релиз не берём.
    String? digest;
    final raw = exe.digest;
    if (raw != null) {
      digest = parseDigest(raw);
      if (digest == null) continue;
    }
    if (best == null || compareVersions(version, best.version) > 0) {
      best = UpdateInfo(
          version: version, installerUrl: exe.url, checksumUrl: sum.url, installerDigest: digest);
    }
  }
  return best;
}

/// «sha256:<64 hex>» → hex в нижнем регистре; иное — null.
String? parseDigest(Object? raw) {
  if (raw is! String) return null;
  final m = RegExp(r'^sha256:([0-9a-fA-F]{64})$').firstMatch(raw.trim());
  return m?.group(1)!.toLowerCase();
}

({Uri url, Object? digest})? _assetFrom(Map a, String tagVersion) {
  final s = a['browser_download_url'];
  if (s is! String) return null;
  if (!s.startsWith('$releaseDownloadPrefix$releaseTagPrefix$tagVersion/')) return null;
  final u = Uri.tryParse(s);
  if (u == null || !isSafeDownloadUrl(u) || u.host.toLowerCase() != 'github.com') return null;
  if (u.hasPort || u.userInfo.isNotEmpty || u.hasQuery || u.hasFragment) return null;
  return (url: u, digest: a['digest']);
}

({Uri url, String? digest})? _asset(List assets, String name, String tagVersion) {
  for (final a in assets) {
    if (a is Map && a['name'] == name) {
      final r = _assetFrom(a, tagVersion);
      if (r == null) return null;
      final d = r.digest;
      // digest не строка и не null — считаем непонятным (parseDigest вернёт null).
      return (url: r.url, digest: d == null ? null : (d is String ? d : ''));
    }
  }
  return null;
}

/// Скачивать можно только по https с github.com и серверов файлов GitHub.
const _safeHosts = {
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

bool isSafeDownloadUrl(Uri u) {
  if (u.scheme != 'https') return false;
  return _safeHosts.contains(u.host.toLowerCase());
}

/// Установщик Windows начинается с «MZ».
bool looksLikeExe(List<int> head) => head.length >= 2 && head[0] == 0x4D && head[1] == 0x5A;

/// Текст этапа обновления для диалога.
String updateStageText(UpdateStage stage, int received, int total) {
  switch (stage) {
    case UpdateStage.downloading:
      if (total <= 0) return 'Скачиваю…';
      return 'Скачиваю ${_mb(received)} из ${_mb(total)} МБ';
    case UpdateStage.verifying:
      return 'Проверяю файл…';
    case UpdateStage.launching:
      return 'Запускаю установщик…';
  }
}

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',');

enum UpdateStage { downloading, verifying, launching }

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
