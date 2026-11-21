import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The rules behind the Kids Portal's second shelf of activities: Times
/// Tables, Telling the Time, Flag Quiz, Patterns, Sudoku, Mazes, Word
/// Search, Word Guess, Tic-Tac-Toe, Snake and Simon Says. Pure Dart, no
/// widgets, so each is tested on its own.

// ── Times Tables ─────────────────────────────────────────────────────────

@immutable
class TimesQuestion {
  const TimesQuestion(this.a, this.b);
  final int a;
  final int b;
  int get answer => a * b;
  String get text => '$a × $b';
}

/// A question from [table] (2..12), or any table when [table] is null.
TimesQuestion timesQuestion(int? table, math.Random rng) {
  final a = table ?? 2 + rng.nextInt(11);
  final b = 1 + rng.nextInt(12);
  return rng.nextBool() ? TimesQuestion(a, b) : TimesQuestion(b, a);
}

// ── Telling the Time ─────────────────────────────────────────────────────

@immutable
class ClockQuestion {
  const ClockQuestion(this.hour, this.minute, this.choices);
  final int hour;
  final int minute;
  final List<String> choices;
  String get answer => clockText(hour, minute);
}

String clockText(int hour, int minute) =>
    '$hour:${minute.toString().padLeft(2, '0')}';

/// A time on the clock face: whole and half hours at level 1, quarters at
/// 2, five minutes at 3. Four different choices, the answer among them.
ClockQuestion clockQuestion(int level, math.Random rng) {
  final step = switch (level) {
    <= 1 => 30,
    2 => 15,
    _ => 5,
  };
  int pickMinute() => rng.nextInt(60 ~/ step) * step;
  final hour = 1 + rng.nextInt(12);
  final minute = pickMinute();
  final answer = clockText(hour, minute);
  final choices = <String>{answer};
  for (var guard = 0; choices.length < 4; guard++) {
    if (guard > 60) {
      choices.add(clockText(1 + rng.nextInt(12), rng.nextInt(12) * 5));
      continue;
    }
    // Near misses teach: the hands swapped, an hour off, minutes off.
    final kind = rng.nextInt(3);
    final h = switch (kind) {
      0 => (minute ~/ 5 == 0 ? 12 : minute ~/ 5),
      1 => ((hour + (rng.nextBool() ? 1 : 11) - 1) % 12) + 1,
      _ => hour,
    };
    final m = switch (kind) {
      0 => (hour % 12) * 5,
      1 => minute,
      _ => pickMinute(),
    };
    choices.add(clockText(h, m));
  }
  return ClockQuestion(hour, minute, choices.toList()..shuffle(rng));
}

// ── Flag Quiz ────────────────────────────────────────────────────────────

/// Countries by ISO code, with their capital, for the flag and capital
/// quizzes. Flags are drawn from the regional indicator emoji.
const kidsCountries = <(String, String, String)>[
  ('US', 'United States', 'Washington, D.C.'),
  ('CA', 'Canada', 'Ottawa'),
  ('MX', 'Mexico', 'Mexico City'),
  ('BR', 'Brazil', 'Brasília'),
  ('AR', 'Argentina', 'Buenos Aires'),
  ('GB', 'United Kingdom', 'London'),
  ('FR', 'France', 'Paris'),
  ('DE', 'Germany', 'Berlin'),
  ('IT', 'Italy', 'Rome'),
  ('ES', 'Spain', 'Madrid'),
  ('PT', 'Portugal', 'Lisbon'),
  ('NL', 'Netherlands', 'Amsterdam'),
  ('SE', 'Sweden', 'Stockholm'),
  ('NO', 'Norway', 'Oslo'),
  ('GR', 'Greece', 'Athens'),
  ('IE', 'Ireland', 'Dublin'),
  ('CH', 'Switzerland', 'Bern'),
  ('IN', 'India', 'New Delhi'),
  ('CN', 'China', 'Beijing'),
  ('JP', 'Japan', 'Tokyo'),
  ('KR', 'South Korea', 'Seoul'),
  ('AU', 'Australia', 'Canberra'),
  ('NZ', 'New Zealand', 'Wellington'),
  ('EG', 'Egypt', 'Cairo'),
  ('ZA', 'South Africa', 'Pretoria'),
  ('KE', 'Kenya', 'Nairobi'),
  ('NG', 'Nigeria', 'Abuja'),
  ('RU', 'Russia', 'Moscow'),
  ('TR', 'Turkey', 'Ankara'),
  ('TH', 'Thailand', 'Bangkok'),
  ('SG', 'Singapore', 'Singapore'),
  ('PH', 'Philippines', 'Manila'),
  ('VN', 'Vietnam', 'Hanoi'),
  ('ID', 'Indonesia', 'Jakarta'),
  ('PK', 'Pakistan', 'Islamabad'),
  ('BD', 'Bangladesh', 'Dhaka'),
  ('LK', 'Sri Lanka', 'Colombo'),
  ('NP', 'Nepal', 'Kathmandu'),
  ('CL', 'Chile', 'Santiago'),
  ('PE', 'Peru', 'Lima'),
  ('CO', 'Colombia', 'Bogotá'),
  ('JM', 'Jamaica', 'Kingston'),
];

