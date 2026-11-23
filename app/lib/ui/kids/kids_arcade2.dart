import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app_container.dart';
import 'kids_activities.dart';
import 'kids_arcade.dart' show Dir, DirMove, arcadeText;
import 'kids_games.dart';
import 'kids_logic.dart' show KidsScores;
import 'kids_motion.dart' show KidsHands, KidsMotionPanel, StepTrigger, kidsPlayWithChips, kidsTrackerFor;

/// More of the Kids Portal's Arcade shelf: Hop Across (cross the road and
/// the river), Sky Glide (fly between the pillars) and Fox Run (jump over
/// what is in the way). Original characters and art.

/// The score line in the frame's corner: a label, the score and the lives.
Widget arcadeHud(BuildContext context, String label, int score, int lives, IconData lifeIcon, Color lifeColor) => ConstrainedBox(
  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.55),
  child: FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: arcadeText(30, const Color(0xFF39D0FF))),
        const SizedBox(width: 18),
        Text(score.toString().padLeft(5, '0'), style: arcadeText(36, const Color(0xFFFFE066))),
        const SizedBox(width: 14),
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(lifeIcon, size: 24, color: i < lives ? lifeColor : Colors.white24),
          ),
      ],
    ),
  ),
);

/// Four arrow buttons, for the games that move a step at a time.
Widget arcadePad(void Function(Dir) onDir) {
  Widget b(IconData icon, Dir d) => KidsBounce(
    onTap: () => onDir(d),
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
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      b(Icons.arrow_upward_rounded, Dir.up),
      const SizedBox(height: 8),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [b(Icons.arrow_back_rounded, Dir.left), const SizedBox(width: 84), b(Icons.arrow_forward_rounded, Dir.right)],
      ),
      const SizedBox(height: 8),
      b(Icons.arrow_downward_rounded, Dir.down),
    ],
  );
}

void _text(Canvas canvas, String text, Offset centre, double size, Color color) {
  final tp = TextPainter(text: TextSpan(text: text, style: arcadeText(size, color)), textDirection: TextDirection.ltr)..layout();
  tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
}

/// What the arcade games share: the game loop, score, lives, the start
/// panel and the game-over card.
abstract class _ArcadeGame<T extends StatefulWidget> extends State<T> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double time = 0;
  int score = 0, lives = 3, level = 0, stage = 1;
  bool playing = false, over = false, newBest = false;

  /// The high-score key (one per difficulty).
  String get scoreKey;
  int starsFor(int score);
  VoidCallback get onBack;

  /// Sets up a new game.
  void reset();

  /// Moves the game on by [dt] seconds.
  void step(double dt);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void begin() {
    setState(() {
      score = 0;
      lives = 3;
      stage = 1;
      time = 0;
      playing = true;
      over = false;
      _last = Duration.zero;
      reset();
    });
    _ticker.start();
  }

  void _tick(Duration now) {
    final dt = math.min(0.033, _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6);
    _last = now;
    time += dt;
    step(dt);
    if (mounted && _ticker.isActive) setState(() {});
  }

  /// Loses a life: false when that was the last one (the game ends).
  bool loseLife() {
    lives--;
    if (lives > 0) return true;
    unawaited(_finish());
    return false;
  }

  Future<void> _finish() async {
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

  Widget arcadeFrame({
    required String title,
    required List<Color> colors,
    required String hud,
    required IconData lifeIcon,
    required Color lifeColor,
    required String overDetail,
    required IconData icon,
    required String pitch,
    required Widget options,
    required WidgetBuilder game,
  }) => KidsActivityFrame(
    title: title,
    colors: colors,
    onBack: onBack,
    trailing: playing ? arcadeHud(context, hud, score, lives, lifeIcon, lifeColor) : null,
    child: over
        ? KidsResult(
            title: 'GAME OVER',
            detail: overDetail,
            stars: starsFor(score),
            newBest: newBest,
            onAgain: () => setState(() => over = false),
          )
        : !playing
        ? KidsStartPanel(
            icon: icon,
            pitch: pitch,
            best: KidsScores.best(scoreKey).then((b) => b == null ? null : 'High score: $b'),
            options: options,
            onStart: begin,
          )
        : game(context),
  );
}

// ── Hop Across ────────────────────────────────────────────────────────────

const hopCols = 11, hopRows = 13;

/// The goal row's nests, by column.
const hopNests = [1, 3, 5, 7, 9];

/// One lane of traffic or of the river. [pattern] repeats along the lane:
/// '.' is empty, anything else a car (road) or a log (river). It slides by
/// [speed] cells a second.
class HopLane {
  HopLane(this.pattern, this.speed, {this.river = false});
  final String pattern;
  final double speed;
  final bool river;

  /// Whether a car or log covers [u] (in cells along the lane) at [t].
  bool solidAt(double u, double t) {
    final p = (u - speed * t) % pattern.length;
    return pattern[p.floor() % pattern.length] != '.';
  }

  /// Each car or log: where it starts in the pattern and how long it is.
  List<(int, int)> get runs {
    final out = <(int, int)>[];
    final n = pattern.length;
    for (var i = 0; i < n; i++) {
      if (pattern[i] == '.' || pattern[(i - 1 + n) % n] != '.') continue;
      var len = 0;
      while (len < n && pattern[(i + len) % n] != '.') {
        len++;
      }
      out.add((i, len));
    }
    return out;
  }
}

/// The lane sets, a set per stage (then round again, faster). Rows 1-5 are
/// the river (top), 7-11 the road.
const _hopSets = [
  (
    river: [('====....', 1.0), ('===....===...', -1.3), ('=====.....', 0.8), ('===...===.....', -1.1), ('====.....====....', 1.2)],
    road: [('xx......', -1.6), ('x......x.....', 1.2), ('xxx.........', -1.0), ('x....x.........', 1.8), ('xx........', -0.9)],
  ),
  (
    river: [('===....', 1.2), ('===....===...', -1.5), ('====......', 1.0), ('===...===....', -1.3), ('===.....', 1.4)],
    road: [('xx....', -1.8), ('x....x....', 1.4), ('xxx.......', -1.2), ('x...x......', 2.0), ('xx.....x....', -1.1)],
  ),
  (
    river: [('==....==....', 1.4), ('===.....', -1.6), ('==...===....', 1.1), ('===.....', -1.5), ('==....==...', 1.6)],
    road: [('xx...x....', -2.0), ('x...x...', 1.6), ('xxx....x...', -1.4), ('x...x...x....', 2.2), ('xx....xx....', -1.3)],
  ),
];

