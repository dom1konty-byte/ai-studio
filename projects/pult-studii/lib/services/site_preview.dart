// Превью сайта: адрес из README/отчёта или локальный просмотр со своего
// компьютера (сервер только на 127.0.0.1, только файлы внутри папки сайта).
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'gh_service.dart';

/// Максимум жизни локального сервера.
const sitePreviewLifetime = Duration(minutes: 30);

final _urlRe = RegExp(r'https://[^\s<>()\[\]"' "'" r'`]+');
final _labelRe = RegExp(r'(сайт|адрес)\s*:', caseSensitive: false);
final _hostedRe = RegExp(r'(pages\.dev|workers\.dev)', caseSensitive: false);

/// Первый подходящий https-адрес сайта в текстах (README проекта, отчёт).
/// Подходят строки с pages.dev, workers.dev или с пометкой «Сайт:»/«Адрес:».
String? findSiteUrl(Iterable<String?> texts) {
  String? fallback;
  for (final text in texts) {
    if (text == null) continue;
    for (final line in text.split('\n')) {
      final hosted = _hostedRe.hasMatch(line);
      if (!hosted && !_labelRe.hasMatch(line)) continue;
      for (final m in _urlRe.allMatches(line)) {
        final url = m.group(0)!.replaceFirst(RegExp(r'[.,;:!?*_]+$'), '');
        final host = safeHttpsHost(url);
        if (host == null) continue;
        final good = host.endsWith('pages.dev') || host.endsWith('workers.dev');
        if (good) return url;
        fallback ??= url;
      }
    }
  }
  return fallback;
}

/// Адрес локального просмотра: только http://127.0.0.1:<порт>/.
bool isLocalPreviewUrl(String? href) {
  if (href == null || RegExp(r'[\s"\x27`<>^|\\\x00-\x1f\x7f]').hasMatch(href)) {
    return false;
  }
  final u = Uri.tryParse(href);
  return u != null &&
      u.scheme == 'http' &&
      u.host == '127.0.0.1' &&
      u.hasPort &&
      u.port > 0 &&
      u.userInfo.isEmpty &&
      u.path == '/' &&
      !u.hasQuery &&
      !u.hasFragment;
}

/// Где лежит собранный сайт.
class SiteRoot {
  const SiteRoot(this.path, {this.needsBuild = false});

  /// Папка с index.html (null — не нашли).
  final String? path;

  /// Есть package.json, а собранного сайта нет.
  final bool needsBuild;
}

/// Ищет папку с index.html внутри папки проекта.
Future<SiteRoot> locateSiteRoot(String projectDir) async {
  Future<bool> hasIndex(String dir) =>
      File(p.join(dir, 'index.html')).exists();
  final hasPackage = await File(p.join(projectDir, 'package.json')).exists();
  final names = hasPackage
      ? const ['dist', 'build', 'out']
      : const ['dist', 'build', 'out', 'public', 'site', ''];
  for (final n in names) {
    final dir = n.isEmpty ? projectDir : p.join(projectDir, n);
    if (await hasIndex(dir)) return SiteRoot(dir);
  }
  return SiteRoot(null, needsBuild: hasPackage);
}

const _types = {
  'html': 'text/html; charset=utf-8',
  'htm': 'text/html; charset=utf-8',
  'css': 'text/css; charset=utf-8',
  'js': 'text/javascript; charset=utf-8',
  'mjs': 'text/javascript; charset=utf-8',
  'svg': 'image/svg+xml',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'ico': 'image/x-icon',
  'json': 'application/json; charset=utf-8',
  'woff2': 'font/woff2',
  'woff': 'font/woff',
  'txt': 'text/plain; charset=utf-8',
};

/// Content-Type по расширению (неизвестное — просто байты).
String contentTypeFor(String path) {
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  return _types[ext] ?? 'application/octet-stream';
}

/// Статический сервер: 127.0.0.1, случайный порт, только GET/HEAD.
class StaticSiteServer {
  StaticSiteServer._(this._server, this.root);

  final HttpServer _server;

  /// Настоящий путь папки сайта (без симлинков).
  final String root;

  String get host => _server.address.address;
  int get port => _server.port;
  String get url => 'http://$host:$port/';

  static Future<StaticSiteServer> start(String dir) async {
    final real = await Directory(dir).resolveSymbolicLinks();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final s = StaticSiteServer._(server, real);
    server.listen(s._handle, onError: (Object _) {});
    return s;
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _fail(HttpResponse r, int code) async {
    try {
      r.statusCode = code;
      r.headers.contentType = ContentType.text;
      r.write(code == 404 ? 'Не найдено' : 'Отказ');
      await r.close();
    } catch (_) {}
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        return _fail(res, 405);
      }
      // защита от подмены адреса (DNS rebinding): только наш host:port
      final h = req.headers.host;
      if (h != '127.0.0.1' || req.headers.port != port) return _fail(res, 403);
      final file = await _resolve(req.uri.pathSegments);
      if (file == null) return _fail(res, 404);
      res.statusCode = 200;
      res.headers.set('content-type', contentTypeFor(file.path));
      res.headers.set('x-content-type-options', 'nosniff');
      res.headers.set('cache-control', 'no-store');
      res.contentLength = await file.length();
      if (req.method == 'HEAD') {
        await res.close();
        return;
      }
      await res.addStream(file.openRead());
      await res.close();
    } catch (_) {
      await _fail(res, 404);
    }
  }

  /// Файл внутри [root] или null. Без `..`, без симлинков.
  Future<File?> _resolve(List<String> segments) async {
    final parts = [...segments];
    if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
    for (final s in parts) {
      if (s.isEmpty ||
          s == '.' ||
          s == '..' ||
          RegExp(r'[\\/:\x00-\x1f]').hasMatch(s)) {
        return null;
      }
    }
    var path = p.joinAll([root, ...parts]);
    if (!p.isWithin(root, path) && !p.equals(root, path)) return null;
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.directory) {
      path = p.join(path, 'index.html');
    }
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    // настоящий путь должен совпасть с запрошенным: значит, нет симлинков
    final real = await File(path).resolveSymbolicLinks();
    if (!p.equals(real, path)) return null;
    return File(path);
  }
}

/// Один локальный просмотр за раз; гаснет через 30 минут.
class SitePreview {
  SitePreview({this.lifetime = sitePreviewLifetime});

  final Duration lifetime;
  StaticSiteServer? _server;
  Timer? _timer;

  bool get running => _server != null;

  /// Поднимает сервер для папки [dir], возвращает адрес.
  Future<String> start(String dir) async {
    await stop();
    final s = await StaticSiteServer.start(dir);
    _server = s;
    _timer = Timer(lifetime, () => unawaited(stop()));
    return s.url;
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final s = _server;
    _server = null;
    try {
      await s?.stop();
    } catch (_) {}
  }
}
