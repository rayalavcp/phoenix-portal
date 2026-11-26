import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/managers/motion/native_motion.dart';
import 'package:kiosk_satellite/ui/kids/kids_motion.dart';
import 'package:kiosk_satellite/ui/kids/kids_motion2.dart';
import 'package:kiosk_satellite/ui/kids/kids_touch.dart';

GameHand hand(double x, double y, double size) => GameHand(Offset(x, y), 5, Float32List(0), size: size);

void main() {
  final t0 = DateTime(2026, 1, 1);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  group('HandReach', () {
    test('a hand starts in the middle of the screen', () {
      expect(HandReach().map(const Offset(0.8, 0.3), 0.05, 0.75, t0), const Offset(0.5, 0.5));
    });

    test('the same arm movement reaches as far near or far', () {
      // Near: a big hand; far: a hand half the size moving half as far.
      final near = HandReach()..map(const Offset(0.5, 0.5), 0.08, 0.75, t0);
      final far = HandReach()..map(const Offset(0.5, 0.5), 0.04, 0.75, t0);
      final a = near.map(const Offset(0.6, 0.5), 0.08, 0.75, at(33));
      final b = far.map(const Offset(0.55, 0.5), 0.04, 0.75, at(33));
      expect(a.dx, closeTo(b.dx, 0.01));
      expect(a.dx, greaterThan(0.6));
    });

    test('reaching past the edge pushes the box, so coming back moves at once', () {
      final r = HandReach()..map(const Offset(0.5, 0.5), 0.05, 0.75, t0);
      expect(r.map(const Offset(0.95, 0.5), 0.05, 0.75, at(33)).dx, 1.0);
      expect(r.map(const Offset(0.9, 0.5), 0.05, 0.75, at(66)).dx, lessThan(1.0));
    });
  });

  group('PlayerLock', () {
    test('the nearest child (biggest hand) becomes the player', () {
      final lock = PlayerLock();
      final picked = lock.pick([hand(0.2, 0.5, 0.03), hand(0.7, 0.5, 0.06)], t0);
      expect(picked!.palm.dx, 0.7);
    });

    test('keeps the player when another child is in view', () {
      final lock = PlayerLock()..pick([hand(0.3, 0.5, 0.05)], t0);
      // A second, bigger hand appears across the picture: still the player.
      final p = lock.pick([hand(0.8, 0.4, 0.07), hand(0.33, 0.52, 0.05)], at(33));
      expect(p!.palm.dx, 0.33);
    });

    test('ignores someone else\'s hand while the player\'s is briefly gone', () {
      final lock = PlayerLock()..pick([hand(0.3, 0.5, 0.05)], t0);
      expect(lock.pick([hand(0.85, 0.5, 0.05)], at(300)), isNull);
      // After a while without the player, the other child takes over.
      expect(lock.pick([hand(0.85, 0.5, 0.05)], at(2000))!.palm.dx, 0.85);
    });
  });

  group('touch games', () {
    test('a swipe hits what it passes through', () {
      expect(swipeHits(const Offset(0, 0), const Offset(100, 0), const Offset(50, 8), 10), isTrue);
      expect(swipeHits(const Offset(0, 0), const Offset(100, 0), const Offset(50, 30), 10), isFalse);
      expect(swipeHits(const Offset(0, 0), const Offset(100, 0), const Offset(130, 0), 10), isFalse);
    });

    test('stacking cuts the overhang, snaps a perfect drop, misses fall', () {
      const top = StackBlock(0.3, 0.4, 0);
      final (cut, perfect) = stackDrop(top, const StackBlock(0.4, 0.4, 0));
      expect(perfect, isFalse);
      expect(cut!.left, 0.4);
      expect(cut.width, closeTo(0.3, 1e-9));
      final (snapped, p2) = stackDrop(top, const StackBlock(0.305, 0.4, 0));
      expect(p2, isTrue);
      expect(snapped!.left, 0.3);
      expect(stackDrop(top, const StackBlock(0.75, 0.4, 0)).$1, isNull);
    });
  });

  group('motion games', () {
    test('the glove saves a shot only near where it lands', () {
      expect(goalieSaves(const Offset(0.5, 0.5), const Offset(0.55, 0.52), 0), isTrue);
      expect(goalieSaves(const Offset(0.2, 0.5), const Offset(0.55, 0.52), 0), isFalse);
      expect(goalieSaves(null, const Offset(0.55, 0.52), 0), isFalse);
    });

    test('wiping clears the frost under the cloth', () {
      final w = FrostWindow(20, 10);
      expect(w.clear, 0);
      for (var i = 0; i < 4; i++) {
        w.wipe(const Offset(0.5, 0.5), 0.2, 0.6);
      }
      expect(w.clear, greaterThan(0.1));
      expect(w.cells[0], 1);
    });
  });

  group('pose and duel games', () {
    test('a pose needs a hand in each spot, either way round', () {
      final pose = dancePoses.first;
      expect(poseFilled(pose, [pose.left, pose.right], 0.1), isTrue);
      expect(poseFilled(pose, [pose.right, pose.left], 0.1), isTrue);
      expect(poseFilled(pose, [pose.left], 0.1), isFalse);
      expect(poseFilled(pose, [pose.left, pose.left], 0.1), isFalse);
    });

    test('Simon zones and duel sides', () {
      expect(inSimonZone('UP HIGH', [const Offset(0.5, 0.1)]), isTrue);
      expect(inSimonZone('UP HIGH', [const Offset(0.5, 0.6)]), isFalse);
      expect(inSimonZone('TO THE LEFT', [const Offset(0.9, 0.5), const Offset(0.1, 0.5)]), isTrue);
      expect(duelSide(const Offset(0.2, 0.5)), 0);
      expect(duelSide(const Offset(0.8, 0.5)), 1);
    });
  });
}