/// The lanes for a stage: null for a safe row.
List<HopLane?> hopLanes(int stage, int difficulty) {
  final set = _hopSets[(stage - 1) % _hopSets.length];
  final round = (stage - 1) ~/ _hopSets.length;
  final pace = math.min(2.2, 0.85 + difficulty * 0.2 + round * 0.25 + (stage - 1) * 0.04);
  return [
    null,
    for (final (p, v) in set.river) HopLane(p, v * pace, river: true),
    null,
    for (final (p, v) in set.road) HopLane(p, v * pace),
    null,
  ];
}

/// Help the chick across the road and the river to the nests.
class HopAcross extends StatefulWidget {
  const HopAcross({super.key, required this.onBack, this.container});
  final VoidCallback onBack;

  /// For hopping by hand or head (none: buttons and swipes only).
  final AppContainer? container;

  @override
  State<HopAcross> createState() => _HopAcrossState();
}

class _HopAcrossState extends _ArcadeGame<HopAcross> {
  late List<HopLane?> _lanes;
  final _nests = List.filled(hopNests.length, false);
  double _px = 5, _hopAnim = 0, _hurt = 0, _banner = 0;
  int _py = hopRows - 1, _bestRow = hopRows - 1;
  Dir _facing = Dir.up;
  KidsHands? _tracker;
  int _playWith = 0; // buttons, hand, head
  final _trigger = StepTrigger();

  @override
  void dispose() {
    _tracker?.dispose();
    super.dispose();
  }

  @override
  String get scoreKey => 'hop${level + 1}';
  @override
  VoidCallback get onBack => widget.onBack;
  @override
  int starsFor(int s) => s >= 4000 ? 3 : (s >= 2000 ? 2 : (s >= 600 ? 1 : 0));

  @override
  void reset() {
    _tracker?.dispose();
    _tracker = kidsTrackerFor(widget.container, _playWith);
    _lanes = hopLanes(stage, level);
    _nests.fillRange(0, _nests.length, false);
    _respawn();
    _banner = 2;
  }

  void _respawn() {
    _px = 5;
    _py = hopRows - 1;
    _bestRow = _py;
    _hurt = 0;
    _facing = Dir.up;
  }

  void _hop(Dir d) {
    if (!playing || _hurt > 0) return;
    _facing = d;
    final nx = _px + d.dx, ny = _py + d.dy;
    if (ny >= hopRows || nx < -0.4 || nx > hopCols - 0.6) return;
    if (ny == 0) {
      // Only into an empty nest (near enough counts).
      var slot = -1;
      for (var i = 0; i < hopNests.length; i++) {
        if ((nx - hopNests[i]).abs() <= 0.6 && !_nests[i]) slot = i;
      }
      if (slot < 0) return;
      _nests[slot] = true;
      score += 200;
      if (_nests.every((n) => n)) {
        stage++;
        score += 1000;
        _lanes = hopLanes(stage, level);
        _nests.fillRange(0, _nests.length, false);
        _banner = 2;
      }
      _respawn();
      return;
    }
    _px = nx;
    _py = ny;
    final lane = _lanes[ny];
    if (lane == null || !lane.river) _px = _px.roundToDouble().clamp(0, hopCols - 1);
    if (_py < _bestRow) {
      _bestRow = _py;
      score += 10;
    }
    _hopAnim = 0.15;
  }

  @override
  void step(double dt) {
    final tracker = _tracker;
    if (tracker != null) {
      tracker.step(dt);
      final s = _trigger.update(tracker.point.value);
      if (s != null) _hop(switch (s) { (1, _) => Dir.right, (-1, _) => Dir.left, (_, 1) => Dir.down, _ => Dir.up });
    }
    _hopAnim = math.max(0, _hopAnim - dt);
    _banner = math.max(0, _banner - dt);
    if (_hurt > 0) {
      _hurt -= dt;
      if (_hurt <= 0 && loseLife()) _respawn();
      return;
    }
    final lane = _lanes[_py];
    if (lane == null) return;
    if (lane.river) _px += lane.speed * dt;
    final u = _px + 0.5;
    final dead = lane.river
        ? !lane.solidAt(u, time) || _px < -0.5 || _px > hopCols - 0.5
        : lane.solidAt(u - 0.3, time) || lane.solidAt(u + 0.3, time);
    if (dead) _hurt = 0.9;
  }

  Widget _controls() {
    final t = _tracker;
    if (t == null) return arcadePad(_hop);
    return KidsMotionPanel(hands: t, hint: t.head ? 'Nod or lean to hop, then back to the middle' : 'Push your hand to hop, then back to the middle');
  }

  @override
  Widget build(BuildContext context) => arcadeFrame(
    title: 'Hop Across',
    colors: const [Color(0xFF12324A), Color(0xFF2F7B4A)],
    hud: 'STAGE $stage',
    lifeIcon: Icons.egg_rounded,
    lifeColor: const Color(0xFFFFE066),
    overDetail: 'Score $score · reached stage $stage',
    icon: Icons.directions_walk_rounded,
    pitch: 'Hop the chick over the road and across the river on the logs. Fill all five nests!',
    options: Column(
      children: [
        kidsLevelChips(const ['Easy', 'Medium', 'Hard'], level, (i) => setState(() => level = i)),
        if (widget.container != null) ...[
          const SizedBox(height: 14),
          kidsPlayWithChips(_playWith, (i) => setState(() => _playWith = i)),
        ],
      ],
    ),
    game: (context) => LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth > box.maxHeight;
        final board = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _hop(Dir.up),
          onPanEnd: (d) {
            final v = d.velocity.pixelsPerSecond;
            if (v.distance < 60) return;
            _hop(v.dx.abs() > v.dy.abs() ? (v.dx > 0 ? Dir.right : Dir.left) : (v.dy > 0 ? Dir.down : Dir.up));
          },
          child: Center(
            child: AspectRatio(aspectRatio: hopCols / hopRows, child: CustomPaint(painter: _HopPainter(this))),
          ),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: wide
              ? Row(children: [Expanded(child: board), const SizedBox(width: 16), _controls()])
              : Column(children: [Expanded(child: board), const SizedBox(height: 12), _controls()]),
        );
      },
    ),
  );
}

