import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app_container.dart';
import 'kids_activities.dart';
import 'kids_arcade.dart' show arcadeText;
import 'kids_arcade2.dart' show arcadeHud;
import 'kids_games.dart';
import 'kids_logic.dart' show KidsScores;
import 'kids_motion.dart';
import 'kids_dj.dart';
import 'kids_play.dart' show KidsTones;

/// More of the Move shelf, played with the whole body in front of the
/// camera: Wall Dodge (lean through the hole in the wall), Air Trace (draw
/// shapes, numbers and letters in the air) and Freeze Dance (dance, then
/// freeze when the music stops). Every game also plays by touch.

void _say(Canvas canvas, String text, Offset centre, double size, Color color) {
  final tp = TextPainter(text: TextSpan(text: text, style: arcadeText(size, color)), textDirection: TextDirection.ltr)..layout();
  tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
}

/// What these games share: tracking, the loop, score, lives, start and end.
abstract class _MoveGame<T extends StatefulWidget> extends State<T> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  KidsHands? hands;
  Size size = Size.zero;
  double time = 0;
  int level = 0, score = 0, lives = 3;
  bool playing = false, over = false, newBest = false;

  /// 0: the head steers, 1: a hand.
  int steer = 0;

  AppContainer get container;
  VoidCallback get onBack;
  String get scoreKey;
  int starsFor(int score);
  void reset();
  void step(double dt);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    hands?.dispose();
    super.dispose();
  }

  /// Whether small movements go a long way (steering) rather than the
  /// point being where the child really is.
  bool get amplify => true;

  void begin() {
    hands?.dispose();
    hands = KidsHands(container.motion, head: steer == 0, amplify: amplify);
    setState(() {
      score = 0;
      lives = 3;
      time = 0;
      playing = true;
      over = false;
      _last = Duration.zero;
      reset();
    });
    _ticker.start();
  }

  void _tick(Duration now) {
    final dt = math.min(0.05, _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6);
    _last = now;
    time += dt;
    hands?.step(dt);
    step(dt);
    if (mounted && _ticker.isActive) setState(() {});
  }

  bool loseLife() {
    lives--;
    if (lives > 0) return true;
    unawaited(finish());
    return false;
  }

  Future<void> finish() async {
    if (!_ticker.isActive) return;
    _ticker.stop();
    final best = await KidsScores.offer(scoreKey, score);
    await KidsScores.addStars(starsFor(score));
    if (mounted) {
      setState(() {
        playing = false;
        over = true;
        newBest = best;
      });
    }
  }

  Widget steerChips(String label, List<String> names) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: kidsText(18, weight: FontWeight.w700)),
      const SizedBox(height: 8),
      kidsLevelChips(names, steer, (i) => setState(() => steer = i)),
    ],
  );

  Widget moveFrame({
    required String title,
    required List<Color> colors,
    required String hud,
    required IconData icon,
    required String pitch,
    required Widget options,
    required String overDetail,
    required CustomPainter painter,
    IconData lifeIcon = Icons.favorite_rounded,
  }) => KidsActivityFrame(
    title: title,
    colors: colors,
    onBack: onBack,
    trailing: playing ? arcadeHud(context, hud, score, lives, lifeIcon, const Color(0xFFFF4D6D)) : null,
    child: over
        ? KidsResult(title: 'GREAT MOVING!', detail: overDetail, stars: starsFor(score), newBest: newBest, onAgain: () => setState(() => over = false))
        : !playing
        ? KidsStartPanel(
            icon: icon,
            pitch: pitch,
            best: KidsScores.best(scoreKey).then((b) => b == null ? null : 'High score: $b'),
            options: options,
            onStart: begin,
          )
        : KidsMotionArena(
            hands: hands!,
            onSize: (s) => size = s,
            painter: painter,
            cursorIcon: hands!.head ? Icons.face_rounded : Icons.back_hand_rounded,
          ),
  );
}

// ── Wall Dodge ────────────────────────────────────────────────────────────

/// Where the hole in the next wall goes (fractions of the play area): a
/// column, or on harder levels a row and column too; smaller as stages go.
Rect wallHole(int difficulty, int stage, math.Random rng) {
  final w = math.max(0.2, const [0.36, 0.3, 0.26][difficulty] - (stage - 1) * 0.012);
  final h = math.max(0.3, const [0.62, 0.42, 0.34][difficulty] - (stage - 1) * 0.01);
  final col = rng.nextInt(3);
  final rows = const [1, 2, 3][difficulty];
  final row = rng.nextInt(rows);
  final cx = 0.2 + col * 0.3;
  final cy = rows == 1 ? 0.5 : 0.25 + row * (0.5 / (rows - 1));
  return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
}

