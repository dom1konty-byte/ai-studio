import 'package:xml/xml.dart';

/// Куда powercfg пишет отчёт и аргументы запуска (списком, без оболочки).
List<String> batteryReportArgs(String outFile) => ['/batteryreport', '/xml', '/output', outFile];

class BatteryInfo {
  const BatteryInfo({required this.design, required this.full, this.cycles});

  /// Новая ёмкость, мВт·ч.
  final int design;

  /// Ёмкость при полной зарядке сейчас, мВт·ч.
  final int full;
  final int? cycles;

  /// Износ, доли 0–1: 1 − full/design.
  double get wear => (1 - full / design).clamp(0.0, 1.0);
  int get wearPercent => (wear * 100).round();

  /// Полная ёмкость не прочиталась (0): износ считать нельзя.
  bool get noData => full <= 0;
}

int? _num(XmlElement b, String name) {
  for (final e in b.descendants.whereType<XmlElement>()) {
    if (e.name.local == name) return int.tryParse(e.innerText.trim());
  }
  return null;
}

/// Разбор XML-отчёта о батарее. null — батареи нет или данных не хватает.
BatteryInfo? parseBatteryReport(String xml) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } catch (_) {
    return null;
  }
  final batteries = doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Battery');
  var design = 0;
  var full = 0;
  int? cycles;
  for (final b in batteries) {
    final d = _num(b, 'DesignCapacity');
    final f = _num(b, 'FullChargeCapacity');
    if (d == null || f == null || d <= 0) continue;
    design += d;
    full += f;
    final c = _num(b, 'CycleCount');
    if (c != null && (cycles == null || c > cycles)) cycles = c;
  }
  if (design <= 0) return null;
  return BatteryInfo(design: design, full: full, cycles: cycles);
}
