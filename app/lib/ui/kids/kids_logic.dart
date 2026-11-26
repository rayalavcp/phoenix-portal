import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kids_more_logic.dart';

/// The rules of the Kids Portal games, kept apart from their widgets so they
/// are unit-tested (test/kids_logic_test.dart). No Flutter UI in here.

// ── Scores and stars ───────────────────────────────────────────────────

/// Best scores per game and today's stars, kept on the device.
abstract final class KidsScores {
  static const _bestPrefix = 'phx.kids.best.';
  static const _starsKey = 'phx.kids.stars';

  /// Bumps whenever a best or today's stars change, so the home redraws.
  static final changes = ValueNotifier<int>(0);

  static String _today(DateTime now) =>
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  static Future<int?> best(String game) async =>
      (await SharedPreferences.getInstance()).getInt('$_bestPrefix$game');

  /// Record [score]; returns true for a new best. [lowerIsBetter] for times.
  /// A score that makes [game]'s top ten also waits in [pendingEntry] for
  /// the player's name, arcade style (the Kids Portal asks for it).
  static Future<bool> offer(String game, int score, {bool lowerIsBetter = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final board = await leaderboard(game);
    final place = boardPlace(board, score, lowerIsBetter: lowerIsBetter);
    if (place != null && score > 0) {
      pendingEntry.value = (game: game, score: score, lowerIsBetter: lowerIsBetter, place: place);
    }
    final old = prefs.getInt('$_bestPrefix$game');
    final better = old == null || (lowerIsBetter ? score < old : score > old);
    if (better) {
      await prefs.setInt('$_bestPrefix$game', score);
      changes.value++;
    }
    return better;
  }

  // ── Leaderboard ──────────────────────────────────────────────────────

  static const boardPrefix = 'phx.kids.board.';
  static const _namesKey = 'phx.kids.names';

  /// How many names each game's leaderboard keeps.
  static const boardSize = 10;

  /// A score that made a top ten and waits for a name (null: none).
  static final pendingEntry = ValueNotifier<({String game, int score, bool lowerIsBetter, int place})?>(null);

  /// [game]'s leaderboard, best first.
  static Future<List<KidsBoardEntry>> leaderboard(String game) async {
    final raw = (await SharedPreferences.getInstance()).getString('$boardPrefix$game');
    if (raw == null) return const [];
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return [for (final e in data['e'] as List) KidsBoardEntry.fromJson(e as Map<String, dynamic>)];
    } catch (_) {
      return const [];
    }
  }

