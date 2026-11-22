import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app_container.dart';
import 'kids_activities.dart';
import 'kids_games.dart';
import 'kids_logic.dart';
import 'kids_motion.dart' show KidsHands;

/// The Kids Portal's Arcade shelf: original retro games. Munch Maze (a maze
/// chase) and Brick Bash (a paddle and bricks). Their own characters, mazes
/// and art: in the spirit of the arcade classics, copies of none.

TextStyle arcadeText(double size, [Color color = Colors.white]) => TextStyle(
  fontFamily: 'VT323',
  fontSize: size,
  color: color,
  letterSpacing: 2,
  shadows: [Shadow(color: color.withValues(alpha: 0.8), blurRadius: 10)],
);

// ── Munch Maze: the rules ─────────────────────────────────────────────────

/// The maze, row by row: '#' wall, '.' seed, 'o' power berry, ' ' open,
/// 'P' where Munchie starts, 'R' where the robots start, '-' the robots'
/// door (robots only). Open ends on a row wrap around.
const munchMaze = [
  '###################',
  '#o.......#.......o#',
  '#.##.###.#.###.##.#',
  '#.................#',
  '#.##.#.#####.#.##.#',
  '#....#...#...#....#',
  '####.###.#.###.####',
  '   #.#.......#.#   ',
  '####.#.##-##.#.####',
  '    ...#RRR#...    ',
  '####.#.#####.#.####',
  '#........P........#',
  '#.##.###.#.###.##.#',
  '#o.#...........#.o#',
  '##.#.#.#####.#.#.##',
  '#....#...#...#....#',
  '#.######.#.######.#',
  '#.................#',
  '###################',
];

enum Dir { up, down, left, right, none }

extension DirMove on Dir {
  int get dx => switch (this) { Dir.left => -1, Dir.right => 1, _ => 0 };
  int get dy => switch (this) { Dir.up => -1, Dir.down => 1, _ => 0 };
  Dir get opposite => switch (this) {
    Dir.up => Dir.down,
    Dir.down => Dir.up,
    Dir.left => Dir.right,
    Dir.right => Dir.left,
    Dir.none => Dir.none,
  };
}

/// The maze as a grid: walls, seeds and berries, the starts.
class MunchBoard {
  MunchBoard(List<String> rows)
      : width = rows.first.length,
        height = rows.length,
        _cells = [for (final r in rows) r.split('')] {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final c = _cells[y][x];
        if (c == 'P') {
          playerStart = (x, y);
          _cells[y][x] = ' ';
        } else if (c == 'R') {
          robotStarts.add((x, y));
          _cells[y][x] = ' ';
        }
      }
    }
  }

  final int width, height;
  final List<List<String>> _cells;
  (int, int) playerStart = (0, 0);
  final robotStarts = <(int, int)>[];

  String at(int x, int y) {
    if (y < 0 || y >= height) return '#';
    return _cells[y][(x + width) % width];
  }

  /// Whether Munchie (or, with [robot], a robot) can stand at [x], [y].
  bool open(int x, int y, {bool robot = false}) {
    final c = at(x, y);
    if (c == '#') return false;
    if (c == '-') return robot;
    return true;
  }

  /// Eats what is at the cell: 10 for a seed, 50 for a berry (and says so).
  ({int points, bool berry}) eat(int x, int y) {
    final xx = (x + width) % width;
    final c = _cells[y][xx];
    if (c == '.') {
      _cells[y][xx] = ' ';
      return (points: 10, berry: false);
    }
    if (c == 'o') {
      _cells[y][xx] = ' ';
      return (points: 50, berry: true);
    }
    return (points: 0, berry: false);
  }

  int get seedsLeft {
    var n = 0;
    for (final row in _cells) {
      for (final c in row) {
        if (c == '.' || c == 'o') n++;
      }
    }
    return n;
  }
}

/// Something that walks the maze a cell at a time: Munchie or a robot.
class Walker {
  Walker(this.x, this.y, {this.dir = Dir.none});
  int x, y; // the cell it is leaving (or standing in)
  Dir dir;
  double t = 0; // 0..1 of the way to the next cell

