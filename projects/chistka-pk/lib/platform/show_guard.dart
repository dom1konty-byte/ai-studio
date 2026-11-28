import 'dart:async';

/// Страховка первого показа: если окно за [timeout] так и не показано
/// (сбой кадра/анимации) — вызывает [onTimeout] (show + opacity 1).
class ShowGuard {
  ShowGuard({required this.onTimeout, this.timeout = const Duration(milliseconds: 2500)});
  final Duration timeout;
  final FutureOr<void> Function() onTimeout;
  Timer? _timer;
  bool shown = false;

  void start() {
    _timer?.cancel();
    _timer = Timer(timeout, () {
      if (!shown) onTimeout();
    });
  }

  void markShown() {
    shown = true;
    _timer?.cancel();
  }
}
