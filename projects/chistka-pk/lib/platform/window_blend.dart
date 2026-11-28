import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'single_instance.dart' show mainWindowClass, mainWindowTitle;

const _awHide = 0x00010000;
const _awActivate = 0x00020000;
const _awBlend = 0x00080000;

typedef _FindN = IntPtr Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _FindD = int Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _AnimN = Int32 Function(IntPtr, Uint32, Uint32);
typedef _AnimD = int Function(int, int, int);

/// Системная плавность Windows: AnimateWindow с AW_BLEND (user32).
/// Вызов блокирует поток на время анимации, поэтому идёт в отдельном изоляте —
/// интерфейс Flutter за это время продолжает рисовать кадры.
/// Возвращает false, если анимация недоступна (тогда нужен запасной вариант).
abstract class WindowBlend {
  Future<bool> show(int ms);
  Future<bool> hide(int ms);
}

class Win32WindowBlend implements WindowBlend {
  @override
  Future<bool> show(int ms) => _run(ms, _awActivate | _awBlend);

  @override
  Future<bool> hide(int ms) => _run(ms, _awHide | _awBlend);

  Future<bool> _run(int ms, int flags) async {
    try {
      return await Isolate.run(() => animate(ms, flags));
    } catch (_) {
      return false;
    }
  }

  /// Выполняется в изоляте; public — для проверки сигнатуры в тестах не нужен.
  static bool animate(int ms, int flags) {
    final u = DynamicLibrary.open('user32.dll');
    final find = u.lookupFunction<_FindN, _FindD>('FindWindowW');
    final anim = u.lookupFunction<_AnimN, _AnimD>('AnimateWindow');
    final cls = mainWindowClass.toNativeUtf16();
    final title = mainWindowTitle.toNativeUtf16();
    try {
      final hwnd = find(cls, title);
      if (hwnd == 0) return false;
      return anim(hwnd, ms, flags) != 0;
    } finally {
      calloc.free(cls);
      calloc.free(title);
    }
  }
}
