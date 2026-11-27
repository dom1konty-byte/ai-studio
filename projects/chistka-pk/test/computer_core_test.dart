import 'package:chistka_pk/core/battery.dart';
import 'package:chistka_pk/core/health.dart';
import 'package:chistka_pk/core/procs.dart';
import 'package:flutter_test/flutter_test.dart';

const _ssd = '{"FriendlyName":"Samsung SSD 980","MediaType":"SSD","HealthStatus":"Healthy",'
    '"OperationalStatus":"OK","Size":512110190592,"DeviceId":"0","IsSystem":true,'
    '"Temperature":38,"Wear":4,"PowerOnHours":1234,"ReadErrorsTotal":0}';

void main() {
  group('здоровье диска: разбор JSON', () {
    test('один объект', () {
      final r = parseDiskHealth(_ssd)!;
      expect(r, hasLength(1));
      expect(r.first.mediaType, 'SSD');
      expect(r.first.state, DiskState.healthy);
      expect(r.first.temperature, 38);
      expect(r.first.wear, 4);
      expect(r.first.powerOnHours, 1234);
      expect(r.first.isSystem, isTrue);
      expect(r.first.needsAdmin, isFalse);
      expect(diskTileText(r.first), 'SSD · Исправен · 38°');
    });

    test('массив, системный диск выбирается', () {
      final hdd = '{"FriendlyName":"WD","MediaType":"HDD","HealthStatus":"Warning","Size":1000}';
      final r = parseDiskHealth('[$hdd,$_ssd]')!;
      expect(r, hasLength(2));
      expect(r.first.state, DiskState.warning);
      expect(pickSystemDisk(r)!.name, 'Samsung SSD 980');
      expect(pickSystemDisk([r.first])!.name, 'WD');
      expect(pickSystemDisk(const []), isNull);
    });

    test('Unhealthy, неизвестное состояние и тип', () {
      final r = parseDiskHealth(
          '[{"MediaType":"Unspecified","HealthStatus":"Unhealthy"},{"HealthStatus":"Strange"}]')!;
      expect(r[0].state, DiskState.unhealthy);
      expect(r[0].state.label, 'Неисправен');
      expect(r[0].mediaType, '');
      expect(r[0].name, 'Диск');
      expect(r[1].state, DiskState.warning);
      expect(diskTileText(r[0]), 'Неисправен');
    });

    test('нет температуры и износа: нужен режим администратора', () {
      final r = parseDiskHealth(
          '{"FriendlyName":"X","MediaType":"SSD","HealthStatus":"Healthy","Temperature":null,"Wear":null}')!;
      expect(r.first.needsAdmin, isTrue);
      expect(diskTileText(r.first), 'SSD · Исправен');
    });

    test('мусор, пусто, BOM', () {
      expect(parseDiskHealth(null), isNull);
      expect(parseDiskHealth('not json'), isNull);
      expect(parseDiskHealth('42'), isNull);
      expect(parseDiskHealth('   '), isEmpty);
      expect(parseDiskHealth('\uFEFF$_ssd'), hasLength(1));
    });

    test('скрипт константный и вызывается без оболочки', () {
      expect(diskHealthArgs.take(5),
          ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-Command']);
      expect(diskHealthArgs.last, diskHealthScript);
      expect(diskHealthScript, contains('[Console]::OutputEncoding'));
      expect(powershellExe(r'C:\Windows'),
          r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe');
      expect(diskHealthTimeout, const Duration(seconds: 20));
    });
  });

  group('процессы', () {
    test('ЦП процесса = дельта / (стена × ядра)', () {
      // 1 с стены, 4 ядра: 1 с процессорного времени = 25 %.
      expect(procCpuPercent(deltaCpu100ns: 10000000, deltaWallMs: 1000, cores: 4), closeTo(25, 1e-9));
      expect(procCpuPercent(deltaCpu100ns: 0, deltaWallMs: 1000, cores: 4), 0);
      expect(procCpuPercent(deltaCpu100ns: -5, deltaWallMs: 1000, cores: 4), 0);
      expect(procCpuPercent(deltaCpu100ns: 10, deltaWallMs: 0, cores: 4), 0);
      expect(procCpuPercent(deltaCpu100ns: 1 << 40, deltaWallMs: 1000, cores: 1), 100);
    });

    SysSample sample(int wall, List<RawProc> p,
            {int idle = 0, int kernel = 0, int user = 0}) =>
        SysSample(
          wallMs: wall,
          idle: idle,
          kernel: kernel,
          user: user,
          memLoadPercent: 61,
          totalPhys: 16 << 30,
          availPhys: 6 << 30,
          procs: p,
          cores: 4,
        );

    test('общая загрузка ЦП', () {
      final a = sample(0, const [], idle: 100, kernel: 200, user: 100);
      final b = sample(2000, const [], idle: 160, kernel: 300, user: 200);
      // всего 200, простой 60 -> 70 %
      expect(totalCpuPercent(a, b), closeTo(70, 1e-9));
      expect(totalCpuPercent(null, b), isNull);
      expect(totalCpuPercent(b, b), isNull);
    });

    test('группировка по имени exe, ЦП и память суммируются', () {
      final a = sample(0, const [
        RawProc(pid: 10, name: 'chrome.exe', cpuTime: 0, memory: 100),
        RawProc(pid: 11, name: 'Chrome.exe', cpuTime: 0, memory: 200),
        RawProc(pid: 20, name: 'notepad.exe', cpuTime: 0, memory: 50),
      ]);
      final b = sample(1000, const [
        RawProc(pid: 10, name: 'chrome.exe', cpuTime: 10000000, memory: 110),
        RawProc(pid: 11, name: 'Chrome.exe', cpuTime: 5000000, memory: 210),
        RawProc(pid: 20, name: 'notepad.exe', cpuTime: 0, memory: 50),
        RawProc(pid: 30, name: 'new.exe', cpuTime: 99999999, memory: 1),
      ]);
      final g = buildGroups(a, b);
      expect(g, hasLength(3));
      final chrome = g.firstWhere((x) => x.name.toLowerCase() == 'chrome.exe');
      expect(chrome.count, 2);
      expect(chrome.pids, [10, 11]);
      expect(chrome.memory, 320);
      expect(chrome.cpu, closeTo(37.5, 1e-9));
      // Новый процесс без прошлого снимка — ЦП 0.
      expect(g.firstWhere((x) => x.name == 'new.exe').cpu, 0);
      // Без прошлого снимка — все нули.
      expect(buildGroups(null, b).every((x) => x.cpu == 0), isTrue);
    });

    test('сортировка по ЦП и памяти', () {
      const g = [
        ProcGroup(name: 'a', pids: [1], cpu: 1, memory: 300, isProtected: false),
        ProcGroup(name: 'b', pids: [2], cpu: 5, memory: 100, isProtected: false),
        ProcGroup(name: 'c', pids: [3], cpu: 3, memory: 200, isProtected: false),
      ];
      expect(sortGroups(g, ProcSort.cpu).map((e) => e.name), ['b', 'c', 'a']);
      expect(sortGroups(g, ProcSort.memory).map((e) => e.name), ['a', 'c', 'b']);
      expect(sortGroups(g, ProcSort.cpu, ascending: true).map((e) => e.name), ['a', 'c', 'b']);
    });

    test('запрещённые процессы', () {
      for (final n in [
        'System', 'System Idle Process', 'Idle', 'Registry', 'smss.exe', 'csrss.exe',
        'wininit.exe', 'winlogon.exe', 'services.exe', 'lsass.exe', 'lsaiso.exe',
        'svchost.exe', 'fontdrvhost.exe', 'dwm.exe', 'explorer.exe', 'sihost.exe',
        'ctfmon.exe', 'Memory Compression', 'MsMpEng.exe', 'SecurityHealthService.exe',
        'spoolsv.exe', 'audiodg.exe', 'conhost.exe', 'RuntimeBroker.exe',
        'StartMenuExperienceHost.exe', 'ShellExperienceHost.exe', 'SearchHost.exe',
        'TextInputHost.exe', 'SVCHOST.EXE',
      ]) {
        expect(isProtectedProcess(n, 1234), isTrue, reason: n);
      }
      expect(isProtectedProcess('chrome.exe', 0), isTrue);
      expect(isProtectedProcess('chrome.exe', 4), isTrue);
      expect(isProtectedProcess('chrome.exe', 77, ownPid: 77), isTrue);
      expect(isProtectedProcess('ChistoDisk.exe', 5), isTrue);
      expect(isProtectedProcess('custom.exe', 5, ownName: 'custom.exe'), isTrue);
      expect(isProtectedProcess('chrome.exe', 1234, ownPid: 1, ownName: 'app.exe'), isFalse);
    });

    test('группа с системным или своим PID защищена', () {
      final s = sample(0, const [
        RawProc(pid: 4, name: 'System'),
        RawProc(pid: 77, name: 'other.exe'),
        RawProc(pid: 88, name: 'other.exe'),
        RawProc(pid: 99, name: 'free.exe'),
      ]);
      final g = buildGroups(null, s, ownPid: 88, ownName: 'app.exe');
      expect(g.firstWhere((x) => x.name == 'System').isProtected, isTrue);
      expect(g.firstWhere((x) => x.name == 'other.exe').isProtected, isTrue);
      expect(g.firstWhere((x) => x.name == 'free.exe').isProtected, isFalse);
    });
  });

  group('батарея: разбор XML', () {
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<BatteryReport xmlns="http://schemas.microsoft.com/battery/2012">
  <ReportInformation><ScanTime>2026-11-27T10:00:00</ScanTime></ReportInformation>
  <Batteries>
    <Battery>
      <Id>DELL ABC</Id>
      <Manufacturer>SMP</Manufacturer>
      <DesignCapacity>50000</DesignCapacity>
      <FullChargeCapacity>44000</FullChargeCapacity>
      <CycleCount>187</CycleCount>
    </Battery>
  </Batteries>
</BatteryReport>''';

    test('ёмкости, циклы, износ', () {
      final b = parseBatteryReport(xml)!;
      expect(b.design, 50000);
      expect(b.full, 44000);
      expect(b.cycles, 187);
      expect(b.wear, closeTo(0.12, 1e-9));
      expect(b.wearPercent, 12);
    });

    test('нет батареи, битый XML, нет полей', () {
      expect(
          parseBatteryReport(
              '<BatteryReport xmlns="http://schemas.microsoft.com/battery/2012"><Batteries/></BatteryReport>'),
          isNull);
      expect(parseBatteryReport('не xml'), isNull);
      expect(parseBatteryReport('<R><Battery><DesignCapacity>0</DesignCapacity></Battery></R>'),
          isNull);
    });

    test('без числа циклов; ёмкость выше проектной не даёт отрицательный износ', () {
      final b = parseBatteryReport(
          '<R><Battery><DesignCapacity>1000</DesignCapacity><FullChargeCapacity>1100</FullChargeCapacity></Battery></R>')!;
      expect(b.cycles, isNull);
      expect(b.wearPercent, 0);
    });

    test('powercfg: аргументы списком', () {
      expect(batteryReportArgs(r'C:\t\battery.xml'),
          ['/batteryreport', '/xml', '/output', r'C:\t\battery.xml']);
    });
  });
}
