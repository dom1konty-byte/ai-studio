import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Верх шкалы спидометра, Мбит/с.
const speedGaugeMax = 1000.0;

/// Сколько замеров хранить в истории.
const speedHistoryLimit = 10;

/// Мбит/с по числу байт за время. Время <= 0 или мусор — 0.
double mbps(int bytes, double seconds) {
  if (bytes <= 0 || seconds.isNaN || seconds <= 0) return 0;
  return bytes * 8 / seconds / 1e6;
}

/// Медиана; пустой список — 0.
double median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Джиттер: среднее абсолютное отличие соседних замеров пинга.
double jitter(List<double> v) {
  if (v.length < 2) return 0;
  var sum = 0.0;
  for (var i = 1; i < v.length; i++) {
    sum += (v[i] - v[i - 1]).abs();
  }
  return sum / (v.length - 1);
}

/// Доля шкалы 0..1 для скорости: логарифмическая шкала 0–1000 Мбит/с.
double gaugeFraction(double v) {
  if (v.isNaN || v <= 0) return 0;
  final f = math.log(1 + v) / math.log(1 + speedGaugeMax);
  return f.clamp(0.0, 1.0).toDouble();
}

/// Результат замера.
class SpeedResult {
  const SpeedResult({
    required this.time,
    required this.pingMs,
    required this.jitterMs,
    required this.downMbps,
    required this.upMbps,
  });

  final DateTime time;
  final double pingMs;
  final double jitterMs;
  final double downMbps;
  final double upMbps;

  Map<String, Object?> toJson() => {
        'time': time.toIso8601String(),
        'ping': pingMs,
        'jitter': jitterMs,
        'down': downMbps,
        'up': upMbps,
      };

  static SpeedResult? fromJson(Object? m) {
    if (m is! Map) return null;
    final t = m['time'] is String ? DateTime.tryParse(m['time'] as String) : null;
    double n(String k) => m[k] is num ? (m[k] as num).toDouble() : 0;
    if (t == null) return null;
    return SpeedResult(
        time: t, pingMs: n('ping'), jitterMs: n('jitter'), downMbps: n('down'), upMbps: n('up'));
  }
}

/// Новая запись первой, не больше [speedHistoryLimit].
List<SpeedResult> addToHistory(List<SpeedResult> old, SpeedResult r) =>
    [r, ...old].take(speedHistoryLimit).toList();

/// История в %LOCALAPPDATA%\ChistoDisk\speed.json.
class SpeedHistoryStore {
  SpeedHistoryStore(this.file);
  final File file;

  Future<List<SpeedResult>> load() async {
    try {
      if (!file.existsSync()) return [];
      final j = jsonDecode(await file.readAsString());
      if (j is! List) return [];
      return j.map(SpeedResult.fromJson).whereType<SpeedResult>().take(speedHistoryLimit).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<SpeedResult> h) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode([for (final r in h) r.toJson()]), flush: true);
    } catch (_) {}
  }
}

enum SpeedPhase { idle, ping, download, upload, done }

/// Ошибка теста. [offline] — нет соединения, иначе «тест не удался».
class SpeedException implements Exception {
  const SpeedException({this.offline = true});
  final bool offline;
}

/// Флаг отмены кнопкой «Стоп».
class SpeedCancel {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];
  bool get isCancelled => _cancelled;

  void onCancel(void Function() f) {
    if (_cancelled) {
      f();
    } else {
      _listeners.add(f);
    }
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final f in _listeners) {
      f();
    }
    _listeners.clear();
  }
}

/// Сеть за интерфейсом: в тестах подменяется фейком.
abstract class SpeedNetwork {
  /// Один запрос пинга, мс. Ошибка сети — [SpeedException].
  Future<double> pingOnce(SpeedCancel cancel);

  /// Поток размеров приходящих кусков; закрывается по окончании или по [limit].
  Stream<int> download(Duration limit, SpeedCancel cancel);

  /// Поток размеров отправленных кусков.
  Stream<int> upload(Duration limit, SpeedCancel cancel);
}

/// Событие прогресса теста.
class SpeedEvent {
  const SpeedEvent(this.phase, {this.value = 0, this.result});
  final SpeedPhase phase;

  /// Текущее значение: мс для пинга, Мбит/с для загрузки/отдачи.
  final double value;
  final SpeedResult? result;
}

/// Прогон теста: Пинг → Загрузка → Отдача.
class SpeedTester {
  SpeedTester(this.net,
      {this.pingCount = 10,
      this.phaseDuration = const Duration(seconds: 8),
      this.tick = const Duration(milliseconds: 100)});