  double get px => x + dir.dx * t;
  double get py => y + dir.dy * t;
}

/// The robots' choice at a crossing: never straight back unless it must,
/// then the way that ends nearest the target (or, while [flee], farthest).
Dir chooseDir(MunchBoard b, Walker w, (double, double) target, {bool flee = false, math.Random? rng}) {
  final options = [
    for (final d in const [Dir.up, Dir.left, Dir.down, Dir.right])
      if (d != w.dir.opposite && b.open(w.x + d.dx, w.y + d.dy, robot: true)) d,
  ];
  if (options.isEmpty) return w.dir.opposite;
  if (rng != null && rng.nextDouble() < 0.15) return options[rng.nextInt(options.length)];
  double score(Dir d) {
    final dx = w.x + d.dx - target.$1, dy = w.y + d.dy - target.$2;
    return dx * dx + dy * dy;
  }

  options.sort((a, b) => flee ? score(b).compareTo(score(a)) : score(a).compareTo(score(b)));
  return options.first;
}

// ── Munch Maze: the game ──────────────────────────────────────────────────

class MunchMaze extends StatefulWidget {
  const MunchMaze({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<MunchMaze> createState() => _MunchMazeState();
}

class _Robot extends Walker {
  _Robot(super.x, super.y, this.color, this.wait);
  final Color color;
  double wait; // seconds before it leaves home
  bool eaten = false;
}

class _MunchMazeState extends State<MunchMaze> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  final _rng = math.Random();
  late MunchBoard _board;
  late Walker _me;
  final _robots = <_Robot>[];
  Dir _wanted = Dir.none;
  Duration _last = Duration.zero;
  double _time = 0, _scared = 0, _hurt = 0;
  int _level = 0, _stage = 1, _score = 0, _lives = 3, _combo = 0;
  bool _playing = false, _over = false, _newBest = false;

  static const _robotColors = [Color(0xFFFF4D6D), Color(0xFF39D0FF), Color(0xFFFFB627)];

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _newBoard() {
    _board = MunchBoard(munchMaze);
    _resetPositions();
  }

  void _resetPositions() {
    final (px, py) = _board.playerStart;
    _me = Walker(px, py, dir: Dir.left);
    _wanted = Dir.left;
    _robots
      ..clear()
      ..addAll([
        for (var i = 0; i < _board.robotStarts.length; i++)
          _Robot(_board.robotStarts[i].$1, _board.robotStarts[i].$2, _robotColors[i % 3], 1.0 + i * 3.0),
      ]);
    _scared = 0;
    _hurt = 1.2; // a moment to get ready
  }

  void _start() {
    setState(() {
      _score = 0;
      _lives = 3;
      _stage = 1;
      _time = 0;
      _playing = true;
      _over = false;
      _last = Duration.zero;
      _newBoard();
    });
    _ticker.start();
  }

  Future<void> _finish() async {
    _ticker.stop();
    final key = 'munch${_level + 1}';
    final best = await KidsScores.offer(key, _score);
    await KidsScores.addStars(_score >= 3000 ? 3 : (_score >= 1500 ? 2 : (_score >= 500 ? 1 : 0)));
    if (mounted) {
      setState(() {
        _playing = false;
        _over = true;
        _newBest = best;
      });
    }
  }

  void _steer(Dir d) {
    _wanted = d;
    // Turning straight back works at once, mid-step.
    if (d == _me.dir.opposite && _me.dir != Dir.none) {
      _me
        ..x += _me.dir.dx
        ..y += _me.dir.dy
        ..t = 1 - _me.t
        ..dir = d;
    }
  }

  void _stepWalker(Walker w, double cells, void Function(Walker) arrive) {
    if (w.dir == Dir.none) {
      arrive(w);
      return;
    }
    w.t += cells;
    while (w.t >= 1) {
      w.t -= 1;
      w.x = (w.x + w.dir.dx + _board.width) % _board.width;
      w.y += w.dir.dy;
      arrive(w);
      if (w.dir == Dir.none) {
        w.t = 0;
        break;
      }
    }
  }

  void _tick(Duration now) {
    final dt = math.min(0.05, _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6);
    _last = now;
    _time += dt;
    if (_hurt > 0) {
      _hurt -= dt;
      setState(() {});
      return;
    }
    _scared = math.max(0, _scared - dt);
    final pace = 1 + (_stage - 1) * 0.08 + _level * 0.12;

    // Munchie.
    _stepWalker(_me, 5.2 * dt, (w) {
      final got = _board.eat(w.x, w.y);
      _score += got.points;
      if (got.berry) {
        _scared = math.max(3.0, 7.0 - _stage * 0.5 - _level);
        _combo = 0;
      }
      if (_wanted != Dir.none && _board.open(w.x + _wanted.dx, w.y + _wanted.dy)) {
        w.dir = _wanted;
      } else if (!_board.open(w.x + w.dir.dx, w.y + w.dir.dy)) {
        w.dir = Dir.none;
      }
    });
    if (_me.dir == Dir.none && _wanted != Dir.none && _board.open(_me.x + _wanted.dx, _me.y + _wanted.dy)) {
      _me.dir = _wanted;
    }

    // Robots.
    final mx = _me.px, my = _me.py;
    for (var i = 0; i < _robots.length; i++) {
      final r = _robots[i];
      if (r.wait > 0) {
        r.wait -= dt;
        continue;
      }
      final flee = _scared > 0 && !r.eaten;
      final speed = r.eaten ? 9.0 : (flee ? 2.8 : 4.4 * pace);
      final home = _board.robotStarts[i];
      (double, double) target() {
        if (r.eaten) return (home.$1.toDouble(), home.$2.toDouble());
        // Each robot has its own idea: straight at Munchie, a few cells
        // ahead of it, or a lazy wander near it.
        return switch (i % 3) {
          0 => (mx, my),
          1 => (mx + _me.dir.dx * 4, my + _me.dir.dy * 4),
          _ => (mx + math.sin(_time) * 5, my + math.cos(_time) * 5),
        };
      }

      if (r.dir == Dir.none) r.dir = chooseDir(_board, r, target(), flee: flee, rng: _rng);
      _stepWalker(r, speed * dt, (w) {
        if (r.eaten && w.x == home.$1 && w.y == home.$2) r.eaten = false;
        w.dir = chooseDir(_board, w, target(), flee: _scared > 0 && !r.eaten, rng: r.eaten ? null : _rng);
      });
      // Caught, or catching.
      final d = (r.px - mx).abs() + (r.py - my).abs();
      if (d < 0.7 && !r.eaten) {
        if (_scared > 0) {
          r.eaten = true;
          _combo++;
          _score += 200 * _combo;
        } else {
          _lives--;
          if (_lives <= 0) {
            unawaited(_finish());
            return;
          }
          _resetPositions();
          setState(() {});
          return;
        }
      }
    }

    if (_board.seedsLeft == 0) {
      _stage++;
      _score += 500;
      _newBoard();
    }
    setState(() {});
  }

  Widget _pad(IconData icon, Dir d) => KidsBounce(
    onTap: () => _steer(d),
    child: Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF39D0FF), width: 2),
      ),
      child: Icon(icon, size: 44, color: const Color(0xFF39D0FF)),
    ),
  );

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Munch Maze',
    colors: const [Color(0xFF1A1340), Color(0xFF0E5A8A)],
    onBack: widget.onBack,
    trailing: _playing
        ? ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.55),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('MAZE $_stage', style: arcadeText(30, const Color(0xFF39D0FF))),
                  const SizedBox(width: 18),
                  Text(_score.toString().padLeft(5, '0'), style: arcadeText(36, const Color(0xFFFFE066))),
                  const SizedBox(width: 14),
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.circle, size: 22, color: i < _lives ? const Color(0xFF7CFF6B) : Colors.white24),
                    ),
                ],
              ),
            ),
          )
        : null,
    child: _over
        ? KidsResult(
            title: 'GAME OVER',
            detail: 'Score $_score · reached maze $_stage',
            stars: _score >= 3000 ? 3 : (_score >= 1500 ? 2 : (_score >= 500 ? 1 : 0)),
            newBest: _newBest,
            onAgain: () => setState(() => _over = false),
          )
        : !_playing
        ? KidsStartPanel(
            icon: Icons.grid_on_rounded,
            pitch: 'Help Munchie eat every seed! Dodge the robots, or grab a power berry and catch them.',
            best: KidsScores.best('munch${_level + 1}').then((b) => b == null ? null : 'High score: $b'),
            options: kidsLevelChips(const ['Easy', 'Medium', 'Hard'], _level, (i) => setState(() => _level = i)),
            onStart: _start,
          )
        : LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight;
              final board = GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanEnd: (d) {
                  final v = d.velocity.pixelsPerSecond;
                  if (v.distance < 60) return;
                  _steer(v.dx.abs() > v.dy.abs() ? (v.dx > 0 ? Dir.right : Dir.left) : (v.dy > 0 ? Dir.down : Dir.up));
                },
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _board.width / _board.height,
                    child: CustomPaint(painter: _MazePainter(this)),
                  ),
                ),
              );
              final pad = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _pad(Icons.arrow_upward_rounded, Dir.up),
                  const SizedBox(height: 8),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _pad(Icons.arrow_back_rounded, Dir.left),
                    const SizedBox(width: 84),
                    _pad(Icons.arrow_forward_rounded, Dir.right),
                  ]),
                  const SizedBox(height: 8),
                  _pad(Icons.arrow_downward_rounded, Dir.down),
                ],
              );
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: wide
                    ? Row(children: [Expanded(child: board), const SizedBox(width: 16), pad])
                    : Column(children: [Expanded(child: board), const SizedBox(height: 12), pad]),
              );
            },
          ),
  );
}