/// Whether the player at [p] fits the hole (a little leeway at the edges).
bool fitsHole(Rect hole, Offset? p) => p != null && hole.inflate(0.03).contains(p);

/// Walls fly towards you: lean (or move a hand) to fit through the hole.
class WallDodge extends StatefulWidget {
  const WallDodge({super.key, required this.container, required this.onBack});
  final AppContainer container;
  final VoidCallback onBack;

  @override
  State<WallDodge> createState() => _WallDodgeState();
}

class _WallDodgeState extends _MoveGame<WallDodge> {
  final _rng = math.Random();
  Rect _hole = const Rect.fromLTWH(0.3, 0.2, 0.3, 0.6);
  double _t = 0, _pause = 0, _flash = 0;
  bool _lastOk = true;
  int _walls = 0, _stage = 1, _streak = 0;
  Color _wallColor = const Color(0xFF7A5CFF);

  static const _colors = [Color(0xFF7A5CFF), Color(0xFFFF6B9A), Color(0xFF2FB8A8), Color(0xFFFF9F1C), Color(0xFF3B8BFF)];

  @override
  AppContainer get container => widget.container;
  @override
  VoidCallback get onBack => widget.onBack;
  @override
  String get scoreKey => 'walls${level + 1}';

  @override
  int starsFor(int s) => s >= 300 ? 3 : (s >= 150 ? 2 : (s >= 50 ? 1 : 0));

  double get _seconds => math.max(1.5, const [3.6, 3.0, 2.5][level] - (_stage - 1) * 0.18);

  @override
  void reset() {
    _walls = 0;
    _stage = 1;
    _streak = 0;
    _pause = 1.5;
    _nextWall();
  }

  void _nextWall() {
    _hole = wallHole(level, _stage, _rng);
    _t = 0;
    _wallColor = _colors[_rng.nextInt(_colors.length)];
  }

  @override
  void step(double dt) {
    _flash = math.max(0, _flash - dt);
    if (_pause > 0) {
      _pause -= dt;
      return;
    }
    _t += dt / _seconds;
    if (_t < 1) return;
    _walls++;
    _lastOk = fitsHole(_hole, hands?.point.value);
    _flash = 0.8;
    if (_lastOk) {
      _streak++;
      score += 10 * math.min(_streak, 5);
    } else {
      _streak = 0;
      if (!loseLife()) return;
    }
    if (_walls % 6 == 0) _stage++;
    _pause = 0.7;
    _nextWall();
  }

  @override
  Widget build(BuildContext context) => moveFrame(
    title: 'Wall Dodge',
    colors: const [Color(0xFF2A1F6B), Color(0xFF7A5CFF)],
    hud: 'WALL ${_walls + 1}',
    icon: Icons.door_sliding_rounded,
    pitch: 'Walls are coming! Lean your body so your face fits through the hole.',
    options: Column(
      children: [
        kidsLevelChips(const ['Easy', 'Medium', 'Hard'], level, (i) => setState(() => level = i)),
        const SizedBox(height: 14),
        steerChips('Dodge with', const ['My head', 'My hand']),
      ],
    ),
    overDetail: 'Score $score · got through $_walls walls',
    painter: _WallPainter(this),
  );
}

class _WallPainter extends CustomPainter {
  _WallPainter(this.g);
  final _WallDodgeState g;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    // A tunnel floor in perspective.
    final c = size.center(Offset.zero);
    final lines = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 2;
    for (final corner in [full.topLeft, full.topRight, full.bottomLeft, full.bottomRight]) {
      canvas.drawLine(c, corner, lines);
    }
    for (var i = 1; i <= 4; i++) {
      final k = ((i / 4) + g.time * 0.3) % 1;
      final r = Rect.fromCenter(center: c, width: size.width * k * k, height: size.height * k * k);
      canvas.drawRect(r, lines..style = PaintingStyle.stroke);
    }
    lines.style = PaintingStyle.fill;
    Rect hole(double s) {
      final h = g._hole;
      return Rect.fromLTRB(
        c.dx + (h.left * size.width - c.dx) * s,
        c.dy + (h.top * size.height - c.dy) * s,
        c.dx + (h.right * size.width - c.dx) * s,
        c.dy + (h.bottom * size.height - c.dy) * s,
      );
    }

