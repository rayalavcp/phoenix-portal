import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/ui/kids/kids_arcade.dart';
import 'package:kiosk_satellite/ui/kids/kids_more_logic.dart';

void main() {
  test('the hand-made mazes pass the same checks as the random ones', () {
    for (final m in munchMazes) {
      expect(munchMazeIsGood(m, deadEndsOk: true), isTrue);
    }
  });

  test('Munch Maze makes a different, playable maze each stage', () {
    final rng = math.Random(1);
    final mazes = {for (var i = 0; i < 20; i++) randomMunchMaze(rng).join('\n')};
    expect(mazes.length, greaterThan(15));
    for (final m in mazes) {
      final rows = m.split('\n');
      expect(munchMazeIsGood(rows), isTrue);
      expect(rows.length, munchMazes.first.length);
      // Mirrored left to right, like the hand-made ones (Munchie's row aside).
      for (final r in rows.where((r) => !r.contains('P'))) {
        expect(r, r.split('').reversed.join());
      }
      expect(MunchBoard(rows).robotStarts.length, 3);
    }
  });

  test('Brick Bash walls change every game and toughen with the stage', () {
    final rng = math.Random(2);
    final early = {for (var i = 0; i < 20; i++) randomBrickLayout(1, rng).join('|')};
    expect(early.length, greaterThan(10));
    for (var i = 0; i < 30; i++) {
      final first = randomBrickLayout(1, rng).join();
      if (!brickLevels.any((l) => l.join() == first)) expect(first.contains(RegExp('[23]')), isFalse);
    }
    final late = [for (var i = 0; i < 30; i++) randomBrickLayout(9, rng).join()];
    expect(late.any((l) => l.contains('3')), isTrue);
  });

  test('sudoku and mazes are new every round', () {
    final rng = math.Random();
    expect({for (var i = 0; i < 5; i++) makeSudoku(4, 8, rng).puzzle.join()}.length, greaterThan(1));
    expect({for (var i = 0; i < 5; i++) makeMaze(8, 8, rng).walls.join()}.length, greaterThan(1));
  });
}
