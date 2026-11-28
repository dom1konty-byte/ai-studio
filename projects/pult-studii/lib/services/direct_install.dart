import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import 'process_runner.dart';

/// Запасной путь установки: прямая загрузка с официальных сайтов.

/// Правило адреса для одной загрузки: основной хост + префикс пути (только
/// https, порт 443). После переадресации разрешены [redirectHosts] (путь любой).
class DownloadRule {
  const DownloadRule(this.host, this.prefix,
      {this.redirectHosts = const {}});

  final String host;
  final String prefix;
  final Set<String> redirectHosts;
}

const _githubRedirects = {
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

const gitApiRule = DownloadRule(
    'api.github.com', '/repos/git-for-windows/git/releases/latest');
const ghApiRule =
    DownloadRule('api.github.com', '/repos/cli/cli/releases/latest');
const gitFileRule = DownloadRule(
    'github.com', '/git-for-windows/git/releases/download/',
    redirectHosts: _githubRedirects);
const ghFileRule = DownloadRule('github.com', '/cli/cli/releases/download/',
    redirectHosts: _githubRedirects);
const nodeIndexRule = DownloadRule('nodejs.org', '/dist/index.json');
const nodeFileRule = DownloadRule('nodejs.org', '/dist/v');
const pythonFileRule = DownloadRule('www.python.org', '/ftp/python/');

/// Лимит размера загрузки: 500 МБ.
const maxDownloadBytes = 500 * 1024 * 1024;

/// Версия Python для прямой загрузки (ветка 3.12).
const pythonDirectVersion = '3.12.10';

/// Фиксированная команда официального установщика Claude Code.
const claudeInstallPsCommand = 'irm https://claude.ai/install.ps1 | iex';

class DownloadException implements Exception {
  DownloadException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Проверка адреса: https, порт 443, хост и префикс пути из правила.
/// Иначе DownloadException.
Uri checkDownloadUrl(Uri u, DownloadRule rule, {bool redirect = false}) {
  final host = u.host.toLowerCase();
  final portOk = !u.hasPort || u.port == 443;
  final hostOk = host == rule.host ||
      (redirect && rule.redirectHosts.contains(host));
  final pathOk = host != rule.host || u.path.startsWith(rule.prefix);
  final plain = u.userInfo.isEmpty;
  if (u.scheme != 'https' || !portOk || !hostOk || !pathOk || !plain) {
    throw DownloadException(
        'Адрес не из списка официальных сайтов (${u.host.isEmpty ? u.scheme : u.host}) — '
        'загрузка отменена.');
  }
  return u;
}

/// Следующий адрес по заголовку Location (с проверкой правила).
Uri nextRedirect(Uri current, String location, DownloadRule rule) =>
    checkDownloadUrl(current.resolve(location), rule, redirect: true);

/// Скачивание: в тестах подменяется фейком.
abstract class Downloader {
  /// Текст по адресу (JSON релиза и т. п.).
  Future<String> fetchText(Uri url, DownloadRule rule);

  /// Файл по адресу в [destPath]; [onProgress] — проценты 0..100
  /// (размер неизвестен — не вызывается).
  Future<void> download(Uri url, String destPath, DownloadRule rule,
      void Function(int percent) onProgress);
}

class HttpDownloader implements Downloader {
  HttpClient _client() => HttpClient()
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..connectionTimeout = const Duration(seconds: 30)
    ..userAgent = 'Rubka-setup';

  Future<HttpClientResponse> _open(
      HttpClient c, Uri url, DownloadRule rule) async {
    var cur = checkDownloadUrl(url, rule);
    for (var i = 0; i < 8; i++) {
      final req = await c.getUrl(cur);
      req.followRedirects = false;
      final resp = await req.close();
      if ({301, 302, 303, 307, 308}.contains(resp.statusCode)) {
        final loc = resp.headers.value('location');
        await resp.drain<void>();
        if (loc == null) throw DownloadException('Сайт ответил непонятно.');
        cur = nextRedirect(cur, loc, rule);
        continue;
      }
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        throw DownloadException('Сайт ответил ошибкой ${resp.statusCode}.');
      }
      return resp;
    }
    throw DownloadException('Слишком много переадресаций.');
  }

  @override
  Future<String> fetchText(Uri url, DownloadRule rule) async {
    final c = _client();
    try {
      final resp = await _open(c, url, rule).timeout(const Duration(seconds: 60));
      return await resp
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(const Duration(seconds: 60));
    } on DownloadException {
      rethrow;
    } catch (e) {
      throw DownloadException('Нет связи с сайтом (проверь интернет): $e');
    } finally {
      c.close(force: true);
    }
  }

  @override
  Future<void> download(Uri url, String destPath, DownloadRule rule,
      void Function(int percent) onProgress) async {
    final c = _client();
    final file = File(destPath);
    try {
      await file.parent.create(recursive: true);
      final resp = await _open(c, url, rule).timeout(const Duration(seconds: 60));
      final total = resp.contentLength;
      if (total > maxDownloadBytes) {
        await resp.drain<void>();
        throw DownloadException('Файл слишком большой — загрузка отменена.');
      }
      var got = 0;
      var last = -1;
      final sink = file.openWrite();
      try {
        await for (final chunk in resp.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          got += chunk.length;
          if (got > maxDownloadBytes) {
            throw DownloadException('Файл слишком большой — загрузка отменена.');
          }
          if (total > 0) {
            final pct = (got * 100 ~/ total).clamp(0, 100);
            if (pct != last) {
              last = pct;
              onProgress(pct);
            }
          }
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && got != total) {
        throw DownloadException('Файл скачался не полностью.');
      }
    } on DownloadException {
      _tryDelete(destPath);
      rethrow;
    } catch (e) {
      _tryDelete(destPath);
      throw DownloadException('Не удалось скачать (проверь интернет): $e');
    } finally {
      c.close(force: true);
    }
  }
}

void _tryDelete(String path) {
  try {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}
}

class ReleaseAsset {
  const ReleaseAsset(this.name, this.url, [this.sha256]);
  final String name;
  final String url;

  /// SHA-256 из поля `digest` ("sha256:…"), если GitHub его отдал.
  final String? sha256;
}

/// Первый файл релиза GitHub, имя которого подходит под [pattern].
ReleaseAsset? pickReleaseAsset(String releaseJson, RegExp pattern) {
  try {
    final j = jsonDecode(releaseJson);
    for (final a in (j as Map)['assets'] as List) {
      final name = (a as Map)['name'];
      final url = a['browser_download_url'];
      if (name is String && url is String && pattern.hasMatch(name)) {
        final d = a['digest'];
        final m = d is String
            ? RegExp(r'^sha256:([0-9a-fA-F]{64})$').firstMatch(d)
            : null;
        return ReleaseAsset(name, url, m?.group(1)?.toLowerCase());
      }
    }
  } catch (_) {}
  return null;
}

/// Версия Node.js LTS из https://nodejs.org/dist/index.json (например `v22.11.0`).
String? pickNodeLts(String indexJson) {
  try {
    for (final e in jsonDecode(indexJson) as List) {
      final m = e as Map;
      final lts = m['lts'];
      final v = m['version'];
      if (lts == null || lts == false) continue;
      if (v is! String || !RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(v)) continue;
      final files = m['files'];
      if (files is List && !files.contains('win-x64-msi')) continue;
      return v;
    }
  } catch (_) {}
  return null;
}

/// Значение CN из строки Subject (`CN="GitHub, Inc.", O=…`) или null.
String? subjectCn(String subject) {
  final m = RegExp(r'(?:^|,\s*)CN=("(?:[^"]|"")*"|[^,]*)').firstMatch(subject);
  if (m == null) return null;
  var v = m.group(1)!.trim();
  if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
    v = v.substring(1, v.length - 1).replaceAll('""', '"');
  }
  return v;
}

/// Разбор ответа Get-AuthenticodeSignature (ConvertTo-Json).
/// Вернёт null, если подпись верная и CN владельца в точности равен
/// одному из [expectedCns]; иначе текст ошибки.
String? checkSignatureJson(String out, List<String> expectedCns) {
  const bad = 'Подпись файла не подтверждена — установка отменена.';
  try {
    final start = out.indexOf('{');
    final end = out.lastIndexOf('}');
    if (start < 0 || end < start) return bad;
    final j = jsonDecode(out.substring(start, end + 1)) as Map;
    final st = j['Status'];
    final valid = st == 0 || st == 'Valid';
    final cn = subjectCn('${j['S'] ?? ''}');
    if (!valid || cn == null || !expectedCns.contains(cn)) return bad;
    return null;
  } catch (_) {
    return bad;
  }
}

/// Хэш файла из SHASUMS256.txt (строки «<sha>  <имя>»).
String? parseShaSums(String text, String fileName) {
  for (final line in text.split('\n')) {
    final m = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(\S+)\s*$').firstMatch(line.trim());
    if (m != null && m.group(2) == fileName) return m.group(1)!.toLowerCase();
  }
  return null;
}

/// Файл, удерживаемый открытым (на Windows это мешает его подменить).
abstract class HeldFile {
  /// SHA-256 содержимого (hex, нижний регистр).
  Future<String> sha256();
  Future<void> close();
}

/// Файловые операции установки: в тестах подменяются.
abstract class InstallFs {
  /// Новая отдельная папка для одной установки.
  Future<String> createTempDir();
  Future<HeldFile> open(String path);

  /// Удалить папку установки вместе с содержимым.
  Future<void> deleteDir(String dir);
}

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) => value = data;
  @override
  void close() {}
}