    // Where the hole will be: a soft outline to aim for.
    final target = hole(1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(target, const Radius.circular(24)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white.withValues(alpha: 0.35 + 0.25 * math.sin(g.time * 6).abs()),
    );
    if (g._pause <= 0 || g._t > 0) {
      final s = 0.1 + 0.9 * g._t * g._t;
      final wall = Rect.fromCenter(center: c, width: size.width * s, height: size.height * s);
      final shape = Path()
        ..fillType = PathFillType.evenOdd
        ..addRRect(RRect.fromRectAndRadius(wall, Radius.circular(20 * s)))
        ..addRRect(RRect.fromRectAndRadius(hole(s), Radius.circular(24 * s)));
      canvas.drawPath(shape, Paint()..color = g._wallColor.withValues(alpha: 0.35 + 0.5 * g._t));
      // Bricks on the wall.
      canvas.save();
      canvas.clipPath(shape);
      final brick = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, 3 * s)
        ..color = Colors.white.withValues(alpha: 0.18 + 0.2 * g._t);
      final bh = 60 * s, bw = 120 * s;
      var row = 0;
      for (var y = wall.top; y < wall.bottom; y += bh, row++) {
        for (var x = wall.left - (row.isOdd ? bw / 2 : 0); x < wall.right; x += bw) {
          canvas.drawRect(Rect.fromLTWH(x, y, bw, bh), brick);
        }
      }
      canvas.restore();
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole(s), Radius.circular(24 * s)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5 * s + 1
          ..color = const Color(0xFFF3DA8A),
      );
    }
    // A bar showing how close the wall is.
    final bar = Rect.fromLTWH(20, size.height - 22, (size.width - 40) * g._t.clamp(0.0, 1.0), 8);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(20, size.height - 22, size.width - 40, 8), const Radius.circular(4)), Paint()..color = Colors.white12);
    canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(4)), Paint()..color = const Color(0xFFF3DA8A));
    if (g._flash > 0) {
      final ok = g._lastOk;
      canvas.drawRect(full, Paint()..color = (ok ? const Color(0xFF7CFF6B) : const Color(0xFFFF4D6D)).withValues(alpha: g._flash * 0.25));
      _say(canvas, ok ? (g._streak >= 3 ? 'SUPER x${math.min(g._streak, 5)}!' : 'SQUEEZE!') : 'BONK!', Offset(c.dx, size.height * 0.15), 56, ok ? const Color(0xFF7CFF6B) : const Color(0xFFFF4D6D));
    } else if (g._pause > 0 && g._walls == 0) {
      _say(canvas, 'GET READY', Offset(c.dx, size.height * 0.15), 56, const Color(0xFFF3DA8A));
    }
  }

  @override
  bool shouldRepaint(_WallPainter old) => true;
}

// ── Air Trace ─────────────────────────────────────────────────────────────

typedef TraceShape = ({String name, List<List<Offset>> strokes});

List<Offset> _ring(double cx, double cy, double rx, double ry, {double from = -math.pi / 2, double sweep = math.pi * 2, int n = 28}) => [
  for (var i = 0; i <= n; i++) Offset(cx + math.cos(from + sweep * i / n) * rx, cy + math.sin(from + sweep * i / n) * ry),
];

List<Offset> _p(List<double> xy) => [for (var i = 0; i < xy.length; i += 2) Offset(xy[i], xy[i + 1])];