/// The flag emoji for an ISO code ("US" → 🇺🇸).
String flagEmoji(String code) => String.fromCharCodes([
  for (final c in code.toUpperCase().codeUnits) 0x1F1E6 + c - 0x41,
]);

@immutable
class FlagQuestion {
  const FlagQuestion(this.code, this.prompt, this.answer, this.choices);
  final String code;
  final String prompt;
  final String answer;
  final List<String> choices;
}

/// A flag to name, or (with [capitals]) a country's capital to pick.
FlagQuestion flagQuestion(math.Random rng, {bool capitals = false}) {
  final pool = [...kidsCountries]..shuffle(rng);
  final (code, country, capital) = pool.first;
  final choices = [
    for (final (_, c, cap) in pool.take(4)) capitals ? cap : c,
  ]..shuffle(rng);
  return FlagQuestion(
    code,
    capitals ? 'What is the capital of $country?' : 'Which country is this?',
    capitals ? capital : country,
    choices,
  );
}

// ── Patterns ─────────────────────────────────────────────────────────────

@immutable
class PatternQuestion {
  const PatternQuestion(this.shown, this.answer, this.choices, this.rule);
  final List<int> shown;
  final int answer;
  final List<int> choices;

  /// The rule in words, shown after an answer.
  final String rule;
}

/// A number sequence with its next term missing. Harder rules arrive with
/// [level]: adding, then doubling, then alternating and growing steps.
PatternQuestion patternQuestion(int level, math.Random rng) {
  final kinds = level <= 1 ? 2 : (level == 2 ? 4 : 6);
  final kind = rng.nextInt(kinds);
  final List<int> seq;
  final String rule;
  switch (kind) {
    case 0:
      final start = 1 + rng.nextInt(10), step = 2 + rng.nextInt(8);
      seq = [for (var i = 0; i < 6; i++) start + step * i];
      rule = 'Add $step each time';
    case 1:
      final step = 2 + rng.nextInt(5), start = step * 8 + rng.nextInt(20);
      seq = [for (var i = 0; i < 6; i++) start - step * i];
      rule = 'Take away $step each time';
    case 2:
      final start = 1 + rng.nextInt(4);
      seq = [for (var i = 0; i < 6; i++) start * (1 << i)];
      rule = 'Double each time';
    case 3:
      final start = 1 + rng.nextInt(5);
      seq = [for (var i = 0; i < 6; i++) start + i * (i + 1) ~/ 2];
      rule = 'Add 1, then 2, then 3, and so on';
    case 4:
      final a = 1 + rng.nextInt(5), b = 2 + rng.nextInt(5);
      seq = [
        for (var i = 0, v = 1 + rng.nextInt(5); i < 6; v += i.isEven ? a : b, i++) v,
      ];
      rule = 'Add $a, then add $b, again and again';
    default:
      final start = 1 + rng.nextInt(4);
      seq = [for (var i = 0; i < 6; i++) (start + i) * (start + i)];
      rule = 'Square numbers: $start×$start, ${start + 1}×${start + 1}, …';
  }
  final answer = seq.last;
  final choices = <int>{answer};
  for (var guard = 0; choices.length < 4; guard++) {
    if (guard > 60) {
      choices.add(answer + choices.length * 7);
      continue;
    }
    final off = (1 + rng.nextInt(math.max(3, answer ~/ 5))) *
        (rng.nextBool() ? 1 : -1);
    if (answer + off > 0) choices.add(answer + off);
  }
  return PatternQuestion(
    seq.sublist(0, 5),
    answer,
    choices.toList()..shuffle(rng),
    rule,
  );
}

