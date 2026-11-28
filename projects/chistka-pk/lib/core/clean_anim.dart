/// Сколько «ещё можно освободить» показывать при очистке: считает вниз от
/// [total] к 0. [remaining] — доля оставшейся работы 0..1 (1 — только начали).
int countdownBytes(int total, double remaining) {
  if (total <= 0 || remaining.isNaN) return 0;
  return (total * remaining.clamp(0.0, 1.0)).round().clamp(0, total);
}