class _RealHeld implements HeldFile {
  _RealHeld(this._raf);
  final RandomAccessFile _raf;

  @override
  Future<String> sha256() async {
    final out = _DigestSink();
    final conv = crypto.sha256.startChunkedConversion(out);
    await _raf.setPosition(0);
    final len = await _raf.length();
    var left = len;
    while (left > 0) {
      final chunk = await _raf.read(left < 65536 ? left : 65536);
      if (chunk.isEmpty) break;
      conv.add(chunk);
      left -= chunk.length;
    }
    conv.close();
    return out.value!.toString();
  }

  @override
  Future<void> close() => _raf.close();
}

class RealInstallFs implements InstallFs {
  @override
  Future<String> createTempDir() async =>
      (await Directory.systemTemp.createTemp('rubka-')).path;

  @override
  Future<HeldFile> open(String path) async =>
      _RealHeld(await File(path).open(mode: FileMode.read));

  @override
  Future<void> deleteDir(String dir) async {
    try {
      await Directory(dir).delete(recursive: true);
    } catch (_) {}
  }
}

typedef StatusCallback = void Function(String status, int? percent);

class _Plan {
  _Plan(this.url, this.rule, this.signers, this.msi, this.args, {this.sha256});
  final Uri url;
  final DownloadRule rule;

