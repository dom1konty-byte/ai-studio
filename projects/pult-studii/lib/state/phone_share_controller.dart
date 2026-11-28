// Раздача APK на телефон: скачать, поднять сервер, ждать 15 минут, убрать.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/phone_share.dart';

enum ShareStep { downloading, serving, stopped, error }

/// Понятная причина, по которой раздача не началась.
class ShareException implements Exception {
  ShareException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PhoneShareController extends ChangeNotifier {
  PhoneShareController({
    required this.slug,
    required this.downloadTo,
    this.addresses = systemAddresses,
    this.makeTemp = makeTempDir,
    this.deleteDir = deleteTempDir,
    this.bindAddress,
    this.lifetime = const Duration(minutes: 15),
    this.tick = const Duration(seconds: 1),
  });

  final String slug;

  /// Скачать артефакты сборки в папку.
  final Future<void> Function(String dir) downloadTo;
  final Future<List<LanAddress>> Function() addresses;
  final Future<String> Function() makeTemp;
  final Future<void> Function(String dir) deleteDir;
  final InternetAddress? bindAddress;
  final Duration lifetime;
  final Duration tick;

  ShareStep step = ShareStep.downloading;
  String? error;
  List<LanAddress> ips = const [];
  LanAddress? selected;
  ApkServer? _server;
  String? _tmp;
  Timer? _timer;
  DateTime _deadline = DateTime.now();
  bool _stopped = false;
  bool _downloading = false;
  bool _disposed = false;

  /// Сколько ещё раздаём.
  Duration get remaining {
    final d = _deadline.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  /// Полный адрес для телефона (null — раздачи нет).
  String? get url {
    final s = _server;
    final ip = selected;
    if (step != ShareStep.serving || s == null || ip == null) return null;
    return s.urlFor(ip.ip);
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  bool _rebinding = false;

  /// Выбрать адрес. Сервер слушает только его, поэтому при смене адреса
  /// он перезапускается с тем же токеном и APK (порт может смениться).
  Future<void> select(LanAddress a) async {
    selected = a;
    notifyListeners();
    if (_rebinding || _stopped || bindAddress != null) return;
    _rebinding = true;
    try {
      while (!_stopped) {
        final old = _server;
        final want = selected;
        if (old == null || want == null || old.address == want.ip) break;
        _server = null;
        notifyListeners();
        await old.stop();
        if (_stopped) return;
        final ApkServer srv;
        try {
          srv = await ApkServer.start(
              apkPath: old.apkPath,
              slug: slug,
              token: old.token,
              bindAddress: InternetAddress(want.ip));
        } catch (e) {
          error = 'Не получилось сменить адрес: $e';
          await stop();
          step = ShareStep.error;
          notifyListeners();
          return;
        }
        if (_stopped) {
          await srv.stop();
          return;
        }
        _server = srv;
      }
    } finally {
      _rebinding = false;
    }
    notifyListeners();
  }

  Future<void> start() async {
    if (_stopped) return;
    step = ShareStep.downloading;
    error = null;
    notifyListeners();
    try {
      final tmp = await makeTemp();
      _tmp = tmp;
      _downloading = true;
      try {
        await downloadTo(tmp);
      } finally {
        _downloading = false;
      }
      if (_stopped) return await _cleanup();
      final apk = await findApk(tmp);
      if (apk == null) throw ShareException('В сборке нет APK-файла.');
      final found = filterLan(await addresses());
      if (found.isEmpty) {
        throw ShareException('Не нашёл адрес компьютера в домашней сети. '
            'Подключи компьютер к той же Wi-Fi, что и телефон, и повтори.');
      }
      final srv = await ApkServer.start(
          apkPath: apk,
          slug: slug,
          bindAddress: bindAddress ?? InternetAddress(found.first.ip));
      if (_stopped) {
        await srv.stop();
        return await _cleanup();
      }
      _server = srv;
      ips = found;
      selected = found.first;
      _deadline = DateTime.now().add(lifetime);
      _timer = Timer.periodic(tick, (_) => _onTick());
      step = ShareStep.serving;
    } on ShareException catch (e) {
      if (_stopped) return _cleanup();
      error = e.message;
      step = ShareStep.error;
      await _cleanup();
    } catch (e) {
      if (_stopped) return _cleanup();
      error = 'Не получилось: $e';
      step = ShareStep.error;
      await _cleanup();
    }
    notifyListeners();
  }

  void _onTick() {
    if (_stopped) return;
    if (remaining == Duration.zero) {
      unawaited(stop());
    } else {
      notifyListeners();
    }
  }

  Future<void> _cleanup() async {
    final t = _tmp;
    _tmp = null;
    if (t != null) await deleteDir(t);
  }

  /// Остановить раздачу и удалить временную папку (можно вызывать много раз).
  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    final s = _server;
    _server = null;
    try {
      await s?.stop();
    } catch (_) {}
    // Идёт скачивание — папку уберёт start, когда оно закончится.
    if (!_downloading) await _cleanup();
    step = ShareStep.stopped;
    notifyListeners();
  }
}