class _MazePainter extends CustomPainter {
  _MazePainter(this.g);
  final _MunchMazeState g;

  @override
  void paint(Canvas canvas, Size size) {
    final b = g._board;
    final cell = size.width / b.width;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)), Paint()..color = const Color(0xFF070418));
    final wall = Paint()..color = const Color(0xFF1E3FA8);
    final wallEdge = Paint()
      ..color = const Color(0xFF5B8CFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.12;
    final seed = Paint()..color = const Color(0xFFFFE8B0);
    final pulse = 0.75 + 0.25 * math.sin(g._time * 8);
    for (var y = 0; y < b.height; y++) {
      for (var x = 0; x < b.width; x++) {
        final c = b.at(x, y);
        final r = Rect.fromLTWH(x * cell, y * cell, cell, cell);
        if (c == '#') {
          final rr = RRect.fromRectAndRadius(r.deflate(cell * 0.08), Radius.circular(cell * 0.22));
          canvas.drawRRect(rr, wall);
          canvas.drawRRect(rr, wallEdge);
        } else if (c == '-') {
          canvas.drawRect(Rect.fromLTWH(r.left, r.center.dy - cell * 0.08, cell, cell * 0.16), Paint()..color = const Color(0xFFFF8AD8));
        } else if (c == '.') {
          canvas.drawRect(Rect.fromCenter(center: r.center, width: cell * 0.2, height: cell * 0.2), seed);
        } else if (c == 'o') {
          canvas.drawCircle(r.center, cell * 0.3 * pulse, Paint()..color = const Color(0xFFFF4D9A));
          canvas.drawCircle(r.center + Offset(-cell * 0.08, -cell * 0.08), cell * 0.08, Paint()..color = Colors.white70);
        }
      }
    }

    // Robots: little square bots with an antenna and a visor.
    for (final r in g._robots) {
      final c = Offset((r.px + 0.5) * cell, (r.py + 0.5) * cell);
      final scared = g._scared > 0 && !r.eaten;
      final blink = scared && g._scared < 1.5 && (g._time * 8).floor().isEven;
      if (!r.eaten) {
        final body = scared ? (blink ? Colors.white : const Color(0xFF3B5BFF)) : r.color;
        final rect = Rect.fromCenter(center: c + Offset(0, cell * 0.05), width: cell * 0.8, height: cell * 0.7);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.18)), Paint()..color = body);
        canvas.drawLine(c + Offset(0, -cell * 0.3), c + Offset(0, -cell * 0.48), Paint()
          ..color = body
          ..strokeWidth = cell * 0.08);
        canvas.drawCircle(c + Offset(0, -cell * 0.5), cell * 0.08, Paint()..color = const Color(0xFFFFE066));
      }
      // The visor and eyes (all that is left of an eaten robot going home).
      final visor = Rect.fromCenter(center: c + Offset(0, -cell * 0.02), width: cell * 0.6, height: cell * 0.22);
      canvas.drawRRect(RRect.fromRectAndRadius(visor, Radius.circular(cell * 0.1)), Paint()..color = const Color(0xFF0A0A1E));
      final look = Offset(r.dir.dx * cell * 0.06, r.dir.dy * cell * 0.04);
      for (final side in const [-1, 1]) {
        canvas.drawCircle(c + Offset(side * cell * 0.14, -cell * 0.02) + look, cell * 0.06, Paint()..color = scared ? Colors.white : const Color(0xFF7CFF6B));
      }
    }

    // Munchie: a round lime critter with a leaf, big eyes and a smile,
    // looking the way it goes.
    final me = Offset((g._me.px + 0.5) * cell, (g._me.py + 0.5) * cell);
    if (g._hurt <= 0 || (g._time * 10).floor().isEven) {
      final bounce = math.sin(g._time * 14).abs() * cell * 0.04;
      final body = me - Offset(0, bounce);
      canvas.drawCircle(body, cell * 0.42, Paint()..color = const Color(0xFF9CFF4D));
      canvas.drawCircle(body + Offset(-cell * 0.1, -cell * 0.12), cell * 0.12, Paint()..color = const Color(0xFFD6FFAE));
      final leaf = Path()
        ..moveTo(body.dx, body.dy - cell * 0.38)
        ..quadraticBezierTo(body.dx + cell * 0.3, body.dy - cell * 0.62, body.dx + cell * 0.12, body.dy - cell * 0.36)
        ..close();
      canvas.drawPath(leaf, Paint()..color = const Color(0xFF2FB872));
      final d = g._me.dir == Dir.none ? Dir.down : g._me.dir;
      final look = Offset(d.dx * cell * 0.07, d.dy * cell * 0.05);
      for (final side in const [-1, 1]) {
        final e = body + Offset(side * cell * 0.15, -cell * 0.06) + look;
        canvas.drawCircle(e, cell * 0.11, Paint()..color = Colors.white);
        canvas.drawCircle(e + look * 0.8, cell * 0.055, Paint()..color = const Color(0xFF1A1340));
      }
      final smile = Rect.fromCenter(center: body + Offset(0, cell * 0.12) + look * 0.5, width: cell * 0.3, height: cell * 0.18);
      canvas.drawArc(smile, 0.2, math.pi - 0.4, false, Paint()
        ..color = const Color(0xFF1A1340)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.06
        ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_MazePainter old) => true;
}