class _HopPainter extends CustomPainter {
  _HopPainter(this.g);
  final _HopAcrossState g;

  static const _cars = [Color(0xFFFF4D6D), Color(0xFF39D0FF), Color(0xFFFFB627), Color(0xFFB04BFF), Color(0xFF7CFF6B)];

  void _chick(Canvas canvas, Offset c, double cell, Dir facing, {double squash = 0}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1 + squash, 1 - squash);
    canvas.drawCircle(Offset(0, cell * 0.04), cell * 0.36, Paint()..color = const Color(0xFFFFD93D));
    canvas.drawCircle(Offset(-cell * 0.1, -cell * 0.06), cell * 0.12, Paint()..color = const Color(0xFFFFF1A8));
    // A little tuft, wings, beak, eyes.
    canvas.drawCircle(Offset(0, -cell * 0.36), cell * 0.07, Paint()..color = const Color(0xFFFFB627));
    for (final s in const [-1, 1]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(s * cell * 0.33, cell * 0.1), width: cell * 0.16, height: cell * 0.26), Paint()..color = const Color(0xFFFFB627));
    }
    final look = Offset(facing.dx * cell * 0.06, facing.dy * cell * 0.05);
    final beak = Path()
      ..moveTo(-cell * 0.08, cell * 0.04)
      ..lineTo(cell * 0.08, cell * 0.04)
      ..lineTo(0, cell * 0.17)
      ..close();
    canvas.drawPath(beak.shift(look), Paint()..color = const Color(0xFFFF7A3D));
    for (final s in const [-1, 1]) {
      canvas.drawCircle(Offset(s * cell * 0.13, -cell * 0.08) + look, cell * 0.06, Paint()..color = const Color(0xFF1A1340));
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / hopCols;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)));
    Rect row(int y) => Rect.fromLTWH(0, y * cell, size.width, cell);
    // The hedge with its nests.
    canvas.drawRect(row(0), Paint()..color = const Color(0xFF1F6B3A));
    for (var x = 0; x < hopCols; x++) {
      canvas.drawCircle(Offset((x + 0.5) * cell, cell * 0.3), cell * 0.32, Paint()..color = const Color(0xFF2A8A4C));
    }
    for (var i = 0; i < hopNests.length; i++) {
      final c = Offset((hopNests[i] + 0.5) * cell, cell * 0.55);
      canvas.drawOval(Rect.fromCenter(center: c, width: cell * 0.9, height: cell * 0.6), Paint()..color = const Color(0xFF8A5A2B));
      canvas.drawOval(Rect.fromCenter(center: c, width: cell * 0.62, height: cell * 0.36), Paint()..color = const Color(0xFF4A2E14));
      if (g._nests[i]) _chick(canvas, c - Offset(0, cell * 0.1), cell * 0.8, Dir.down);
    }
    // The river.
    canvas.drawRect(Rect.fromLTWH(0, cell, size.width, cell * 5), Paint()..color = const Color(0xFF1C5DA8));
    final wave = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = cell * 0.05
      ..strokeCap = StrokeCap.round;
    for (var y = 1; y <= 5; y++) {
      for (var x = 0; x < hopCols; x++) {
        final dx = ((g.time * 0.6 + x * 0.37 + y * 0.21) % 1) * cell;
        canvas.drawLine(Offset(x * cell + dx * 0.4, (y + 0.3) * cell), Offset(x * cell + dx * 0.4 + cell * 0.25, (y + 0.3) * cell), wave);
      }
    }
    // The meadows and the road.
    for (final y in [6, hopRows - 1]) {
      canvas.drawRect(row(y), Paint()..color = const Color(0xFF3E9A4E));
      for (var x = 0; x < hopCols; x++) {
        canvas.drawCircle(Offset((x + 0.3) * cell, (y + 0.7) * cell), cell * 0.05, Paint()..color = const Color(0xFFFFE066));
      }
    }
    canvas.drawRect(Rect.fromLTWH(0, 7 * cell, size.width, cell * 5), Paint()..color = const Color(0xFF2B2B3A));
    final dash = Paint()..color = Colors.white.withValues(alpha: 0.35);
    for (var y = 8; y <= 11; y++) {
      for (var x = 0.0; x < hopCols; x += 1) {
        canvas.drawRect(Rect.fromLTWH((x + 0.2) * cell, y * cell - cell * 0.03, cell * 0.5, cell * 0.06), dash);
      }
    }
    // Logs and cars.
    for (var y = 0; y < g._lanes.length; y++) {
      final lane = g._lanes[y];
      if (lane == null) continue;
      final n = lane.pattern.length;
      final shift = (lane.speed * g.time) % n;
      for (final (start, len) in lane.runs) {
        for (var k = -2; k * n < hopCols + n; k++) {
          final u = start + shift + k * n;
          if (u + len < -1 || u > hopCols + 1) continue;
          final r = Rect.fromLTWH(u * cell, y * cell, len * cell, cell);
          if (lane.river) {
            final log = RRect.fromRectAndRadius(r.deflate(cell * 0.1), Radius.circular(cell * 0.3));
            canvas.drawRRect(log, Paint()..color = const Color(0xFF8A5A2B));
            canvas.drawRect(Rect.fromLTWH(log.left + cell * 0.2, log.top + cell * 0.12, log.width - cell * 0.4, cell * 0.1), Paint()..color = const Color(0xFFB07A44));
            for (final ex in [log.left + cell * 0.22, log.right - cell * 0.22]) {
              canvas.drawCircle(Offset(ex, log.center.dy), cell * 0.16, Paint()..color = const Color(0xFFD9A066));
              canvas.drawCircle(Offset(ex, log.center.dy), cell * 0.07, Paint()..color = const Color(0xFF8A5A2B));
            }
          } else {
            final body = r.deflate(cell * 0.14);
            final color = _cars[(y + start) % _cars.length];
            for (final wx in [body.left + cell * 0.25, body.right - cell * 0.25]) {
              for (final wy in [body.top, body.bottom]) {
                canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(wx, wy), width: cell * 0.26, height: cell * 0.14), Radius.circular(cell * 0.04)), Paint()..color = Colors.black);
              }
            }
            canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(cell * 0.18)), Paint()..color = color);
            final front = lane.speed > 0 ? body.right - cell * 0.42 : body.left + cell * 0.12;
            canvas.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTWH(front, body.top + body.height * 0.2, cell * 0.3, body.height * 0.6), Radius.circular(cell * 0.06)),
              Paint()..color = const Color(0xFFBFE9FF),
            );
            final light = lane.speed > 0 ? body.right - cell * 0.04 : body.left + cell * 0.04;
            for (final ly in [body.top + body.height * 0.2, body.bottom - body.height * 0.2]) {
              canvas.drawCircle(Offset(light, ly), cell * 0.05, Paint()..color = const Color(0xFFFFF4B0));
            }
          }
        }
      }
    }
    // The chick.
    final c = Offset((g._px + 0.5) * cell, (g._py + 0.5) * cell);
    if (g._hurt > 0) {
      _text(canvas, 'OOPS!', c - Offset(0, cell * 0.2), cell * 0.8, const Color(0xFFFF4D6D));
      for (var i = 0; i < 6; i++) {
        final a = i * math.pi / 3 + g.time * 3;
        canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * cell * 0.4 * (1.2 - g._hurt), cell * 0.06, Paint()..color = const Color(0xFFFFE066));
      }
    } else {
      _chick(canvas, c, cell, g._facing, squash: g._hopAnim > 0 ? 0.12 : 0);
    }
    if (g._banner > 0) {
      _text(canvas, 'STAGE ${g.stage}', Offset(size.width / 2, 6.5 * cell), cell * 1.1, const Color(0xFFFFE066));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HopPainter old) => true;
}