  /// Допустимые CN владельца подписи (точное совпадение).
  final List<String> signers;
  final bool msi;
  final List<String> args;

  /// Ожидаемый SHA-256 (null — нет источника, остаётся проверка подписи).
  final String? sha256;
}

class DirectInstaller {
  DirectInstaller({required this.proc, required this.downloader, InstallFs? fs})
      : fs = fs ?? RealInstallFs();

  factory DirectInstaller.real(ProcessRunner proc) =>
      DirectInstaller(proc: proc, downloader: HttpDownloader());

  final ProcessRunner proc;
  final Downloader downloader;
  final InstallFs fs;

  static const _downloading = 'скачиваю с официального сайта';

  /// Установить [id] (git, gh, node, python, claude). Вернёт текст ошибки или null.
  Future<String?> install(String id, StatusCallback onStatus) async {
    try {
      if (id == 'claude') return await _claude(onStatus);
      onStatus(_downloading, null);
      final plan = await _plan(id);
      return await _downloadAndRun(id, plan, onStatus);
    } on DownloadException catch (e) {
      return e.message;
    } catch (e) {
      return 'Не получилось: $e';
    }
  }

  Future<String?> _claude(StatusCallback onStatus) async {
    onStatus('устанавливаю официальным установщиком Claude', null);
    // Строка идёт в irm | iex (не файл скрипта), политика запуска скриптов
    // не мешает, поэтому -ExecutionPolicy Bypass не нужен.
    final r = await proc.run(
        powershellPath(), ['-NoProfile', '-Command', claudeInstallPsCommand],
        timeout: const Duration(minutes: 10));
    if (r.ok) return null;
    final t = '${r.stderr}${r.stdout}'.trim();
    return 'Установщик Claude не сработал'
        '${t.isEmpty ? '' : ': ${t.length > 200 ? t.substring(t.length - 200) : t}'}';
  }

  Future<String> _text(String url, DownloadRule rule) =>
      downloader.fetchText(checkDownloadUrl(Uri.parse(url), rule), rule);