// ── Brick Bash ────────────────────────────────────────────────────────────

/// The playfield is a fixed 100 × 70 units, scaled to the screen.
const _fieldW = 100.0, _fieldH = 70.0;

class _Brick {
  _Brick(this.rect, this.hp, this.color);
  final Rect rect;
  int hp;
  final Color color;
}

class _Ball {
  _Ball(this.x, this.y, this.vx, this.vy);
  double x, y, vx, vy;
}

class _Drop {
  _Drop(this.x, this.y, this.wide);
  double x, y;
  final bool wide;
}

/// The brick layouts, a row of letters per row: '.' none, '1' one hit,
/// '2' two hits.
const brickLevels = [
  ['..........', '1111111111', '1111111111', '1111111111', '..........'],
  ['1.1.1.1.1.', '.1.1.1.1.1', '2222222222', '1.1.1.1.1.', '.1.1.1.1.1'],
  ['....22....', '...2112...', '..211112..', '.21111112.', '2111111112'],
  ['2.2.2.2.2.', '1111111111', '.2.2.2.2.2', '1111111111', '2222222222'],
];

List<_Brick> _bricksFor(int stage) {
  final layout = brickLevels[(stage - 1) % brickLevels.length];
  const colors = [Color(0xFFFF4D6D), Color(0xFFFF9F1C), Color(0xFFFFE066), Color(0xFF7CFF6B), Color(0xFF39D0FF)];
  final out = <_Brick>[];
  const w = _fieldW / 10, h = 3.6;
  for (var r = 0; r < layout.length; r++) {
    for (var c = 0; c < 10; c++) {
      final k = layout[r][c];
      if (k == '.') continue;
      out.add(_Brick(Rect.fromLTWH(c * w + 0.4, 8 + r * (h + 0.8), w - 0.8, h), k == '2' ? 2 : 1, colors[r % colors.length]));
    }
  }
  return out;
}