  final SpeedNetwork net;
  final int pingCount;
  final Duration phaseDuration;
  final Duration tick;

  /// Ошибка сети приходит ошибкой потока ([SpeedException]); при отмене
  /// поток просто закрывается без результата.
  Stream<SpeedEvent> run(SpeedCancel cancel) {
    final out = StreamController<SpeedEvent>();
    () async {
      try {
        final pings = <double>[];
        out.add(const SpeedEvent(SpeedPhase.ping));
        for (var i = 0; i < pingCount; i++) {
          if (cancel.isCancelled) return;
          pings.add(await net.pingOnce(cancel));
          out.add(SpeedEvent(SpeedPhase.ping, value: median(pings)));
        }
        if (cancel.isCancelled) return;
        final down = await _measure(SpeedPhase.download, net.download(phaseDuration, cancel), cancel, out);
        if (cancel.isCancelled) return;
        final up = await _measure(SpeedPhase.upload, net.upload(phaseDuration, cancel), cancel, out);
        if (cancel.isCancelled) return;
        out.add(SpeedEvent(
          SpeedPhase.done,
          result: SpeedResult(
            time: DateTime.now(),
            pingMs: median(pings),
            jitterMs: jitter(pings),
            downMbps: down,
            upMbps: up,
          ),
        ));
      } catch (e) {
        if (!cancel.isCancelled) {
          out.addError(e is SpeedException ? e : const SpeedException(offline: false));
        }
      } finally {
        await out.close();
      }
    }();
    return out.stream;
  }

  Future<double> _measure(
      SpeedPhase phase, Stream<int> s, SpeedCancel cancel, StreamController<SpeedEvent> out) async {
    out.add(SpeedEvent(phase));
    final sw = Stopwatch()..start();
    var bytes = 0;
    final done = Completer<void>();
    final sub = s.listen(
      (b) => bytes += b,
      onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    cancel.onCancel(() {
      if (!done.isCompleted) done.complete();
    });
    final limit = Timer(phaseDuration + const Duration(seconds: 3), () {
      if (!done.isCompleted) done.complete();
    });
    final ticker = Timer.periodic(tick, (_) {
      out.add(SpeedEvent(phase, value: mbps(bytes, sw.elapsedMicroseconds / 1e6)));
    });
    try {
      await done.future;
    } finally {
      ticker.cancel();
      limit.cancel();
      await sub.cancel();
    }
    if (bytes == 0 && !cancel.isCancelled) throw const SpeedException(offline: true);
    final v = mbps(bytes, sw.elapsedMicroseconds / 1e6);
    out.add(SpeedEvent(phase, value: v));
    return v;
  }
}

/// Настоящая сеть: speed.cloudflare.com через dart:io HttpClient, без ключей.
class CloudflareSpeedNetwork implements SpeedNetwork {
  CloudflareSpeedNetwork({this.host = 'https://speed.cloudflare.com', this.timeout = const Duration(seconds: 8)});

  /// Адрес сервера (в тестах — локальный).
  final String host;
  final Duration timeout;

  HttpClient _client(SpeedCancel cancel) {
    final c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..idleTimeout = const Duration(seconds: 5);
    cancel.onCancel(() => c.close(force: true));
    return c;
  }

  static SpeedException _wrap(Object e) => SpeedException(
      offline: e is SocketException || e is TimeoutException || e is HandshakeException || e is HttpException);

  @override
  Future<double> pingOnce(SpeedCancel cancel) async {
    // Клиент пинга — на каждый запуск (свой SpeedCancel); после «Стоп» не переиспользуется.
    if (_pingClient == null || !identical(_pingOwner, cancel)) {
      _pingClient?.close(force: true);
      final created = _client(cancel);
      _pingClient = created;
      _pingOwner = cancel;
      cancel.onCancel(() {
        if (identical(_pingClient, created)) _pingClient = null;
      });
    }
    final c = _pingClient!;
    final sw = Stopwatch()..start();
    try {
      final req = await c.getUrl(Uri.parse('$host/__down?bytes=0')).timeout(timeout);
      req.followRedirects = false;
      final resp = await req.close().timeout(timeout);
      await resp.drain<void>().timeout(timeout);
      if (resp.statusCode != 200) throw const SpeedException(offline: false);
      return sw.elapsedMicroseconds / 1000;
    } catch (e) {
      if (cancel.isCancelled) return 0;
      if (e is SpeedException) rethrow;
      throw _wrap(e);
    }
  }