/// What there is to trace, by set: shapes, numbers, letters. Each is one or
/// more strokes of points in a unit square.
final traceSets = <String, List<TraceShape>>{
  'Shapes': [
    (name: 'circle', strokes: [_ring(0.5, 0.5, 0.45, 0.45)]),
    (name: 'square', strokes: [_p([0.08, 0.08, 0.92, 0.08, 0.92, 0.92, 0.08, 0.92, 0.08, 0.08])]),
    (name: 'triangle', strokes: [_p([0.5, 0.05, 0.95, 0.92, 0.05, 0.92, 0.5, 0.05])]),
    (name: 'zigzag', strokes: [_p([0.02, 0.25, 0.26, 0.75, 0.5, 0.25, 0.74, 0.75, 0.98, 0.25])]),
    (
      name: 'star',
      strokes: [
        [
          for (var i = 0; i <= 10; i++)
            Offset(0.5 + math.cos(-math.pi / 2 + i * math.pi / 5) * (i.isEven ? 0.47 : 0.2), 0.53 + math.sin(-math.pi / 2 + i * math.pi / 5) * (i.isEven ? 0.47 : 0.2)),
        ],
      ],
    ),
    (
      name: 'heart',
      strokes: [
        [
          for (var i = 0; i <= 32; i++)
            () {
              final t = i / 32 * 2 * math.pi;
              final x = 16 * math.pow(math.sin(t), 3);
              final y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t);
              return Offset(0.5 + x / 36, 0.45 - y / 36);
            }(),
        ],
      ],
    ),
    (name: 'wave', strokes: [for (var k = 0; k < 1; k++) [for (var i = 0; i <= 24; i++) Offset(0.02 + i / 24 * 0.96, 0.5 - math.sin(i / 24 * math.pi * 3) * 0.3)]]),
    (name: 'spiral', strokes: [[for (var i = 0; i <= 40; i++) Offset(0.5 + math.cos(i / 40 * math.pi * 4) * (0.05 + i / 40 * 0.42), 0.5 + math.sin(i / 40 * math.pi * 4) * (0.05 + i / 40 * 0.42))]]),
  ],
  'Numbers': [
    (name: '0', strokes: [_ring(0.5, 0.5, 0.3, 0.46)]),
    (name: '1', strokes: [_p([0.3, 0.2, 0.55, 0.02, 0.55, 0.98])]),
    (name: '2', strokes: [[..._ring(0.5, 0.3, 0.32, 0.27, from: math.pi, sweep: math.pi * 1.25, n: 14), ..._p([0.15, 0.98, 0.88, 0.98])]]),
    (name: '3', strokes: [[..._ring(0.48, 0.27, 0.3, 0.24, from: -math.pi * 0.9, sweep: math.pi * 1.4, n: 12), ..._ring(0.48, 0.73, 0.33, 0.25, from: -math.pi * 0.5, sweep: math.pi * 1.4, n: 12)]]),
    (name: '4', strokes: [_p([0.7, 0.98, 0.7, 0.02, 0.08, 0.68, 0.92, 0.68])]),
    (name: '5', strokes: [[..._p([0.82, 0.03, 0.25, 0.03, 0.2, 0.45]), ..._ring(0.48, 0.67, 0.34, 0.3, from: -math.pi * 0.72, sweep: math.pi * 1.5, n: 14)]]),
    (name: '7', strokes: [_p([0.1, 0.03, 0.9, 0.03, 0.4, 0.98])]),
  ],
  'Letters': [
    (name: 'A', strokes: [_p([0.05, 0.98, 0.5, 0.02, 0.95, 0.98]), _p([0.25, 0.6, 0.75, 0.6])]),
    (name: 'C', strokes: [_ring(0.55, 0.5, 0.42, 0.46, from: -math.pi * 0.25, sweep: -math.pi * 1.5, n: 22)]),
    (name: 'E', strokes: [_p([0.85, 0.03, 0.15, 0.03, 0.15, 0.97, 0.85, 0.97]), _p([0.15, 0.5, 0.7, 0.5])]),
    (name: 'L', strokes: [_p([0.2, 0.02, 0.2, 0.97, 0.85, 0.97])]),
    (name: 'M', strokes: [_p([0.05, 0.98, 0.05, 0.03, 0.5, 0.6, 0.95, 0.03, 0.95, 0.98])]),
    (name: 'N', strokes: [_p([0.12, 0.98, 0.12, 0.03, 0.88, 0.97, 0.88, 0.02])]),
    (name: 'T', strokes: [_p([0.05, 0.04, 0.95, 0.04]), _p([0.5, 0.04, 0.5, 0.98])]),
    (name: 'U', strokes: [[..._p([0.12, 0.02, 0.12, 0.6]), ..._ring(0.5, 0.6, 0.38, 0.37, from: math.pi, sweep: -math.pi, n: 14), ..._p([0.88, 0.02])]]),
    (name: 'V', strokes: [_p([0.05, 0.03, 0.5, 0.97, 0.95, 0.03])]),
    (name: 'W', strokes: [_p([0.02, 0.03, 0.25, 0.97, 0.5, 0.35, 0.75, 0.97, 0.98, 0.03])]),
    (name: 'Z', strokes: [_p([0.1, 0.04, 0.9, 0.04, 0.1, 0.96, 0.9, 0.96])]),
  ],
};