/// Bounce the ball off the paddle to smash every brick. The paddle follows
/// a finger, or a hand or the head in front of the camera.
class BrickBash extends StatefulWidget {
  const BrickBash({super.key, required this.container, required this.onBack});
  final AppContainer container;
  final VoidCallback onBack;

  @override
  State<BrickBash> createState() => _BrickBashState();
}

class _BrickBashState extends State<BrickBash> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  final _rng = math.Random();
  KidsHands? _tracker;
  int _steer = 0; // 0 finger, 1 hand, 2 head
  List<_Brick> _bricks = [];
  final _balls = <_Ball>[];
  final _drops = <_Drop>[];
  Duration _last = Duration.zero;
  double _wide = 0, _serve = 0;
  double _paddleX = _fieldW / 2;
  int _level = 0, _stage = 1, _score = 0, _lives = 3;
  bool _playing = false, _over = false, _newBest = false;

  double get _paddleW => _wide > 0 ? 24 : 15;

  @override
  void dispose() {
    _ticker.dispose();
    _tracker?.dispose();
    super.dispose();
  }

  void _start() {
    _tracker?.dispose();
    _tracker = _steer == 0 ? null : KidsHands(widget.container.motion, head: _steer == 2);
    setState(() {
      _score = 0;
      _lives = 3;
      _stage = 1;
      _bricks = _bricksFor(1);
      _playing = true;
      _over = false;
      _last = Duration.zero;
      _serveBall();
    });
    _ticker.start();
  }

  void _serveBall() {
    _balls
      ..clear()
      ..add(_Ball(_paddleX, _fieldH - 8, 0, 0));
    _drops.clear();
    _serve = 1.2;
  }

  Future<void> _finish() async {
    _ticker.stop();
    final key = 'bricks${_level + 1}';
    final best = await KidsScores.offer(key, _score);
    await KidsScores.addStars(_score >= 2500 ? 3 : (_score >= 1200 ? 2 : (_score >= 400 ? 1 : 0)));
    if (mounted) {
      setState(() {
        _playing = false;
        _over = true;
        _newBest = best;
      });
    }
  }

  void _tick(Duration now) {
    final dt = math.min(0.033, _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6);
    _last = now;
    _wide = math.max(0, _wide - dt);
    final tracker = _tracker;
    if (tracker != null) {
      tracker.step(dt);
      final p = tracker.point.value;
      if (p != null) _paddleX = p.dx * _fieldW;
    }
    _paddleX = _paddleX.clamp(_paddleW / 2, _fieldW - _paddleW / 2);
    const paddleY = _fieldH - 5;
    const radius = 1.3;
    final speed = (48 + _level * 10 + _stage * 3).toDouble();

    if (_serve > 0) {
      _serve -= dt;
      final b = _balls.first;
      b.x = _paddleX;
      b.y = paddleY - 2.5;
      if (_serve <= 0) {
        final a = -math.pi / 2 + (_rng.nextDouble() - 0.5) * 0.8;
        b.vx = math.cos(a) * speed;
        b.vy = math.sin(a) * speed;
      }
    } else {
      for (final b in _balls) {
        b.x += b.vx * dt;
        b.y += b.vy * dt;
        if (b.x < radius) {
          b.x = radius;
          b.vx = b.vx.abs();
        } else if (b.x > _fieldW - radius) {
          b.x = _fieldW - radius;
          b.vx = -b.vx.abs();
        }
        if (b.y < radius) {
          b.y = radius;
          b.vy = b.vy.abs();
        }
        // The paddle: where it hits picks the angle out.
        if (b.vy > 0 && b.y + radius >= paddleY && b.y < paddleY + 2 && (b.x - _paddleX).abs() <= _paddleW / 2 + radius) {
          final off = ((b.x - _paddleX) / (_paddleW / 2)).clamp(-1.0, 1.0);
          final a = -math.pi / 2 + off * 1.05;
          b.vx = math.cos(a) * speed;
          b.vy = math.sin(a) * speed;
          b.y = paddleY - radius;
        }
        // Bricks.
        for (final br in _bricks) {
          if (br.hp <= 0) continue;
          final r = br.rect.inflate(radius);
          if (!r.contains(Offset(b.x, b.y))) continue;
          br.hp--;
          if (br.hp <= 0) {
            _score += 50;
            if (_rng.nextDouble() < 0.12) _drops.add(_Drop(br.rect.center.dx, br.rect.center.dy, _rng.nextBool()));
          } else {
            _score += 10;
          }
          // Bounce off the side it came in from.
          final fromSide = (b.x < br.rect.left || b.x > br.rect.right) && (b.y > br.rect.top && b.y < br.rect.bottom);
          if (fromSide) {
            b.vx = -b.vx;
          } else {
            b.vy = -b.vy;
          }
          break;
        }
      }
      _balls.removeWhere((b) => b.y > _fieldH + 3);
      if (_balls.isEmpty) {
        _lives--;
        if (_lives <= 0) {
          unawaited(_finish());
          return;
        }
        _serveBall();
      }
    }

    // Power-ups: a wide paddle, or an extra ball.
    for (final d in _drops) {
      d.y += 18 * dt;
      if (d.y >= paddleY - 1 && d.y <= paddleY + 2 && (d.x - _paddleX).abs() <= _paddleW / 2 + 2) {
        d.y = 999;
        _score += 25;
        if (d.wide) {
          _wide = 12;
        } else if (_balls.isNotEmpty) {
          final b = _balls.first;
          _balls.add(_Ball(b.x, b.y, -b.vx, b.vy));
        }
      }
    }
    _drops.removeWhere((d) => d.y > _fieldH + 2);

    _bricks.removeWhere((b) => b.hp <= 0);
    if (_bricks.isEmpty) {
      _stage++;
      _score += 300;
      _bricks = _bricksFor(_stage);
      _serveBall();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Brick Bash',
    colors: const [Color(0xFF1A1340), Color(0xFF8A1E5A)],
    onBack: widget.onBack,
    trailing: _playing
        ? ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.55),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('LEVEL $_stage', style: arcadeText(30, const Color(0xFF39D0FF))),
                  const SizedBox(width: 18),
                  Text(_score.toString().padLeft(5, '0'), style: arcadeText(36, const Color(0xFFFFE066))),
                  const SizedBox(width: 14),
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.sports_baseball_rounded, size: 24, color: i < _lives ? Colors.white : Colors.white24),
                    ),
                ],
              ),
            ),
          )
        : null,
    child: _over
        ? KidsResult(
            title: 'GAME OVER',
            detail: 'Score $_score · reached level $_stage',
            stars: _score >= 2500 ? 3 : (_score >= 1200 ? 2 : (_score >= 400 ? 1 : 0)),
            newBest: _newBest,
            onAgain: () => setState(() => _over = false),
          )
        : !_playing
        ? KidsStartPanel(
            icon: Icons.view_module_rounded,
            pitch: 'Bounce the ball with your paddle and smash all the bricks!',
            best: KidsScores.best('bricks${_level + 1}').then((b) => b == null ? null : 'High score: $b'),
            options: Column(
              children: [
                kidsLevelChips(const ['Easy', 'Medium', 'Hard'], _level, (i) => setState(() => _level = i)),
                const SizedBox(height: 14),
                Text('Move the paddle with', style: kidsText(18, weight: FontWeight.w700)),
                const SizedBox(height: 8),
                kidsLevelChips(const ['My finger', 'My hand', 'My head'], _steer, (i) => setState(() => _steer = i)),
              ],
            ),
            onStart: _start,
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Center(
              child: AspectRatio(
                aspectRatio: _fieldW / _fieldH,
                child: LayoutBuilder(
                  builder: (context, box) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanDown: (d) => _paddleX = d.localPosition.dx / box.maxWidth * _fieldW,
                    onPanUpdate: (d) => _paddleX = d.localPosition.dx / box.maxWidth * _fieldW,
                    child: CustomPaint(painter: _BricksPainter(this)),
                  ),
                ),
              ),
            ),
          ),
  );
}