// ── Sudoku ───────────────────────────────────────────────────────────────

/// Box shape per board size: 4 is 2×2 boxes, 6 is 2×3, 9 is 3×3.
(int, int) sudokuBox(int size) => switch (size) {
  4 => (2, 2),
  6 => (2, 3),
  _ => (3, 3),
};

bool sudokuAllowed(List<int> grid, int size, int index, int value) {
  final (bh, bw) = sudokuBox(size);
  final row = index ~/ size, col = index % size;
  for (var i = 0; i < size; i++) {
    if (grid[row * size + i] == value || grid[i * size + col] == value) {
      return false;
    }
  }
  final r0 = row - row % bh, c0 = col - col % bw;
  for (var r = r0; r < r0 + bh; r++) {
    for (var c = c0; c < c0 + bw; c++) {
      if (grid[r * size + c] == value) return false;
    }
  }
  return true;
}

bool _fill(List<int> grid, int size, math.Random rng) {
  final i = grid.indexOf(0);
  if (i < 0) return true;
  final values = [for (var v = 1; v <= size; v++) v]..shuffle(rng);
  for (final v in values) {
    if (sudokuAllowed(grid, size, i, v)) {
      grid[i] = v;
      if (_fill(grid, size, rng)) return true;
      grid[i] = 0;
    }
  }
  return false;
}

/// Solutions of [grid], counted up to [limit].
int _countSolutions(List<int> grid, int size, int limit) {
  final i = grid.indexOf(0);
  if (i < 0) return 1;
  var count = 0;
  for (var v = 1; v <= size && count < limit; v++) {
    if (sudokuAllowed(grid, size, i, v)) {
      grid[i] = v;
      count += _countSolutions(grid, size, limit - count);
      grid[i] = 0;
    }
  }
  return count;
}

@immutable
class SudokuPuzzle {
  const SudokuPuzzle(this.size, this.puzzle, this.solution);
  final int size;

  /// 0 for an empty cell.
  final List<int> puzzle;
  final List<int> solution;
}

/// A puzzle with exactly one solution. [blanks] is how many cells to try
/// to empty (fewer if emptying more would allow a second solution).
SudokuPuzzle makeSudoku(int size, int blanks, math.Random rng) {
  final solution = List<int>.filled(size * size, 0);
  _fill(solution, size, rng);
  final puzzle = [...solution];
  final order = [for (var i = 0; i < size * size; i++) i]..shuffle(rng);
  var removed = 0;
  for (final i in order) {
    if (removed >= blanks) break;
    final keep = puzzle[i];
    puzzle[i] = 0;
    if (_countSolutions([...puzzle], size, 2) == 1) {
      removed++;
    } else {
      puzzle[i] = keep;
    }
  }
  return SudokuPuzzle(size, puzzle, solution);
}

// ── Maze ─────────────────────────────────────────────────────────────────

/// A perfect maze: every cell reachable by exactly one path. Walls per
/// cell as bits: 1 north, 2 east, 4 south, 8 west.
@immutable
class Maze {
  const Maze(this.width, this.height, this.walls);
  final int width;
  final int height;
  final List<int> walls;

  bool open(int x, int y, int dx, int dy) {
    final bit = switch ((dx, dy)) {
      (0, -1) => 1,
      (1, 0) => 2,
      (0, 1) => 4,
      _ => 8,
    };
    return walls[y * width + x] & bit == 0;
  }
}

