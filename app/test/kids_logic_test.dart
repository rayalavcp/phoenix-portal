import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/ui/kids/kids_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Math Blitz', () {
    test('levels climb every five answers', () {
      expect(mathLevel(0), 1);
      expect(mathLevel(4), 1);
      expect(mathLevel(5), 2);
      expect(mathLevel(17), 4);
    });

    test('problems are solvable, whole and offer four distinct choices', () {
      final rng = math.Random(1);
      for (var level = 1; level <= 5; level++) {
        for (var i = 0; i < 300; i++) {
          final p = mathProblem(level, rng);
          final [a, op, b] = p.text.split(' ');
          final x = int.parse(a), y = int.parse(b);
          final expected = switch (op) {
            '+' => x + y,
            '−' => x - y,
            '×' => x * y,
            _ => x ~/ y,
          };
          expect(p.answer, expected, reason: p.text);
          if (op == '÷') expect(x % y, 0, reason: p.text);
          expect(p.answer, greaterThanOrEqualTo(0), reason: p.text);
          expect(p.choices.toSet().length, 4);
          expect(p.choices, contains(p.answer));
          expect(p.choices.every((c) => c >= 0), isTrue);
          if (level == 1) expect(op, anyOf('+', '−'));
        }
      }
    });
  });

  group('Word Scramble', () {
    test('words are upper case, 4 to 8 letters', () {
      for (final w in scrambleWords.values.expand((l) => l)) {
        expect(w, matches(RegExp(r'^[A-Z]{4,8}$')), reason: w);
      }
    });
    test('a scramble is never the word itself and keeps its letters', () {
      final rng = math.Random(3);
      for (final w in scrambleWords.values.expand((l) => l)) {
        final s = scramble(w, rng);
        expect(s.join(), isNot(w));
        expect((List.of(s)..sort()).join(), (w.split('')..sort()).join());
      }
    });
  });

  group('2048', () {
    test('a row slides and merges once per pair', () {
      expect(slideRow([2, 2, 2, 2]).$1, [4, 4, 0, 0]);
      expect(slideRow([2, 2, 2, 2]).$2, 8);
      expect(slideRow([0, 4, 0, 4]).$1, [8, 0, 0, 0]);
      expect(slideRow([2, 4, 8, 16]).$1, [2, 4, 8, 16]);
      expect(slideRow([4, 4, 8, 0]).$1, [8, 8, 0, 0]);
    });

    test('the board moves in every direction', () {
      final board = [
        [2, 0, 0, 2],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [2, 0, 0, 0],
      ];
      expect(slideBoard(board, Dir.left).board.first, [4, 0, 0, 0]);
      expect(slideBoard(board, Dir.right).board.first, [0, 0, 0, 4]);
      expect(slideBoard(board, Dir.down).board[3].first, 4);
      expect(slideBoard(board, Dir.up).board[0].first, 4);
      final stuck = [
        [2, 4, 2, 4],
        [4, 2, 4, 2],
        [2, 4, 2, 4],
        [4, 2, 4, 2],
      ];
      expect(canMove(stuck), isFalse);
      expect(slideBoard(stuck, Dir.left).moved, isFalse);
    });

    test('spawn fills an empty cell with a 2 or 4', () {
      final board = List.generate(4, (_) => List.filled(4, 0));
      final cell = spawnTile(board, math.Random(5))!;
      expect([2, 4], contains(board[cell.$1][cell.$2]));
    });
  });

  group('Connect Four', () {
    test('pieces fall to the bottom and wins are found in every direction', () {
      final b = C4();
      expect(b.drop(0, 1), c4Rows - 1);
      expect(b.drop(0, 1), c4Rows - 2);
      final h = C4();
      for (var c = 0; c < 4; c++) {
        h.drop(c, 1);
      }
      expect(h.winner, 1);
      final v = C4();
      for (var i = 0; i < 4; i++) {
        v.drop(2, 2);
      }
      expect(v.winner, 2);
      final d = C4();
      // A rising diagonal for player 1 from column 0 to 3.
      d.drop(0, 1);
      d..drop(1, 2)..drop(1, 1);
      d..drop(2, 2)..drop(2, 2)..drop(2, 1);
      d..drop(3, 2)..drop(3, 2)..drop(3, 2)..drop(3, 1);
      expect(d.winner, 1);
    });

    test('the computer takes a win and blocks one', () {
      final win = C4();
      for (var i = 0; i < 3; i++) {
        win.drop(5, 2);
      }
      expect(c4AiMove(win, hard: true, rng: math.Random(1)), 5);
      final block = C4();
      for (var c = 0; c < 3; c++) {
        block.drop(c, 1);
      }
      expect(c4AiMove(block, hard: true, rng: math.Random(1)), 3);
    });
  });

  group('scores', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('best scores keep the better result', () async {
      expect(await KidsScores.offer('math', 10), isTrue);
      expect(await KidsScores.offer('math', 8), isFalse);
      expect(await KidsScores.best('math'), 10);
      expect(await KidsScores.offer('memory', 40, lowerIsBetter: true), isTrue);
      expect(await KidsScores.offer('memory', 50, lowerIsBetter: true), isFalse);
      expect(await KidsScores.offer('memory', 30, lowerIsBetter: true), isTrue);
    });

    test('stars count per day', () async {
      final day = DateTime(2026, 11, 21);
      await KidsScores.addStars(2, now: day);
      await KidsScores.addStars(3, now: day);
      expect(await KidsScores.starsToday(now: day), 5);
      expect(await KidsScores.starsToday(now: DateTime(2026, 11, 22)), 0);
    });
  });
}
