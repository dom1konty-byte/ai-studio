import 'dart:io';

import 'package:chistka_pk/core/catalog.dart';
import 'package:chistka_pk/core/settings.dart';
import 'package:chistka_pk/platform/glass.dart';
import 'package:chistka_pk/state/app_controller.dart';
import 'package:chistka_pk/ui/app.dart';
import 'package:chistka_pk/ui/pult_tile.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_platform.dart';

AppController _make({String? dir}) => AppController(
      platform: FakePlatform(),
      env: const Env({}),
      dataDir: dir,
      downloadsScan: (_) async => [],
      largeScan: (_, __) async => [],
    );

Future<void> _pump(WidgetTester tester, AppController c) async {
  tester.view.physicalSize = const Size(1200, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChistoApp(controller: c));
  await tester.pump();
  await tester.pump();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('chisto_v14'));
  tearDown(() {
    glassAvailable.value = false;
    tmp.deleteSync(recursive: true);
  });

  group('«Прозрачная панель»', () {
    test('по умолчанию вкл., сохраняется и читается', () async {
      expect(const AppSettings().transparentPanel, isTrue);
      final c = _make(dir: tmp.path);
      await c.init();
      expect(c.settings.transparentPanel, isTrue);
      await c.setTransparentPanel(false);
      final c2 = _make(dir: tmp.path);
      await c2.init();
      expect(c2.settings.transparentPanel, isFalse);
      await c2.setTransparentPanel(true);
      final c3 = _make(dir: tmp.path);
      await c3.init();
      expect(c3.settings.transparentPanel, isTrue);
    });

    test('эффект: Windows 11 — mica, Windows 10 или прозрачность выкл. — обычный фон', () {
      expect(pickGlassEffect(build: 22631, transparencyOn: true), GlassEffect.mica);
      expect(pickGlassEffect(build: 19045, transparencyOn: true), GlassEffect.none);
      expect(pickGlassEffect(build: 22631, transparencyOn: false), GlassEffect.none);
      expect(windowsBuild('"Windows 10 Pro" 10.0 (Build 22631)'), 22631);
      expect(windowsBuild('что-то странное'), 0);
      expect(parseEnableTransparency('    EnableTransparency    REG_DWORD    0x0\r\n'), isFalse);
      expect(parseEnableTransparency('    EnableTransparency    REG_DWORD    0x1\r\n'), isTrue);
      expect(parseEnableTransparency('ошибка'), isTrue);
    });

    testWidgets('панель и фон: стекло только при включённой настройке и эффекте', (tester) async {
      final c = _make();
      await _pump(tester, c);
      expect(find.byKey(const Key('waves')), findsNothing); // эффекта нет — сплошной фон
      glassAvailable.value = true;
      await tester.pump();
      expect(find.byKey(const Key('waves')), findsOneWidget);
      await c.setTransparentPanel(false);
      await tester.pump();
      expect(find.byKey(const Key('waves')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('переключатель в Настройках', (tester) async {
      final c = _make();
      await _pump(tester, c);
      c.go(Section.settings);
      await tester.pumpAndSettle();
      expect(c.settings.transparentPanel, isTrue);
      await tester.tap(find.byKey(const Key('transparent-panel-switch')));
      await tester.pumpAndSettle();
      expect(c.settings.transparentPanel, isFalse);
    });
  });

  group('анимации', () {
    testWidgets('«Убрать анимации»: волны стоят, pumpAndSettle завершается', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      glassAvailable.value = true;
      await _pump(tester, _make());
      expect(find.byKey(const Key('waves')), findsOneWidget);
      await tester.pumpAndSettle(); // не зависает: бесконечных анимаций нет
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('со включёнными анимациями волны идут', (tester) async {
      glassAvailable.value = true;
      await _pump(tester, _make());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('плитки появляются по очереди и успокаиваются', (tester) async {
      await _pump(tester, _make());
      await tester.pump(const Duration(milliseconds: 20));
      final first = tester.widgetList<FadeTransition>(find.descendant(
          of: find.byType(TileGrid), matching: find.byType(FadeTransition)));
      expect(first.first.opacity.value, lessThan(1)); // ещё проявляется
      await tester.pumpAndSettle();
      for (final f in tester.widgetList<FadeTransition>(find.descendant(
          of: find.byType(TileGrid), matching: find.byType(FadeTransition)))) {
        expect(f.opacity.value, 1);
      }
    });

    testWidgets('наведение: плитка поднимается на 2 px, иконка растёт до 1,08', (tester) async {
      await _pump(tester, _make());
      await tester.pumpAndSettle();
      final tile = find.byType(PultTile).first;
      final icon = find.descendant(of: tile, matching: find.byType(IconCircle));
      final before = tester.getCenter(icon).dy;
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: Offset.zero);
      addTearDown(g.removePointer);
      await g.moveTo(tester.getCenter(tile));
      await tester.pumpAndSettle();
      expect(tester.getCenter(icon).dy, before - 2);
      final scale = tester.widget<AnimatedScale>(
          find.descendant(of: tile, matching: find.byType(AnimatedScale)));
      expect(scale.scale, 1.08);
      await g.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(tester.getCenter(icon).dy, before);
    });
  });

  group('плитки', () {
    testWidgets('у каждой плитки Очистки свой цвет, кружок — ровный круг', (tester) async {
      await _pump(tester, _make());
      await tester.pumpAndSettle();
      final tiles = tester.widgetList<PultTile>(find.byType(PultTile)).toList();
      expect(tiles, hasLength(5));
      final tints = tiles.map((t) => t.tint).toList();
      expect(tints.every((t) => t != null), isTrue);
      expect(tints.toSet(), hasLength(5));
      expect(tints, [
        tintDownloads.bg,
        tintBig.bg,
        tintDupes.bg,
        tintEmpty.bg,
        tintMap.bg,
      ]);
      for (final r in tester.widgetList<IconCircle>(find.byType(IconCircle))) {
        final box = find.byWidget(r);
        final s = tester.getSize(box);
        expect(s.width, s.height);
      }
    });

    testWidgets('Компьютер: диск, процессы и батарея — разные оттенки', (tester) async {
      final c = _make();
      await _pump(tester, c);
      c.go(Section.computer);
      await tester.pumpAndSettle();
      final tints = tester.widgetList<PultTile>(find.byType(PultTile)).map((t) => t.tint).toList();
      expect(tints.length, greaterThanOrEqualTo(2));
      expect(tints.every((t) => t != null), isTrue);
      expect(tints.toSet(), hasLength(tints.length));
      expect(tints.first, tintDisk.bg);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
