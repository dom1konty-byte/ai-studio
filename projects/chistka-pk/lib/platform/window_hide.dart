/// Мгновенное скрытие окна (без анимации): сначала остановить волны и опрос,
/// запомнить границы, затем спрятать. Любая ошибка не мешает спрятать окно.
Future<void> hideWindowNow({
  required void Function() pause,
  required Future<void> Function() saveBounds,
  required Future<void> Function() hide,
}) async {
  pause();
  try {
    await saveBounds();
  } catch (_) {}
  await hide();
}