  Future<_Plan> _plan(String id) async {
    switch (id) {
      case 'git':
        final a = pickReleaseAsset(
            await _text(
                'https://api.github.com/repos/git-for-windows/git/releases/latest',
                gitApiRule),
            RegExp(r'^Git-.*-64-bit\.exe$'));
        if (a == null) throw DownloadException('Не нашёл установщик Git на сайте.');
        return _Plan(checkDownloadUrl(Uri.parse(a.url), gitFileRule), gitFileRule,
            const ['Johannes Schindelin'], false,
            const ['/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', '/CURRENTUSER'],
            sha256: a.sha256);
      case 'gh':
        final a = pickReleaseAsset(
            await _text('https://api.github.com/repos/cli/cli/releases/latest',
                ghApiRule),
            RegExp(r'^gh_.*_windows_amd64\.msi$'));
        if (a == null) throw DownloadException('Не нашёл установщик GitHub CLI на сайте.');
        return _Plan(checkDownloadUrl(Uri.parse(a.url), ghFileRule), ghFileRule,
            const ['GitHub, Inc.'], true, const [],
            sha256: a.sha256);
      case 'node':
        final v = pickNodeLts(
            await _text('https://nodejs.org/dist/index.json', nodeIndexRule));
        if (v == null) throw DownloadException('Не нашёл версию Node.js на сайте.');
        final file = 'node-$v-x64.msi';
        final sums = await _text(
            'https://nodejs.org/dist/$v/SHASUMS256.txt', nodeFileRule);
        final sha = parseShaSums(sums, file);
        if (sha == null) {
          throw DownloadException(
              'Не нашёл контрольную сумму Node.js на сайте — установка отменена.');
        }
        return _Plan(
            checkDownloadUrl(
                Uri.parse('https://nodejs.org/dist/$v/$file'), nodeFileRule),
            nodeFileRule,
            const ['OpenJS Foundation'],
            true,
            const [],
            sha256: sha);
      case 'python':
        // Контрольной суммы в удобном виде нет — только проверка подписи.
        return _Plan(
            checkDownloadUrl(
                Uri.parse(
                    'https://www.python.org/ftp/python/$pythonDirectVersion/python-$pythonDirectVersion-amd64.exe'),
                pythonFileRule),
            pythonFileRule,
            const ['Python Software Foundation'],
            false,
            const ['/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_launcher=1']);
    }
    throw DownloadException('Для этой программы нет прямой загрузки.');
  }

  Future<String?> _downloadAndRun(
      String id, _Plan plan, StatusCallback onStatus) async {
    final name = plan.url.pathSegments.isEmpty ? '' : plan.url.pathSegments.last;
    final okName = RegExp(r'^[A-Za-z0-9._-]+\.(exe|msi)$').hasMatch(name);
    if (!okName) return 'Странное имя файла на сайте — загрузка отменена.';
    // Отдельная папка на каждую установку: чужой файл с таким именем не подхватится.
    final dir = await fs.createTempDir();
    final path = p.join(dir, name);
    HeldFile? held;
    try {
      if (path.contains("'") || path.contains('"') || path.contains('\n')) {
        return 'В пути к временной папке есть кавычка — проверить подпись нельзя.';
      }
      await downloader.download(
          plan.url, path, plan.rule, (pct) => onStatus(_downloading, pct));
      // Держим файл открытым до запуска установщика.
      held = await fs.open(path);
      final want = plan.sha256;
      if (want != null) {
        onStatus('проверяю контрольную сумму', null);
        final got = await held.sha256();
        if (got.toLowerCase() != want.toLowerCase()) {
          return 'Контрольная сумма файла не совпала — установка отменена.';
        }
      }
      onStatus('проверяю подпись файла', null);
      final sig = await proc.run(
          powershellPath(),
          [
            '-NoProfile',
            '-Command',
            "(Get-AuthenticodeSignature -LiteralPath '$path') | "
                r"Select Status,@{n='S';e={$_.SignerCertificate.Subject}} | ConvertTo-Json",
          ],
          timeout: const Duration(minutes: 2));
      final err = checkSignatureJson(sig.stdout, plan.signers);
      if (err != null) return err;
      onStatus(plan.msi ? 'устанавливаю (Windows спросит разрешение — нажми «Да»)' : 'устанавливаю', null);
      final r = plan.msi
          ? await proc.run(sys32('msiexec.exe'), ['/i', path, '/passive', '/norestart'],
              timeout: const Duration(minutes: 20))
          : await proc.run(path, plan.args, timeout: const Duration(minutes: 20));
      if (r.ok || r.exitCode == 3010 || r.exitCode == 1641) return null;
      if (r.exitCode == 1602 || r.exitCode == 1223) {
        return 'Установка отменена: Windows спросил разрешение, нужно нажать «Да».';
      }
      return 'Установщик закончил с ошибкой (код ${r.exitCode}).';
    } finally {
      try {
        await held?.close();
      } catch (_) {}
      await fs.deleteDir(dir);
    }
  }
}
