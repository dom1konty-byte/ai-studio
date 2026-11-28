import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _GetCurrentProcessN = IntPtr Function();
typedef _GetCurrentProcessD = int Function();
typedef _OpenTokenN = Int32 Function(IntPtr, Uint32, Pointer<IntPtr>);
typedef _OpenTokenD = int Function(int, int, Pointer<IntPtr>);
typedef _GetTokenInfoN = Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32, Pointer<Uint32>);
typedef _GetTokenInfoD = int Function(int, int, Pointer<Void>, int, Pointer<Uint32>);
typedef _CloseN = Int32 Function(IntPtr);
typedef _CloseD = int Function(int);

const _tokenQuery = 0x0008;
const _tokenElevation = 20;

/// Запущен ли процесс с повышенными правами: токен процесса, TokenElevation.
/// Не по настройке — по факту. Ошибка → false.
bool isProcessElevated() {
  try {
    final k = DynamicLibrary.open('kernel32.dll');
    final a = DynamicLibrary.open('advapi32.dll');
    final getProc = k.lookupFunction<_GetCurrentProcessN, _GetCurrentProcessD>('GetCurrentProcess');
    final close = k.lookupFunction<_CloseN, _CloseD>('CloseHandle');
    final openToken = a.lookupFunction<_OpenTokenN, _OpenTokenD>('OpenProcessToken');
    final getInfo = a.lookupFunction<_GetTokenInfoN, _GetTokenInfoD>('GetTokenInformation');
    final token = calloc<IntPtr>();
    final info = calloc<Uint32>();
    final ret = calloc<Uint32>();
    try {
      if (openToken(getProc(), _tokenQuery, token) == 0) return false;
      try {
        final ok = getInfo(token.value, _tokenElevation, info.cast<Void>(), 4, ret);
        return ok != 0 && info.value != 0;
      } finally {
        close(token.value);
      }
    } finally {
      calloc.free(token);
      calloc.free(info);
      calloc.free(ret);
    }
  } catch (_) {
    return false;
  }
}
