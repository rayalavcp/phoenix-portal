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
  'APPLE', 'TIGER', 'CLOUD', 'HOUSE', 'PIZZA', 'TRAIN', 'BEACH', 'HORSE', 'SPOON', 'GHOST',
  'TELESCOPE', 'DETECTIVE', 'WATERFALL', 'SKATEBOARD', 'BLUEBERRY', 'CROCODILE',
];

// ── Fractions ────────────────────────────────────────────────────────────

/// A fraction question: the picture's parts and shaded parts, the answer
/// as "a/b", and four choices. Level 1 halves to quarters, 2 up to tenths,
/// 3 in simplest form.
@immutable
class FractionQuestion {
  const FractionQuestion(this.parts, this.shaded, this.prompt, this.answer, this.choices);
  final int parts;
  final int shaded;
  final String prompt;
  final String answer;
  final List<String> choices;
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

FractionQuestion fractionQuestion(int level, math.Random rng) {
  final parts = switch (level) {
    <= 1 => [2, 3, 4][rng.nextInt(3)],
    2 => 2 + rng.nextInt(9),
    _ => [4, 6, 8, 9, 10, 12][rng.nextInt(6)],
  };
  final shaded = 1 + rng.nextInt(parts - 1);
  String frac(int a, int b) => '$a/$b';
  final g = _gcd(shaded, parts);
  final answer = level >= 3 ? frac(shaded ~/ g, parts ~/ g) : frac(shaded, parts);
  final choices = <String>{answer};
  for (var guard = 0; choices.length < 4 && guard < 80; guard++) {
    final b = level >= 3 ? 2 + rng.nextInt(10) : math.max(2, parts + rng.nextInt(3) - 1);
    final a = 1 + rng.nextInt(b - 1);
    choices.add(frac(a, b));
  }
  while (choices.length < 4) {
    choices.add(frac(choices.length, choices.length + 5));
  }
  return FractionQuestion(
    parts,
    shaded,
    level >= 3 ? 'What part is shaded? (simplest form)' : 'What part is shaded?',
    answer,
    choices.toList()..shuffle(rng),
  );
}

// ── Money ────────────────────────────────────────────────────────────────

@immutable
class MoneyQuestion {
  const MoneyQuestion(this.coins, this.prompt, this.answer, this.choices);

