import 'package:flutter_test/flutter_test.dart';
import 'package:pult_studii/services/direct_install.dart';
import 'package:pult_studii/services/process_runner.dart';

import 'fakes.dart';

const _gitBase = 'https://github.com/git-for-windows/git/releases/download/v2.50.0/';
const _gitRelease = '{"assets":['
    '{"name":"PortableGit-2.50.0-64-bit.7z.exe","browser_download_url":"${_gitBase}PortableGit-2.50.0-64-bit.7z.exe"},'
    '{"name":"Git-2.50.0-32-bit.exe","browser_download_url":"${_gitBase}Git-2.50.0-32-bit.exe"},'
    '{"name":"Git-2.50.0-64-bit.exe","browser_download_url":"${_gitBase}Git-2.50.0-64-bit.exe"}]}';
const _gitApi = 'https://api.github.com/repos/git-for-windows/git/releases/latest';
const _sha = FakeInstallFs.okHash;
const _shaSums = '$_sha  node-v22.5.0-x64.msi\n'
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  node-v22.5.0-x64.zip\n';

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

  test('чужой домен, http, порт и чужой путь отклоняются', () {
    bool bad(String url, DownloadRule r) {
      try {
        checkDownloadUrl(Uri.parse(url), r);
        return false;
      } on DownloadException {
        return true;
      }
    }

    expect(bad('https://evil.com/a.exe', gitFileRule), isTrue);
    expect(bad('http://github.com/git-for-windows/git/releases/download/a.exe', gitFileRule), isTrue);
    expect(bad('https://github.com:8443/git-for-windows/git/releases/download/a.exe', gitFileRule), isTrue);
    expect(bad('https://github.com:443/git-for-windows/git/releases/download/a.exe', gitFileRule), isFalse);
    // A3: у каждой программы свой префикс пути
    expect(bad('https://github.com/cli/cli/releases/download/v1/a.msi', gitFileRule), isTrue);
    expect(bad('https://github.com/git-for-windows/git/releases/download/v1/a.exe', ghFileRule), isTrue);
    expect(bad('https://github.com/cli/cli/releases/download/v1/a.msi', ghFileRule), isFalse);
    expect(bad('https://nodejs.org/dist/v22.5.0/node-v22.5.0-x64.msi', nodeFileRule), isFalse);
    expect(bad('https://nodejs.org/download/a.msi', nodeFileRule), isTrue);
    expect(bad('https://www.python.org/ftp/python/3.12.10/p.exe', pythonFileRule), isFalse);
    expect(bad('https://www.python.org/other/p.exe', pythonFileRule), isTrue);
    expect(bad('https://storage.googleapis.com/x/p.exe', pythonFileRule), isTrue);
    // хост-редирект сам по себе не годится как первый адрес
    expect(bad('https://objects.githubusercontent.com/f', gitFileRule), isTrue);

    final from = Uri.parse('https://github.com/git-for-windows/git/releases/download/a');
    expect(nextRedirect(from, 'https://objects.githubusercontent.com/f', gitFileRule).host,
        'objects.githubusercontent.com');
    expect(nextRedirect(from, 'https://release-assets.githubusercontent.com/f', gitFileRule).host,
        'release-assets.githubusercontent.com');
    expect(() => nextRedirect(from, 'https://evil.com/f', gitFileRule),
        throwsA(isA<DownloadException>()));
    expect(() => nextRedirect(from, 'http://github.com/f', gitFileRule),
        throwsA(isA<DownloadException>()));
    expect(() => nextRedirect(from, '/cli/cli/releases/download/x', gitFileRule),
        throwsA(isA<DownloadException>()));
    expect(() => nextRedirect(from, 'https://objects.githubusercontent.com:444/f', gitFileRule),
        throwsA(isA<DownloadException>()));
  });

  test('проверка подписи: CN сравнивается точно', () {
    expect(checkSignatureJson('{"Status":0,"S":"CN=Johannes Schindelin, O=X"}', ['Johannes Schindelin']), isNull);
    expect(checkSignatureJson(r'{"Status":"Valid","S":"CN=\"GitHub, Inc.\", O=\"GitHub, Inc.\", L=SF"}', ['GitHub, Inc.']), isNull);
    expect(checkSignatureJson('{"Status":2,"S":"CN=GitHub"}', ['GitHub']), isNotNull);
    expect(checkSignatureJson('{"Status":0,"S":"CN=Evil"}', ['GitHub, Inc.']), isNotNull);
    expect(checkSignatureJson('', ['GitHub, Inc.']), isNotNull);
    // подстрока в чужом имени не проходит
    expect(checkSignatureJson('{"Status":0,"S":"CN=Not Johannes Schindelin Fake"}', ['Johannes Schindelin']), isNotNull);
    expect(checkSignatureJson('{"Status":0,"S":"CN=Evil, O=Johannes Schindelin"}', ['Johannes Schindelin']), isNotNull);
    expect(checkSignatureJson('{"Status":0,"S":"CN=GitHub"}', ['GitHub, Inc.']), isNotNull);
    expect(subjectCn(r'O=X, CN="A, B", L=Y'), 'A, B');
    expect(subjectCn('CN=Plain'), 'Plain');
    expect(subjectCn('O=X'), isNull);
  });

  test('SHASUMS256 и digest ассета', () {
    expect(parseShaSums(_shaSums, 'node-v22.5.0-x64.msi'), _sha);
    expect(parseShaSums(_shaSums, 'нет.msi'), isNull);
    final a = pickReleaseAsset(
        '{"assets":[{"name":"gh_1_windows_amd64.msi","browser_download_url":"u","digest":"sha256:$_sha"}]}',
        RegExp(r'^gh_'));
    expect(a!.sha256, _sha);
    expect(pickReleaseAsset('{"assets":[{"name":"gh_1","browser_download_url":"u","digest":"md5:1"}]}', RegExp('gh_'))!.sha256, isNull);
  });

  group('DirectInstaller', () {
    late FakeDownloader dl;
    late FakeProc proc;
    late FakeInstallFs fs;
    late DirectInstaller inst;
    String sig = '{"Status":0,"S":"CN=Johannes Schindelin"}';

    setUp(() {
      sig = '{"Status":0,"S":"CN=Johannes Schindelin"}';
      dl = FakeDownloader()
        ..texts[_gitApi] = _gitRelease
        ..texts['https://nodejs.org/dist/index.json'] = _nodeIndex
        ..texts['https://nodejs.org/dist/v22.5.0/SHASUMS256.txt'] = _shaSums;
      fs = FakeInstallFs();
      proc = FakeProc((exe, args, cwd) {
        if (exe == powershellPath() && args.join(' ').contains('Get-Authenticode')) {
          return ProcResult(0, sig);
        }
        return const ProcResult(0);
      });
      inst = DirectInstaller(proc: proc, downloader: dl, fs: fs);
    });

    test('Git: скачали, проверили подпись, запустили с ключами', () async {
      final seen = <String>[];
      final err = await inst.install('git', (s, p) => seen.add('$s $p'));
      expect(err, isNull);
      expect(dl.downloaded, ['${_gitBase}Git-2.50.0-64-bit.exe']);
      expect(proc.calls.last.replaceAll(r'\', '/'),
          '/tmp/rubka-test/rubka-0/Git-2.50.0-64-bit.exe /VERYSILENT /NORESTART /NOCANCEL /SP- /CURRENTUSER');
      expect(seen.any((s) => s.endsWith(' 50')), isTrue);
      // файл держали открытым до конца, папка установки удалена
      expect(fs.opened, hasLength(1));
      expect(fs.closed, fs.opened);
      expect(fs.deletedDirs, fs.createdDirs);
    });

    test('каждая установка — своя папка', () async {
      await inst.install('git', (_, __) {});
      await inst.install('git', (_, __) {});
      expect(fs.createdDirs.toSet(), hasLength(2));
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

    test('A1: GitHub digest не совпал → не проверяем подпись и не запускаем',
        () async {
      dl.texts[_gitApi] = _gitRelease.replaceFirst(
          '"name":"Git-2.50.0-64-bit.exe",',
          '"name":"Git-2.50.0-64-bit.exe","digest":"sha256:${'c' * 64}",');
      final err = await inst.install('git', (_, __) {});
      expect(err, contains('Контрольная сумма'));
      expect(proc.calls.any((c) => c.contains('VERYSILENT')), isFalse);
      expect(proc.calls.any((c) => c.contains('Get-Authenticode')), isFalse);
      expect(fs.closed, fs.opened);
      expect(fs.deletedDirs, fs.createdDirs);
    });

    test('A1: GitHub digest совпал → ставим', () async {
      dl.texts[_gitApi] = _gitRelease.replaceFirst(
          '"name":"Git-2.50.0-64-bit.exe",',
          '"name":"Git-2.50.0-64-bit.exe","digest":"sha256:$_sha",');
      expect(await inst.install('git', (_, __) {}), isNull);
      expect(proc.calls.any((c) => c.contains('VERYSILENT')), isTrue);
    });

    test('ассет на чужом домене → отказ, ничего не скачано', () async {
      dl.texts[_gitApi] =
          '{"assets":[{"name":"Git-1-64-bit.exe","browser_download_url":"https://evil.com/Git-1-64-bit.exe"}]}';
      final err = await inst.install('git', (_, __) {});
      expect(err, contains('официальных'));
      expect(dl.downloaded, isEmpty);
    });

    test('ассет Git из чужого репозитория на github.com → отказ', () async {
      dl.texts[_gitApi] =
          '{"assets":[{"name":"Git-1-64-bit.exe","browser_download_url":"https://github.com/evil/x/releases/download/v/Git-1-64-bit.exe"}]}';
      final err = await inst.install('git', (_, __) {});
      expect(err, contains('официальных'));
      expect(dl.downloaded, isEmpty);
    });

    test('Node: msiexec /passive, адрес из LTS, сумма из SHASUMS256.txt', () async {
      sig = '{"Status":0,"S":"CN=OpenJS Foundation"}';
      final err = await inst.install('node', (_, __) {});
      expect(err, isNull);
      expect(dl.downloaded, ['https://nodejs.org/dist/v22.5.0/node-v22.5.0-x64.msi']);
      expect(proc.calls.last.replaceAll(r'\', '/'),
          '${sys32('msiexec.exe')} /i /tmp/rubka-test/rubka-0/node-v22.5.0-x64.msi /passive /norestart'
              .replaceAll(r'\', '/'));
    });

    test('A1: Node — сумма не совпала → не запускаем', () async {
      sig = '{"Status":0,"S":"CN=OpenJS Foundation"}';
      fs.defaultHash = 'd' * 64;
      final err = await inst.install('node', (_, __) {});
      expect(err, contains('Контрольная сумма'));
      expect(proc.calls.any((c) => c.contains('msiexec')), isFalse);
    });

    test('Node: нет SHASUMS256.txt → отказ', () async {
      dl.texts.remove('https://nodejs.org/dist/v22.5.0/SHASUMS256.txt');
      expect(await inst.install('node', (_, __) {}), isNotNull);
      expect(dl.downloaded, isEmpty);
    });

    test('Python: фиксированная версия и ключи, без проверки суммы', () async {
      sig = '{"Status":0,"S":"CN=Python Software Foundation"}';
      fs.defaultHash = 'e' * 64;
      expect(await inst.install('python', (_, __) {}), isNull);
      expect(proc.calls.last, endsWith('/quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1'));
    });

    test('Claude: фиксированная строка powershell без ExecutionPolicy', () async {
      expect(await inst.install('claude', (_, __) {}), isNull);
      expect(proc.calls.last,
          '${powershellPath()} -NoProfile -Command $claudeInstallPsCommand');
      expect(dl.downloaded, isEmpty);
    });

    test('ошибка скачивания → текст ошибки', () async {
      dl.failDownload = true;
      expect(await inst.install('git', (_, __) {}), contains('скачать'));
    });
  });
}