  /// Whether [game]'s leaderboard counts lower scores as better (times).
  static Future<bool> boardLowerIsBetter(String game) async {
    final raw = (await SharedPreferences.getInstance()).getString('$boardPrefix$game');
    if (raw == null) return false;
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)['low'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Every game with a leaderboard.
  static Future<List<String>> boardGames() async => [
    for (final k in (await SharedPreferences.getInstance()).getKeys())
      if (k.startsWith(boardPrefix)) k.substring(boardPrefix.length),
  ]..sort();

  /// Puts [name] on [game]'s leaderboard with [score]; returns its place
  /// (1 = top), or null when it did not make the cut.
  static Future<int?> addToBoard(String game, int score, String name, {bool lowerIsBetter = false, DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final entry = KidsBoardEntry(name.trim().isEmpty ? 'Player' : name.trim(), score, now ?? DateTime.now());
    final next = boardInsert(await leaderboard(game), entry, lowerIsBetter: lowerIsBetter);
    await prefs.setString(
      '$boardPrefix$game',
      jsonEncode({'low': lowerIsBetter, 'e': [for (final e in next) e.toJson()]}),
    );
    // The names used, newest first, for quick picks next time.
    final names = [entry.name, ...(prefs.getStringList(_namesKey) ?? const []).where((n) => n != entry.name)].take(8).toList();
    await prefs.setStringList(_namesKey, names);
    changes.value++;
    final i = next.indexOf(entry);
    return i < 0 ? null : i + 1;
  }

  /// Names typed before, newest first.
  static Future<List<String>> recentNames() async => (await SharedPreferences.getInstance()).getStringList(_namesKey) ?? const [];

  static Future<int> starsToday({DateTime? now}) async {
    final raw = (await SharedPreferences.getInstance()).getString(_starsKey) ?? '';
    final parts = raw.split(':');
    return parts.length == 2 && parts[0] == _today(now ?? DateTime.now()) ? int.tryParse(parts[1]) ?? 0 : 0;
  }

  static const _challengeKey = 'phx.kids.challenge_done';

  /// Whether today's challenge (kids_more_logic.dart) is already won.
  static Future<bool> challengeDone({DateTime? now}) async =>
      (await SharedPreferences.getInstance()).getString(_challengeKey) ==
      _today(now ?? DateTime.now());

  /// A finished round of [game]: when it is today's challenge and [score]
  /// meets it, three bonus stars, once a day. True when this won it.
  static Future<bool> offerChallenge(String game, int score, {DateTime? now}) async {
    final day = now ?? DateTime.now();
    final challenge = dailyChallenge(day);
    if (challenge.game != game || !challenge.met(score)) return false;
    if (await challengeDone(now: day)) return false;
    await (await SharedPreferences.getInstance()).setString(_challengeKey, _today(day));
    await addStars(3, now: day);
    return true;
  }

  static Future<void> addStars(int stars, {DateTime? now}) async {
    if (stars <= 0) return;
    final total = await starsToday(now: now) + stars;
    await (await SharedPreferences.getInstance()).setString(_starsKey, '${_today(now ?? DateTime.now())}:$total');
    changes.value++;
  }
}

// ── Leaderboard entries ─────────────────────────────────────────────────

/// One name on a game's leaderboard.
@immutable
class KidsBoardEntry {
  const KidsBoardEntry(this.name, this.score, this.when);
  final String name;
  final int score;
  final DateTime when;

  factory KidsBoardEntry.fromJson(Map<String, dynamic> j) =>
      KidsBoardEntry('${j['n'] ?? 'Player'}', (j['s'] as num?)?.toInt() ?? 0, DateTime.fromMillisecondsSinceEpoch((j['t'] as num?)?.toInt() ?? 0));

  Map<String, Object> toJson() => {'n': name, 's': score, 't': when.millisecondsSinceEpoch};
}

/// Where [score] would land on [board] (1 = top), or null when it would
/// not make the top [KidsScores.boardSize]. A tie goes below the earlier
/// score, as on an arcade machine.
int? boardPlace(List<KidsBoardEntry> board, int score, {bool lowerIsBetter = false}) {
  var place = 1;
  for (final e in board) {
    final ahead = lowerIsBetter ? e.score <= score : e.score >= score;
    if (ahead) place++;
  }
  return place <= KidsScores.boardSize ? place : null;
}

/// [board] with [entry] put in its place, cut to the top ten.
List<KidsBoardEntry> boardInsert(List<KidsBoardEntry> board, KidsBoardEntry entry, {bool lowerIsBetter = false}) {
  final place = boardPlace(board, entry.score, lowerIsBetter: lowerIsBetter);
  if (place == null) return board;
  return [...board.take(place - 1), entry, ...board.skip(place - 1)].take(KidsScores.boardSize).toList();
}

// ── Math Blitz ─────────────────────────────────────────────────────────

@immutable
class MathProblem {
  const MathProblem(this.text, this.answer, this.choices);
  final String text;
  final int answer;
  final List<int> choices;
}

/// The level for a running score: a new level every five right answers.
int mathLevel(int score) => 1 + score ~/ 5;

/// A problem for [level], with the answer and three near-miss choices.
/// Level 1: + and − within 20. 2: adds 2–5 times tables. 3: tables to 10
/// and division. 4+: tables to 12, + and − to 100.
MathProblem mathProblem(int level, math.Random rng) {
  int r(int lo, int hi) => lo + rng.nextInt(hi - lo + 1);
  final ops = <String>[
    '+', '−',
    if (level >= 2) '×',
    if (level >= 3) '÷',
  ];
  final op = ops[rng.nextInt(ops.length)];
  final big = level >= 4;
  final tables = level >= 4 ? 12 : (level >= 3 ? 10 : 5);
  late int a, b, answer;
  switch (op) {
    case '+':
      a = r(1, big ? 60 : 12);
      b = r(1, big ? 40 : 8);
      answer = a + b;
    case '−':
      a = r(5, big ? 99 : 20);
      b = r(1, a);
      answer = a - b;
    case '×':
      a = r(2, tables);
      b = r(2, tables);
      answer = a * b;
    default: // ÷, always a whole answer
      b = r(2, tables);
      answer = r(2, tables);
      a = b * answer;
  }
  final choices = <int>{answer};
  final spread = math.max(3, answer ~/ 5);
  while (choices.length < 4) {
    final c = answer + r(-spread, spread);
    if (c >= 0 && c != answer) choices.add(c);
  }
  final list = choices.toList()..shuffle(rng);
  return MathProblem('$a $op $b', answer, list);
}

// ── Word Scramble ──────────────────────────────────────────────────────

/// Themed words for school-age children, 4 to 8 letters.
const scrambleWords = <String, List<String>>{
  'Animals': ['TIGER', 'ZEBRA', 'PANDA', 'KOALA', 'OTTER', 'EAGLE', 'SHARK', 'RABBIT', 'GIRAFFE', 'DOLPHIN', 'PENGUIN', 'TURTLE', 'MONKEY', 'BEAVER', 'CHEETAH', 'LIZARD', 'HAMSTER', 'OCTOPUS', 'LOBSTER', 'BUFFALO'],
  'Space': ['MOON', 'STAR', 'COMET', 'ORBIT', 'PLANET', 'ROCKET', 'GALAXY', 'METEOR', 'SATURN', 'JUPITER', 'NEBULA', 'ASTEROID', 'GRAVITY', 'ECLIPSE', 'COSMOS', 'MARS', 'VENUS', 'SHUTTLE', 'CRATER', 'SOLAR'],
  'Sports': ['SOCCER', 'TENNIS', 'HOCKEY', 'KARATE', 'SKATING', 'CRICKET', 'BOXING', 'ARCHERY', 'CYCLING', 'SURFING', 'GOLF', 'RUGBY', 'SKIING', 'ROWING', 'DIVING', 'BASEBALL', 'FENCING', 'JUDO', 'RELAY', 'SPRINT'],
  'Science': ['ATOM', 'MAGNET', 'ENERGY', 'FOSSIL', 'VOLCANO', 'CRYSTAL', 'PLASMA', 'OXYGEN', 'CARBON', 'MATTER', 'NEURON', 'ROBOT', 'LASER', 'THEORY', 'GENE', 'SPECIES', 'CLIMATE', 'MINERAL', 'BATTERY', 'CIRCUIT'],
};

/// [word]'s letters in an order that is not the word itself.
List<String> scramble(String word, math.Random rng) {
  final letters = word.split('');
  if (letters.toSet().length < 2) return letters;
  do {
    letters.shuffle(rng);
  } while (letters.join() == word);
  return letters;
}

// ── 2048 ───────────────────────────────────────────────────────────────

enum Dir { left, right, up, down }

@immutable
class SlideResult {
  const SlideResult(this.board, this.gained, this.moved);
  final List<List<int>> board;
  final int gained;
  final bool moved;
}

/// Slide one row toward index 0, merging equal neighbours once.
(List<int>, int) slideRow(List<int> row) {
  final tiles = row.where((v) => v != 0).toList();
  final out = <int>[];
  var gained = 0;
  for (var i = 0; i < tiles.length; i++) {
    if (i + 1 < tiles.length && tiles[i] == tiles[i + 1]) {
      out.add(tiles[i] * 2);
      gained += tiles[i] * 2;
      i++;
    } else {
      out.add(tiles[i]);
    }
  }
  while (out.length < row.length) {
    out.add(0);
  }
  return (out, gained);
}

/// Move the whole board in [dir].
SlideResult slideBoard(List<List<int>> board, Dir dir) {
  final n = board.length;
  List<int> line(int i) => switch (dir) {
    Dir.left => [for (var c = 0; c < n; c++) board[i][c]],
    Dir.right => [for (var c = n - 1; c >= 0; c--) board[i][c]],
    Dir.up => [for (var r = 0; r < n; r++) board[r][i]],
    Dir.down => [for (var r = n - 1; r >= 0; r--) board[r][i]],
  };
  final out = List.generate(n, (_) => List.filled(n, 0));
  var gained = 0;
  for (var i = 0; i < n; i++) {
    final (row, g) = slideRow(line(i));
    gained += g;
    for (var k = 0; k < n; k++) {
      switch (dir) {
        case Dir.left:
          out[i][k] = row[k];
        case Dir.right:
          out[i][n - 1 - k] = row[k];
        case Dir.up:
          out[k][i] = row[k];
        case Dir.down:
          out[n - 1 - k][i] = row[k];
      }
    }
  }
  var moved = false;
  for (var r = 0; r < n && !moved; r++) {
    for (var c = 0; c < n; c++) {
      if (out[r][c] != board[r][c]) {
        moved = true;
        break;
      }
    }
  }
  return SlideResult(out, gained, moved);
}

bool canMove(List<List<int>> board) => Dir.values.any((d) => slideBoard(board, d).moved);

/// Put a 2 (90%) or 4 on a random empty cell; returns the cell or null.
(int, int)? spawnTile(List<List<int>> board, math.Random rng) {
  final empty = [
    for (var r = 0; r < board.length; r++)
      for (var c = 0; c < board.length; c++)
        if (board[r][c] == 0) (r, c),
  ];
  if (empty.isEmpty) return null;
  final (r, c) = empty[rng.nextInt(empty.length)];
  board[r][c] = rng.nextDouble() < 0.9 ? 2 : 4;
  return (r, c);
}

// ── Connect Four ───────────────────────────────────────────────────────

const c4Cols = 7, c4Rows = 6;

/// A Connect Four board: [cells][row][col], row 0 at the top; 0 empty, 1
/// the player, 2 the computer.
class C4 {
  C4() : cells = List.generate(c4Rows, (_) => List.filled(c4Cols, 0));
  C4._(this.cells);

  final List<List<int>> cells;

  C4 copy() => C4._([for (final r in cells) List.of(r)]);

  bool canDrop(int col) => cells[0][col] == 0;

  /// Drop a piece; returns the row it landed in, or null for a full column.
  int? drop(int col, int who) {
    for (var r = c4Rows - 1; r >= 0; r--) {
      if (cells[r][col] == 0) {
        cells[r][col] = who;
        return r;
      }
    }
    return null;
  }

  bool get full => List.generate(c4Cols, canDrop).every((ok) => !ok);

  /// The four winning cells, or null.
  List<(int, int)>? winLine() {
    const dirs = [(0, 1), (1, 0), (1, 1), (1, -1)];
    for (var r = 0; r < c4Rows; r++) {
      for (var c = 0; c < c4Cols; c++) {
        final who = cells[r][c];
        if (who == 0) continue;
        for (final (dr, dc) in dirs) {
          final line = [for (var k = 0; k < 4; k++) (r + dr * k, c + dc * k)];
          if (line.every((p) => p.$1 >= 0 && p.$1 < c4Rows && p.$2 >= 0 && p.$2 < c4Cols && cells[p.$1][p.$2] == who)) {
            return line;
          }
        }
      }
    }
    return null;
  }

  int? get winner {
    final line = winLine();
    return line == null ? null : cells[line.first.$1][line.first.$2];
  }
}

int _windowScore(List<int> w, int me) {
  final mine = w.where((v) => v == me).length;
  final theirs = w.where((v) => v == 3 - me).length;
  final empty = w.where((v) => v == 0).length;
  if (mine == 4) return 1000;
  if (mine == 3 && empty == 1) return 6;
  if (mine == 2 && empty == 2) return 2;
  if (theirs == 3 && empty == 1) return -8;
  return 0;
}

int _evaluate(C4 b, int me) {
  var score = 0;
  for (var r = 0; r < c4Rows; r++) {
    if (b.cells[r][3] == me) score += 3; // the centre column is worth most
  }
  for (var r = 0; r < c4Rows; r++) {
    for (var c = 0; c < c4Cols; c++) {
      if (c + 3 < c4Cols) score += _windowScore([for (var k = 0; k < 4; k++) b.cells[r][c + k]], me);
      if (r + 3 < c4Rows) score += _windowScore([for (var k = 0; k < 4; k++) b.cells[r + k][c]], me);
      if (r + 3 < c4Rows && c + 3 < c4Cols) score += _windowScore([for (var k = 0; k < 4; k++) b.cells[r + k][c + k]], me);
      if (r + 3 < c4Rows && c - 3 >= 0) score += _windowScore([for (var k = 0; k < 4; k++) b.cells[r + k][c - k]], me);
    }
  }
  return score;
}

int _minimax(C4 b, int depth, int alpha, int beta, bool maximizing) {
  final w = b.winner;
  if (w == 2) return 100000 + depth;
  if (w == 1) return -100000 - depth;
  if (depth == 0 || b.full) return _evaluate(b, 2);
  const order = [3, 2, 4, 1, 5, 0, 6];
  if (maximizing) {
    var best = -1 << 30;
    for (final c in order) {
      if (!b.canDrop(c)) continue;
      final n = b.copy()..drop(c, 2);
      best = math.max(best, _minimax(n, depth - 1, alpha, beta, false));
      alpha = math.max(alpha, best);
      if (alpha >= beta) break;
    }
    return best;
  }
  var best = 1 << 30;
  for (final c in order) {
    if (!b.canDrop(c)) continue;
    final n = b.copy()..drop(c, 1);
    best = math.min(best, _minimax(n, depth - 1, alpha, beta, true));
    beta = math.min(beta, best);
    if (alpha >= beta) break;
  }
  return best;
}

/// The computer's column. Hard looks five moves ahead; easy two, with a
/// little randomness so it can be beaten.
int c4AiMove(C4 board, {required bool hard, math.Random? rng}) {
  final random = rng ?? math.Random();
  final depth = hard ? 5 : 2;
  var bestScore = -1 << 30;
  final best = <int>[];
  for (var c = 0; c < c4Cols; c++) {
    if (!board.canDrop(c)) continue;
    final n = board.copy()..drop(c, 2);
    var s = _minimax(n, depth - 1, -1 << 30, 1 << 30, false);
    if (!hard) s += random.nextInt(6);
    if (s > bestScore) {
      bestScore = s;
      best
        ..clear()
        ..add(c);
    } else if (s == bestScore) {
      best.add(c);
    }
  }
  return best.isEmpty ? 3 : best[random.nextInt(best.length)];
}
