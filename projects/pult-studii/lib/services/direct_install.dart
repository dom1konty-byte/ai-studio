import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'process_runner.dart';

/// Запасной путь установки: прямая загрузка с официальных сайтов.

/// Только эти домены (https), в том числе после переадресаций.
const allowedDownloadHosts = {
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
  'api.github.com',
  'nodejs.org',
  'www.python.org',
  'claude.ai',
  'downloads.claude.ai',
  'storage.googleapis.com',
};

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

/// Проверка адреса: https и домен из списка. Иначе DownloadException.
Uri checkDownloadUrl(Uri u) {
  if (u.scheme != 'https' || !allowedDownloadHosts.contains(u.host.toLowerCase())) {
    throw DownloadException(
        'Адрес не из списка официальных сайтов (${u.host.isEmpty ? u.scheme : u.host}) — '
        'загрузка отменена.');
  }
  return u;
}

/// Следующий адрес по заголовку Location (с проверкой домена).
Uri nextRedirect(Uri current, String location) =>
    checkDownloadUrl(current.resolve(location));

/// Скачивание: в тестах подменяется фейком.
abstract class Downloader {
  /// Текст по адресу (JSON релиза и т. п.).
  Future<String> fetchText(Uri url);

  /// Файл по адресу в [destPath]; [onProgress] — проценты 0..100
  /// (размер неизвестен — не вызывается).
  Future<void> download(Uri url, String destPath, void Function(int percent) onProgress);
}

class HttpDownloader implements Downloader {
  HttpClient _client() => HttpClient()
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..connectionTimeout = const Duration(seconds: 30)
    ..userAgent = 'Rubka-setup';

