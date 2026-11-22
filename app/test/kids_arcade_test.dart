import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/app_container.dart';
import 'package:kiosk_satellite/ui/kids/kids_arcade.dart';
import 'package:kiosk_satellite/ui/kids/kids_arcade2.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Munch Maze rules', () {
    for (var m = 0; m < munchMazes.length; m++) {
      final maze = munchMazes[m];
      test('maze ${m + 1}: rows the same width, starts there', () {
        expect(maze, hasLength(19));
        for (final r in maze) {
          expect(r.length, 19, reason: r);
        }
        final b = MunchBoard(maze);
        expect(b.robotStarts, hasLength(3));
        expect('P'.allMatches(maze.join()).length, 1);
        expect(b.open(b.playerStart.$1, b.playerStart.$2), isTrue);
      });

      Set<(int, int)> reach(MunchBoard b, (int, int) from, {bool robot = false}) {
        final seen = <(int, int)>{from};
        final q = Queue.of([from]);
        while (q.isNotEmpty) {
          final (x, y) = q.removeFirst();
          for (final d in const [Dir.up, Dir.down, Dir.left, Dir.right]) {
            final nx = (x + d.dx + b.width) % b.width, ny = y + d.dy;
            if (b.open(nx, ny, robot: robot) && seen.add((nx, ny))) q.add((nx, ny));
          }
        }
        return seen;
      }

      test('maze ${m + 1}: Munchie reaches every seed, robots get out', () {
        final b = MunchBoard(maze);
        final seen = reach(b, b.playerStart);
        for (var y = 0; y < b.height; y++) {
          for (var x = 0; x < b.width; x++) {
            if ('.o'.contains(b.at(x, y))) expect(seen.contains((x, y)), isTrue, reason: 'seed at $x,$y');
          }
        }
        for (final r in b.robotStarts) {
          expect(reach(b, r, robot: true).contains(b.playerStart), isTrue);
        }
        // Munchie cannot get into the robots' home.
        expect(seen.any(b.robotStarts.contains), isFalse);
        expect(munchWallColors.length, greaterThanOrEqualTo(munchMazes.length));
      });
    }

    test('robots can leave home through their door, Munchie cannot enter', () {
      final b = MunchBoard(munchMaze);
      final door = munchMaze.indexWhere((r) => r.contains('-'));
      final dx = munchMaze[door].indexOf('-');
      expect(b.open(dx, door), isFalse);
      expect(b.open(dx, door, robot: true), isTrue);
    });

    test('robots never turn straight back when they have a choice', () {
      final b = MunchBoard(munchMaze);
      final rng = math.Random(1);
      for (var y = 1; y < b.height - 1; y++) {
        for (var x = 1; x < b.width - 1; x++) {
          if (!b.open(x, y, robot: true)) continue;
          for (final d in const [Dir.up, Dir.down, Dir.left, Dir.right]) {
            final w = Walker(x, y, dir: d);
            final c = chooseDir(b, w, (rng.nextDouble() * 19, rng.nextDouble() * 19), rng: rng);
            final others = [
              for (final o in const [Dir.up, Dir.down, Dir.left, Dir.right])
                if (o != d.opposite && b.open(x + o.dx, y + o.dy, robot: true)) o,
            ];
            if (others.isNotEmpty) expect(c, isNot(d.opposite));
            expect(b.open(x + c.dx, y + c.dy, robot: true), isTrue);
          }
        }
      }
    });

    test('eating scores seeds and berries once', () {
      final b = MunchBoard(munchMaze);
      final before = b.seedsLeft;
      expect(b.eat(1, 1), (points: 50, berry: true));
      expect(b.eat(1, 1), (points: 0, berry: false));
      expect(b.eat(2, 1), (points: 10, berry: false));
      expect(b.seedsLeft, before - 2);
    });

    test('brick layouts are 10 wide, fit above the paddle, and the starts exist', () {
      expect(brickLevels.length, greaterThanOrEqualTo(12));
      for (final l in brickLevels) {
        expect(l.length, lessThanOrEqualTo(7));
        for (final r in l) {
          expect(r.length, 10);
          expect(RegExp(r'^[.123]+$').hasMatch(r), isTrue, reason: r);
        }
        expect(l.join().replaceAll('.', ''), isNotEmpty);
      }
      for (final s in brickStarts) {
        expect(s, inInclusiveRange(1, brickLevels.length));
      }
    });
  });

  group('Hop Across rules', () {
    test('every stage has a river on top and a road below, all passable', () {
      for (var stage = 1; stage <= 9; stage++) {
        for (var d = 0; d < 3; d++) {
          final lanes = hopLanes(stage, d);
          expect(lanes, hasLength(hopRows));
          expect([lanes[0], lanes[6], lanes[12]], everyElement(isNull));
          for (var y = 1; y <= 5; y++) {
            final l = lanes[y]!;
            expect(l.river, isTrue);
            // Logs at least 2 long, gaps never longer than 6.
            for (final (_, len) in l.runs) {
              expect(len, greaterThanOrEqualTo(2), reason: l.pattern);
            }
            expect(RegExp(r'\.{7,}').hasMatch(l.pattern + l.pattern), isFalse, reason: l.pattern);
            expect(l.speed.abs(), lessThanOrEqualTo(2.2 * 2.2));
          }
          for (var y = 7; y <= 11; y++) {
            final l = lanes[y]!;
            expect(l.river, isFalse);
            // Room between cars: at least 3 empty cells.
            final p = l.pattern + l.pattern;
            for (final m in RegExp(r'x(\.+)x').allMatches(p)) {
              expect(m.group(1)!.length, greaterThanOrEqualTo(3), reason: l.pattern);
            }
          }
        }
      }
    });

    test('a lane slides its pattern along', () {
      final l = HopLane('xx..', 1);
      expect(l.solidAt(0.5, 0), isTrue);
      expect(l.solidAt(2.5, 0), isFalse);
      expect(l.solidAt(2.5, 2), isTrue);
      expect(l.runs, [(0, 2)]);
      expect(HopLane('x..x', 1).runs, [(3, 2)]);
    });
  });

  group('Sky Glide and Fox Run rules', () {
    test('gaps stay flyable and inside the sky', () {
      final rng = math.Random(2);
      for (var d = 0; d < 3; d++) {
        for (var stage = 1; stage < 30; stage++) {
          final gap = skyGap(d, stage);
          expect(gap, inInclusiveRange(17, 30));
          expect(skySpeed(d, stage), lessThanOrEqualTo(40));
          var y = 30.0;
          for (var i = 0; i < 50; i++) {
            final next = nextGapY(y, gap, rng);
            expect(next - gap / 2, greaterThanOrEqualTo(4 - 1e-9));
            expect(next + gap / 2, lessThanOrEqualTo(56 + 1e-9));
            expect((next - y).abs(), lessThanOrEqualTo(18.0001));
            y = next;
          }
        }
      }
    });

    test('there is always room to land between obstacles', () {
      final rng = math.Random(5);
      for (final speed in [30.0, 45.0, 62.0]) {
        for (var i = 0; i < 200; i++) {
          // In the air for 2 × 62 / 190 s: the gap must be longer than a jump.
          expect(runnerGap(speed, rng), greaterThan(speed * 2 * 62 / 190 + 9));
        }
      }
    });
  });

  group('arcade games play', () {
    late AppContainer c;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      c = AppContainer();
      await c.settings.init();
    });

    Future<void> play(WidgetTester tester, Widget game, Size size, Future<void> Function() moves) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: game)));
      await tester.pump();
      await tester.ensureVisible(find.text('Start'));
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pump();
      await moves();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('leaving before starting is fine', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: BrickBash(container: c, onBack: _none))));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MunchMaze(onBack: _none))));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HopAcross(onBack: _none))));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SkyGlide(container: c, onBack: _none))));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FoxRun(container: c, onBack: _none))));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });

    for (final size in const [Size(1280, 800), Size(800, 1280), Size(1024, 600)]) {
      testWidgets('Munch Maze at $size', (tester) => play(tester, const MunchMaze(onBack: _none), size, () async {
            for (final icon in [Icons.arrow_upward_rounded, Icons.arrow_forward_rounded, Icons.arrow_downward_rounded, Icons.arrow_back_rounded]) {
              await tester.tap(find.byIcon(icon).last);
              for (var i = 0; i < 20; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
            }
            // Swipe too.
            await tester.fling(find.byType(CustomPaint).last, const Offset(0, -200), 800);
            for (var i = 0; i < 60; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }));
      testWidgets('Hop Across at $size', (tester) => play(tester, const HopAcross(onBack: _none), size, () async {
            for (final icon in [Icons.arrow_upward_rounded, Icons.arrow_upward_rounded, Icons.arrow_back_rounded, Icons.arrow_forward_rounded, Icons.arrow_downward_rounded]) {
              await tester.tap(find.byIcon(icon).last);
              for (var i = 0; i < 10; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
            }
            for (var i = 0; i < 20; i++) {
              await tester.tap(find.byType(CustomPaint).last, warnIfMissed: false);
              await tester.pump(const Duration(milliseconds: 300));
            }
          }));
      testWidgets('Sky Glide at $size', (tester) => play(tester, SkyGlide(container: c, onBack: _none), size, () async {
            for (var i = 0; i < 80; i++) {
              if (i % 4 == 0) await tester.tap(find.byType(CustomPaint).last, warnIfMissed: false);
              await tester.pump(const Duration(milliseconds: 100));
            }
          }));
      testWidgets('Fox Run at $size', (tester) => play(tester, FoxRun(container: c, onBack: _none), size, () async {
            for (var i = 0; i < 100; i++) {
              if (i % 7 == 0) await tester.tap(find.byType(CustomPaint).last, warnIfMissed: false);
              await tester.pump(const Duration(milliseconds: 100));
            }
          }));
      testWidgets('Brick Bash at $size', (tester) => play(tester, BrickBash(container: c, onBack: _none), size, () async {
            final g = await tester.startGesture(tester.getCenter(find.byType(Scaffold)));
            for (var i = 0; i < 100; i++) {
              await g.moveBy(Offset(i % 10 < 5 ? 30 : -30, 0));
              await tester.pump(const Duration(milliseconds: 100));
            }
            await g.up();
          }));
    }
  });
}

void _none() {}
