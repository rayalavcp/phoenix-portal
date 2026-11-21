import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/ui/kids/kids_more_logic.dart';

// The rules behind the Kids Portal's newer activities.
void main() {
  final rng = math.Random(7);

  test('times tables stay in the table and range', () {
    for (var i = 0; i < 200; i++) {
      final q = timesQuestion(7, rng);
      expect(q.a == 7 || q.b == 7, isTrue);
      expect(q.answer, q.a * q.b);
    }
  });

  test('clock questions offer four different times, the answer among them', () {
    for (final level in [1, 2, 3]) {
      for (var i = 0; i < 200; i++) {
        final q = clockQuestion(level, rng);
        expect(q.choices.toSet(), hasLength(4));
        expect(q.choices, contains(q.answer));
        expect(q.minute % (level == 1 ? 30 : (level == 2 ? 15 : 5)), 0);
      }
    }
  });

  test('flags: the emoji and four different answers', () {
    expect(flagEmoji('US'), '🇺🇸');
    for (var i = 0; i < 100; i++) {
      final q = flagQuestion(rng, capitals: i.isEven);
      expect(q.choices.toSet(), hasLength(4));
      expect(q.choices, contains(q.answer));
    }
  });

  test('patterns: four positive choices including the answer', () {
    for (final level in [1, 2, 3]) {
      for (var i = 0; i < 300; i++) {
        final q = patternQuestion(level, rng);
        expect(q.shown, hasLength(5));
        expect(q.choices.toSet(), hasLength(4));
        expect(q.choices, contains(q.answer));
        expect(q.choices.every((c) => c > 0), isTrue);
      }
    }
  });

  test('sudoku puzzles have one solution that fits the rules', () {
    for (final size in [4, 6, 9]) {
      final p = makeSudoku(size, size == 9 ? 40 : size * 2, rng);
      expect(p.solution.contains(0), isFalse);
      for (var i = 0; i < size * size; i++) {
        final v = p.solution[i];
        final grid = [...p.solution]..[i] = 0;
        expect(sudokuAllowed(grid, size, i, v), isTrue);
        if (p.puzzle[i] != 0) expect(p.puzzle[i], v);
      }
      expect(p.puzzle.where((v) => v == 0), isNotEmpty);
    }
  });

  test('mazes connect every cell', () {
    final m = makeMaze(12, 8, rng);
    final seen = <int>{0};
    final queue = [0];
    while (queue.isNotEmpty) {
      final c = queue.removeLast();
      final x = c % m.width, y = c ~/ m.width;
      for (final (dx, dy) in const [(0, -1), (1, 0), (0, 1), (-1, 0)]) {
        if (m.open(x, y, dx, dy) && seen.add((y + dy) * m.width + x + dx)) {
          queue.add((y + dy) * m.width + x + dx);
        }
      }
    }
    expect(seen, hasLength(12 * 8));
  });

  test('word search hides every word along its cells', () {
    final ws = makeWordSearch(kidsWordThemes['Animals']!, 10, 6, rng);
    expect(ws.words, hasLength(6));
    for (final w in ws.words) {
      final cells = ws.places[w]!;
      expect([for (final c in cells) ws.letters[c]].join(), w);
      expect(wordSearchLine(10, cells.first, cells.last), cells);
    }
    expect(wordSearchLine(10, 0, 12), isEmpty);
  });

  test('tic-tac-toe: hard never loses a line it can block', () {
    // X threatens the top row; O must block at 2.
    final b = ['X', 'X', '', '', 'O', '', '', '', ''];
    expect(tttMove(b, true, rng), 2);
    expect(tttWinner(['X', 'X', 'X', '', '', '', '', '', '']), 'X');
    expect(tttWinner(['X', 'O', 'X', 'X', 'O', 'O', 'O', 'X', 'X']), 'draw');
  });

  test('the daily challenge is stable for a day and meets its rule', () {
    final a = dailyChallenge(DateTime(2026, 11, 21, 8));
    final b = dailyChallenge(DateTime(2026, 11, 21, 20));
    expect(a.game, b.game);
    const maze = DailyChallenge('maze', 'Maze', 60, '', lowerIsBetter: true);
    expect(maze.met(45), isTrue);
    expect(maze.met(75), isFalse);
  });

  test('tones are WAV files', () {
    final wav = toneWav(440, millis: 100);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(wav.length, 44 + 22050 ~/ 10 * 2);
  });
}
