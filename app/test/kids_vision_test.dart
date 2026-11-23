import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/app_container.dart';
import 'package:kiosk_satellite/managers/motion/native_motion.dart';
import 'package:kiosk_satellite/ui/kids/kids_motion.dart';
import 'package:kiosk_satellite/ui/kids/kids_motion2.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the low-lag filter', () {
    test('a still point stays still through jitter', () {
      final f = OneEuro();
      final rng = math.Random(1);
      double out = 0;
      for (var i = 0; i < 90; i++) {
        out = f.filter(0.5 + (rng.nextDouble() - 0.5) * 0.01, 1 / 30);
      }
      expect((out - 0.5).abs(), lessThan(0.003));
    });

    test('a fast move is followed closely, not trailed', () {
      final f = OneEuro();
      double out = 0;
      // A hand sweeping across the picture in half a second.
      for (var i = 0; i <= 15; i++) {
        out = f.filter(0.1 + 0.8 * i / 15, 1 / 30);
      }
      // The old smoothing (k = dt * 14) was still about 0.15 behind here.
      expect(0.9 - out, lessThan(0.08));
    });

    test('it settles on a new place within a few frames', () {
      final f = OneEuro();
      for (var i = 0; i < 10; i++) {
        f.filter(0.2, 1 / 30);
      }
      double out = 0;
      for (var i = 0; i < 8; i++) {
        out = f.filter(0.8, 1 / 30);
      }
      expect((0.8 - out).abs(), lessThan(0.05));
    });
  });

  group('reading the camera', () {
    test('game hands come across with their points', () {
      final pts = Float32List.fromList([for (var i = 0; i < 42; i++) i / 42]);
      final t = NativeMotionTick.fromNative({
        'ghands': [
          {'x': 0.3, 'y': 0.4, 'f': 2, 'lm': pts},
          {'x': 0.7, 'y': 0.5, 'f': 5, 'lm': pts},
        ],
      });
      expect(t.isGameHands, isTrue);
      expect(t.gameHands, hasLength(2));
      expect(t.gameHands![0].palm, const Offset(0.3, 0.4));
      expect(t.gameHands![1].fingers, 5);
      expect(t.gameHands![0].point(1).dx, closeTo(2 / 42, 1e-6));
      expect(NativeMotionTick.fromNative({'ghands': <Object>[]}).gameHands, isEmpty);
    });

    test('a body mask comes across, and a broken one does not', () {
      final t = NativeMotionTick.fromNative({'body': Uint8List(64 * 48), 'bw': 64, 'bh': 48});
      expect(t.isBody, isTrue);
      expect(t.body!.width, 64);
      expect(NativeMotionTick.fromNative({'body': Uint8List(10), 'bw': 64, 'bh': 48}).isBody, isFalse);
    });

    test('older events still read as before', () {
      expect(NativeMotionTick.fromNative({'head': true, 'x': 0.5, 'y': 0.4}).isHead, isTrue);
      expect(NativeMotionTick.fromNative({'palms': 1, 'fingers': 3}).fingers, 3);
    });
  });

  group('the play area', () {
    late AppContainer c;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      c = AppContainer();
      await c.settings.init();
    });

    testWidgets('two pretty cursors with sparkle trails, nothing of the child drawn', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: WallDodge(container: c, onBack: () {}))));
      await tester.tap(find.text('Start'));
      await tester.pump();
      final state = tester.state(find.byType(WallDodge)) as dynamic;
      final hands = state.hands as KidsHands;
      hands.trails[0].addAll([const Offset(0.2, 0.4), const Offset(0.25, 0.4)]);
      hands.trails[1].addAll([const Offset(0.7, 0.4), const Offset(0.65, 0.4)]);
      hands.points.value = [const Offset(0.3, 0.4), const Offset(0.6, 0.4)];
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