// ── Sky Glide ─────────────────────────────────────────────────────────────

const _skyW = 100.0, _skyH = 60.0, _pipX = 24.0, _pillarW = 9.0;

/// The opening between a pair of pillars: smaller on harder levels and
/// later zones, never too small to fly through.
double skyGap(int difficulty, int stage) => (30 - difficulty * 4 - (stage - 1) * 1.2).clamp(17.0, 30.0);

/// How fast the pillars come (units a second).
double skySpeed(int difficulty, int stage) => math.min(40, 24 + difficulty * 3 + (stage - 1) * 1.5);

/// Where the next opening's centre goes: inside the sky and not too far
/// from the last one.
double nextGapY(double previous, double gap, math.Random rng) {
  final lo = gap / 2 + 4, hi = _skyH - gap / 2 - 4;
  final y = previous + (rng.nextDouble() * 2 - 1) * 18;
  return y.clamp(lo, hi);
}

class _Pillar {
  _Pillar(this.x, this.gapY, this.gap);
  double x;
  final double gapY, gap;
  bool passed = false, star = true;
}

/// The skies, a zone per stage: top colour, bottom colour, pillar colour.
const _skyZones = [
  ('DAY', Color(0xFF4FA8FF), Color(0xFFBDE6FF), Color(0xFF8E7CFF)),
  ('SUNSET', Color(0xFF6A3FA0), Color(0xFFFF9F6B), Color(0xFFFF6BA8)),
  ('NIGHT', Color(0xFF0B1240), Color(0xFF283A80), Color(0xFF5BC8FF)),
  ('SPACE', Color(0xFF05010F), Color(0xFF2A0B4A), Color(0xFFB98CFF)),
];

/// Fly Pip between the crystal pillars: tap to flap, or steer with the head.
class SkyGlide extends StatefulWidget {
  const SkyGlide({super.key, required this.container, required this.onBack});
  final AppContainer container;
  final VoidCallback onBack;

  @override
  State<SkyGlide> createState() => _SkyGlideState();
}

class _SkyGlideState extends _ArcadeGame<SkyGlide> {
  final _rng = math.Random();
  final _pillars = <_Pillar>[];
  KidsHands? _tracker;
  int _steer = 0; // 0 tap, 1 head, 2 hand
  double _y = _skyH / 2, _vy = 0, _safe = 0, _ready = 0, _banner = 0;
  int _passed = 0;

  @override
  String get scoreKey => 'sky${level + 1}';
  @override
  VoidCallback get onBack => widget.onBack;
  @override
  int starsFor(int s) => s >= 600 ? 3 : (s >= 300 ? 2 : (s >= 100 ? 1 : 0));

  @override
  void dispose() {
    _tracker?.dispose();
    super.dispose();
  }

  @override
  void reset() {
    _tracker?.dispose();
    _tracker = _steer == 0 ? null : KidsHands(widget.container.motion, head: _steer == 1, body: false);
    _pillars.clear();
    _y = _skyH / 2;
    _vy = 0;
    _passed = 0;
    _safe = 0;
    _ready = 1.2;
    _banner = 2;
  }

  void _flap() {
    if (!playing) return;
    _ready = 0;
    _vy = -40;
  }

