import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Имя мьютекса. Совпадает с AppMutex в installer/setup.iss.
const instanceMutexName = 'ChistoDiskSingleInstance';
const mainWindowTitle = 'ЧистоДиск';

/// Класс окна Flutter runner (windows/runner/win32_window.cpp).
const mainWindowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';

const _errorAlreadyExists = 183;
const _errorAccessDenied = 5;

/// DACL: всем (WD) полный доступ — обычный и повышенный процессы видят один мьютекс.
const _sddlAllowAll = 'D:(A;;GA;;;WD)';

typedef _CreateMutexN = IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>);
typedef _CreateMutexD = int Function(Pointer<Void>, int, Pointer<Utf16>);
typedef _LastErrN = Uint32 Function();
typedef _LastErrD = int Function();
typedef _CloseN = Int32 Function(IntPtr);
typedef _CloseD = int Function(int);
typedef _ConvertSdN = Int32 Function(Pointer<Utf16>, Uint32, Pointer<Pointer<Void>>, Pointer<Uint32>);
typedef _ConvertSdD = int Function(Pointer<Utf16>, int, Pointer<Pointer<Void>>, Pointer<Uint32>);
typedef _LocalFreeN = IntPtr Function(Pointer<Void>);
typedef _LocalFreeD = int Function(Pointer<Void>);
typedef _FindWindowN = IntPtr Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _FindWindowD = int Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _ShowWindowN = Int32 Function(IntPtr, Int32);
typedef _ShowWindowD = int Function(int, int);
typedef _FgN = Int32 Function(IntPtr);
typedef _FgD = int Function(int);

final class _SecurityAttributes extends Struct {
  @Uint32()
  external int nLength;
  external Pointer<Void> lpSecurityDescriptor;
  @Int32()
  external int bInheritHandle;
}

/// Один экземпляр программы: именованный мьютекс + показ уже открытого окна.
class SingleInstance {
  static int handle = 0; // держим до конца процесса

  /// true — это первый экземпляр (мьютекс создан и удерживается).
  /// Мьютекс создаётся с DACL «всем разрешено», чтобы повышенный и обычный
  /// процессы видели один и тот же. ERROR_ACCESS_DENIED = мьютекс уже есть
  /// (создан другим уровнем прав) — считаем «уже запущено». Прочий сбой
  /// (handle == 0) — запуск не блокируем.
  static bool acquire() {
    final k = DynamicLibrary.open('kernel32.dll');
    final create = k.lookupFunction<_CreateMutexN, _CreateMutexD>('CreateMutexW');
    final lastError = k.lookupFunction<_LastErrN, _LastErrD>('GetLastError');
    final close = k.lookupFunction<_CloseN, _CloseD>('CloseHandle');
    final name = instanceMutexName.toNativeUtf16();
    Pointer<Void> sd = nullptr;
    Pointer<_SecurityAttributes> sa = nullptr;
    try {
      try {
        final a = DynamicLibrary.open('advapi32.dll');
        final convert = a.lookupFunction<_ConvertSdN, _ConvertSdD>(
            'ConvertStringSecurityDescriptorToSecurityDescriptorW');
        final sddl = _sddlAllowAll.toNativeUtf16();
        final out = calloc<Pointer<Void>>();
        try {
          if (convert(sddl, 1, out, nullptr) != 0) sd = out.value;
        } finally {
          calloc.free(sddl);
          calloc.free(out);
        }
        if (sd != nullptr) {
          sa = calloc<_SecurityAttributes>();
          sa.ref
            ..nLength = sizeOf<_SecurityAttributes>()
            ..lpSecurityDescriptor = sd
            ..bInheritHandle = 0;
        }
      } catch (_) {
        sa = nullptr; // без DACL — как раньше
      }
      final h = create(sa.cast<Void>(), 0, name);
      final err = lastError();
      if (h == 0) return err != _errorAccessDenied;
      if (err == _errorAlreadyExists) {
        close(h);
        return false;
      }
      handle = h;
      return true;
    } finally {
      calloc.free(name);
      if (sa != nullptr) calloc.free(sa);
      if (sd != nullptr) {
        DynamicLibrary.open('kernel32.dll')
            .lookupFunction<_LocalFreeN, _LocalFreeD>('LocalFree')(sd);
      }
    }
  }

  /// Отпускает мьютекс (перед запуском нового экземпляра при перезапуске с другими
  /// правами: иначе новый процесс решит, что программа уже открыта, и выйдет).
  static void release() {
    if (handle == 0) return;
    final k = DynamicLibrary.open('kernel32.dll');
    final close = k.lookupFunction<_CloseN, _CloseD>('CloseHandle');
    close(handle);
    handle = 0;
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
