// Раздача APK на телефон: поиск файла, адрес в домашней сети, мини-сервер.
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'git_service.dart';
import 'temp_cleanup.dart';

/// Ищет `*.apk` строго внутри [dir] (без симлинков). Нет — null.
Future<String?> findApk(String dir) async {
  final root = Directory(dir);
  if (!await root.exists()) return null;
  final found = <String>[];
  try {
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File || !e.path.toLowerCase().endsWith('.apk')) continue;
      if (!p.isWithin(dir, e.path)) continue;
      if (await FileSystemEntity.type(e.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      found.add(e.path);
    }
  } on FileSystemException {
    return null;
  }
  if (found.isEmpty) return null;
  found.sort();
  return found.firstWhere((f) => f.toLowerCase().contains('release'),
      orElse: () => found.first);
}

/// Адрес компьютера в сети: имя адаптера и IPv4.
class LanAddress {
  const LanAddress(this.name, this.ip);

  final String name;
  final String ip;
}

final _virtualRe = RegExp(
    r'vEthernet|VirtualBox|VMware|WSL|Hyper-V|Loopback|docker',
    caseSensitive: false);

/// 10/8, 172.16/12, 192.168/16.
bool isPrivateIPv4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final n = parts.map(int.tryParse).toList();
  if (n.any((x) => x == null || x < 0 || x > 255)) return false;
  final a = n[0]!;
  final b = n[1]!;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}

/// Частные адреса без виртуальных адаптеров (без повторов).
List<LanAddress> filterLan(List<LanAddress> all) {
  final seen = <String>{};
  return [
    for (final a in all)
      if (isPrivateIPv4(a.ip) && !_virtualRe.hasMatch(a.name) && seen.add(a.ip))
        a,
  ];
}

/// Все IPv4-адреса компьютера.
Future<List<LanAddress>> systemAddresses() async {
  final res = <LanAddress>[];
  for (final i in await NetworkInterface.list(
      type: InternetAddressType.IPv4, includeLoopback: false)) {
    for (final a in i.addresses) {
      res.add(LanAddress(i.name, a.address));
    }
  }
  return res;
}

const _tokenChars =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

/// Случайный токен из 24 символов.
String randomToken([Random? rng]) {
  final r = rng ?? Random.secure();
  return String.fromCharCodes(
      List.generate(24, (_) => _tokenChars.codeUnitAt(r.nextInt(62))));
}

/// Сколько загрузок одновременно (остальным — 503).
const maxApkConnections = 4;

/// Раздаёт один APK по адресу `/<токен>/app.apk`; всё остальное — 404.
class ApkServer {
  ApkServer._(this._server, this.token, this._apk, this.slug, this._maxActive) {
    _server.idleTimeout = const Duration(seconds: 30);
    _server.listen(_handle, onError: (Object _) {});
  }

  final HttpServer _server;
  final String token;
  final String _apk;
  final String slug;
  final int _maxActive;
  int _active = 0;

  /// Путь к раздаваемому APK.
  String get apkPath => _apk;

  /// Адрес, на котором слушает сервер.
  String get address => _server.address.address;

  /// Сколько раз APK отдан целиком.
  int served = 0;

  int get port => _server.port;

  /// [bindAddress] по умолчанию — все адреса (0.0.0.0), порт случайный.
  /// Сверх [maxConnections] одновременных загрузок отвечаем 503.
  static Future<ApkServer> start({
    required String apkPath,
    required String slug,
    InternetAddress? bindAddress,
    String? token,
    int maxConnections = maxApkConnections,
  }) async {
    if (!isSafeSlug(slug)) throw ArgumentError('slug');
    final t = token ?? randomToken();
    if (t.length < 16 || !RegExp(r'^[A-Za-z0-9]+$').hasMatch(t)) {
      throw ArgumentError('token');
    }
    final server = await HttpServer.bind(bindAddress ?? InternetAddress.anyIPv4, 0);
    return ApkServer._(server, t, apkPath, slug, maxConnections);
  }

  String pathPart() => '/$token/app.apk';

  String urlFor(String host) => 'http://$host:$port${pathPart()}';

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.method != 'GET' || req.uri.path != pathPart()) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      if (_active >= _maxActive) {
        res.statusCode = HttpStatus.serviceUnavailable;
        await res.close();
        return;
      }
      _active++;
      try {
        await _send(res);
      } finally {
        _active--;
      }
    } catch (_) {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> _send(HttpResponse res) async {
    try {
      final f = File(_apk);
      final len = await f.length();
      res.statusCode = HttpStatus.ok;
      res.headers
        ..contentType = ContentType('application', 'vnd.android.package-archive')
        ..set('Content-Disposition', 'attachment; filename=$slug.apk')
        ..set('Cache-Control', 'no-store');
      res.contentLength = len;
      await res.addStream(f.openRead());
      await res.close();
      served++;
    } catch (_) {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> stop() => _server.close(force: true);
}

/// Удаляет временную папку раздачи (только `aistudio-apk-*` внутри temp).
Future<void> deleteTempDir(String dir) async {
  try {
    if (!p.isWithin(Directory.systemTemp.path, dir) ||
        !p.basename(dir).startsWith('aistudio-apk-')) {
      return;
    }
    final d = Directory(dir);
    if (await d.exists()) await d.delete(recursive: true);
  } catch (_) {}
}

Future<String> makeTempDir() async =>
    (await Directory.systemTemp.createTemp('aistudio-apk-')).path;

/// При запуске: убрать папки `aistudio-apk-*` старше часа (остались после сбоя).
Future<void> cleanOldApkDirs({Directory? root, DateTime? now}) =>
    cleanOldTempDirs('aistudio-apk-', root: root, now: now);
