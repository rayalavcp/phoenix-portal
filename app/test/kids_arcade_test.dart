import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/app_container.dart';
import 'package:kiosk_satellite/ui/kids/kids_arcade.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Munch Maze rules', () {
    test('every row is the same width and the starts exist', () {
      for (final r in munchMaze) {
        expect(r.length, munchMaze.first.length, reason: r);
      }
      final b = MunchBoard(munchMaze);
      expect(b.robotStarts, hasLength(3));
      expect(b.open(b.playerStart.$1, b.playerStart.$2), isTrue);
    });

    test('Munchie can reach every seed and berry', () {
      final b = MunchBoard(munchMaze);
      final seen = <(int, int)>{b.playerStart};
      final q = Queue.of([b.playerStart]);
      while (q.isNotEmpty) {
        final (x, y) = q.removeFirst();
        for (final d in const [Dir.up, Dir.down, Dir.left, Dir.right]) {
          final nx = (x + d.dx + b.width) % b.width, ny = y + d.dy;
          if (b.open(nx, ny) && seen.add((nx, ny))) q.add((nx, ny));
        }
      }
      for (var y = 0; y < b.height; y++) {
        for (var x = 0; x < b.width; x++) {
          if ('.o'.contains(b.at(x, y))) expect(seen.contains((x, y)), isTrue, reason: 'seed at $x,$y');
        }
      }
    });

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

    test('brick layouts are 10 wide', () {
      for (final l in brickLevels) {
        for (final r in l) {
          expect(r.length, 10);
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
