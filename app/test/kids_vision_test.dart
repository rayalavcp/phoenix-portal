import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/app_container.dart';
import 'package:kiosk_satellite/managers/motion/native_motion.dart';
import 'package:kiosk_satellite/ui/kids/kids_motion.dart';
import 'package:kiosk_satellite/ui/kids/kids_motion2.dart';
import 'package:shared_preferences/shared_preferences.dart';

BodyMask _blob(int w, int h, bool Function(int x, int y) inside) {
  final cells = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (inside(x, y)) cells[y * w + x] = 255;
    }
  }
  return BodyMask(w, h, cells);
}

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

  group('the glowing outline', () {
    test('a square body traces a closed outline round it', () {
      final m = _blob(20, 16, (x, y) => x >= 5 && x < 15 && y >= 4 && y < 12);
      final segs = maskContour(m);
      // 10 × 8 cells: 2 × (10 + 8) = 36 unit steps round it.
      expect(segs.length, 36);
      // Every end point is shared by exactly two segments: a closed loop.
      final ends = <Offset, int>{};
      for (final (a, b) in segs) {
        ends[a] = (ends[a] ?? 0) + 1;
        ends[b] = (ends[b] ?? 0) + 1;
      }
      expect(ends.values.every((n) => n == 2), isTrue);
      // It runs half a cell outside the body's cell centres.
      final xs = [for (final (a, b) in segs) ...[a.dx, b.dx]];
      expect(xs.reduce(math.min), 5.0);
      expect(xs.reduce(math.max), 15.0);
    });

    test('nothing there, nothing drawn; a body at the edge still closes', () {
      expect(maskContour(_blob(10, 10, (x, y) => false)), isEmpty);
      final segs = maskContour(_blob(10, 10, (x, y) => y >= 5));
      expect(segs, isNotEmpty);
    });
  });

  group('the play area draws what the camera sees', () {
    late AppContainer c;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      c = AppContainer();
      await c.settings.init();
    });

    testWidgets('body outline, two glowing hands and two cursors', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: WallDodge(container: c, onBack: () {}))));
      await tester.tap(find.text('Start'));
      await tester.pump();
      final state = tester.state(find.byType(WallDodge)) as dynamic;
      final hands = state.hands as KidsHands;
      hands.outline.value = _blob(64, 48, (x, y) => math.pow(x - 32, 2) / 120 + math.pow(y - 26, 2) / 300 < 1);
      final hand = [for (var i = 0; i < 21; i++) Offset(0.3 + (i % 5) * 0.02, 0.4 + (i ~/ 5) * 0.03)];
      hands.skeletons.value = [hand, [for (final p in hand) p + const Offset(0.3, 0)]];
      hands.points.value = [const Offset(0.3, 0.4), const Offset(0.6, 0.4)];
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