/// The dots to touch, in order: each stroke walked every [gap] or closer.
List<Offset> traceDots(TraceShape shape, {double gap = 0.09}) {
  final out = <Offset>[];
  for (final stroke in shape.strokes) {
    for (var i = 0; i < stroke.length; i++) {
      if (i == 0) {
        out.add(stroke[0]);
        continue;
      }
      final a = stroke[i - 1], b = stroke[i];
      final n = math.max(1, ((b - a).distance / gap).ceil());
      for (var k = 1; k <= n; k++) {
        out.add(Offset.lerp(a, b, k / n)!);
      }
    }
  }
  // Drop dots on top of each other.
  final kept = <Offset>[];
  for (final d in out) {
    if (kept.isEmpty || (kept.last - d).distance > gap * 0.45) kept.add(d);
  }
  return kept;
}

/// Draw in the air: follow the dots with a finger (or the nose!).
class AirTrace extends StatefulWidget {
  const AirTrace({super.key, required this.container, required this.onBack});
  final AppContainer container;
  final VoidCallback onBack;

  @override
  State<AirTrace> createState() => _AirTraceState();
}

class _AirTraceState extends _MoveGame<AirTrace> {
  static const _seconds = 120.0;
  final _rng = math.Random();
  int _set = 0;
  late List<TraceShape> _queue;
  late TraceShape _shape;
  List<Offset> _dots = const [];
  int _next = 0, _done = 0;
  double _left = _seconds, _cheer = 0;
  final _trail = <Offset>[];

  @override
  void initState() {
    super.initState();
    steer = 1; // a hand, by default
  }

  @override
  AppContainer get container => widget.container;
  @override
  VoidCallback get onBack => widget.onBack;
  @override
  String get scoreKey => 'trace${_set + 1}';
  @override
  int starsFor(int s) => s >= 8 ? 3 : (s >= 5 ? 2 : (s >= 2 ? 1 : 0));

  String get _setName => traceSets.keys.elementAt(_set);

  @override
  void reset() {
    lives = 0; // filled in as stars, one per picture (up to 3)
    _done = 0;
    _left = _seconds;
    _queue = [...traceSets[_setName]!]..shuffle(_rng);
    _nextShape();
  }

  void _nextShape() {
    if (_queue.isEmpty) _queue = [...traceSets[_setName]!]..shuffle(_rng);
    _shape = _queue.removeLast();
    _dots = traceDots(_shape, gap: const [0.16, 0.12, 0.09][level]);
    _next = 0;
    _trail.clear();
  }

  /// The drawing's box in the play area: a centred square.
  Rect get _box {
    final side = math.min(size.width, size.height) * 0.72;
    return Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side);
  }

  Offset _onScreen(Offset unit) => _box.topLeft + Offset(unit.dx * _box.width, unit.dy * _box.height);

  @override
  void step(double dt) {
    _left -= dt;
    _cheer = math.max(0, _cheer - dt);
    if (_left <= 0) {
      unawaited(finish());
      return;
    }
    final p = hands?.point.value;
    if (p == null || size == Size.zero || _cheer > 0) return;
    final at = Offset(p.dx * size.width, p.dy * size.height);
    _trail.add(at);
    if (_trail.length > 40) _trail.removeAt(0);
    final reach = math.min(size.width, size.height) * const [0.09, 0.07, 0.055][level];
    // The next dot, or one just after it (a shaky hand skips one).
    for (var k = 0; k < 3 && _next + k < _dots.length; k++) {
      if ((_onScreen(_dots[_next + k]) - at).distance < reach) {
        _next += k + 1;
        break;
      }
    }
    if (_next >= _dots.length) {
      _done++;
      score = _done;
      lives = math.min(3, _done);
      _cheer = 1.4;
      Timer(const Duration(milliseconds: 1400), () {
        if (mounted && playing) _nextShape();
      });
    }
  }

  @override
  Widget build(BuildContext context) => moveFrame(
    title: 'Air Trace',
    colors: const [Color(0xFF14365A), Color(0xFF2FB8A8)],
    hud: '${_left.ceil()}s',
    icon: Icons.gesture_rounded,
    lifeIcon: Icons.star_rounded,
    pitch: 'Draw in the air! Follow the glowing dot with your finger to trace each picture.',
    options: Column(
      children: [
        kidsLevelChips(const ['Shapes', 'Numbers', 'Letters'], _set, (i) => setState(() => _set = i)),
        const SizedBox(height: 14),
        kidsLevelChips(const ['Big dots', 'Medium', 'Tricky'], level, (i) => setState(() => level = i)),
        const SizedBox(height: 14),
        steerChips('Draw with', const ['My nose', 'My hand']),
      ],
    ),
    overDetail: 'You traced $_done pictures',
    painter: _TracePainter(this),
  );
}

class _TracePainter extends CustomPainter {
  _TracePainter(this.g);
  final _AirTraceState g;