  Future<HttpClientResponse> _open(HttpClient c, Uri url) async {
    var cur = checkDownloadUrl(url);
    for (var i = 0; i < 8; i++) {
      final req = await c.getUrl(cur);
      req.followRedirects = false;
      final resp = await req.close();
      if ({301, 302, 303, 307, 308}.contains(resp.statusCode)) {
        final loc = resp.headers.value('location');
        await resp.drain<void>();
        if (loc == null) throw DownloadException('Сайт ответил непонятно.');
        cur = nextRedirect(cur, loc);
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
  Future<String> fetchText(Uri url) async {
    final c = _client();
    try {
      final resp = await _open(c, url).timeout(const Duration(seconds: 60));
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
  Future<void> download(
      Uri url, String destPath, void Function(int percent) onProgress) async {
    final c = _client();
    final file = File(destPath);
    try {
      await file.parent.create(recursive: true);
      final resp = await _open(c, url).timeout(const Duration(seconds: 60));
      final total = resp.contentLength;
      var got = 0;
      var last = -1;
      final sink = file.openWrite();
      try {
        await for (final chunk in resp.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          got += chunk.length;
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
  const ReleaseAsset(this.name, this.url);
  final String name;
  final String url;
}

/// Первый файл релиза GitHub, имя которого подходит под [pattern].
ReleaseAsset? pickReleaseAsset(String releaseJson, RegExp pattern) {
  try {
    final j = jsonDecode(releaseJson);
    for (final a in (j as Map)['assets'] as List) {
      final name = (a as Map)['name'];
      final url = a['browser_download_url'];
      if (name is String && url is String && pattern.hasMatch(name)) {
        return ReleaseAsset(name, url);
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

/// Разбор ответа Get-AuthenticodeSignature (ConvertTo-Json).
/// Вернёт null, если подпись верная и в имени владельца есть [expected];
/// иначе текст ошибки.
String? checkSignatureJson(String out, String expected) {
  const bad = 'Подпись файла не подтверждена — установка отменена.';
  try {
    final start = out.indexOf('{');
    final end = out.lastIndexOf('}');
    if (start < 0 || end < start) return bad;
    final j = jsonDecode(out.substring(start, end + 1)) as Map;
    final st = j['Status'];
    final valid = st == 0 || st == 'Valid';
    final subject = '${j['S'] ?? ''}';
    if (!valid || !subject.contains(expected)) return bad;
    return null;
  } catch (_) {
    return bad;
  }
}

typedef StatusCallback = void Function(String status, int? percent);

class _Plan {
  _Plan(this.url, this.signer, this.msi, this.args);
  final Uri url;
  final String signer;
  final bool msi;
  final List<String> args;
}

class DirectInstaller {
  DirectInstaller(
      {required this.proc, required this.downloader, required this.tempDir});

  factory DirectInstaller.real(ProcessRunner proc) => DirectInstaller(
      proc: proc,
      downloader: HttpDownloader(),
      tempDir: p.join(Directory.systemTemp.path, 'rubka-setup'));

  final ProcessRunner proc;
  final Downloader downloader;
  final String tempDir;

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
    final r = await proc.run(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          claudeInstallPsCommand,
        ],
        timeout: const Duration(minutes: 10));
    if (r.ok) return null;
    final t = '${r.stderr}${r.stdout}'.trim();
    return 'Установщик Claude не сработал'
        '${t.isEmpty ? '' : ': ${t.length > 200 ? t.substring(t.length - 200) : t}'}';
  }

  Future<String> _text(String url) => downloader.fetchText(checkDownloadUrl(Uri.parse(url)));

  Future<_Plan> _plan(String id) async {
    switch (id) {
      case 'git':
        final a = pickReleaseAsset(
            await _text('https://api.github.com/repos/git-for-windows/git/releases/latest'),
            RegExp(r'^Git-.*-64-bit\.exe$'));
        if (a == null) throw DownloadException('Не нашёл установщик Git на сайте.');
        return _Plan(checkDownloadUrl(Uri.parse(a.url)), 'Johannes Schindelin', false,
            ['/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', '/CURRENTUSER']);
      case 'gh':
        final a = pickReleaseAsset(
            await _text('https://api.github.com/repos/cli/cli/releases/latest'),
            RegExp(r'^gh_.*_windows_amd64\.msi$'));
        if (a == null) throw DownloadException('Не нашёл установщик GitHub CLI на сайте.');
        return _Plan(checkDownloadUrl(Uri.parse(a.url)), 'GitHub', true, const []);
      case 'node':
        final v = pickNodeLts(await _text('https://nodejs.org/dist/index.json'));
        if (v == null) throw DownloadException('Не нашёл версию Node.js на сайте.');
        return _Plan(Uri.parse('https://nodejs.org/dist/$v/node-$v-x64.msi'),
            'OpenJS Foundation', true, const []);
      case 'python':
        return _Plan(
            Uri.parse(
                'https://www.python.org/ftp/python/$pythonDirectVersion/python-$pythonDirectVersion-amd64.exe'),
            'Python Software Foundation',
            false,
            ['/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_launcher=1']);
    }
    throw DownloadException('Для этой программы нет прямой загрузки.');
  }

  Future<String?> _downloadAndRun(
      String id, _Plan plan, StatusCallback onStatus) async {
    checkDownloadUrl(plan.url);
    final name = plan.url.pathSegments.isEmpty ? '' : plan.url.pathSegments.last;
    final okName = RegExp(r'^[A-Za-z0-9._-]+\.(exe|msi)$').hasMatch(name);
    if (!okName) return 'Странное имя файла на сайте — загрузка отменена.';
    final path = p.join(tempDir, name);
    if (path.contains("'") || path.contains('"') || path.contains('\n')) {
      return 'В пути к временной папке есть кавычка — проверить подпись нельзя.';
    }
    try {
      await downloader.download(plan.url, path, (pct) => onStatus(_downloading, pct));
      onStatus('проверяю подпись файла', null);
      final sig = await proc.run(
          'powershell',
          [
            '-NoProfile',
            '-Command',
            "(Get-AuthenticodeSignature -LiteralPath '$path') | "
                r"Select Status,@{n='S';e={$_.SignerCertificate.Subject}} | ConvertTo-Json",
          ],
          timeout: const Duration(minutes: 2));
      final err = checkSignatureJson(sig.stdout, plan.signer);
      if (err != null) return err;
      onStatus(plan.msi ? 'устанавливаю (Windows спросит разрешение — нажми «Да»)' : 'устанавливаю', null);
      final r = plan.msi
          ? await proc.run('msiexec', ['/i', path, '/passive', '/norestart'],
              timeout: const Duration(minutes: 20))
          : await proc.run(path, plan.args, timeout: const Duration(minutes: 20));
      if (r.ok || r.exitCode == 3010 || r.exitCode == 1641) return null;
      if (r.exitCode == 1602 || r.exitCode == 1223) {
        return 'Установка отменена: Windows спросил разрешение, нужно нажать «Да».';
      }
      return 'Установщик закончил с ошибкой (код ${r.exitCode}).';
    } finally {
      _tryDelete(path);
    }
  }
}
