import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Накопитель времени кадров (мс) для отладки заставки.
class FrameStats {
  final _ms = <double>[];

  void add(double ms) => _ms.add(ms);

  int get count => _ms.length;
  double get max => _ms.isEmpty ? 0 : _ms.reduce((a, b) => a > b ? a : b);
  double get avg => _ms.isEmpty ? 0 : _ms.reduce((a, b) => a + b) / _ms.length;

  /// Кадры дольше 16,7 мс (не уложились в 60 к/с).
  int get slow => _ms.where((m) => m > 16.7).length;

  String summary(String label) =>
      '[$label] кадров: $count, среднее ${avg.toStringAsFixed(1)} мс, '
      'максимум ${max.toStringAsFixed(1)} мс, медленных (>16,7): $slow';
}

/// Только в debug: пишет время кадров, пока идёт [start]…[stop]. В release ничего не делает.
class FrameLog {
  FrameLog(this.label);
  final String label;
  final stats = FrameStats();
  bool _on = false;

  void start() {
    if (!kDebugMode || _on) return;
    _on = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> t) {
    for (final f in t) {
      stats.add(f.totalSpan.inMicroseconds / 1000);
      if (f.totalSpan.inMilliseconds > 16) {
        debugPrint('[$label] медленный кадр: ${f.totalSpan.inMilliseconds} мс '
            '(build ${f.buildDuration.inMilliseconds}, raster ${f.rasterDuration.inMilliseconds})');
      }
    }
  }

  void stop() {
    if (!_on) return;
    _on = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    debugPrint(stats.summary(label));
  }
}