  @override
  void paint(Canvas canvas, Size size) {
    if (g._dots.isEmpty) return;
    final short = math.min(size.width, size.height);
    // The faint picture to follow.
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = short * 0.035
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.14);
    for (final stroke in g._shape.strokes) {
      final path = Path();
      for (var i = 0; i < stroke.length; i++) {
        final o = g._onScreen(stroke[i]);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, guide);
    }
    // The dots: done (gold, joined up), next (glowing), still to go.
    final done = Paint()
      ..color = const Color(0xFFF3DA8A)
      ..strokeWidth = short * 0.03
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < g._next && i < g._dots.length; i++) {
      final a = g._dots[i - 1], b = g._dots[i];
      if ((a - b).distance < 0.2) canvas.drawLine(g._onScreen(a), g._onScreen(b), done);
    }
    for (var i = 0; i < g._dots.length; i++) {
      final o = g._onScreen(g._dots[i]);
      if (i < g._next) {
        canvas.drawCircle(o, short * 0.018, Paint()..color = const Color(0xFFF3DA8A));
      } else if (i == g._next) {
        final pulse = 1 + 0.25 * math.sin(g.time * 8);
        canvas.drawCircle(o, short * 0.05 * pulse, Paint()..color = const Color(0x66FFFFFF));
        canvas.drawCircle(o, short * 0.028, Paint()..color = Colors.white);
        if (i == 0) _say(canvas, 'START', o - Offset(0, short * 0.08), short * 0.06, Colors.white);
      } else {
        canvas.drawCircle(o, short * 0.012, Paint()..color = Colors.white54);
      }
    }
    // The hand's trail.
    for (var i = 1; i < g._trail.length; i++) {
      canvas.drawLine(g._trail[i - 1], g._trail[i], Paint()
        ..color = const Color(0xFF39D0FF).withValues(alpha: i / g._trail.length * 0.8)
        ..strokeWidth = short * 0.012
        ..strokeCap = StrokeCap.round);
    }
    final label = 'Trace the ${g._shape.name}';
    _say(canvas, g._cheer > 0 ? 'WELL DONE!' : label, Offset(size.width / 2, size.height * 0.07), short * 0.07, g._cheer > 0 ? const Color(0xFF7CFF6B) : Colors.white);
    if (g._cheer > 0) {
      for (var i = 0; i < 14; i++) {
        final a = i * math.pi * 2 / 14;
        final r = short * (0.1 + (1.4 - g._cheer) * 0.4);
        canvas.drawCircle(size.center(Offset.zero) + Offset(math.cos(a), math.sin(a)) * r, short * 0.015, Paint()..color = const Color(0xFFF3DA8A));
      }
    }
  }

  @override
  bool shouldRepaint(_TracePainter old) => true;
}

// ── Freeze Dance ──────────────────────────────────────────────────────────

/// How much the player is moving: the tracked point's speed (play-area
/// widths a second), smoothed over about half a second.
class MotionMeter {
  Offset? _last;
  double level = 0;

  void add(Offset? p, double dt) {
    if (p == null || dt <= 0) return;
    final last = _last;
    _last = p;
    if (last == null) return;
    final speed = (p - last).distance / dt;
    final k = math.min(1.0, dt * 2.5);
    level += (speed - level) * k;
  }

  void reset() {
    _last = null;
    level = 0;
  }
}


/// Dance while the music plays; freeze the moment it stops.
class FreezeDance extends StatefulWidget {
  const FreezeDance({super.key, required this.container, required this.onBack, this.tones});
  final AppContainer container;
  final VoidCallback onBack;
  final KidsTones? tones;

  @override
  State<FreezeDance> createState() => _FreezeDanceState();
}

class _FreezeDanceState extends _MoveGame<FreezeDance> {
  static const _seconds = 90.0;
  final _rng = math.Random();
  final meter = MotionMeter();
  bool _frozen = false, _caught = false, _musicReady = false;
  double _phase = 0, _left = _seconds, _flash = 0, _still = 0, _phraseLeft = 0;
  int _freezes = 0;
  String _message = '';

  /// The DJ, and the song picked (the last choice shuffles).
  late final KidsDj _dj = KidsDj(container.sound.playFile, container.sound.stopFile);
  int _pick = djSongs.length;
  int _song = 0;

  String get songName => djSongs[_song].$1;

  @override
  void dispose() {
    unawaited(_dj.stop());
    super.dispose();
  }

  @override
  Future<void> finish() async {
    unawaited(_dj.stop());
    await super.finish();
  }

