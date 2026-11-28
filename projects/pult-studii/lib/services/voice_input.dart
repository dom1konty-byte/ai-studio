/// Запуск голосового ввода Windows (в тестах подменяется фейком).
abstract class VoiceInput {
  /// Нажимает Win+H. true — клавиши отправлены, false — не получилось.
  Future<bool> trigger();
}

/// Пауза между фокусом в поле ввода и нажатием Win+H.
const voiceDelay = Duration(milliseconds: 150);

/// Подсказка, если Win+H не нажалось само.
const voiceFallbackText =
    'Нажми Win+H, чтобы включить голосовой ввод Windows';