Maze makeMaze(int width, int height, math.Random rng) {
  final walls = List<int>.filled(width * height, 15);
  final seen = List<bool>.filled(width * height, false);
  final stack = <int>[0];
  seen[0] = true;
  const dirs = [(0, -1, 1, 4), (1, 0, 2, 8), (0, 1, 4, 1), (-1, 0, 8, 2)];
  while (stack.isNotEmpty) {
    final cell = stack.last;
    final x = cell % width, y = cell ~/ width;
    final options = [
      for (final d in dirs)
        if (x + d.$1 >= 0 &&
            x + d.$1 < width &&
            y + d.$2 >= 0 &&
            y + d.$2 < height &&
            !seen[(y + d.$2) * width + x + d.$1])
          d,
    ];
    if (options.isEmpty) {
      stack.removeLast();
      continue;
    }
    final d = options[rng.nextInt(options.length)];
    final next = (y + d.$2) * width + x + d.$1;
    walls[cell] &= ~d.$3;
    walls[next] &= ~d.$4;
    seen[next] = true;
    stack.add(next);
  }
  return Maze(width, height, walls);
}

// ── Word Search ──────────────────────────────────────────────────────────

const kidsWordThemes = <String, List<String>>{
  'Animals': ['TIGER', 'ZEBRA', 'PANDA', 'KOALA', 'EAGLE', 'SHARK', 'OTTER', 'CAMEL', 'HORSE', 'MOUSE', 'WHALE', 'SLOTH'],
  'Space': ['PLANET', 'ROCKET', 'COMET', 'ORBIT', 'MOON', 'STAR', 'MARS', 'GALAXY', 'SATURN', 'ALIEN'],
  'Food': ['PIZZA', 'APPLE', 'MANGO', 'BREAD', 'PASTA', 'TACO', 'CURRY', 'GRAPE', 'HONEY', 'LEMON'],
  'Sports': ['SOCCER', 'TENNIS', 'HOCKEY', 'GOLF', 'RUGBY', 'SKATE', 'SWIM', 'CHESS', 'KARATE', 'CRICKET'],
};

@immutable
class WordSearch {
  const WordSearch(this.size, this.letters, this.words, this.places);
  final int size;
  final List<String> letters;
  final List<String> words;

  /// Each word's cells, in order.
  final Map<String, List<int>> places;
}

/// [count] words from [pool] hidden across, down and diagonally (never
/// backwards: kind to young readers) in a [size]×[size] grid.
WordSearch makeWordSearch(
  List<String> pool,
  int size,
  int count,
  math.Random rng,
) {
  const dirs = [(1, 0), (0, 1), (1, 1)];
  for (var attempt = 0; attempt < 50; attempt++) {
    final grid = List<String>.filled(size * size, '');
    final places = <String, List<int>>{};
    final words = ([...pool]..shuffle(rng))
        .where((w) => w.length <= size)
        .take(count)
        .toList();
    var ok = true;
    for (final word in words) {
      var placed = false;
      for (var tries = 0; tries < 200 && !placed; tries++) {
        final (dx, dy) = dirs[rng.nextInt(dirs.length)];
        final x0 = rng.nextInt(size - (dx * (word.length - 1)));
        final y0 = rng.nextInt(size - (dy * (word.length - 1)));
        final cells = [
          for (var i = 0; i < word.length; i++) (y0 + dy * i) * size + x0 + dx * i,
        ];
        if ([
          for (var i = 0; i < word.length; i++)
            grid[cells[i]].isEmpty || grid[cells[i]] == word[i],
        ].every((e) => e)) {
          for (var i = 0; i < word.length; i++) {
            grid[cells[i]] = word[i];
          }
          places[word] = cells;
          placed = true;
        }
      }
      if (!placed) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;
    const abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    for (var i = 0; i < grid.length; i++) {
      if (grid[i].isEmpty) grid[i] = abc[rng.nextInt(26)];
    }
    return WordSearch(size, grid, words, places);
  }
  throw StateError('could not place the words');
}

/// The cells on the straight line from [a] to [b] (across, down or
/// diagonal), or empty when they are not on one line.
List<int> wordSearchLine(int size, int a, int b) {
  final ax = a % size, ay = a ~/ size, bx = b % size, by = b ~/ size;
  final dx = (bx - ax).sign, dy = (by - ay).sign;
  final steps = math.max((bx - ax).abs(), (by - ay).abs());
  if (!(ax == bx || ay == by || (bx - ax).abs() == (by - ay).abs())) {
    return const [];
  }
  return [for (var i = 0; i <= steps; i++) (ay + dy * i) * size + ax + dx * i];
}

// ── Word Guess ───────────────────────────────────────────────────────────

const kidsGuessWords = [
  'BUTTERFLY', 'VOLCANO', 'PENGUIN', 'RAINBOW', 'DINOSAUR', 'TREASURE',
  'PYRAMID', 'ELEPHANT', 'KANGAROO', 'LIBRARY', 'BLANKET', 'PUMPKIN',
  'DOLPHIN', 'JUNGLE', 'CASTLE', 'GIRAFFE', 'MAGNET', 'PLANET', 'ROBOT',
  'SANDWICH', 'TORNADO', 'UMBRELLA', 'WIZARD', 'ASTRONAUT', 'BICYCLE',
  'CHOCOLATE', 'FIREWORKS', 'HELICOPTER', 'OCTOPUS', 'SNOWFLAKE',
];

/// [word] with unguessed letters as underscores.
String maskedWord(String word, Set<String> guessed) =>
    [for (final ch in word.split('')) guessed.contains(ch) ? ch : '_'].join(' ');

// ── Tic-Tac-Toe ──────────────────────────────────────────────────────────

const _lines = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8],
  [0, 3, 6], [1, 4, 7], [2, 5, 8],
  [0, 4, 8], [2, 4, 6],
];