  /// The music comes (back) in on a new phrase.
  void _music() {
    if (!_musicReady) return;
    unawaited(_dj.nextPhrase());
    _phraseLeft = djPhraseSeconds;
  }

  @override
  AppContainer get container => widget.container;
  @override
  VoidCallback get onBack => widget.onBack;
  @override
  String get scoreKey => 'freeze${level + 1}';
  @override
  int starsFor(int s) => s >= 150 ? 3 : (s >= 80 ? 2 : (s >= 30 ? 1 : 0));

  /// Faster than this while frozen and you moved (per level).
  double get _freezeLimit => const [0.35, 0.25, 0.17][level];

  @override
  void reset() {
    meter.reset();
    _frozen = false;
    _phase = 4 + _rng.nextDouble() * 4;
    _left = _seconds;
    _freezes = 0;
    _message = 'DANCE!';
    _flash = 1.2;
    _musicReady = false;
    _song = _pick >= djSongs.length ? _rng.nextInt(djSongs.length) : _pick;
    unawaited(_dj.load(_song).then((_) {
      if (!mounted || !playing) return;
      _musicReady = true;
      if (!_frozen) _music();
    }));
  }

  @override
  void step(double dt) {
    _left -= dt;
    _flash = math.max(0, _flash - dt);
    if (_left <= 0) {
      unawaited(finish());
      return;
    }
    meter.add(hands?.point.value, dt);
    _phase -= dt;
    if (!_frozen) {
      // The music plays, phrase after phrase; points for moving.
      if (_musicReady) {
        _phraseLeft -= dt;
        if (_phraseLeft <= 0) _music();
      }
      if (meter.level > 0.12) {
        _still = 0;
        _scoreTimer += dt;
        if (_scoreTimer >= 0.5) {
          _scoreTimer = 0;
          score++;
        }
      } else {
        _still += dt;
        if (_still > 2.5) {
          _message = 'KEEP DANCING!';
          _flash = 1;
          _still = 0;
        }
      }
      if (_phase <= 0) {
        _frozen = true;
        _caught = false;
        _phase = const [3.0, 4.0, 5.0][level];
        _message = 'FREEZE!';
        _flash = 1.2;
        // The DJ cuts the record.
        unawaited(_dj.freeze());
      }
    } else {
      // Frozen: a short grace to stop, then any movement counts.
      final grace = const [3.0, 4.0, 5.0][level] - _phase > 0.7;
      if (grace && !_caught && meter.level > _freezeLimit) {
        _caught = true;
        _message = 'YOU MOVED!';
        _flash = 1.2;
        if (!loseLife()) return;
      }
      if (_phase <= 0) {
        if (!_caught) {
          _freezes++;
          score += 10;
          _message = 'GREAT FREEZE! +10';
        } else {
          _message = 'DANCE!';
        }
        _flash = 1.2;
        _frozen = false;
        _phase = 4 + _rng.nextDouble() * 5;
        _music();
      }
    }
  }

  double _scoreTimer = 0;