  HttpClient? _pingClient;
  SpeedCancel? _pingOwner;

  @override
  Stream<int> download(Duration limit, SpeedCancel cancel) {
    _pingClient?.close(force: true);
    _pingClient = null;
    return _parallel(limit, cancel, (c, add, active) async {
      final req = await c.getUrl(Uri.parse('$host/__down?bytes=25000000')).timeout(timeout);
      req.followRedirects = false;
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) throw const SpeedException(offline: false);
      await for (final chunk in resp) {
        if (!active()) break;
        add(chunk.length);
      }
    });
  }

  @override
  Stream<int> upload(Duration limit, SpeedCancel cancel) {
    final rnd = math.Random();
    final chunk = List<int>.generate(256 * 1024, (_) => rnd.nextInt(256));
    const total = 10 * 1024 * 1024;
    return _parallel(limit, cancel, (c, add, active) async {
      final req = await c.postUrl(Uri.parse('$host/__up')).timeout(timeout);
      req.followRedirects = false;
      req.headers.contentType = ContentType.binary;
      req.contentLength = total;
      var sent = 0;
      while (sent < total && active()) {
        final n = math.min(chunk.length, total - sent);
        req.add(n == chunk.length ? chunk : chunk.sublist(0, n));
        await req.flush().timeout(timeout);
        sent += n;
        add(n);
      }
      if (sent < total) {
        req.abort();
        return;
      }
      final resp = await req.close().timeout(timeout);
      await resp.drain<void>().timeout(timeout);
    });
  }

  Stream<int> _parallel(
    Duration limit,
    SpeedCancel cancel,
    Future<void> Function(HttpClient, void Function(int), bool Function()) job, {
    int workers = 4,
  }) {
    final out = StreamController<int>();
    final client = _client(cancel);
    final sw = Stopwatch()..start();
    bool active() => !cancel.isCancelled && sw.elapsed < limit;
    // Страховка: по таймеру лимита принудительно закрываем клиент, чтобы зависшие запросы не жили.
    final guard = Timer(limit + const Duration(seconds: 2), () => client.close(force: true));
    var running = workers;
    Object? failure;
    var got = false;
    for (var i = 0; i < workers; i++) {
      () async {
        try {
          while (active()) {
            await job(client, (n) {
              got = true;
              if (!out.isClosed) out.add(n);
            }, active);
          }
        } catch (e) {
          // Ошибка после начала передачи — просто конец; до неё — ошибка теста.
          if (!cancel.isCancelled && !got) failure ??= e;
        } finally {
          if (--running == 0) {
            if (failure != null && !out.isClosed) out.addError(_wrap(failure!));
            guard.cancel();
            client.close(force: true);
            await out.close();
          }
        }
      }();
    }
    return out.stream;
  }
}

/// Важность совета: внимание или норма.
enum TipKind { warning, ok }

/// Совет по итогам замера.
class Tip {
  const Tip(this.kind, this.title, this.text);
  final TipKind kind;
  final String title;
  final String text;
}

/// Не больше двух советов, самые важные первыми.
/// [result] == null или загрузка 0 — нет соединения.
List<Tip> speedTips(SpeedResult? result, {int limit = 2}) {
  if (result == null || result.downMbps <= 0) {
    return const [Tip(TipKind.warning, 'Нет соединения', 'Проверьте кабель, Wi-Fi и роутер.')];
  }
  final tips = <Tip>[];
  if (result.pingMs > 100) {
    tips.add(const Tip(TipKind.warning, 'Высокая задержка',
        'Подключите кабель или подойдите к роутеру.'));
  }
  if (result.jitterMs > 30) {
    tips.add(const Tip(TipKind.warning, 'Связь нестабильна', 'Перезагрузите роутер.'));
  }
  if (result.downMbps < 10) {
    tips.add(const Tip(TipKind.warning, 'Низкая скорость',
        'Проверьте, не качается ли что-то, или тариф.'));
  }
  if (result.upMbps < result.downMbps * 0.2) {
    tips.add(const Tip(TipKind.warning, 'Отдача заметно ниже загрузки',
        'Это обычно для домашнего тарифа; для видеозвонков может не хватить.'));
  }
  if (tips.isEmpty && result.pingMs < 40 && result.downMbps >= 50) {
    tips.add(const Tip(TipKind.ok, 'Всё в порядке', 'Связь быстрая и стабильная.'));
  }
  return tips.take(limit).toList();
}
