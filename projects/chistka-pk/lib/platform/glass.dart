import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_acrylic/flutter_acrylic.dart';

/// Системный эффект под окном.
enum GlassEffect { none, mica, acrylic }

/// Первая сборка Windows 11.
const win11Build = 22000;

const _personalizeKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize';

/// Номер сборки из `Platform.operatingSystemVersion` («… (Build 22631)»); 0 — не нашли.
int windowsBuild(String osVersion) {
  final m = RegExp(r'Build\s+(\d+)', caseSensitive: false).firstMatch(osVersion);
  return m == null ? 0 : int.parse(m.group(1)!);
}

/// Windows 11 и прозрачность включена — Mica; Windows 10 и ниже — обычный фон.
GlassEffect pickGlassEffect({required int build, required bool transparencyOn}) =>
    transparencyOn && build >= win11Build ? GlassEffect.mica : GlassEffect.none;

/// Разбор вывода `reg query … /v EnableTransparency`; не поняли — считаем, что включена.
bool parseEnableTransparency(String out) {
  final m = RegExp(r'EnableTransparency\s+REG_DWORD\s+0x([0-9a-fA-F]+)').firstMatch(out);
  return m == null ? true : int.parse(m.group(1)!, radix: 16) != 0;
}

/// Состояние «стекла»: true — эффект под окном реально включён.
/// Пока false (тесты, Windows 10, ошибка, прозрачность выключена) — сплошной фон.
final ValueNotifier<bool> glassAvailable = ValueNotifier(false);

/// Применяет эффект при запуске. Любая ошибка — обычный фон, программа работает дальше.
Future<void> initGlass({required bool dark}) async {
  glassAvailable.value = false;
  if (!Platform.isWindows) return;
  try {
    var on = true;
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final r = await Process.run(
        '$root\\System32\\reg.exe', ['query', _personalizeKey, '/v', 'EnableTransparency']);
    if (r.exitCode == 0) on = parseEnableTransparency('${r.stdout}');
    final effect =
        pickGlassEffect(build: windowsBuild(Platform.operatingSystemVersion), transparencyOn: on);
    if (effect == GlassEffect.none) return;
    await Window.initialize();
    try {
      await Window.setEffect(effect: WindowEffect.mica, dark: dark);
    } catch (_) {
      await Window.setEffect(
          effect: WindowEffect.acrylic, color: const Color(0xCCF4FAFA), dark: dark);
    }
    glassAvailable.value = true;
  } catch (_) {
    glassAvailable.value = false;
  }
}
