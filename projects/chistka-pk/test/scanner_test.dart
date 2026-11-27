import 'dart:io';

import 'package:chistka_pk/core/browsers.dart';
import 'package:chistka_pk/core/models.dart';
import 'package:chistka_pk/core/scanner.dart';
import 'package:chistka_pk/core/stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 27, 12);

  test('Загрузки: только старше 30 дней, по размеру', () {
    final all = [
      FileInfo(r'C:\D\new.zip', 900, now.subtract(const Duration(days: 5))),
      FileInfo(r'C:\D\edge.txt', 50, now.subtract(const Duration(days: 30))),
      FileInfo(r'C:\D\old_small.txt', 10, now.subtract(const Duration(days: 31))),
      FileInfo(r'C:\D\old_big.exe', 500, now.subtract(const Duration(days: 100))),
    ];
    final res = filterOldDownloads(all, now);
    expect(res.map((f) => f.name), ['old_big.exe', 'old_small.txt']);
    expect(isOldEnough(now.subtract(const Duration(days: 30)), now), isFalse);
    expect(isOldEnough(now.subtract(const Duration(days: 30, minutes: 1)), now), isTrue);
  });

  test('типы файлов', () {
    expect(fileKind(r'C:\D\Setup.EXE'), FileKind.installer);
    expect(fileKind(r'C:\D\a.msi'), FileKind.installer);
    expect(fileKind(r'C:\D\a.zip'), FileKind.archive);
    expect(fileKind(r'C:\D\a.rar'), FileKind.archive);
    expect(fileKind(r'C:\D\a.7z'), FileKind.archive);
    expect(fileKind(r'C:\D\a.pdf'), FileKind.other);
  });

  test('топ-N больших файлов', () {
    final all = [for (var i = 1; i <= 10; i++) FileInfo('C:\\f$i', i * 100, now)];
    final top = topLargest(all, 3);
    expect(top.map((f) => f.size), [1000, 900, 800]);
    expect(topLargest(all, 50).length, 10);
  });

  test('сканирование папки: топ и подпапки', () {
    final dir = Directory.systemTemp.createTempSync('chisto_scan');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}${Platform.pathSeparator}a.bin').writeAsBytesSync(List.filled(300, 1));
    final sub = Directory('${dir.path}${Platform.pathSeparator}sub')..createSync();
    File('${sub.path}${Platform.pathSeparator}b.bin').writeAsBytesSync(List.filled(900, 1));
    File('${sub.path}${Platform.pathSeparator}c.bin').writeAsBytesSync(List.filled(100, 1));
    final res = scanLargestSync([dir.path], 2);
    expect(res.map((f) => f.size), [900, 300]);
  });

  test('ссылки не обходятся', () {
    final dir = Directory.systemTemp.createTempSync('chisto_link');
    addTearDown(() => dir.deleteSync(recursive: true));
    final outside = Directory('${dir.path}${Platform.pathSeparator}outside')..createSync();
    File('${outside.path}${Platform.pathSeparator}secret.bin')
        .writeAsBytesSync(List.filled(5000, 1));
    final root = Directory('${dir.path}${Platform.pathSeparator}root')..createSync();
    File('${root.path}${Platform.pathSeparator}real.bin').writeAsBytesSync(List.filled(10, 1));
    try {
      Link('${root.path}${Platform.pathSeparator}lnk').createSync(outside.path);
    } catch (_) {
      return; // нет прав на создание ссылок — проверка недоступна
    }
    final res = scanLargestSync([root.path], 10);
    expect(res.map((f) => f.name), ['real.bin']);
  });

  test('статистика на временной папке', () async {
    final dir = Directory.systemTemp.createTempSync('chisto_stats');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = StatsStore(File('${dir.path}${Platform.pathSeparator}sub${Platform.pathSeparator}stats.json'));
    expect(await store.load(), 0);
    expect(await store.add(1000), 1000);
    expect(await store.add(500), 1500);
    expect(await StatsStore(store.file).load(), 1500);
    store.file.writeAsStringSync('мусор');
    expect(await store.load(), 0);
  });

  test('запущенные браузеры из tasklist', () {
    const out = '"System","4","Services","0","148 K"\r\n'
        '"chrome.exe","1234","Console","1","200 K"\r\n'
        '"chrome.exe","1235","Console","1","100 K"\r\n'
        '"msedge.exe","99","Console","1","100 K"\r\n'
        '"browser.exe","77","Console","1","100 K"\r\n';
    expect(parseRunningBrowsers(out), ['Chrome', 'Edge', 'Яндекс']);
    expect(parseRunningBrowsers(''), isEmpty);
  });
}