/// 'X' or 'O' when a line is complete, 'draw' when full, null otherwise.
String? tttWinner(List<String> b) {
  for (final l in _lines) {
    if (b[l[0]].isNotEmpty && b[l[0]] == b[l[1]] && b[l[1]] == b[l[2]]) {
      return b[l[0]];
    }
  }
  return b.every((c) => c.isNotEmpty) ? 'draw' : null;
}

/// The winning line's cells, or null.
List<int>? tttLine(List<String> b) {
  for (final l in _lines) {
    if (b[l[0]].isNotEmpty && b[l[0]] == b[l[1]] && b[l[1]] == b[l[2]]) {
      return l;
    }
  }
  return null;
}

int _minimax(List<String> b, bool oTurn) {
  final w = tttWinner(b);
  if (w == 'O') return 1;
  if (w == 'X') return -1;
  if (w == 'draw') return 0;
  var best = oTurn ? -2 : 2;
  for (var i = 0; i < 9; i++) {
    if (b[i].isNotEmpty) continue;
    b[i] = oTurn ? 'O' : 'X';
    final s = _minimax(b, !oTurn);
    b[i] = '';
    best = oTurn ? math.max(best, s) : math.min(best, s);
  }
  return best;
}

/// The computer's move as O. [hard] plays perfectly; otherwise it wins or
/// blocks when it sees it and is random a third of the time.
int tttMove(List<String> board, bool hard, math.Random rng) {
  final free = [for (var i = 0; i < 9; i++) if (board[i].isEmpty) i];
  if (!hard) {
    for (final mark in ['O', 'X']) {
      for (final i in free) {
        final b = [...board]..[i] = mark;
        if (tttWinner(b) == mark) return i;
      }
    }
    if (rng.nextInt(3) == 0) return free[rng.nextInt(free.length)];
  }
  var best = -3, move = free.first;
  for (final i in free..shuffle(rng)) {
    final b = [...board]..[i] = 'O';
    final s = _minimax(b, false);
    if (s > best) {
      best = s;
      move = i;
    }
  }
  return move;
}

// ── Pixel Paint ──────────────────────────────────────────────────────────

