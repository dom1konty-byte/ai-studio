/// «Не давать компьютеру уснуть» (в тестах подменяется фейком).
abstract class SleepGuard {
  /// true — не давать уснуть, false — снять запрет.
  void keepAwake(bool on);
}
