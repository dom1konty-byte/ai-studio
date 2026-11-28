import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'voice_input.dart';

/// Win+H через SendInput (без оболочки и команд).
class WindowsVoiceInput implements VoiceInput {
  static const _keyH = 0x48;

  @override
  Future<bool> trigger() async {
    const steps = <(int, bool)>[
      (VK_LWIN, false),
      (_keyH, false),
      (_keyH, true),
      (VK_LWIN, true),
    ];
    final inputs = calloc<INPUT>(steps.length);
    try {
      for (var i = 0; i < steps.length; i++) {
        final item = inputs[i];
        item.type = INPUT_KEYBOARD;
        item.ki.wVk = steps[i].$1;
        item.ki.dwFlags = steps[i].$2 ? KEYEVENTF_KEYUP : 0;
      }
      final sent = SendInput(steps.length, inputs, sizeOf<INPUT>());
      return sent == steps.length;
    } catch (_) {
      return false;
    } finally {
      calloc.free(inputs);
    }
  }
}