  @override
  void step(double dt) {
    _safe = math.max(0, _safe - dt);
    _banner = math.max(0, _banner - dt);
    final tracker = _tracker;
    if (tracker != null) {
      tracker.step(dt);
      final p = tracker.point.value;
      if (p != null) {
        _ready = 0;
        _y += (p.dy * _skyH - _y) * math.min(1, dt * 8);
        _vy = 0;
      }
    }
    if (_ready > 0) {
      // Hover until the first flap.
      _ready -= dt;
      _y = _skyH / 2 + math.sin(time * 4) * 1.5;
      if (tracker == null) return;
    } else if (tracker == null || tracker.point.value == null) {
      _vy = math.min(60, _vy + 110 * dt);
      _y += _vy * dt;
    }
    if (_y < 3) {
      _y = 3;
      _vy = 0;
    }
    final speed = skySpeed(level, stage);
    for (final p in _pillars) {
      p.x -= speed * dt;
    }
    _pillars.removeWhere((p) => p.x < -_pillarW - 2);
    if (_pillars.isEmpty || _pillars.last.x < _skyW - 34) {
      final gap = skyGap(level, stage);
      _pillars.add(_Pillar(_skyW + 4, nextGapY(_pillars.isEmpty ? _skyH / 2 : _pillars.last.gapY, gap, _rng), gap));
    }
    var hit = _y > _skyH - 3;
    for (final p in _pillars) {
      final inside = _pipX + 3 > p.x && _pipX - 3 < p.x + _pillarW;
      if (inside && (_y - 3 < p.gapY - p.gap / 2 || _y + 3 > p.gapY + p.gap / 2)) hit = true;
      if (p.star && (Offset(_pipX, _y) - Offset(p.x + _pillarW / 2, p.gapY)).distance < 5) {
        p.star = false;
        score += 25;
      }
      if (!p.passed && p.x + _pillarW < _pipX) {
        p.passed = true;
        score += 10;
        _passed++;
        if (_passed % 10 == 0) {
          stage++;
          score += 100;
          _banner = 2;
        }
      }
    }
    if (hit && _safe <= 0) {
      if (!loseLife()) return;
      _safe = 2;
      _y = _skyH / 2;
      _vy = -20;
    } else if (_y > _skyH - 3) {
      _y = _skyH - 3;
      _vy = -30;
    }
  }

  @override
  Widget build(BuildContext context) => arcadeFrame(
    title: 'Sky Glide',
    colors: const [Color(0xFF1A1340), Color(0xFF2F7BD6)],
    hud: _skyZones[(stage - 1) % _skyZones.length].$1,
    lifeIcon: Icons.favorite_rounded,
    lifeColor: const Color(0xFFFF4D6D),
    overDetail: 'Score $score · $_passed pillars',
    icon: Icons.air_rounded,
    pitch: 'Fly Pip through the gaps between the crystal pillars and catch the stars!',
    options: Column(
      children: [
        kidsLevelChips(const ['Easy', 'Medium', 'Hard'], level, (i) => setState(() => level = i)),
        const SizedBox(height: 14),
        Text('Fly with', style: kidsText(18, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        kidsLevelChips(const ['Taps', 'My head', 'My hand'], _steer, (i) => setState(() => _steer = i)),
      ],
    ),
    game: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Center(
        child: AspectRatio(
          aspectRatio: _skyW / _skyH,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _flap(),
            child: CustomPaint(painter: _SkyPainter(this)),
          ),
        ),
      ),
    ),
  );
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.g);
  final _SkyGlideState g;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _skyW;
    final (_, top, bottom, crystal) = _skyZones[(g.stage - 1) % _skyZones.length];
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)));
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]).createShader(Offset.zero & size),
    );
    // Far-off clouds or stars, drifting.
    final rng = math.Random(7);
    for (var i = 0; i < 14; i++) {
      final x = ((rng.nextDouble() * 120 - g.time * (3 + i % 3)) % 120 - 10) * k;
      final y = rng.nextDouble() * _skyH * 0.8 * k;
      if ((g.stage - 1) % _skyZones.length >= 2) {
        canvas.drawCircle(Offset(x, y), k * 0.4, Paint()..color = Colors.white70);
      } else {
        final p = Paint()..color = Colors.white.withValues(alpha: 0.35);
        canvas.drawCircle(Offset(x, y), k * 2.4, p);
        canvas.drawCircle(Offset(x + k * 2.6, y + k * 0.6), k * 1.8, p);
        canvas.drawCircle(Offset(x - k * 2.4, y + k * 0.8), k * 1.6, p);
      }
    }
    // Crystal pillars.
    for (final p in g._pillars) {
      // A spire from the top and one from the bottom, each faceted and
      // pointed at the opening.
      final left = p.x * k, right = (p.x + _pillarW) * k, mid = (p.x + _pillarW / 2) * k;
      final tip = k * 3.5;
      for (final (edge, far) in [((p.gapY - p.gap / 2) * k, -k), ((p.gapY + p.gap / 2) * k, (_skyH + 1) * k)]) {
        final down = far < edge; // the top spire points down
        final body = edge + (down ? -tip : tip);
        final shape = Path()
          ..moveTo(left, far)
          ..lineTo(left, body)
          ..lineTo(mid, edge)
          ..lineTo(right, body)
          ..lineTo(right, far)
          ..close();
        canvas.drawPath(shape, Paint()..color = crystal);
        canvas.drawPath(
          Path()
            ..moveTo(mid, far)
            ..lineTo(mid, edge)
            ..lineTo(right, body)
            ..lineTo(right, far)
            ..close(),
          Paint()..color = Colors.black.withValues(alpha: 0.18),
        );
        canvas.drawLine(Offset(left + k * 1.6, far), Offset(left + k * 1.6, body), Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..strokeWidth = k * 0.9);
        canvas.drawPath(shape, Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = k * 0.3);
      }
      if (p.star) {
        final c = Offset((p.x + _pillarW / 2) * k, p.gapY * k);
        final star = Path();
        for (var i = 0; i < 10; i++) {
          final a = -math.pi / 2 + i * math.pi / 5 + g.time;
          final r = (i.isEven ? 2.4 : 1.0) * k;
          final pt = c + Offset(math.cos(a), math.sin(a)) * r;
          i == 0 ? star.moveTo(pt.dx, pt.dy) : star.lineTo(pt.dx, pt.dy);
        }
        canvas.drawPath(star..close(), Paint()..color = const Color(0xFFFFE066));
      }
    }
    // Pip: a round sky-puff with a propeller cap.
    if (g._safe <= 0 || (g.time * 10).floor().isEven) {
      final c = Offset(_pipX * k, g._y * k);
      final tilt = (g._vy / 60).clamp(-0.5, 0.6);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(tilt);
      canvas.drawCircle(Offset.zero, k * 3.2, Paint()..color = const Color(0xFFFF8AD8));
      canvas.drawCircle(Offset(-k * 0.9, -k * 1), k * 1.1, Paint()..color = const Color(0xFFFFC6EE));
      canvas.drawCircle(Offset(k * 1.2, -k * 0.5), k * 0.9, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(k * 1.5, -k * 0.5), k * 0.45, Paint()..color = const Color(0xFF1A1340));
      canvas.drawArc(Rect.fromCenter(center: Offset(k * 1.2, k * 0.8), width: k * 1.6, height: k * 1.0), 0.2, math.pi - 0.4, false, Paint()
        ..color = const Color(0xFF1A1340)
        ..style = PaintingStyle.stroke
        ..strokeWidth = k * 0.35);
      canvas.drawRect(Rect.fromCenter(center: Offset(0, -k * 3.4), width: k * 0.5, height: k * 1.2), Paint()..color = const Color(0xFF39D0FF));
      final spin = math.cos(g.time * 30).abs();
      canvas.drawOval(Rect.fromCenter(center: Offset(0, -k * 4), width: k * 5 * spin + k * 0.6, height: k * 0.7), Paint()..color = const Color(0xFFFFE066));
      // A wing that flaps.
      canvas.drawOval(
        Rect.fromCenter(center: Offset(-k * 2.2, k * 0.4 + math.sin(g.time * 18) * k * 0.6), width: k * 2.2, height: k * 1.2),
        Paint()..color = const Color(0xFFFF5EB8),
      );
      canvas.restore();
    }
    if (g._ready > 0 && g._tracker == null) _text(canvas, 'TAP TO FLY', Offset(size.width / 2, size.height * 0.75), k * 6, Colors.white);
    if (g._banner > 0) {
      _text(canvas, _skyZones[(g.stage - 1) % _skyZones.length].$1, Offset(size.width / 2, size.height * 0.3), k * 8, const Color(0xFFFFE066));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SkyPainter old) => true;
}