  /// Coin values in cents, as drawn.
  final List<int> coins;
  final String prompt;
  final String answer;
  final List<String> choices;
}

String cents(int c) => c >= 100 ? '\$${(c / 100).toStringAsFixed(2)}' : '$c¢';

/// Level 1 counts pennies, nickels and dimes; 2 adds quarters; 3 asks for
/// the change from a dollar.
MoneyQuestion moneyQuestion(int level, math.Random rng) {
  final kinds = level <= 1 ? [1, 5, 10] : [1, 5, 10, 25];
  final n = 2 + rng.nextInt(level <= 1 ? 3 : 4);
  final coins = [for (var i = 0; i < n; i++) kinds[rng.nextInt(kinds.length)]]..sort((a, b) => b.compareTo(a));
  while (level >= 3 && coins.fold(0, (a, b) => a + b) >= 100) {
    coins.removeAt(0);
  }
  final total = coins.fold(0, (a, b) => a + b);
  final value = level >= 3 ? 100 - total : total;
  final choices = <int>{value};
  for (var guard = 0; choices.length < 4 && guard < 80; guard++) {
    final off = [1, 5, 10, 15, 25][rng.nextInt(5)] * (rng.nextBool() ? 1 : -1);
    if (value + off > 0) choices.add(value + off);
  }
  return MoneyQuestion(
    coins,
    level >= 3 ? 'You pay one dollar for this. How much change?' : 'How much money is this?',
    cents(value),
    [for (final c in choices.toList()..shuffle(rng)) cents(c)],
  );
}

// ── Science, spelling, opposites ─────────────────────────────────────────

/// (question, answer, three wrong answers) by level.
const kidsScience = <int, List<(String, String, List<String>)>>{
  1: [
    ('What do plants need from the sun?', 'Light', ['Sand', 'Snow', 'Noise']),
    ('Which animal lays eggs?', 'Chicken', ['Dog', 'Cow', 'Cat']),
    ('What is ice made of?', 'Water', ['Milk', 'Glass', 'Salt']),
    ('How many legs does a spider have?', '8', ['6', '4', '10']),
    ('Which is the closest star to Earth?', 'The Sun', ['The Moon', 'Mars', 'Polaris']),
    ('What do bees make?', 'Honey', ['Milk', 'Silk', 'Bread']),
    ('Which sense uses your nose?', 'Smell', ['Taste', 'Touch', 'Hearing']),
    ('What season comes after winter?', 'Spring', ['Summer', 'Fall', 'Autumn']),
    ('Which animal is a mammal?', 'Whale', ['Shark', 'Frog', 'Eagle']),
    ('What gas do we need to breathe?', 'Oxygen', ['Helium', 'Smoke', 'Steam']),
    ('Which planet do we live on?', 'Earth', ['Mars', 'Venus', 'Jupiter']),
    ('What helps a fish breathe?', 'Gills', ['Lungs', 'Fins', 'Scales']),
  ],
  2: [
    ('Which planet is the largest?', 'Jupiter', ['Saturn', 'Earth', 'Neptune']),
    ('What part of a plant makes its food?', 'Leaves', ['Roots', 'Stem', 'Flower']),
    ('Water boils at how many °C?', '100', ['50', '0', '212']),
    ('What force pulls things down to Earth?', 'Gravity', ['Magnetism', 'Friction', 'Wind']),
    ('Which organ pumps blood?', 'Heart', ['Lungs', 'Brain', 'Stomach']),
    ('A caterpillar turns into a…', 'Butterfly', ['Beetle', 'Bee', 'Spider']),
    ('Which of these is a liquid?', 'Juice', ['Rock', 'Steam', 'Wood']),
    ('Animals that eat only plants are…', 'Herbivores', ['Carnivores', 'Omnivores', 'Predators']),
    ('Which planet is called the Red Planet?', 'Mars', ['Venus', 'Mercury', 'Jupiter']),
    ('How many bones does an adult human have?', '206', ['106', '306', '26']),
    ('What do magnets attract?', 'Iron', ['Wood', 'Plastic', 'Glass']),
    ('Which layer of Earth do we live on?', 'Crust', ['Core', 'Mantle', 'Magma']),
  ],
  3: [
    ('What is H₂O?', 'Water', ['Salt', 'Oxygen', 'Hydrogen']),
    ('Plants take in which gas?', 'Carbon dioxide', ['Oxygen', 'Nitrogen', 'Helium']),
    ('What is the center of an atom called?', 'Nucleus', ['Electron', 'Shell', 'Cell']),
    ('Sound travels fastest through…', 'Solids', ['Air', 'Space', 'Gas']),
    ('Which blood cells fight germs?', 'White blood cells', ['Red blood cells', 'Platelets', 'Plasma']),
    ('Water boils at how many °F?', '212', ['100', '180', '32']),
    ('Rock made from cooled lava is…', 'Igneous', ['Sedimentary', 'Metamorphic', 'Fossil']),
    ('Which part of a cell holds DNA?', 'Nucleus', ['Membrane', 'Wall', 'Cytoplasm']),
    ('The Moon shines because it…', 'Reflects sunlight', ['Burns gas', 'Has lamps', 'Is a star']),
    ('Which simple machine is a ramp?', 'Inclined plane', ['Lever', 'Pulley', 'Wheel']),
    ('A scientist who studies rocks is a…', 'Geologist', ['Biologist', 'Chemist', 'Astronomer']),
    ('What is the closest planet to the Sun?', 'Mercury', ['Venus', 'Earth', 'Mars']),
  ],
};

/// (correct spelling, misspellings) by level.
const kidsSpelling = <int, List<(String, List<String>)>>{
  1: [
    ('because', ['becuase', 'becaus', 'beacause']), ('friend', ['freind', 'frend', 'friendd']),
    ('school', ['skool', 'shcool', 'scool']), ('said', ['sed', 'siad', 'sayd']),
    ('their', ['thier', 'theyr', 'thir']), ('people', ['poeple', 'peeple', 'pepole']),
    ('animal', ['animel', 'aminal', 'anemal']), ('water', ['watter', 'wator', 'warter']),
    ('little', ['littel', 'litle', 'lttle']), ('happy', ['hapy', 'happey', 'happie']),
  ],
  2: [
    ('different', ['diffrent', 'diferent', 'differant']), ('beautiful', ['beutiful', 'beautifull', 'butiful']),
    ('library', ['libary', 'liberry', 'librery']), ('February', ['Febuary', 'Februery', 'Febrary']),
    ('separate', ['seperate', 'saparate', 'seprate']), ('surprise', ['suprise', 'surprize', 'serprise']),
    ('believe', ['beleive', 'belive', 'beleeve']), ('neighbor', ['nieghbor', 'nabor', 'naybor']),
    ('calendar', ['calender', 'calandar', 'callendar']), ('favorite', ['favrite', 'faverite', 'favorit']),
  ],
  3: [
    ('necessary', ['neccessary', 'necessery', 'nessecary']), ('definitely', ['definately', 'defiantly', 'definetly']),
    ('rhythm', ['rythm', 'rhythem', 'rhytm']), ('occasion', ['occassion', 'ocasion', 'occation']),
    ('environment', ['enviroment', 'environmant', 'envirnment']), ('government', ['goverment', 'govermant', 'governmint']),
    ('restaurant', ['restaraunt', 'resturant', 'restarant']), ('conscience', ['concience', 'conscence', 'consience']),
    ('embarrass', ['embarass', 'embarras', 'embaress']), ('accommodate', ['accomodate', 'acommodate', 'accomadate']),
  ],
};

/// (word, opposite, three others) by level.
const kidsOpposites = <int, List<(String, String, List<String>)>>{
  1: [
    ('hot', 'cold', ['warm', 'big', 'wet']), ('up', 'down', ['over', 'top', 'high']),
    ('happy', 'sad', ['glad', 'funny', 'kind']), ('big', 'small', ['tall', 'huge', 'wide']),
    ('fast', 'slow', ['quick', 'far', 'loud']), ('day', 'night', ['noon', 'sun', 'week']),
    ('open', 'closed', ['wide', 'empty', 'free']), ('full', 'empty', ['heavy', 'whole', 'big']),
  ],
  2: [
    ('ancient', 'modern', ['old', 'early', 'past']), ('brave', 'afraid', ['bold', 'strong', 'calm']),
    ('generous', 'selfish', ['kind', 'giving', 'rich']), ('include', 'exclude', ['contain', 'add', 'invite']),
    ('arrive', 'depart', ['reach', 'enter', 'stay']), ('victory', 'defeat', ['win', 'trophy', 'game']),
    ('rough', 'smooth', ['hard', 'bumpy', 'tough']), ('increase', 'decrease', ['grow', 'raise', 'add']),
  ],
  3: [
    ('abundant', 'scarce', ['plenty', 'ample', 'large']), ('transparent', 'opaque', ['clear', 'shiny', 'thin']),
    ('optimistic', 'pessimistic', ['hopeful', 'cheerful', 'positive']), ('expand', 'contract', ['grow', 'stretch', 'swell']),
    ('voluntary', 'compulsory', ['optional', 'free', 'willing']), ('minimum', 'maximum', ['least', 'small', 'lowest']),
    ('humble', 'arrogant', ['modest', 'meek', 'shy']), ('temporary', 'permanent', ['brief', 'short', 'passing']),
  ],
};

// ── Lights Out ───────────────────────────────────────────────────────────

/// Press a light and it and its neighbours flip. A puzzle made by pressing
/// random lights on a dark board is always solvable.
List<bool> lightsOutPuzzle(int n, int presses, math.Random rng) {
  final b = List<bool>.filled(n * n, false);
  for (var i = 0; i < presses; i++) {
    lightsOutPress(b, n, rng.nextInt(n * n));
  }
  if (!b.contains(true)) lightsOutPress(b, n, rng.nextInt(n * n));
  return b;
}

void lightsOutPress(List<bool> b, int n, int i) {
  final x = i % n, y = i ~/ n;
  for (final (dx, dy) in const [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]) {
    final nx = x + dx, ny = y + dy;
    if (nx >= 0 && ny >= 0 && nx < n && ny < n) b[ny * n + nx] = !b[ny * n + nx];
  }
}

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

/// 16-bit mono PCM samples (-1..1) as a WAV file.
Uint8List wavBytes(Float64List samples, {int rate = 44100}) {
  final n = samples.length;
  final data = ByteData(44 + n * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + n * 2, Endian.little);
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
  data.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// A short plain tone as a WAV (kept for simple beeps).
Uint8List toneWav(double frequency, {int millis = 450, int rate = 22050}) {
  final n = rate * millis ~/ 1000;
  final out = Float64List(n);
  final attack = rate * 0.01;
  for (var i = 0; i < n; i++) {
    final env = math.min(1.0, i / attack) * math.exp(-3.0 * i / n);
    final t = i / rate;
    out[i] = (math.sin(2 * math.pi * frequency * t) * 0.8 + math.sin(4 * math.pi * frequency * t) * 0.2) * env * 0.6;
  }
  return wavBytes(out, rate: rate);
}

/// The Kids Portal's instruments.
enum KidsInstrument { piano, xylophone, musicBox }

/// One note of [instrument] at [frequency], as samples (-1..1).
///
/// The piano is modelled on a struck string: about a dozen overtones, each
/// slightly sharp (a real string is stiff), the higher ones fading faster;
/// two strings a hair out of tune with each other, which gives a piano its
/// slow shimmer; a soft felt knock at the start; low notes ring longer than
/// high ones. The xylophone is a wooden bar (its overtones are not whole
/// multiples) hit by a hard mallet, the music box a tiny steel comb.
Float64List instrumentNote(double frequency, KidsInstrument instrument, {int rate = 44100}) {
  final rnd = math.Random(frequency.round());
  switch (instrument) {
    case KidsInstrument.piano:
      final seconds = (2.6 - (frequency - 260) / 900).clamp(1.4, 2.6);
      final n = (rate * seconds).round();
      final out = Float64List(n);
      const b = 0.00035; // string stiffness
      final baseDecay = 0.9 + frequency / 520; // per second
      final brightness = (1.25 - frequency / 2600).clamp(0.6, 1.2);
      for (final detune in const [-0.0006, 0.0006]) {
        for (var h = 1; h <= 12; h++) {
          final f = frequency * h * math.sqrt(1 + b * h * h) * (1 + detune);
          if (f > rate / 2.2) break;
          final amp = math.pow(h, -1.6 * (1.3 - brightness * 0.3)).toDouble() * (h == 1 ? 1.0 : 0.9) * (h % 7 == 0 ? 0.3 : 1);
          final decay = baseDecay * (1 + 0.45 * (h - 1));
          final w = 2 * math.pi * f / rate;
          final phase = rnd.nextDouble() * 0.2;
          for (var i = 0; i < n; i++) {
            out[i] += amp * math.sin(w * i + phase) * math.exp(-decay * i / rate);
          }
        }
      }
      // The hammer: a short, dull knock.
      var lp = 0.0;
      final knock = (rate * 0.018).round();
      for (var i = 0; i < knock && i < n; i++) {
        lp += 0.12 * ((rnd.nextDouble() * 2 - 1) - lp);
        out[i] += lp * 0.5 * (1 - i / knock);
      }
      return _shape(out, rate, attackMs: 2.5, releaseMs: 180, peak: 0.62 - (frequency - 260) / 4000);
    case KidsInstrument.xylophone:
      final n = (rate * 1.1).round();
      final out = Float64List(n);
      for (final (ratio, amp, decay) in const [(1.0, 1.0, 4.2), (3.932, 0.35, 11.0), (9.538, 0.12, 22.0)]) {
        final w = 2 * math.pi * frequency * ratio / rate;
        if (frequency * ratio > rate / 2.2) continue;
        for (var i = 0; i < n; i++) {
          out[i] += amp * math.sin(w * i) * math.exp(-decay * i / rate);
        }
      }
      final click = (rate * 0.004).round();
      for (var i = 0; i < click; i++) {
        out[i] += (rnd.nextDouble() * 2 - 1) * 0.35 * (1 - i / click);
      }
      return _shape(out, rate, attackMs: 0.8, releaseMs: 120, peak: 0.6);
    case KidsInstrument.musicBox:
      final n = (rate * 1.8).round();
      final out = Float64List(n);
      for (final (ratio, amp, decay) in const [(1.0, 1.0, 2.2), (2.0, 0.12, 4.0), (5.404, 0.28, 7.5), (8.93, 0.08, 12.0)]) {
        final w = 2 * math.pi * frequency * 2 * ratio / rate; // an octave up: a tiny comb
        if (frequency * 2 * ratio > rate / 2.2) continue;
        for (var i = 0; i < n; i++) {
          out[i] += amp * math.sin(w * i) * math.exp(-decay * i / rate);
        }
      }
      return _shape(out, rate, attackMs: 1, releaseMs: 200, peak: 0.5);
  }
}

/// Soft start and end, scaled to [peak], so notes never click or clip.
Float64List _shape(Float64List out, int rate, {required double attackMs, required double releaseMs, required double peak}) {
  final attack = rate * attackMs / 1000, release = rate * releaseMs / 1000;
  var max = 0.0;
  for (final v in out) {
    if (v.abs() > max) max = v.abs();
  }
  final scale = max == 0 ? 0.0 : peak / max;
  for (var i = 0; i < out.length; i++) {
    final a = i < attack ? i / attack : 1.0;
    final left = out.length - i;
    final r = left < release ? left / release : 1.0;
    out[i] *= scale * a * r;
  }
  return out;
}

/// Two octaves, C4 to C6, every semitone: (name, frequency, black key).
final kidsPianoNotes = <(String, double, bool)>[
  for (var i = 0; i <= 24; i++)
    (
      const ['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'][i % 12],
      261.6256 * math.pow(2, i / 12).toDouble(),
      const [1, 3, 6, 8, 10].contains(i % 12),
    ),
];

/// Songs for the piano: (semitones above C4, beats). Checked against their
/// usual melodies in C (Happy Birthday in F, so it fits the two octaves).
const kidsPianoSongs = <String, List<(int, double)>>{
  'Twinkle Twinkle': [
    (0, 1), (0, 1), (7, 1), (7, 1), (9, 1), (9, 1), (7, 2),
    (5, 1), (5, 1), (4, 1), (4, 1), (2, 1), (2, 1), (0, 2),
  ],
  'Mary Had a Little Lamb': [
    (4, 1), (2, 1), (0, 1), (2, 1), (4, 1), (4, 1), (4, 2),
    (2, 1), (2, 1), (2, 2), (4, 1), (7, 1), (7, 2),
    (4, 1), (2, 1), (0, 1), (2, 1), (4, 1), (4, 1), (4, 1), (4, 1),
    (2, 1), (2, 1), (4, 1), (2, 1), (0, 2),
  ],
  'Row Your Boat': [
    (0, 1.5), (0, 1.5), (0, 1), (2, 0.5), (4, 1.5),
    (4, 1), (2, 0.5), (4, 1), (5, 0.5), (7, 3),
    (12, 0.5), (12, 0.5), (12, 0.5), (7, 0.5), (7, 0.5), (7, 0.5),
    (4, 0.5), (4, 0.5), (4, 0.5), (0, 0.5), (0, 0.5), (0, 0.5),
    (7, 1), (5, 0.5), (4, 1), (2, 0.5), (0, 3),
  ],
  'Ode to Joy': [
    (4, 1), (4, 1), (5, 1), (7, 1), (7, 1), (5, 1), (4, 1), (2, 1),
    (0, 1), (0, 1), (2, 1), (4, 1), (4, 1.5), (2, 0.5), (2, 2),
    (4, 1), (4, 1), (5, 1), (7, 1), (7, 1), (5, 1), (4, 1), (2, 1),
    (0, 1), (0, 1), (2, 1), (4, 1), (2, 1.5), (0, 0.5), (0, 2),
  ],
  'Jingle Bells': [
    (4, 1), (4, 1), (4, 2), (4, 1), (4, 1), (4, 2),
    (4, 1), (7, 1), (0, 1.5), (2, 0.5), (4, 4),
    (5, 1), (5, 1), (5, 1.5), (5, 0.5), (5, 1), (4, 1), (4, 1), (4, 0.5), (4, 0.5),
    (4, 1), (2, 1), (2, 1), (4, 1), (2, 2), (7, 2),
  ],
  'Happy Birthday': [
    (0, 0.75), (0, 0.25), (2, 1), (0, 1), (5, 1), (4, 2),
    (0, 0.75), (0, 0.25), (2, 1), (0, 1), (7, 1), (5, 2),
    (0, 0.75), (0, 0.25), (12, 1), (9, 1), (5, 1), (4, 1), (2, 2),
    (10, 0.75), (10, 0.25), (9, 1), (5, 1), (7, 1), (5, 2),
  ],
  'Old MacDonald': [
    (7, 1), (7, 1), (7, 1), (2, 1), (4, 1), (4, 1), (2, 2),
    (11, 1), (11, 1), (9, 1), (9, 1), (7, 3),
  ],
};