class _BricksPainter extends CustomPainter {
  _BricksPainter(this.g);
  final _BrickBashState g;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _fieldW;
    Rect s(Rect r) => Rect.fromLTRB(r.left * k, r.top * k, r.right * k, r.bottom * k);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)),
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0B0620), Color(0xFF1A0B33)])
            .createShader(Offset.zero & size),
    );
    // Faint pixel grid.
    final grid = Paint()..color = const Color(0x0FFFFFFF);
    for (var x = 0.0; x < size.width; x += k * 5) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), grid);
    }
    for (final b in g._bricks) {
      final r = s(b.rect);
      final c = b.hp >= 2 ? Color.lerp(b.color, Colors.white, 0.35)! : b.color;
      canvas.drawRect(r, Paint()..color = c);
      canvas.drawRect(Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.25), Paint()..color = Colors.white.withValues(alpha: 0.35));
      canvas.drawRect(Rect.fromLTWH(r.left, r.bottom - r.height * 0.2, r.width, r.height * 0.2), Paint()..color = Colors.black.withValues(alpha: 0.25));
      if (b.hp >= 2) {
        canvas.drawRect(r.deflate(k * 0.6), Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = k * 0.3);
      }
    }
    for (final d in g._drops) {
      final r = Rect.fromCenter(center: Offset(d.x * k, d.y * k), width: k * 6, height: k * 3);
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(k)), Paint()..color = d.wide ? const Color(0xFF39D0FF) : const Color(0xFFFF9F1C));
      final tp = TextPainter(
        text: TextSpan(text: d.wide ? 'W' : '+1', style: TextStyle(fontFamily: 'VT323', fontSize: k * 3, color: const Color(0xFF0B0620))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
    }
    // The paddle.
    final pr = s(Rect.fromCenter(center: Offset(g._paddleX, _fieldH - 4), width: g._paddleW, height: 2.4));
    canvas.drawRRect(
      RRect.fromRectAndRadius(pr, Radius.circular(k)),
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFF39D0FF), Color(0xFFB04BFF)]).createShader(pr),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pr.inflate(k * 0.6), Radius.circular(k * 1.5)),
      Paint()
        ..color = const Color(0x5539D0FF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Balls.
    for (final b in g._balls) {
      final c = Offset(b.x * k, b.y * k);
      canvas.drawCircle(c, k * 2.2, Paint()
        ..color = const Color(0x55FFFFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(c, k * 1.3, Paint()..color = Colors.white);
    }
    if (g._serve > 0) {
      final tp = TextPainter(text: TextSpan(text: 'GET READY', style: arcadeText(k * 6, const Color(0xFFFFE066))), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height * 0.55));
    }
  }

  @override
  bool shouldRepaint(_BricksPainter old) => true;
}