// ── Fox Run ───────────────────────────────────────────────────────────────

const _runW = 100.0, _runH = 50.0, _ground = 40.0, _foxX = 18.0;
const _jumpV = 62.0, _gravity = 190.0;

/// The space before the next obstacle: always room to land and jump again.
double runnerGap(double speed, math.Random rng) {
  final air = 2 * _jumpV / _gravity; // seconds in the air
  final min = speed * air + 10;
  return min + rng.nextDouble() * (min * 0.9);
}

class _Obstacle {
  _Obstacle(this.x, this.w, this.h, this.kind);
  double x;
  final double w, h;
  final int kind;
}

class _Coin {
  _Coin(this.x, this.y);
  double x;
  final double y;
  bool taken = false;
}

/// The worlds, one per stage: name, sky top, sky bottom, hills, ground.
const _runWorlds = [
  ('MEADOW', Color(0xFF7CC8FF), Color(0xFFD8F1FF), Color(0xFF6CC46C), Color(0xFF4E9A3E)),
  ('DESERT', Color(0xFFFFB46B), Color(0xFFFFE3B0), Color(0xFFE0A058), Color(0xFFC98A42)),
  ('SNOW', Color(0xFF9BB8E0), Color(0xFFEAF2FF), Color(0xFFDDE8F5), Color(0xFFB8CCE4)),
  ('NIGHT', Color(0xFF0B1240), Color(0xFF3A3F8F), Color(0xFF2A2F6A), Color(0xFF1E2350)),
];

/// Run with the fox and jump over what is in the way: tap to jump (twice
/// for a double jump), or jump by moving the head up.
class FoxRun extends StatefulWidget {
  const FoxRun({super.key, required this.container, required this.onBack});
  final AppContainer container;
  final VoidCallback onBack;

  @override
  State<FoxRun> createState() => _FoxRunState();
}

class _FoxRunState extends _ArcadeGame<FoxRun> {
  final _rng = math.Random();
  final _obstacles = <_Obstacle>[];
  final _coins = <_Coin>[];
  KidsHands? _tracker;
  int _steer = 0; // 0 tap, 1 head, 2 hand
  double _y = _ground, _vy = 0, _safe = 0, _run = 0, _next = 60, _banner = 0;
  double? _headRest;
  int _jumps = 0, _coinCount = 0;

  @override
  String get scoreKey => 'run${level + 1}';
  @override
  VoidCallback get onBack => widget.onBack;
  @override
  int starsFor(int s) => s >= 800 ? 3 : (s >= 400 ? 2 : (s >= 150 ? 1 : 0));

  double get _speed => math.min(62, 30 + level * 5 + (stage - 1) * 3);

  @override
  void dispose() {
    _tracker?.dispose();
    super.dispose();
  }

  @override
  void reset() {
    _tracker?.dispose();
    _tracker = _steer == 0 ? null : KidsHands(widget.container.motion, head: _steer == 1, body: false);
    _headRest = null;
    _obstacles.clear();
    _coins.clear();
    _y = _ground;
    _vy = 0;
    _run = 0;
    _next = 60;
    _jumps = 0;
    _coinCount = 0;
    _safe = 0;
    _banner = 2;
  }

  void _jump() {
    if (!playing || _jumps >= 2) return;
    _vy = _jumps == 0 ? -_jumpV : -_jumpV * 0.85;
    _jumps++;
  }