/// Pixel pictures to colour by number: rows of palette indexes, 0 blank.
const kidsPixelArt = <String, (List<int>, List<String>)>{
  'Heart': (
    [0xFFFFFFFF, 0xFFE0303C, 0xFFFF7A8A],
    [
      '0110001100',
      '1221011221',
      '1222112221',
      '1222222221',
      '0122222210',
      '0012222100',
      '0001221000',
      '0000110000',
    ],
  ),
  'Rocket': (
    [0xFFFFFFFF, 0xFF5B6CFF, 0xFFE0E4F0, 0xFFF28A1E, 0xFFE0303C],
    [
      '0000110000',
      '0001221000',
      '0012222100',
      '0012112100',
      '0012222100',
      '0112222110',
      '1212222121',
      '1100440011',
      '0003443000',
      '0000330000',
    ],
  ),
  'Cat': (
    [0xFFFFFFFF, 0xFF3E3A35, 0xFFF2A65A, 0xFF7BD389],
    [
      '1000000001',
      '1100000011',
      '1211111121',
      '1222222221',
      '1232222321',
      '1222222221',
      '1222112221',
      '0122222210',
      '0011111100',
    ],
  ),
  'Tree': (
    [0xFFFFFFFF, 0xFF1F8A4C, 0xFF52D69F, 0xFF8B5A2B, 0xFFE0303C],
    [
      '0000110000',
      '0001221000',
      '0012242100',
      '0122222210',
      '0012422100',
      '0122222410',
      '1222222221',
      '0000330000',
      '0000330000',
    ],
  ),
};

// ── Daily Challenge ──────────────────────────────────────────────────────

@immutable
class DailyChallenge {
  const DailyChallenge(this.game, this.title, this.target, this.text, {this.lowerIsBetter = false});

  /// The score key the result arrives under (KidsScores.offer).
  final String game;
  final String title;
  final int target;
  final String text;
  final bool lowerIsBetter;

  bool met(int score) => lowerIsBetter ? score <= target : score >= target;
}

const _challenges = [
  DailyChallenge('math', 'Math Blitz', 15, 'Solve 15 in Math Blitz'),
  DailyChallenge('times', 'Times Tables', 16, 'Get 16 of 20 right in Times Tables'),
  DailyChallenge('clock', 'Telling the Time', 8, 'Read 8 clocks right'),
  DailyChallenge('flags', 'Flag Quiz', 8, 'Name 8 flags'),
  DailyChallenge('patterns', 'Patterns', 7, 'Crack 7 patterns'),
  DailyChallenge('words', 'Word Scramble', 40, 'Score 40 in Word Scramble'),
  DailyChallenge('snake', 'Snake', 12, 'Grow your snake to 12'),
  DailyChallenge('simon', 'Simon Says', 7, 'Remember 7 in Simon Says'),
  DailyChallenge('maze', 'Maze', 60, 'Escape a maze in under a minute', lowerIsBetter: true),
  DailyChallenge('memory', 'Memory Pro', 45, 'Match all pairs in 45 seconds', lowerIsBetter: true),
];

/// The same challenge for everyone all day, a new one each day.
DailyChallenge dailyChallenge(DateTime day) {
  final n = DateTime.utc(day.year, day.month, day.day)
      .difference(DateTime.utc(2024))
      .inDays;
  return _challenges[n % _challenges.length];
}

// ── Sound ────────────────────────────────────────────────────────────────

/// A short tone as a 16-bit mono WAV: a sine with a soft attack and decay,
/// so a quick run of notes does not click.
Uint8List toneWav(double frequency, {int millis = 450, int rate = 22050}) {
  final samples = rate * millis ~/ 1000;
  final data = ByteData(44 + samples * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  final attack = rate * 0.01;
  for (var i = 0; i < samples; i++) {
    final env = math.min(1.0, i / attack) * math.exp(-3.0 * i / samples);
    final t = i / rate;
    // A touch of the octave makes it sound like a toy piano, not a beep.
    final v = math.sin(2 * math.pi * frequency * t) * 0.8 +
        math.sin(4 * math.pi * frequency * t) * 0.2;
    data.setInt16(44 + i * 2, (v * env * 0.6 * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// The C major scale from middle C, two octaves: the piano's keys.
const kidsPianoNotes = <(String, double)>[
  ('C', 261.63), ('D', 293.66), ('E', 329.63), ('F', 349.23),
  ('G', 392.00), ('A', 440.00), ('B', 493.88), ('C', 523.25),
  ('D', 587.33), ('E', 659.25), ('F', 698.46), ('G', 783.99),
  ('A', 880.00), ('B', 987.77), ('C', 1046.50),
];
