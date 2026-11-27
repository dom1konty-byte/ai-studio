import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/programs.dart';
import 'package:chistka_pk/platform/platform_api.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:chistka_pk/ui/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_platform.dart';

AppController _controller(FakePlatform p) => AppController(
      platform: p,
      env: const Env({}),
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
      fileExists: (_) => true,
      dirExists: (_) => true,
      exitApp: () async {},
    );

Future<void> _pump(WidgetTester tester, AppController c) async {
  tester.view.physicalSize = const Size(1100, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChistoApp(controller: c));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('плашка «Режим администратора» видна при повышенных правах', (tester) async {
    final p = FakePlatform()..elevated = true;
    await _pump(tester, _controller(p));
    expect(find.text('Режим администратора'), findsOneWidget);
  });

  testWidgets('Настройки: подтверждение → UAC отменён → сообщение, переключатель выкл.', (tester) async {
    final p = FakePlatform()..relaunchResult = RelaunchResult.cancelled;
    final c = _controller(p);
    await _pump(tester, c);
    c.go(Section.settings);
    await tester.pumpAndSettle();
    expect(find.textContaining('попросит разрешение Windows'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Перезапустить с правами администратора?'), findsOneWidget);
    expect(p.relaunches, isEmpty);

    await tester.tap(find.text('Перезапустить'));
    await tester.pumpAndSettle();
    expect(p.relaunches, [true]);
    expect(find.text('Разрешение не получено'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('admin-switch'))).value, isFalse);
  });

  testWidgets('Настройки: «Отмена» в подтверждении ничего не запускает', (tester) async {
    final p = FakePlatform();
    final c = _controller(p);
    await _pump(tester, c);
    c.go(Section.settings);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(p.relaunches, isEmpty);
  });

  testWidgets('Программы: ссылка на папку, значок-заглушка и итог внизу', (tester) async {
    final p = FakePlatform()
      ..uninstallEntries = [
        const RawUninstall('HKLM', r'HKLM\X\a', {
          'DisplayName': 'Foo Editor',
          'InstallLocation': r'C:\Program Files\Foo',
          'EstimatedSize': '1024',
        }),
        const RawUninstall('HKLM', r'HKLM\X\b', {
          'DisplayName': 'Bar',
          'EstimatedSize': '2048',
        }),
      ];
    final c = _controller(p);
    await _pump(tester, c);
    c.go(Section.programs);
    await tester.pumpAndSettle();

    expect(find.text('Всего программ: 2 · 3,0 МБ'), findsOneWidget);
    expect(find.byKey(const Key('program-icon-fallback')), findsNWidgets(2));
    final link = find.byKey(const Key('install-path-link'));
    expect(link, findsOneWidget); // у Bar пути установки нет
    final text = tester.widget<Text>(find.descendant(of: link, matching: find.byType(Text)));
    expect(text.style!.decoration, TextDecoration.underline);

    await tester.tap(link);
    await tester.pump();
    expect(p.openedFolders, [r'C:\Program Files\Foo']);

    c.setProgramQuery('foo');
    await tester.pumpAndSettle();
    expect(find.text('Всего программ: 1 · 1,0 МБ'), findsOneWidget);
  });
}