  @override
  void step(double dt) {
    _safe = math.max(0, _safe - dt);
    _banner = math.max(0, _banner - dt);
    final tracker = _tracker;
    if (tracker != null) {
      tracker.step(dt);
      final p = tracker.point.value;
      if (p != null) {
        final rest = _headRest ??= p.dy;
        if (p.dy < rest - 0.1 && _jumps == 0) _jump();
        _headRest = rest + (p.dy - rest) * math.min(1, dt * 0.8);
      }
    }
    final speed = _speed;
    final dx = speed * dt;
    _run += dx;
    final reached = 1 + (_run / 900).floor();
    if (reached > stage) {
      stage = reached;
      _banner = 2;
    }
    // The fox.
    _vy += _gravity * dt;
    _y += _vy * dt;
    if (_y >= _ground) {
      _y = _ground;
      _vy = 0;
      _jumps = 0;
    }
    // The world goes by.
    for (final o in _obstacles) {
      o.x -= dx;
    }
    for (final c in _coins) {
      c.x -= dx;
    }
    _obstacles.removeWhere((o) => o.x + o.w < -5);
    _coins.removeWhere((c) => c.x < -5 || c.taken);
    _next -= dx;
    if (_next <= 0) {
      final kind = _rng.nextInt(4);
      final (w, h) = switch (kind) { 0 => (4.0, 4.0), 1 => (6.0, 5.0), 2 => (9.0, 3.0), _ => (3.0, 7.0 + math.min(stage, 4) * 0.5) };
      _obstacles.add(_Obstacle(_runW + 4, w, h, kind));
      final gap = runnerGap(speed, _rng);
      // Coins in an arc over the obstacle, or along the ground after it.
      final n = 3 + _rng.nextInt(3);
      final arc = _rng.nextBool();
      for (var i = 0; i < n; i++) {
        final t = n == 1 ? 0.5 : i / (n - 1);
        _coins.add(
          arc
              ? _Coin(_runW + 4 + w / 2 + (t - 0.5) * 16, _ground - h - 4 - math.sin(t * math.pi) * 5)
              : _Coin(_runW + 4 + w + 10 + i * 5, _ground - 3),
        );
      }
      _next = gap;
    }
    // Coins and bumps.
    final fox = Rect.fromLTRB(_foxX - 3, _y - 7, _foxX + 3, _y);
    for (final c in _coins) {
      if (!c.taken && fox.inflate(1.5).contains(Offset(c.x, c.y))) {
        c.taken = true;
        _coinCount++;
      }
    }
    score = (_run / 10).floor() + _coinCount * 5;
    if (_safe <= 0) {
      for (final o in _obstacles) {
        final r = Rect.fromLTWH(o.x, _ground - o.h, o.w, o.h).deflate(0.8);
        if (r.overlaps(fox)) {
          if (!loseLife()) return;
          _safe = 1.6;
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => arcadeFrame(
    title: 'Fox Run',
    colors: const [Color(0xFF1A1340), Color(0xFFB0581E)],
    hud: _runWorlds[(stage - 1) % _runWorlds.length].$1,
    lifeIcon: Icons.favorite_rounded,
    lifeColor: const Color(0xFFFF4D6D),
    overDetail: 'Score $score · ${(_run / 10).floor()} m · $_coinCount coins',
    icon: Icons.directions_run_rounded,
    pitch: 'Run with Fennec the fox! Jump over the rocks and logs and grab the coins. Tap twice for a double jump.',
    options: Column(
      children: [
        kidsLevelChips(const ['Easy', 'Medium', 'Hard'], level, (i) => setState(() => level = i)),
        const SizedBox(height: 14),
        Text('Jump with', style: kidsText(18, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        kidsLevelChips(const ['Taps', 'My head', 'My hand'], _steer, (i) => setState(() => _steer = i)),
      ],
    ),
    game: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Center(
        child: AspectRatio(
          aspectRatio: _runW / _runH,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _jump(),
            child: CustomPaint(painter: _RunPainter(this)),
          ),
        ),
      ),
    ),
  );
}

class _RunPainter extends CustomPainter {
  _RunPainter(this.g);
  final _FoxRunState g;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _runW;
    final (_, top, bottom, hills, ground) = _runWorlds[(g.stage - 1) % _runWorlds.length];
    final night = (g.stage - 1) % _runWorlds.length == 3;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)));
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]).createShader(Offset.zero & size),
    );
    // Sun or moon.
    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.2), k * 5, Paint()..color = night ? const Color(0xFFF4F1D0) : const Color(0xFFFFE89A));
    if (night) {
      final rng = math.Random(3);
      for (var i = 0; i < 30; i++) {
        canvas.drawCircle(Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height * 0.6), k * 0.3, Paint()..color = Colors.white70);
      }
    }
    // Hills, slower than the ground.
    final hill = Path()..moveTo(0, size.height);
    for (var x = 0.0; x <= _runW; x += 2) {
      final u = x + g._run * 0.3;
      hill.lineTo(x * k, (_ground - 8 - math.sin(u * 0.06) * 5 - math.sin(u * 0.13) * 2) * k);
    }
    hill
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(hill, Paint()..color = hills.withValues(alpha: 0.8));
    // Ground with stripes that run by.
    canvas.drawRect(Rect.fromLTRB(0, _ground * k, size.width, size.height), Paint()..color = ground);
    for (var x = -(g._run % 8); x < _runW; x += 8) {
      canvas.drawRect(Rect.fromLTWH(x * k, (_ground + 2) * k, k * 3, k * 0.8), Paint()..color = Colors.black.withValues(alpha: 0.12));
    }
    canvas.drawRect(Rect.fromLTWH(0, _ground * k, size.width, k * 0.8), Paint()..color = Colors.white.withValues(alpha: 0.25));
    // Obstacles.
    for (final o in g._obstacles) {
      final r = Rect.fromLTWH(o.x * k, (_ground - o.h) * k, o.w * k, o.h * k);
      switch (o.kind) {
        case 0: // a rock
          canvas.drawRRect(RRect.fromRectAndCorners(r, topLeft: Radius.circular(k * 2), topRight: Radius.circular(k * 1.2)), Paint()..color = const Color(0xFF8A8FA0));
          canvas.drawCircle(r.topLeft + Offset(k * 1.3, k * 1.2), k * 0.6, Paint()..color = Colors.white38);
        case 1: // a bush
          final p = Paint()..color = night ? const Color(0xFF2E7A5A) : const Color(0xFF2FA05A);
          canvas.drawCircle(Offset(r.left + r.width * 0.3, r.bottom - r.height * 0.45), r.height * 0.5, p);
          canvas.drawCircle(Offset(r.left + r.width * 0.7, r.bottom - r.height * 0.45), r.height * 0.5, p);
          canvas.drawCircle(Offset(r.center.dx, r.bottom - r.height * 0.7), r.height * 0.45, p);
          canvas.drawCircle(Offset(r.center.dx, r.bottom - r.height * 0.6), k * 0.5, Paint()..color = const Color(0xFFFF4D6D));
        case 2: // a log
          canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(k)), Paint()..color = const Color(0xFF8A5A2B));
          canvas.drawCircle(Offset(r.right - r.height / 2, r.center.dy), r.height * 0.42, Paint()..color = const Color(0xFFD9A066));
        default: // a crystal spike
          final spike = Path()
            ..moveTo(r.left, r.bottom)
            ..lineTo(r.center.dx, r.top)
            ..lineTo(r.right, r.bottom)
            ..close();
          canvas.drawPath(spike, Paint()..color = const Color(0xFF39D0FF));
          canvas.drawPath(
            Path()
              ..moveTo(r.center.dx, r.top)
              ..lineTo(r.right, r.bottom)
              ..lineTo(r.center.dx, r.bottom)
              ..close(),
            Paint()..color = const Color(0xFF1C7FB8),
          );
      }
    }
    // Coins.
    for (final c in g._coins) {
      final w = math.cos(g.time * 6 + c.x * 0.2).abs();
      final r = Rect.fromCenter(center: Offset(c.x * k, c.y * k), width: k * 2.4 * w + k * 0.4, height: k * 2.4);
      canvas.drawOval(r, Paint()..color = const Color(0xFFFFC93D));
      canvas.drawOval(r.deflate(k * 0.45), Paint()..color = const Color(0xFFFFE89A));
    }
    // Fennec the fox.
    if (g._safe <= 0 || (g.time * 10).floor().isEven) {
      final feet = Offset(_foxX * k, g._y * k);
      final air = g._y < _ground - 0.1;
      final legs = air ? 0.0 : math.sin(g._run * 0.9);
      final leg = Paint()
        ..color = const Color(0xFF8A3A12)
        ..strokeWidth = k * 0.9
        ..strokeCap = StrokeCap.round;
      for (final (sx, ph) in [(-1.4, 1.0), (1.4, -1.0)]) {
        canvas.drawLine(feet + Offset(sx * k, -k * 2.4), feet + Offset((sx + legs * ph * 1.1) * k, -k * 0.3), leg);
      }
      // Tail with a white tip.
      final tail = feet + Offset(-k * 4.2, -k * 4.6 + math.sin(g.time * 8) * k * 0.4);
      canvas.drawOval(Rect.fromCenter(center: tail, width: k * 4.4, height: k * 2.2), Paint()..color = const Color(0xFFFF8A2B));
      canvas.drawCircle(tail - Offset(k * 1.8, 0), k * 0.9, Paint()..color = Colors.white);
      // Body and head.
      canvas.drawOval(Rect.fromCenter(center: feet + Offset(0, -k * 3.8), width: k * 6.4, height: k * 3.6), Paint()..color = const Color(0xFFFF8A2B));
      canvas.drawOval(Rect.fromCenter(center: feet + Offset(k * 0.3, -k * 3.2), width: k * 3.6, height: k * 1.8), Paint()..color = const Color(0xFFFFE3C2));
      final head = feet + Offset(k * 3.2, -k * 6.4);
      for (final ex in [-1.0, 0.9]) {
        final ear = Path()
          ..moveTo(head.dx + ex * k - k * 0.9, head.dy - k * 1.2)
          ..lineTo(head.dx + ex * k + k * 0.3, head.dy - k * 4.2)
          ..lineTo(head.dx + ex * k + k * 1.1, head.dy - k * 1.0)
          ..close();
        canvas.drawPath(ear, Paint()..color = const Color(0xFFFF8A2B));
      }
      canvas.drawCircle(head, k * 2.2, Paint()..color = const Color(0xFFFF8A2B));
      final snout = Path()
        ..moveTo(head.dx + k * 0.6, head.dy - k * 0.4)
        ..lineTo(head.dx + k * 3.4, head.dy + k * 0.6)
        ..lineTo(head.dx + k * 0.6, head.dy + k * 1.6)
        ..close();
      canvas.drawPath(snout, Paint()..color = const Color(0xFFFFE3C2));
      canvas.drawCircle(head + Offset(k * 3.3, k * 0.6), k * 0.5, Paint()..color = const Color(0xFF1A1340));
      canvas.drawCircle(head + Offset(k * 0.6, -k * 0.6), k * 0.55, Paint()..color = const Color(0xFF1A1340));
      // A scarf that flutters.
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: head + Offset(-k * 1, k * 1.9), width: k * 3.4, height: k * 1.1), Radius.circular(k * 0.5)), Paint()..color = const Color(0xFF39D0FF));
      final flap = math.sin(g.time * 14) * k * 0.6;
      canvas.drawLine(head + Offset(-k * 2.4, k * 1.9), head + Offset(-k * 4.6, k * 1.4 + flap), Paint()
        ..color = const Color(0xFF39D0FF)
        ..strokeWidth = k * 0.9
        ..strokeCap = StrokeCap.round);
    }
    _text(canvas, '${(g._run / 10).floor()} m', Offset(size.width * 0.12, size.height * 0.08), k * 5, Colors.white);
    if (g._banner > 0) {
      _text(canvas, _runWorlds[(g.stage - 1) % _runWorlds.length].$1, Offset(size.width / 2, size.height * 0.3), k * 8, const Color(0xFFFFE066));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RunPainter old) => true;
}
