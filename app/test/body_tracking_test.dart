import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/app_container.dart';
import 'package:kiosk_satellite/managers/motion/native_motion.dart';
import 'package:kiosk_satellite/ui/kids/kids_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real MediaPipe Pose (lite) results for one photo of a person with both
/// arms stretched out, placed at several sizes in a 640×480 frame
/// (test/fixtures/body_poses.json; how they were made is in HANDOFF.md).
void main() {
  final fx = jsonDecode(File('test/fixtures/body_poses.json').readAsStringSync()) as Map<String, Object?>;
  final aspect = (fx['aspect']! as num).toDouble();
  BodyPose pose(Object? raw) => BodyPose(Float32List.fromList([for (final v in raw! as List) (v as num).toDouble()]), aspect: aspect);
  List<BodyPose> poses(Object? list) => [for (final p in list! as List) pose(p)];
  final t0 = DateTime(2026, 1, 1);

  test('arms stretched out reach both sides of the screen, near or far', () {
    final xs = <double>[];
    for (final MapEntry(key: size, value: list) in (fx['scales']! as Map).entries) {
      final view = BodyView.of(poses(list).single)!;
      final a = bodyCursor(view.hand(0)!, view), b = bodyCursor(view.hand(1)!, view);
      final (left, right) = a.dx < b.dx ? (a, b) : (b, a);
      expect(left.dx, lessThan(0.08), reason: 'left hand at $size');
      expect(right.dx, greaterThan(0.92), reason: 'right hand at $size');
      // Arms at shoulder height: about the middle, a little above it.
      expect(left.dy, inInclusiveRange(0.4, 0.65), reason: 'height at $size');
      xs.add(view.width);
    }
    // The body really was a different size each time.
    expect(xs.reduce((a, b) => a > b ? a : b) / xs.reduce((a, b) => a < b ? a : b), greaterThan(2));
  });

  test('walking away from the Portal keeps the cursor where it was', () {
    final walk = fx['walk']! as List;
    Offset? first;
    for (final step in walk) {
      final list = poses((step as Map)['poses']);
      expect(list, isNotEmpty, reason: 'still followed at ${step['frac']} of the frame height');
      final v = BodyView.of(list.single)!;
      final c = bodyCursor(v.hand(1)!, v);
      first ??= c;
      expect((c - first).distance, lessThan(0.08), reason: 'at ${step['frac']}');
    }
  });

  test('two children: the nearest plays, then stays the player', () {
    final two = [for (final p in poses(fx['two'])) BodyView.of(p)!];
    final lock = BodyLock();
    final player = lock.pick(two, t0)!;
    final bigger = two.reduce((a, b) => b.width > a.width ? b : a);
    expect(player.centre, bigger.centre);
    // The other child alone is not the player for a moment...
    final other = two.firstWhere((v) => v.centre != bigger.centre);
    expect(lock.pick([other], t0.add(const Duration(milliseconds: 300))), isNull);
    // ...and takes over once the player has gone.
    expect(lock.pick([other], t0.add(const Duration(seconds: 2)))!.centre, other.centre);
  });

  testWidgets('the game cursor follows the body, and two players split the screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = AppContainer();
    await c.settings.init();
    final one = KidsHands(c.motion);
    expect(one.body, isTrue);
    final arms = poses((fx['scales']! as Map)['0.55']);
    one.debugFollow(arms, DateTime.now());
    one.step(0.016);
    expect(one.point.value, isNotNull);
    // One cursor, on the hand doing the most.
    expect(one.points.value, hasLength(1));
    one.dispose();

    final duel = KidsHands(c.motion, twoHands: true, people: true);
    duel.debugFollow(poses(fx['two']), DateTime.now());
    duel.step(0.016);
    final spots = [...duel.points.value]..sort((a, b) => a.dx.compareTo(b.dx));
    expect(spots, hasLength(2));
    expect(spots[0].dx, lessThanOrEqualTo(0.5));
    expect(spots[1].dx, greaterThanOrEqualTo(0.5));
    duel.dispose();

    // Finger Math keeps the hand tracker.
    final fingers = KidsHands(c.motion, twoHands: true, fingerCount: true);
    expect(fingers.body, isFalse);
    fingers.dispose();
  });
}
