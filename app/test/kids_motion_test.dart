import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/app_container.dart';
import 'package:kiosk_satellite/ui/kids/kids_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Finger Math answers fit on one hand and add up', () {
    final rng = math.Random(4);
    for (final level in [0, 1, 2]) {
      for (var i = 0; i < 500; i++) {
        final q = fingerMathQuestion(level, rng);
        expect(q.a, inInclusiveRange(0, 5));
        final m = RegExp(r'^(\d+) ([+−]) (\d+)$').firstMatch(q.q)!;
        final x = int.parse(m.group(1)!), y = int.parse(m.group(3)!);
        expect(m.group(2) == '+' ? x + y : x - y, q.a, reason: q.q);
        if (level == 0) expect(m.group(2), '+');
        if (level == 1) expect(m.group(2), '−');
      }
    }
  });

  group('camera games play by touch', () {
    late AppContainer c;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      c = AppContainer();
      await c.settings.init();
    });

    Future<void> play(WidgetTester tester, Widget game, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final old = FlutterError.onError;
      FlutterError.onError = (d) {
        debugPrint('FULLERR ${d.toString().split('\n').where((l) => l.contains('kids_') || l.contains('Row') || l.contains('creator')).take(12).join(' | ')}');
        old?.call(d);
      };
      addTearDown(() => FlutterError.onError = old);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: game)));
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pump();
      // Steer by touch across the play area for a few seconds.
      final centre = tester.getCenter(find.byType(Scaffold));
      final gesture = await tester.startGesture(centre);
      for (var i = 0; i < 40; i++) {
        await gesture.moveBy(Offset(i.isEven ? 40 : -40, 0));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      final err = tester.takeException();
      if (err != null) debugPrint('ERRDETAIL $err');
      expect(err, isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    }

    for (final size in const [Size(1280, 800), Size(800, 1280)]) {
      testWidgets('Bubble Pop at $size', (tester) => play(tester, BubblePop(container: c, onBack: () {}), size));
      testWidgets('Space Blaster at $size', (tester) => play(tester, SpaceBlaster(container: c, onBack: () {}), size));
      testWidgets('Fruit Catcher at $size', (tester) => play(tester, FruitCatcher(container: c, onBack: () {}), size));
      testWidgets('Finger Math at $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: FingerMath(container: c, onBack: () {}))));
        await tester.pump();
        await tester.tap(find.text('Start'));
        await tester.pump();
        // Answer by tapping a number: the round moves on.
        expect(find.textContaining('1 / 10'), findsOneWidget);
        await tester.tap(find.text('3').last);
        await tester.pump(const Duration(seconds: 2));
        expect(find.textContaining('2 / 10'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
      });
    }
  });
}