  @override
  Widget build(BuildContext context) => moveFrame(
    title: 'Freeze Dance',
    colors: const [Color(0xFF5A1F6B), Color(0xFFFF6B9A)],
    hud: '${_left.ceil()}s',
    icon: Icons.music_note_rounded,
    pitch: 'The DJ is spinning! Dance while the music plays. When the record stops, FREEZE like a statue until it starts again.',
    options: Column(
      children: [
        kidsLevelChips(const ['Easy', 'Medium', 'Hard'], level, (i) => setState(() => level = i)),
        const SizedBox(height: 14),
        Text('DJ mix', style: kidsText(18, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        kidsLevelChips([for (final (name, _) in djSongs) name, 'Shuffle'], _pick, (i) => setState(() => _pick = i)),
        const SizedBox(height: 14),
        steerChips('The camera watches', const ['My head', 'My hand']),
      ],
    ),
    overDetail: 'Score $score · $_freezes great freezes',
    painter: _DancePainter(this),
  );
}

class _DancePainter extends CustomPainter {
  _DancePainter(this.g);
  final _FreezeDanceState g;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final c = size.center(Offset.zero);
    final short = math.min(size.width, size.height);
    if (!g._frozen) {
      // Disco lights sweeping round.
      const colors = [Color(0xFFFF4D9A), Color(0xFF39D0FF), Color(0xFFF3DA8A), Color(0xFF7CFF6B), Color(0xFFB04BFF)];
      for (var i = 0; i < 5; i++) {
        final a = g.time * (0.8 + i * 0.15) + i * 1.3;
        final beam = Path()
          ..moveTo(c.dx, -20)
          ..lineTo(c.dx + math.cos(a) * size.width - 60, size.height + 20)
          ..lineTo(c.dx + math.cos(a) * size.width + 60, size.height + 20)
          ..close();
        canvas.drawPath(beam, Paint()..color = colors[i].withValues(alpha: 0.18));
      }
    } else {
      canvas.drawRect(full, Paint()..color = const Color(0xFF9FD8FF).withValues(alpha: 0.28));
      final rng = math.Random(4);
      for (var i = 0; i < 26; i++) {
        final x = rng.nextDouble() * size.width;
        final y = (rng.nextDouble() * size.height + g.time * 30 * (0.5 + rng.nextDouble())) % size.height;
        _flake(canvas, Offset(x, y), short * 0.015);
      }
    }
    // The dancing star: bounces to the beat, turns to ice when frozen.
    // The star bounces on the beat.
    final bounce = g._frozen ? 0.0 : math.sin(g.time * math.pi / djBeat).abs() * short * 0.05;
    final star = c + Offset(0, short * 0.12 - bounce);
    final tilt = g._frozen ? 0.0 : math.sin(g.time * 4) * 0.25;
    final r = short * 0.16;
    final path = Path();
    for (var i = 0; i <= 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5 + tilt;
      final rr = i.isEven ? r : r * 0.48;
      final p = star + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, Paint()..color = g._frozen ? const Color(0xFFBFE9FF) : const Color(0xFFFFD93D));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = g._frozen ? Colors.white : const Color(0xFFFF9F1C));
    for (final s in const [-1, 1]) {
      canvas.drawCircle(star + Offset(s * r * 0.2, -r * 0.05), r * 0.08, Paint()..color = const Color(0xFF1A1340));
    }
    canvas.drawArc(Rect.fromCenter(center: star + Offset(0, r * 0.12), width: r * 0.35, height: r * 0.22), 0.2, math.pi - 0.4, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF1A1340));
    if (!g._frozen) {
      for (var i = 0; i < 3; i++) {
        final a = g.time * 2 + i * 2.1;
        final o = star + Offset(math.cos(a) * r * 1.6, math.sin(a) * r * 0.9 - r * 0.6);
        _say(canvas, '♪', o, short * 0.08, Colors.white70);
      }
    }
    if (g._musicReady && !g._frozen) {
      _say(canvas, 'DJ MIX: ${g.songName.toUpperCase()}', Offset(c.dx, size.height * 0.88), short * 0.045, Colors.white70);
    }
    // The motion meter: how much you are moving, and the freeze line.
    final meterBox = Rect.fromLTWH(24, size.height - 34, size.width - 48, 14);
    canvas.drawRRect(RRect.fromRectAndRadius(meterBox, const Radius.circular(7)), Paint()..color = Colors.white12);
    final fill = (g.meter.level / 1.2).clamp(0.0, 1.0);
    final over = g._frozen && g.meter.level > g._freezeLimit;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(meterBox.left, meterBox.top, meterBox.width * fill, meterBox.height), const Radius.circular(7)),
      Paint()..color = over ? const Color(0xFFFF4D6D) : (g._frozen ? const Color(0xFF9FD8FF) : const Color(0xFF7CFF6B)),
    );
    if (g._frozen) {
      final x = meterBox.left + meterBox.width * (g._freezeLimit / 1.2);
      canvas.drawRect(Rect.fromLTWH(x - 1.5, meterBox.top - 6, 3, meterBox.height + 12), Paint()..color = Colors.white);
    }
    final big = g._flash > 0 || g._frozen;
    if (big) {
      final text = g._frozen && g._flash <= 0 ? (g._caught ? 'OOPS!' : 'STAY STILL...') : g._message;
      final color = text.startsWith('YOU') || text == 'OOPS!' ? const Color(0xFFFF4D6D) : (g._frozen ? Colors.white : const Color(0xFFF3DA8A));
      _say(canvas, text, Offset(c.dx, size.height * 0.14), short * 0.11, color);
    }
  }

  void _flake(Canvas canvas, Offset c, double r) {
    final p = Paint()
      ..color = Colors.white70
      ..strokeWidth = 2;
    for (var i = 0; i < 3; i++) {
      final a = i * math.pi / 3;
      canvas.drawLine(c - Offset(math.cos(a), math.sin(a)) * r, c + Offset(math.cos(a), math.sin(a)) * r, p);
    }
  }

  @override
  bool shouldRepaint(_DancePainter old) => true;
}
