import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Имя мьютекса. Совпадает с AppMutex в installer/setup.iss.
const instanceMutexName = 'ChistoDiskSingleInstance';
const mainWindowTitle = 'ЧистоДиск';

/// Класс окна Flutter runner (windows/runner/win32_window.cpp).
const mainWindowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';

const _errorAlreadyExists = 183;

typedef _CreateMutexN = IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>);
typedef _CreateMutexD = int Function(Pointer<Void>, int, Pointer<Utf16>);
typedef _LastErrN = Uint32 Function();
typedef _LastErrD = int Function();
typedef _CloseN = Int32 Function(IntPtr);
typedef _CloseD = int Function(int);
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
  /// Если мьютекс создать не удалось (handle == 0), узнать про другой экземпляр
  /// нельзя — запуск не блокируем.
  static bool acquire() {
    final k = DynamicLibrary.open('kernel32.dll');
    final create = k.lookupFunction<_CreateMutexN, _CreateMutexD>('CreateMutexW');
    final lastError = k.lookupFunction<_LastErrN, _LastErrD>('GetLastError');
    final close = k.lookupFunction<_CloseN, _CloseD>('CloseHandle');
    final name = instanceMutexName.toNativeUtf16();
    try {
      final h = create(nullptr, 0, name);
      final err = lastError();
      if (h == 0) return true;
      if (err == _errorAlreadyExists) {
        close(h);
        return false;
      }
      handle = h;
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
    final cls = mainWindowClass.toNativeUtf16();
    final title = mainWindowTitle.toNativeUtf16();
    try {
      final hwnd = find(cls, title);
      if (hwnd == 0) return;
      show(hwnd, 9); // SW_RESTORE
      fg(hwnd);
    } finally {
      calloc.free(cls);
      calloc.free(title);
    }
  }
}
