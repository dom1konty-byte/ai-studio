import 'package:win32/win32.dart';

import 'sleep_guard.dart';

/// Windows: SetThreadExecutionState (без оболочки и команд).
class WindowsSleepGuard implements SleepGuard {
  static const _esContinuous = 0x80000000;
  static const _esSystemRequired = 0x00000001;

  @override
  void keepAwake(bool on) {
    try {
      SetThreadExecutionState(
          on ? (_esContinuous | _esSystemRequired) : _esContinuous);
    } catch (_) {}
  }
}
