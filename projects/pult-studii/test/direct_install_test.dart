import 'package:flutter_test/flutter_test.dart';
import 'package:pult_studii/services/direct_install.dart';
import 'package:pult_studii/services/process_runner.dart';

import 'fakes.dart';

const _gitRelease = '{"assets":['
    '{"name":"PortableGit-2.50.0-64-bit.7z.exe","browser_download_url":"https://github.com/x/PortableGit-2.50.0-64-bit.7z.exe"},'
    '{"name":"Git-2.50.0-32-bit.exe","browser_download_url":"https://github.com/x/Git-2.50.0-32-bit.exe"},'
    '{"name":"Git-2.50.0-64-bit.exe","browser_download_url":"https://github.com/x/Git-2.50.0-64-bit.exe"}]}';

const _nodeIndex = '['
    '{"version":"v25.0.0","lts":false,"files":["win-x64-msi"]},'
    '{"version":"v24.1.0","lts":"Krypton","files":["linux-x64"]},'
    '{"version":"v22.5.0","lts":"Jod","files":["win-x64-msi"]},'
    '{"version":"v20.1.0","lts":"Iron","files":["win-x64-msi"]}]';

void main() {
  test('ассет Git и gh выбирается из JSON релиза', () {
    final a = pickReleaseAsset(_gitRelease, RegExp(r'^Git-.*-64-bit\.exe$'));
    expect(a!.name, 'Git-2.50.0-64-bit.exe');
    expect(pickReleaseAsset('{"assets":[]}', RegExp('x')), isNull);
    expect(pickReleaseAsset('мусор', RegExp('x')), isNull);
  });

  test('Node LTS из index.json', () {
    expect(pickNodeLts(_nodeIndex), 'v22.5.0');
    expect(pickNodeLts('[]'), isNull);
  });

  test('чужой домен и http отклоняются, в том числе после редиректа', () {
    expect(() => checkDownloadUrl(Uri.parse('https://evil.com/a.exe')),
        throwsA(isA<DownloadException>()));
    expect(() => checkDownloadUrl(Uri.parse('http://github.com/a.exe')),
        throwsA(isA<DownloadException>()));
    final from = Uri.parse('https://github.com/a/b');
    expect(nextRedirect(from, 'https://objects.githubusercontent.com/f').host,
        'objects.githubusercontent.com');
    expect(nextRedirect(from, '/other').host, 'github.com');
    expect(() => nextRedirect(from, 'https://evil.com/f'),
        throwsA(isA<DownloadException>()));
    expect(() => nextRedirect(from, 'http://github.com/f'),
        throwsA(isA<DownloadException>()));
  });

  test('проверка подписи', () {
    expect(checkSignatureJson('{"Status":0,"S":"CN=Johannes Schindelin"}', 'Johannes Schindelin'), isNull);
    expect(checkSignatureJson('{"Status":"Valid","S":"CN=GitHub, Inc."}', 'GitHub'), isNull);
    expect(checkSignatureJson('{"Status":2,"S":"CN=GitHub"}', 'GitHub'), isNotNull);
    expect(checkSignatureJson('{"Status":0,"S":"CN=Evil"}', 'GitHub'), isNotNull);
    expect(checkSignatureJson('', 'GitHub'), isNotNull);
  });

  group('DirectInstaller', () {
    late FakeDownloader dl;
    late FakeProc proc;
    late DirectInstaller inst;
    String sig = '{"Status":0,"S":"CN=Johannes Schindelin"}';

    setUp(() {
      sig = '{"Status":0,"S":"CN=Johannes Schindelin"}';
      dl = FakeDownloader()
        ..texts['https://api.github.com/repos/git-for-windows/git/releases/latest'] =
            _gitRelease
        ..texts['https://nodejs.org/dist/index.json'] = _nodeIndex;
      proc = FakeProc((exe, args, cwd) {
        if (exe == 'powershell' && args.join(' ').contains('Get-Authenticode')) {
          return ProcResult(0, sig);
        }
        return const ProcResult(0);
      });
      inst = DirectInstaller(proc: proc, downloader: dl, tempDir: '/tmp/rubka-test');
    });

    test('Git: скачали, проверили подпись, запустили с ключами', () async {
      final seen = <String>[];
      final err = await inst.install('git', (s, p) => seen.add('$s $p'));
      expect(err, isNull);
      expect(dl.downloaded, ['https://github.com/x/Git-2.50.0-64-bit.exe']);
      expect(proc.calls.last.replaceAll(r'\', '/'),
          '/tmp/rubka-test/Git-2.50.0-64-bit.exe /VERYSILENT /NORESTART /NOCANCEL /SP- /CURRENTUSER');
      expect(seen.any((s) => s.endsWith(' 50')), isTrue);
    });

    test('подпись чужая → не запускаем', () async {
      sig = '{"Status":0,"S":"CN=Evil Corp"}';
      final err = await inst.install('git', (_, __) {});
      expect(err, contains('Подпись'));
      expect(proc.calls.any((c) => c.contains('VERYSILENT')), isFalse);
    });

    test('подпись не Valid → не запускаем', () async {
      sig = '{"Status":4,"S":"CN=Johannes Schindelin"}';
      final err = await inst.install('git', (_, __) {});
      expect(err, isNotNull);
      expect(proc.calls.any((c) => c.contains('VERYSILENT')), isFalse);
    });

    test('ассет на чужом домене → отказ, ничего не скачано', () async {
      dl.texts['https://api.github.com/repos/git-for-windows/git/releases/latest'] =
          '{"assets":[{"name":"Git-1-64-bit.exe","browser_download_url":"https://evil.com/Git-1-64-bit.exe"}]}';
      final err = await inst.install('git', (_, __) {});
      expect(err, contains('официальных'));
      expect(dl.downloaded, isEmpty);
    });

    test('Node: msiexec /passive и адрес из LTS', () async {
      sig = '{"Status":0,"S":"CN=OpenJS Foundation"}';
      final err = await inst.install('node', (_, __) {});
      expect(err, isNull);
      expect(dl.downloaded, ['https://nodejs.org/dist/v22.5.0/node-v22.5.0-x64.msi']);
      expect(proc.calls.last.replaceAll(r'\', '/'),
          'msiexec /i /tmp/rubka-test/node-v22.5.0-x64.msi /passive /norestart');
    });

    test('Python: фиксированная версия и ключи', () async {
      sig = '{"Status":0,"S":"CN=Python Software Foundation"}';
      expect(await inst.install('python', (_, __) {}), isNull);
      expect(proc.calls.last, endsWith('/quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1'));
    });

    test('Claude: фиксированная строка powershell', () async {
      expect(await inst.install('claude', (_, __) {}), isNull);
      expect(proc.calls.last,
          'powershell -NoProfile -ExecutionPolicy Bypass -Command $claudeInstallPsCommand');
      expect(dl.downloaded, isEmpty);
    });

    test('ошибка скачивания → текст ошибки', () async {
      dl.failDownload = true;
      expect(await inst.install('git', (_, __) {}), contains('скачать'));
    });
  });
}
