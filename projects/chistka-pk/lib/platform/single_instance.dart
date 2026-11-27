import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Имя мьютекса. Совпадает с AppMutex в installer/setup.iss.
const instanceMutexName = 'ChistoDiskSingleInstance';
const mainWindowTitle = 'ЧистоДиск';

typedef _OpenMutexN = IntPtr Function(Uint32, Int32, Pointer<Utf16>);
typedef _OpenMutexD = int Function(int, int, Pointer<Utf16>);
typedef _CreateMutexN = IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>);
typedef _CreateMutexD = int Function(Pointer<Void>, int, Pointer<Utf16>);
typedef _FindWindowN = IntPtr Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _FindWindowD = int Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _ShowWindowN = Int32 Function(IntPtr, Int32);
typedef _ShowWindowD = int Function(int, int);
typedef _FgN = Int32 Function(IntPtr);
typedef _FgD = int Function(int);

/// Один экземпляр программы: именованный мьютекс + показ уже открытого окна.
class SingleInstance {
  static int handle = 0; // держим до конца процесса

  /// true — это первый экземпляр (мьютекс создан и удерживается).
  static bool acquire() {
    final k = DynamicLibrary.open('kernel32.dll');
    final open = k.lookupFunction<_OpenMutexN, _OpenMutexD>('OpenMutexW');
    final create = k.lookupFunction<_CreateMutexN, _CreateMutexD>('CreateMutexW');
    final name = instanceMutexName.toNativeUtf16();
    try {
      const synchronize = 0x00100000;
      if (open(synchronize, 0, name) != 0) return false; // уже есть
      handle = create(nullptr, 0, name);
      return true;
    } finally {
      calloc.free(name);
    }
  }

  /// Показывает окно уже запущенной программы (в т.ч. спрятанное в трей).
  static void showExisting() {
    final u = DynamicLibrary.open('user32.dll');
    final find = u.lookupFunction<_FindWindowN, _FindWindowD>('FindWindowW');
    final show = u.lookupFunction<_ShowWindowN, _ShowWindowD>('ShowWindow');
    final fg = u.lookupFunction<_FgN, _FgD>('SetForegroundWindow');
    final title = mainWindowTitle.toNativeUtf16();
    try {
      final hwnd = find(nullptr, title);
      if (hwnd == 0) return;
      show(hwnd, 9); // SW_RESTORE
      fg(hwnd);
    } finally {
      calloc.free(title);
    }
  }
}
