import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/app_container.dart';
import 'package:kiosk_satellite/ui/kids/kids_arcade.dart';
import 'package:kiosk_satellite/ui/kids/kids_arcade2.dart';
import 'package:kiosk_satellite/ui/kids/kids_motion.dart';
import 'package:kiosk_satellite/ui/kids/kids_motion2.dart';
import 'package:kiosk_satellite/ui/kids/kids_play.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('steering by hand or head', () {
    test('the middle is still; a push picks the stronger way', () {
      expect(steerFrom(null), isNull);
      expect(steerFrom(const Offset(0.5, 0.5)), isNull);
      expect(steerFrom(const Offset(0.6, 0.45)), isNull);
      expect(steerFrom(const Offset(0.9, 0.6)), (1, 0));
      expect(steerFrom(const Offset(0.1, 0.4)), (-1, 0));
      expect(steerFrom(const Offset(0.55, 0.9)), (0, 1));
      expect(steerFrom(const Offset(0.45, 0.1)), (0, -1));
    });

    test('a step fires once, then again only after coming back', () {
      final t = StepTrigger();
      expect(t.update(const Offset(0.5, 0.1)), (0, -1));
      expect(t.update(const Offset(0.5, 0.1)), isNull);
      expect(t.update(const Offset(0.5, 0.2)), isNull);
      expect(t.update(const Offset(0.5, 0.36)), isNull); // not quite back
      expect(t.update(const Offset(0.5, 0.15)), isNull);
      expect(t.update(const Offset(0.5, 0.5)), isNull);
      expect(t.update(const Offset(0.9, 0.5)), (1, 0));
    });
  });

  group('Move game rules', () {
    test('wall holes stay on screen and fit a player', () {
      final rng = math.Random(3);
      for (var d = 0; d < 3; d++) {
        for (var stage = 1; stage < 40; stage++) {
          final h = wallHole(d, stage, rng);
          expect(h.left, greaterThanOrEqualTo(0));
          expect(h.top, greaterThanOrEqualTo(0));
          expect(h.right, lessThanOrEqualTo(1));
          expect(h.bottom, lessThanOrEqualTo(1));
          expect(h.width, greaterThanOrEqualTo(0.2 - 1e-9));
          expect(h.height, greaterThanOrEqualTo(0.3 - 1e-9));
          expect(fitsHole(h, h.center), isTrue);
        }
      }
      const h = Rect.fromLTWH(0.1, 0.2, 0.3, 0.4);
      expect(fitsHole(h, null), isFalse);
      expect(fitsHole(h, const Offset(0.8, 0.5)), isFalse);
    });

    test('every picture to trace has dots in the box, close together', () {
      for (final set in traceSets.entries) {
        expect(set.value, isNotEmpty);
        for (final shape in set.value) {
          for (final gap in [0.16, 0.12, 0.09]) {
            final dots = traceDots(shape, gap: gap);
            expect(dots.length, greaterThanOrEqualTo(4), reason: shape.name);
            for (final d in dots) {
              expect(d.dx, inInclusiveRange(-0.01, 1.01), reason: shape.name);
              expect(d.dy, inInclusiveRange(-0.01, 1.01), reason: shape.name);
            }
            // Within a stroke no dot is far from the last one.
            if (shape.strokes.length == 1) {
              for (var i = 1; i < dots.length; i++) {
                expect((dots[i] - dots[i - 1]).distance, lessThanOrEqualTo(gap * 1.5), reason: shape.name);
              }
            }
          }
        }
      }
    });

    test('the motion meter tells still from dancing', () {
      final m = MotionMeter();
      final rng = math.Random(1);
      for (var i = 0; i < 60; i++) {
        m.add(Offset(0.5 + rng.nextDouble() * 0.003, 0.5), 1 / 30);
      }
      expect(m.level, lessThan(0.12));
      for (var i = 0; i < 60; i++) {
        m.add(Offset(0.5 + math.sin(i / 3) * 0.2, 0.5), 1 / 30);
      }
      expect(m.level, greaterThan(0.35));
    });
  });

  group('games play by touch', () {
    late AppContainer c;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      c = AppContainer();
      await c.settings.init();
    });

    Future<void> play(WidgetTester tester, Widget game, Size size, {String? chip, bool wiggle = true}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: game)));
      await tester.pump();
      if (chip != null) {
        await tester.ensureVisible(find.text(chip));
        await tester.pump();
        await tester.tap(find.text(chip));
        await tester.pump();
      }
      await tester.ensureVisible(find.text('Start'));
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pump();
      final centre = tester.getCenter(find.byType(Scaffold));
      final g = await tester.startGesture(centre);
      for (var i = 0; i < 120; i++) {
        if (wiggle) await g.moveBy(Offset(i.isEven ? 50 : -50, i % 4 < 2 ? 20 : -20));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await g.up();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    }

    for (final size in const [Size(1280, 800), Size(800, 1280), Size(1024, 600)]) {
      testWidgets('Wall Dodge at $size', (tester) => play(tester, WallDodge(container: c, onBack: () {}), size));
      testWidgets('Air Trace at $size', (tester) => play(tester, AirTrace(container: c, onBack: () {}), size, chip: 'Letters'));
      testWidgets('Freeze Dance at $size', (tester) => play(tester, FreezeDance(container: c, onBack: () {}), size));
      testWidgets('Munch Maze by hand at $size', (tester) async {
        await play(tester, MunchMaze(container: c, onBack: () {}), size, chip: 'My hand', wiggle: false);
      });
      testWidgets('Hop Across by head at $size', (tester) => play(tester, HopAcross(container: c, onBack: () {}), size, chip: 'My head', wiggle: false));
      testWidgets('Snake by hand at $size', (tester) => play(tester, SnakeGame(container: c, onBack: () {}), size, chip: 'My hand', wiggle: false));
    }

    testWidgets('the hand panel replaces the buttons', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MunchMaze(container: c, onBack: () {}))));
      await tester.ensureVisible(find.text('My hand'));
      await tester.tap(find.text('My hand'));
      await tester.pump();
      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(find.byType(KidsMotionPanel), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('every camera game fills the screen with its play area', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final g in <Widget>[
        BubblePop(container: c, onBack: () {}),
        FruitCatcher(container: c, onBack: () {}),
        WallDodge(container: c, onBack: () {}),
        AirTrace(container: c, onBack: () {}),
        FreezeDance(container: c, onBack: () {}),
      ]) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: g)));
        await tester.ensureVisible(find.text('Start'));
        await tester.tap(find.text('Start'));
        await tester.pump(const Duration(milliseconds: 200));
        final r = tester.getRect(find.byType(KidsMotionArena));
        expect(r.width, greaterThan(1000), reason: '${g.runtimeType}');
        expect(r.height, greaterThan(500), reason: '${g.runtimeType}');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
      }
    });

    testWidgets('leaving before starting is fine', (tester) async {
      for (final g in [
        WallDodge(container: c, onBack: () {}),
        AirTrace(container: c, onBack: () {}),
        FreezeDance(container: c, onBack: () {}),
      ]) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: g)));
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      }
    });
  });
}
