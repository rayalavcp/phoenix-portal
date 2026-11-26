import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app_container.dart';
import '../../managers/motion/motion_manager.dart';
import '../../managers/motion/native_motion.dart' show GameHand;
import 'kids_activities.dart';
import 'kids_games.dart';
import 'kids_logic.dart';

/// The Kids Portal's Move shelf: games played by moving a hand in front of
/// the Portal's camera. The hand tracker (MediaPipe, on the device) reports
/// the palm's position and the fingers shown; nothing is recorded, stored
/// or sent anywhere. Every game also plays by touch, for a Portal with the
/// camera off.

/// A low-lag smoother for one tracked value (the "One Euro" filter):
/// steady while the hand or head is nearly still, close to raw when it
/// moves fast, so the cursor neither jitters nor trails behind.
class OneEuro {
  OneEuro({this.minCutoff = 1.0, this.beta = 6.0, this.dCutoff = 1.0});
  final double minCutoff, beta, dCutoff;
  double? _x;
  double _dx = 0;

  /// The speed the filter last saw (units a second).
  double get velocity => _dx;

  static double _alpha(double cutoff, double dt) {
    final tau = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + tau / dt);
  }

  double filter(double x, double dt) {
    final prev = _x;
    if (prev == null || dt <= 0) {
      _x = x;
      _dx = 0;
      return x;
    }
    final raw = (x - prev) / dt;
    _dx += (raw - _dx) * _alpha(dCutoff, dt);
    final cutoff = minCutoff + beta * _dx.abs();
    final out = prev + (x - prev) * _alpha(cutoff, dt);
    _x = out;
    return out;
  }

  void reset() {
    _x = null;
    _dx = 0;
  }
}

/// One followed point (a hand's palm or the head): filtered, with a short
/// look ahead along its speed to make up for the camera's own delay.
class _Track {
  final _fx = OneEuro(), _fy = OneEuro();
  Offset? at;
  Offset _v = Offset.zero;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// The camera-to-screen delay the look ahead makes up for, seconds.
  static const lead = 0.04;

  /// After this long without a sighting the point starts afresh where the
  /// hand comes back, instead of sweeping over from where it was lost.
  static const _lostAfter = 0.4;

  void measure(Offset p, DateTime now) {
    final gap = now.difference(_last).inMicroseconds / 1e6;
    if (at != null && gap > _lostAfter) reset();
    final dt = at == null ? 0.0 : gap.clamp(0.0, 0.25);
    _last = now;
    at = Offset(_fx.filter(p.dx, dt), _fy.filter(p.dy, dt));
    _v = Offset(_fx.velocity, _fy.velocity);
  }

  /// Where to draw it now: the filtered point, led along its speed.
  Offset? shown(DateTime now) {
    final a = at;
    if (a == null) return null;
    // Led along its speed between sightings, but never far: a long lead
    // overshoots when the hand stops.
    final since = (now.difference(_last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    final speed = _v.distance;
    final p = a + _v * (math.min(lead + since, 0.07) * (speed < 0.15 ? speed / 0.15 : 1.0));
    return Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0));
  }

  void reset() {
    _fx.reset();
    _fy.reset();
    at = null;
    _v = Offset.zero;
  }
}

/// Which hand is the player's when more than one is in view (two
/// children, or a parent next to the child): once a hand is followed,
/// the one nearest where it was and about its size (the same distance from
/// the Portal) stays the player's; a hand that jumps across the picture
/// or is a very different size belongs to someone else and is ignored.
/// When the player's hand has been gone a moment, the biggest hand (the
/// child nearest the Portal) becomes the player.
class PlayerLock {
  Offset? _at;
  double _size = 0;
  DateTime _seen = DateTime.fromMillisecondsSinceEpoch(0);

  /// How long the player's hand may be gone before another can take over.
  static const hold = Duration(milliseconds: 1200);

  bool get locked => _at != null;

  GameHand? pick(List<GameHand> hands, DateTime now) {
    if (hands.isEmpty) return null;
    final at = _at;
    GameHand? best;
    if (at != null && now.difference(_seen) < hold) {
      var bestCost = double.infinity;
      for (final h in hands) {
        final jump = (h.palm - at).distance;
        final ratio = _size > 0 && h.size > 0 ? math.max(h.size / _size, _size / h.size) : 1.0;
        // Too far, or clearly nearer or further from the Portal: not them.
        if (jump > 0.3 || ratio > 1.8) continue;
        final cost = jump + (ratio - 1) * 0.15;
        if (cost < bestCost) {
          bestCost = cost;
          best = h;
        }
      }
      if (best == null) return null; // only someone else's hand: wait
    } else {
      // Nobody followed yet (or they left): the nearest child plays.
      best = hands.reduce((a, b) => b.size > a.size ? b : a);
    }
    _at = best.palm;
    _size = best.size > 0 ? (_size == 0 ? best.size : _size + (best.size - _size) * 0.2) : _size;
    _seen = now;
    return best;
  }

  void reset() {
    _at = null;
    _size = 0;
  }
}

/// Turns where a hand is in the camera's picture into where the cursor is
/// on the screen, the same way near or far: a box about an arm's sweep
/// wide (measured in hand sizes, so it shrinks as the child steps back)
/// covers the whole screen. The box starts centred on the hand and is
/// pushed along when the hand reaches past its edge, so the cursor always
/// reaches the edges of the screen without the child walking about.
class HandReach {
  /// The box, in hand sizes (wrist to middle knuckle): about 70 by 50 cm
  /// for a child's hand.
  static const across = 7.0, down = 5.0;

  Offset? _centre;
  double _size = 0;
  DateTime _seen = DateTime.fromMillisecondsSinceEpoch(0);

  Offset map(Offset palm, double size, double aspect, DateTime now) {
    final gap = now.difference(_seen).inMilliseconds;
    _seen = now;
    // A hand's size swings as it turns: follow it slowly.
    _size = _size == 0 || gap > 1500 ? size : _size + (size - _size) * 0.08;
    final w = (across * _size).clamp(0.22, 0.9);
    final h = (down * _size / aspect).clamp(0.22, 0.9);
    var c = _centre;
    if (c == null || gap > 1500) {
      // A hand that comes back starts in the middle of the screen.
      c = palm;
    }
    // Push the box along when the hand reaches past an edge.
    var cx = c.dx, cy = c.dy;
    if (palm.dx < cx - w / 2) cx = palm.dx + w / 2;
    if (palm.dx > cx + w / 2) cx = palm.dx - w / 2;
    if (palm.dy < cy - h / 2) cy = palm.dy + h / 2;
    if (palm.dy > cy + h / 2) cy = palm.dy - h / 2;
    _centre = Offset(cx, cy);
    return Offset(((palm.dx - cx) / w + 0.5).clamp(0.0, 1.0), ((palm.dy - cy) / h + 0.5).clamp(0.0, 1.0));
  }
}

/// A camera session for a game: starts the hand tracker (the game vision,
/// up to two hands) or the head tracker when the game opens and stops it
/// when it closes, so the camera is free again. Nothing of the child is
/// drawn: only a friendly cursor where each hand (or the head) points.
class KidsHands {
  KidsHands(this._motion, {this.head = false, this.amplify = true, this.twoHands = false}) {
    if (head) {
      if (_motion.headsAvailable) {
        _motion.startHeadTracking();
        _motion.headTest.addListener(_onHead);
      }
    } else if (_motion.handsAvailable) {
      _motion.gameHands.addListener(_onHands);
      _motion.startGameVision(hands: true);
    }
  }

  final MotionManager _motion;

  /// Steering by head (the face's position) instead of a hand.
  final bool head;

  /// Small movements go a long way (steering games); off, the point is
  /// where the child really is.
  final bool amplify;

  /// Follow two hands (games that count fingers or pop with both).
  final bool twoHands;

  final _reach = HandReach();

  /// Whether the camera is following (false: touch only).
  bool get camera => head ? _motion.headsAvailable : _motion.handsAvailable;

  /// Where the hand (or head) is now, 0..1 across and down; null while none.
  final point = ValueNotifier<Offset?>(null);

  /// Every hand in view (the first is [point]), for games two hands play.
  final points = ValueNotifier<List<Offset>>(const []);

  /// Each cursor's last few places, newest last, for its sparkle trail.
  final trails = <List<Offset>>[[], []];

  /// Fingers shown (both hands together; null: no hand).
  final fingers = ValueNotifier<int?>(null);

  /// Swap left and right, if the camera's picture comes out mirrored.
  bool flip = false;

  final _tracks = [_Track(), _Track()];
  Offset? _touch;
  DateTime _seen = DateTime.fromMillisecondsSinceEpoch(0);

  bool get handInView => DateTime.now().difference(_seen) < const Duration(milliseconds: 700);

  /// From the camera's picture to the screen: flipped if asked, and
  /// stretched around the middle when [amplify] (hands a little, heads more).
  Offset map(Offset raw) {
    final x = flip ? 1 - raw.dx : raw.dx;
    if (!amplify) return Offset(x.clamp(0.0, 1.0), raw.dy.clamp(0.0, 1.0));
    final (kx, ky) = head ? (2.6, 2.2) : (1.6, 1.6);
    return Offset(((x - 0.5) * kx + 0.5).clamp(0.0, 1.0), ((raw.dy - 0.5) * ky + 0.5).clamp(0.0, 1.0));
  }

  void _onHead() {
    final p = _motion.headTest.value;
    if (p == null) return;
    final now = DateTime.now();
    _seen = now;
    _touch = null;
    _tracks[0].measure(map(p), now);
  }

  void _onHands() {
    final hands = _motion.gameHands.value;
    final now = DateTime.now();
    if (!twoHands) {
      _onPlayerHand(hands, now);
      return;
    }
    if (hands.isEmpty) {
      fingers.value = null;
      return;
    }
    _seen = now;
    _touch = null;
    // Keep each hand on its own track: the first track takes the hand
    // nearest where it was, so the cursor does not swap between hands.
    final palms = [for (final h in hands.take(2)) map(h.palm)];
    var first = 0;
    final was = _tracks[0].at;
    if (was != null && palms.length == 2 && (palms[1] - was).distance < (palms[0] - was).distance) first = 1;
    _tracks[0].measure(palms[first], now);
    if (palms.length == 2) {
      _tracks[1].measure(palms[1 - first], now);
    } else {
      _tracks[1].reset();
    }
    fingers.value = hands.take(2).fold<int>(0, (a, h) => a + h.fingers);
  }

  final _player = PlayerLock();

  /// One-player games: follow the player's hand only, even with another
  /// child (or a parent) in view.
  void _onPlayerHand(List<GameHand> hands, DateTime now) {
    final h = _player.pick(hands, now);
    if (h == null) {
      if (hands.isEmpty) fingers.value = null;
      return;
    }
    _seen = now;
    _touch = null;
    final raw = flip ? Offset(1 - h.palm.dx, h.palm.dy) : h.palm;
    // Steer through the reach box (the same arm movement near or far).
    _tracks[0].measure(amplify && h.size > 0 ? _reach.map(raw, h.size, h.aspect, now) : map(h.palm), now);
    _tracks[1].reset();
    fingers.value = h.fingers;
  }

  /// Touch steers too (and is how the game plays without a camera).
  void touch(Offset fraction) {
    _seen = DateTime.now();
    _touch = fraction;
    point.value = fraction;
    points.value = [fraction];
    _trail(0, fraction);
  }

  static const _trailLength = 9;

  void _trail(int i, Offset? p) {
    final t = trails[i];
    if (p == null) {
      t.clear();
      return;
    }
    t.add(p);
    if (t.length > _trailLength) t.removeAt(0);
  }

  /// Brings the shown points up to now (call once a frame).
  void step(double dt) {
    if (_touch != null) return;
    final now = DateTime.now();
    final a = _tracks[0].shown(now);
    final b = handInView ? _tracks[1].shown(now) : null;
    if (a == null) return;
    _trail(0, a);
    _trail(1, b);
    point.value = a;
    points.value = [a, ?b];
  }

  void dispose() {
    if (head) {
      _motion.headTest.removeListener(_onHead);
      _motion.stopHeadTracking();
    } else {
      _motion.gameHands.removeListener(_onHands);
      _motion.stopGameVision();
    }
    point.dispose();
    points.dispose();
    fingers.dispose();
  }
}

/// The hint along the bottom: show your hand, or play by touch.
class KidsHandHint extends StatelessWidget {
  const KidsHandHint({super.key, required this.hands, required this.visible});
  final KidsHands hands;
  final bool visible;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: visible ? 1 : 0,
    duration: const Duration(milliseconds: 300),
    child: Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFF101828).withValues(alpha: 0.7), borderRadius: BorderRadius.circular(24)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hands.camera ? (hands.head ? Icons.face_rounded : Icons.back_hand_rounded) : Icons.touch_app_rounded,
              color: const Color(0xFFF2CF6E),
              size: 28,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                !hands.camera
                    ? 'Camera is off: play with your finger on the screen'
                    : hands.head
                    ? 'Look at the camera, then lean left and right'
                    : 'Hold up your hand to the camera',
                textAlign: TextAlign.center,
                style: kidsText(20),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The cursors: a soft pastel bubble with a white rim where each hand (or
/// the head) points, and a short trail of fading sparkles behind it.
class _CursorPainter extends CustomPainter {
  _CursorPainter(this.hands, this.icon) : super(repaint: hands.points);
  final KidsHands hands;
  final IconData icon;

  static const _hues = [Color(0xFFFF9EC7), Color(0xFF8FD8FF)];
  static const _headHue = Color(0xFFFFD36E);

  static void _sparkle(Canvas canvas, Offset c, double r, Paint paint) {
    // A soft four-pointed star.
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ps = hands.points.value;
    final short = math.min(size.width, size.height);
    for (var i = 0; i < ps.length && i < 2; i++) {
      final hue = hands.head ? _headHue : _hues[i];
      final r = short * (i == 0 ? 0.065 : 0.055);
      Offset px(Offset f) => Offset(f.dx * size.width, f.dy * size.height);
      // The trail: older sparkles smaller and fainter.
      final trail = hands.trails[i];
      for (var k = 0; k < trail.length - 1; k++) {
        final age = (k + 1) / trail.length;
        _sparkle(canvas, px(trail[k]), r * 0.45 * age, Paint()..color = Color.lerp(Colors.white, hue, 0.3)!.withValues(alpha: 0.85 * age));
      }
      final c = px(ps[i]);
      canvas.drawCircle(c, r * 1.35, Paint()..color = hue.withValues(alpha: 0.35)..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.4),
            colors: [Colors.white, Color.lerp(Colors.white, hue, 0.55)!, hue],
            stops: const [0, 0.45, 1],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = math.max(2, r * 0.09)..color = Colors.white);
      final glyph = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: r * 1.1, color: Colors.white, shadows: [Shadow(color: hue, blurRadius: 6)]),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      glyph.paint(canvas, c - Offset(glyph.width / 2, glyph.height / 2));
    }
  }

  @override
  bool shouldRepaint(_CursorPainter old) => old.icon != icon || old.hands != hands;
}

// ── Bubble Pop ─────────────────────────────────────────────────────────────

class _Bubble {
  _Bubble(this.x, this.y, this.r, this.speed, this.hue);
  double x, y; // fractions
  final double r; // fraction of the shorter side
  final double speed; // fraction of the height a second
  final double hue;
  double pop = -1; // >= 0 while popping
}

/// Wave your hand to pop the bubbles floating up. One minute a round.
class BubblePop extends StatefulWidget {
  const BubblePop({super.key, required this.container, required this.onBack});
  final AppContainer container;
  final VoidCallback onBack;

  @override
  State<BubblePop> createState() => _BubblePopState();
}

class _BubblePopState extends State<BubblePop> with SingleTickerProviderStateMixin {
  static const _seconds = 60;
  // Made on Start: the camera only runs while the game is being played.
  KidsHands? _tracker;
  KidsHands get _hands => _tracker ??= KidsHands(widget.container.motion, twoHands: true);

  @visibleForTesting
  KidsHands get debugHands => _hands;
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  final _rng = math.Random();
  final _bubbles = <_Bubble>[];
  Duration _last = Duration.zero;
  double _spawn = 0, _left = _seconds.toDouble();
  int _level = 0, _score = 0;
  bool _playing = false, _over = false, _newBest = false;
  Size _size = Size.zero;

  @override
  void dispose() {
    _ticker.dispose();
    _tracker?.dispose();
    super.dispose();
  }

  void _start() {
    _hands;
    setState(() {
      _bubbles.clear();
      _score = 0;
      _left = _seconds.toDouble();
      _playing = true;
      _over = false;
      _last = Duration.zero;
    });
    _ticker.start();
  }

  Future<void> _finish() async {
    _ticker.stop();
    final key = 'bubbles${_level + 1}';
    final best = await KidsScores.offer(key, _score);
    await KidsScores.addStars(_score >= 40 ? 3 : (_score >= 25 ? 2 : (_score >= 12 ? 1 : 0)));
    if (mounted) {
      setState(() {
        _playing = false;
        _over = true;
        _newBest = best;
      });
    }
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    _hands.step(dt);
    _left -= dt;
    if (_left <= 0) {
      unawaited(_finish());
      return;
    }
    final every = const [1.0, 0.7, 0.45][_level];
    _spawn -= dt;
    if (_spawn <= 0) {
      _spawn = every * (0.6 + _rng.nextDouble() * 0.8);
      _bubbles.add(
        _Bubble(
          0.08 + _rng.nextDouble() * 0.84,
          1.15,
          0.06 + _rng.nextDouble() * 0.05,
          (0.10 + _rng.nextDouble() * 0.08) * (1 + _level * 0.45),
          _rng.nextDouble() * 360,
        ),
      );
    }
    final handsNow = _hands.points.value;
    final short = math.min(_size.width, _size.height);
    for (final b in _bubbles) {
      if (b.pop >= 0) {
        b.pop += dt;
        continue;
      }
      b.y -= b.speed * dt;
      b.x += math.sin(b.y * 9 + b.hue) * 0.0015;
      if (_size != Size.zero) {
        // Either hand pops it.
        for (final hand in handsNow) {
          final d = Offset((b.x - hand.dx) * _size.width, (b.y - hand.dy) * _size.height).distance;
          if (d < b.r * short + short * 0.06) {
            b.pop = 0;
            _score++;
            break;
          }
        }
      }
    }
    _bubbles.removeWhere((b) => b.y < -0.2 || b.pop > 0.35);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Bubble Pop',
    colors: const [Color(0xFF2F7BD6), Color(0xFF6A4CFF)],
    onBack: widget.onBack,
    trailing: _playing ? Text('${_left.ceil()} s   Popped $_score', style: kidsText(28)) : null,
    child: _over
        ? KidsResult(
            title: 'Pop-tastic!',
            detail: 'You popped $_score bubbles',
            stars: _score >= 40 ? 3 : (_score >= 25 ? 2 : (_score >= 12 ? 1 : 0)),
            newBest: _newBest,
            onAgain: () => setState(() => _over = false),
          )
        : !_playing
        ? KidsStartPanel(
            icon: Icons.bubble_chart_rounded,
            pitch: 'Wave your hand in front of the Portal to pop the bubbles!',
            best: KidsScores.best('bubbles${_level + 1}').then((b) => b == null ? null : 'Best: $b bubbles'),
            options: kidsLevelChips(const ['Easy', 'Medium', 'Hard'], _level, (i) => setState(() => _level = i)),
            onStart: _start,
          )
        : KidsMotionArena(hands: _hands, onSize: (s) => _size = s, painter: _BubblesPainter(_bubbles)),
  );
}

class _BubblesPainter extends CustomPainter {
  _BubblesPainter(this.bubbles);
  final List<_Bubble> bubbles;

  @override
  void paint(Canvas canvas, Size size) {
    final short = math.min(size.width, size.height);
    for (final b in bubbles) {
      final c = Offset(b.x * size.width, b.y * size.height);
      final r = b.r * short * (b.pop >= 0 ? 1 + b.pop * 2.5 : 1);
      final fade = b.pop >= 0 ? (1 - b.pop / 0.35).clamp(0.0, 1.0) : 1.0;
      final tint = HSVColor.fromAHSV(1, b.hue, 0.45, 1).toColor();
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.35),
            colors: [
              Colors.white.withValues(alpha: 0.75 * fade),
              tint.withValues(alpha: 0.35 * fade),
              tint.withValues(alpha: 0.12 * fade),
            ],
            stops: const [0, 0.55, 1],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white.withValues(alpha: 0.8 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_BubblesPainter old) => true;
}

/// The play area: the game's picture, the hand cursor, touch steering and
/// the "show your hand" hint.
class KidsMotionArena extends StatelessWidget {
  const KidsMotionArena({super.key, required this.hands, required this.onSize, required this.painter, this.cursorIcon = Icons.back_hand_rounded});
  final KidsHands hands;
  final ValueChanged<Size> onSize;
  final CustomPainter painter;
  final IconData cursorIcon;

  @override
  // Fills the space it is given: its Stack holds only positioned layers,
  // so without this it shrinks to nothing (a blank play area).
  Widget build(BuildContext context) => SizedBox.expand(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: LayoutBuilder(
          builder: (context, box) {
            final size = Size(box.maxWidth, box.maxHeight);
            onSize(size);
            Offset frac(Offset local) => Offset((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) => hands.touch(frac(d.localPosition)),
              onPanUpdate: (d) => hands.touch(frac(d.localPosition)),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF101828).withValues(alpha: 0.25),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 2),
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                  Positioned.fill(child: CustomPaint(painter: painter)),
                  Positioned.fill(
                    child: IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _CursorPainter(hands, cursorIcon)))),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 14,
                    child: KidsHandHint(hands: hands, visible: !hands.handInView),
                  ),
                  if (hands.camera)
                    Positioned(
                      right: 10,
                      top: 10,
                      child: IconButton(
                        tooltip: 'Swap left and right',
                        color: Colors.white70,
                        icon: const Icon(Icons.swap_horiz_rounded),
                        onPressed: () => hands.flip = !hands.flip,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

// ── Fruit Catcher ─────────────────────────────────────────────────────────

class _Fruit {
  _Fruit(this.x, this.kind, this.speed);
  final double x;
  double y = -0.1;
  final int kind;
  final double speed;
  double caught = -1;
}

const _fruitEmoji = ['🍎', '🍌', '🍓', '🍇', '🍊', '🍉', '🍒', '🍐'];

/// Move your hand left and right: the basket follows it and catches the
/// falling fruit. Three misses and the round ends.
class FruitCatcher extends StatefulWidget {
  const FruitCatcher({super.key, required this.container, required this.onBack});
  final AppContainer container;
  final VoidCallback onBack;

  @override
  State<FruitCatcher> createState() => _FruitCatcherState();
}

class _FruitCatcherState extends State<FruitCatcher> with SingleTickerProviderStateMixin {
  bool _byHead = false;
  KidsHands? _tracker;
  KidsHands get _hands => _tracker ??= KidsHands(widget.container.motion, head: _byHead);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  final _rng = math.Random();
  final _fruit = <_Fruit>[];
  Duration _last = Duration.zero;
  double _spawn = 0;
  int _level = 0, _score = 0, _lives = 3;
  bool _playing = false, _over = false, _newBest = false;

  double get _basketX => _tracker?.point.value?.dx ?? 0.5;

  @override
  void dispose() {
    _ticker.dispose();
    _tracker?.dispose();
    super.dispose();
  }

  void _start() {
    if (_tracker != null && _tracker!.head != _byHead) {
      _tracker!.dispose();
      _tracker = null;
    }
    _hands;
    setState(() {
      _fruit.clear();
      _score = 0;
      _lives = 3;
      _playing = true;
      _over = false;
      _last = Duration.zero;
    });
    _ticker.start();
  }

  Future<void> _finish() async {
    _ticker.stop();
    final key = 'catch${_level + 1}';
    final best = await KidsScores.offer(key, _score);
    await KidsScores.addStars(_score >= 30 ? 3 : (_score >= 18 ? 2 : (_score >= 8 ? 1 : 0)));
    if (mounted) {
      setState(() {
        _playing = false;
        _over = true;
        _newBest = best;
      });
    }
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    _hands.step(dt);
    // A little faster as the score climbs.
    final pace = (1 + _level * 0.4) * (1 + math.min(_score, 40) / 60);
    _spawn -= dt;
    if (_spawn <= 0) {
      _spawn = (1.3 - _level * 0.3) * (0.7 + _rng.nextDouble() * 0.6) / math.sqrt(pace);
      _fruit.add(_Fruit(0.08 + _rng.nextDouble() * 0.84, _rng.nextInt(_fruitEmoji.length), (0.22 + _rng.nextDouble() * 0.08) * pace));
    }
    final basket = _basketX;
    const basketHalf = 0.11;
    for (final f in _fruit) {
      if (f.caught >= 0) {
        f.caught += dt;
        continue;
      }
      f.y += f.speed * dt;
      if (f.y >= 0.84 && f.y < 0.95 && (f.x - basket).abs() < basketHalf) {
        f.caught = 0;
        _score++;
      } else if (f.y > 1.05) {
        f.caught = 99; // gone
        _lives--;
      }
    }
    _fruit.removeWhere((f) => f.caught > 0.3);
    if (_lives <= 0) {
      unawaited(_finish());
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Fruit Catcher',
    colors: const [Color(0xFF13B88A), Color(0xFF2F7BD6)],
    onBack: widget.onBack,
    trailing: _playing
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) Icon(Icons.favorite_rounded, color: i < _lives ? const Color(0xFFFF6B8B) : Colors.white24, size: 30),
              const SizedBox(width: 14),
              Text('Caught $_score', style: kidsText(28)),
            ],
          )
        : null,
    child: _over
        ? KidsResult(
            title: 'Yummy!',
            detail: 'You caught $_score fruit',
            stars: _score >= 30 ? 3 : (_score >= 18 ? 2 : (_score >= 8 ? 1 : 0)),
            newBest: _newBest,
            onAgain: () => setState(() => _over = false),
          )
        : !_playing
        ? KidsStartPanel(
            icon: Icons.shopping_basket_rounded,
            pitch: _byHead
                ? 'Lean your head left and right to catch the fruit in the basket!'
                : 'Move your hand left and right to catch the fruit in the basket!',
            best: KidsScores.best('catch${_level + 1}').then((b) => b == null ? null : 'Best: $b fruit'),
            options: Column(
              children: [
                kidsLevelChips(const ['Easy', 'Medium', 'Hard'], _level, (i) => setState(() => _level = i)),
                const SizedBox(height: 14),
                Text('Steer with', style: kidsText(18, weight: FontWeight.w700)),
                const SizedBox(height: 8),
                kidsLevelChips(const ['My hand', 'My head'], _byHead ? 1 : 0, (i) => setState(() => _byHead = i == 1)),
              ],
            ),
            onStart: _start,
          )
        : KidsMotionArena(hands: _hands, onSize: (_) {}, cursorIcon: Icons.back_hand_rounded, painter: _FruitPainter(_fruit, _basketX)),
  );
}

class _FruitPainter extends CustomPainter {
  _FruitPainter(this.fruit, this.basketX);
  final List<_Fruit> fruit;
  final double basketX;

  @override
  void paint(Canvas canvas, Size size) {
    final short = math.min(size.width, size.height);
    for (final f in fruit) {
      if (f.caught > 1) continue;
      final fade = f.caught >= 0 ? (1 - f.caught / 0.3).clamp(0.0, 1.0) : 1.0;
      final tp = TextPainter(
        text: TextSpan(
          text: _fruitEmoji[f.kind],
          style: TextStyle(
            fontSize: short * 0.1,
            color: Colors.white.withValues(alpha: fade),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(f.x * size.width - tp.width / 2, f.y * size.height - tp.height / 2));
    }
    // The basket.
    final w = size.width * 0.22, h = short * 0.12;
    final rect = Rect.fromCenter(center: Offset(basketX * size.width, size.height * 0.92), width: w, height: h);
    final basket = Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right - w * 0.12, rect.bottom)
      ..lineTo(rect.left + w * 0.12, rect.bottom)
      ..close();
    canvas.drawPath(basket, Paint()..color = const Color(0xFFC98B4A));
    final weave = Paint()
      ..color = const Color(0xFF8A5A2B)
      ..strokeWidth = 3;
    for (var i = 1; i < 6; i++) {
      final x = rect.left + w * i / 6;
      canvas.drawLine(Offset(x, rect.top), Offset(x + (i < 3 ? 4 : -4), rect.bottom), weave);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(rect.left - 6, rect.top - 6, w + 12, 12), const Radius.circular(6)),
      Paint()..color = const Color(0xFFE0A866),
    );
  }

  @override
  bool shouldRepaint(_FruitPainter old) => true;
}

// ── Finger Math ───────────────────────────────────────────────────────────

/// A sum whose answer is 0 to 5: what one hand can show. Level 0 adds,
/// 1 takes away, 2 mixes both.
({String q, int a}) fingerMathQuestion(int level, math.Random rng) {
  final kind = level == 2 ? rng.nextInt(2) : level;
  final answer = rng.nextInt(6);
  if (kind == 0) {
    final x = rng.nextInt(answer + 1);
    return (q: '$x + ${answer - x}', a: answer);
  }
  final take = rng.nextInt(5) + 1;
  return (q: '${answer + take} − $take', a: answer);
}

/// Answer each sum by holding up that many fingers to the camera (or by
/// tapping the number). Ten sums a round.
class FingerMath extends StatefulWidget {
  const FingerMath({super.key, required this.container, required this.onBack});
  final AppContainer container;
  final VoidCallback onBack;

  @override
  State<FingerMath> createState() => _FingerMathState();
}

class _FingerMathState extends State<FingerMath> {
  static const _count = 10;
  late final KidsHands _hands = KidsHands(widget.container.motion, twoHands: true);
  final _rng = math.Random();
  int _level = 0, _index = 0, _score = 0;
  bool _playing = false, _over = false, _newBest = false;
  ({String q, int a}) _item = (q: '', a: 0);
  int? _shown;
  double _hold = 0;
  bool? _result;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _hands.fingers.addListener(_onFingers);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hands.fingers.removeListener(_onFingers);
    _hands.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _playing = true;
      _over = false;
      _index = 0;
      _score = 0;
      _next();
    });
    _timer?.cancel();
    // Holding the answer for a moment counts: a passing count does not.
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_playing || _result != null) return;
      final f = _hands.fingers.value;
      if (f != null && f == _shown) {
        _hold += 0.1;
        if (_hold >= 0.8) _answer(f);
      } else {
        _hold = 0;
      }
      if (mounted) setState(() {});
    });
  }

  void _next() {
    _item = fingerMathQuestion(_level, _rng);
    _result = null;
    _hold = 0;
  }

  void _onFingers() {
    final f = _hands.fingers.value;
    if (f != _shown) {
      _shown = f;
      _hold = 0;
    }
  }

  Future<void> _answer(int value) async {
    if (_result != null) return;
    final right = value == _item.a;
    setState(() {
      _result = right;
      if (right) _score++;
    });
    await Future<void>.delayed(Duration(milliseconds: right ? 900 : 1500));
    if (!mounted) return;
    if (_index + 1 >= _count) {
      _timer?.cancel();
      final best = await KidsScores.offer('fingermath${_level + 1}', _score);
      await KidsScores.addStars(_score >= 9 ? 3 : (_score >= 7 ? 2 : (_score >= 5 ? 1 : 0)));
      if (mounted) {
        setState(() {
          _playing = false;
          _over = true;
          _newBest = best;
        });
      }
      return;
    }
    setState(() {
      _index++;
      _next();
    });
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Finger Math',
    colors: const [Color(0xFFFF7A3D), Color(0xFFB04BFF)],
    onBack: widget.onBack,
    trailing: _playing ? Text('${_index + 1} / $_count   ★ $_score', style: kidsText(28)) : null,
    child: _over
        ? KidsResult(
            title: _score >= 9 ? 'Super maths hands!' : 'Nice counting!',
            detail: '$_score of $_count right',
            stars: _score >= 9 ? 3 : (_score >= 7 ? 2 : (_score >= 5 ? 1 : 0)),
            newBest: _newBest,
            onAgain: () => setState(() => _over = false),
          )
        : !_playing
        ? KidsStartPanel(
            icon: Icons.front_hand_rounded,
            pitch: _hands.camera ? 'Show the answer with your fingers!' : 'Tap the answer (turn the camera on to use your fingers!)',
            best: KidsScores.best('fingermath${_level + 1}').then((b) => b == null ? null : 'Best: $b of $_count'),
            options: kidsLevelChips(const ['Adding', 'Taking away', 'Mixed'], _level, (i) => setState(() => _level = i)),
            onStart: _start,
          )
        : _board(),
  );

  Widget _board() {
    final shown = _hands.fingers.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: _result == null
                    ? const Color(0xFF101828).withValues(alpha: 0.45)
                    : (_result! ? const Color(0xFF2FB872) : const Color(0xFFE0525A)).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(child: Text('${_item.q} = ?', style: kidsText(110))),
                  const SizedBox(height: 12),
                  if (_result == null && _hands.camera)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.front_hand_rounded, color: Color(0xFFF2CF6E), size: 44),
                        const SizedBox(width: 12),
                        Text(shown == null ? 'Show me your fingers!' : 'You show $shown', style: kidsText(34)),
                        if (shown != null) ...[
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: CircularProgressIndicator(
                              value: (_hold / 0.8).clamp(0.0, 1.0),
                              strokeWidth: 6,
                              color: const Color(0xFFF2CF6E),
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ],
                      ],
                    ),
                  if (_result != null) Text(_result! ? 'Yes! It is ${_item.a}' : 'It is ${_item.a}', style: kidsText(40)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var n = 0; n <= 5; n++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: KidsBounce(
                      onTap: _result == null ? () => unawaited(_answer(n)) : null,
                      child: Container(
                        height: 84,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(22),
                          border: Border(bottom: BorderSide(color: Color(0xFF6A4CFF).withValues(alpha: 0.8), width: 7)),
                        ),
                        child: Text('$n', style: kidsText(44, color: const Color(0xFF1E2A44))),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Space Blaster ─────────────────────────────────────────────────────────

/// Pixel art: each string is a row, '.' empty, letters pick a colour.
const _shipArt = ['....W....', '...WCW...', '...WCW...', '..WWCWW..', '.RWWWWWR.', 'RWWBWBWWR', 'RW.WWW.WR', 'R..O.O..R'];
const _droneArt = ['....CCC....', '...CWWWC...', '..GGGGGGG..', '.GGGGGGGGG.', 'GOGGOGGOGGO', '.GGGGGGGGG.', '...G...G...'];
const _rockArt = ['..SSSS..', '.SSDSSS.', 'SSSSSDSS', 'SDSSSSSS', 'SSSSDSSS', '.SSSSSD.', '..SSSS..'];
const _pixelColors = {
  'W': Color(0xFFE8F1FF),
  'C': Color(0xFF39D0FF),
  'R': Color(0xFFFF3D6E),
  'B': Color(0xFF2B3A8F),
  'O': Color(0xFFE7B663),
  'G': Color(0xFF7CFF6B),
  'S': Color(0xFF9A8F86),
  'D': Color(0xFF6B625B),
};

void _drawPixels(Canvas canvas, List<String> art, Offset centre, double cell, {double alpha = 1, Color? tint}) {
  final h = art.length, w = art.first.length;
  final paint = Paint();
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = _pixelColors[art[y][x]];
      if (c == null) continue;
      paint.color = (tint ?? c).withValues(alpha: alpha);
      canvas.drawRect(Rect.fromLTWH(centre.dx + (x - w / 2) * cell, centre.dy + (y - h / 2) * cell, cell + 0.5, cell + 0.5), paint);
    }
  }
}

class _Foe {
  _Foe(this.x, this.y, this.drone, this.speed, this.hp);
  double x, y;
  final bool drone;
  final double speed;
  int hp;
  double hit = 0; // flash after a hit
  double phase = 0;
}

class _Shot {
  _Shot(this.x, this.y, this.dx);
  double x, y;
  final double dx;
}

class _Spark {
  _Spark(this.x, this.y, this.vx, this.vy, this.color);
  double x, y, life = 0;
  final double vx, vy;
  final Color color;
}

class _Power {
  _Power(this.x, this.y, this.shield);
  double x, y;
  final bool shield;
}

/// Steer the ship with your hand (or a finger on the screen); it fires by
/// itself. Blast the asteroids and drones, grab the power-ups, and keep your
/// three ships as long as you can. The waves get faster as you go.
class SpaceBlaster extends StatefulWidget {
  const SpaceBlaster({super.key, required this.container, required this.onBack});
  final AppContainer container;
  final VoidCallback onBack;

  @override
  State<SpaceBlaster> createState() => _SpaceBlasterState();
}

class _SpaceBlasterState extends State<SpaceBlaster> with SingleTickerProviderStateMixin {
  /// Steer with the head (the default) or a hand.
  bool _byHead = true;
  KidsHands? _tracker;
  KidsHands get _hands => _tracker ??= KidsHands(widget.container.motion, head: _byHead);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  final _rng = math.Random();
  final _foes = <_Foe>[];
  final _shots = <_Shot>[];
  final _sparks = <_Spark>[];
  final _powers = <_Power>[];
  final _stars = List.generate(70, (i) => (math.Random(i).nextDouble(), math.Random(i * 7 + 1).nextDouble(), 1 + (i % 3)));
  Duration _last = Duration.zero;
  double _time = 0, _spawn = 0, _fire = 0, _triple = 0, _shield = 0, _hurt = 0;
  int _level = 0, _score = 0, _lives = 3, _wave = 1;
  bool _playing = false, _over = false, _newBest = false;

  Offset get _ship {
    final p = _tracker?.point.value ?? const Offset(0.5, 0.85);
    // The ship keeps to the lower part of space.
    return Offset(p.dx.clamp(0.06, 0.94), (0.55 + p.dy * 0.4).clamp(0.55, 0.92));
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tracker?.dispose();
    super.dispose();
  }

  void _start() {
    // Start the tracker the player chose (and stop any other).
    if (_tracker != null && _tracker!.head != _byHead) {
      _tracker!.dispose();
      _tracker = null;
    }
    _hands;
    setState(() {
      _foes.clear();
      _shots.clear();
      _sparks.clear();
      _powers.clear();
      _score = 0;
      _lives = 3;
      _wave = 1;
      _time = 0;
      _triple = 0;
      _shield = 2; // a moment to get ready
      _playing = true;
      _over = false;
      _last = Duration.zero;
    });
    _ticker.start();
  }

  Future<void> _finish() async {
    _ticker.stop();
    final key = 'blaster${_level + 1}';
    final best = await KidsScores.offer(key, _score);
    await KidsScores.addStars(_score >= 1500 ? 3 : (_score >= 800 ? 2 : (_score >= 300 ? 1 : 0)));
    if (mounted) {
      setState(() {
        _playing = false;
        _over = true;
        _newBest = best;
      });
    }
  }

  void _boom(double x, double y, Color color, int n) {
    for (var i = 0; i < n; i++) {
      final a = _rng.nextDouble() * math.pi * 2, v = 0.1 + _rng.nextDouble() * 0.35;
      _sparks.add(_Spark(x, y, math.cos(a) * v, math.sin(a) * v, i.isEven ? color : const Color(0xFFF3DA8A)));
    }
  }

  void _tick(Duration now) {
    final dt = math.min(0.05, _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6);
    _last = now;
    _time += dt;
    _hands.step(dt);
    _wave = 1 + (_time ~/ 25);
    final pace = (1 + _level * 0.35) * (1 + (_wave - 1) * 0.18);
    final ship = _ship;
    _triple = math.max(0, _triple - dt);
    _shield = math.max(0, _shield - dt);
    _hurt = math.max(0, _hurt - dt);

    // Fire.
    _fire -= dt;
    if (_fire <= 0) {
      _fire = 0.22;
      _shots.add(_Shot(ship.dx, ship.dy - 0.05, 0));
      if (_triple > 0) {
        _shots
          ..add(_Shot(ship.dx, ship.dy - 0.04, -0.25))
          ..add(_Shot(ship.dx, ship.dy - 0.04, 0.25));
      }
    }
    for (final s in _shots) {
      s.y -= 1.3 * dt;
      s.x += s.dx * dt;
    }
    _shots.removeWhere((s) => s.y < -0.05 || s.x < 0 || s.x > 1);

    // Spawn.
    _spawn -= dt;
    if (_spawn <= 0) {
      _spawn = (1.1 - _level * 0.2) / math.sqrt(pace) * (0.6 + _rng.nextDouble() * 0.8);
      final drone = _rng.nextDouble() < 0.35 + _wave * 0.04;
      _foes.add(_Foe(0.08 + _rng.nextDouble() * 0.84, -0.08, drone, (drone ? 0.13 : 0.17 + _rng.nextDouble() * 0.08) * pace, drone ? 2 : 1));
    }
    for (final f in _foes) {
      f.phase += dt;
      f.y += f.speed * dt;
      if (f.drone) f.x = (f.x + math.sin(f.phase * 2.5) * 0.12 * dt).clamp(0.05, 0.95);
      f.hit = math.max(0, f.hit - dt);
    }

    // Hits.
    for (final f in _foes) {
      for (final s in _shots) {
        if (f.hp > 0 && (s.x - f.x).abs() < 0.045 && (s.y - f.y).abs() < 0.05) {
          s.y = -1;
          f.hp--;
          f.hit = 0.12;
          if (f.hp <= 0) {
            _score += f.drone ? 50 : 20;
            _boom(f.x, f.y, f.drone ? const Color(0xFF7CFF6B) : const Color(0xFFFF8A3D), 16);
            if (_rng.nextDouble() < 0.08) _powers.add(_Power(f.x, f.y, _rng.nextBool()));
          }
        }
      }
      // Crashes.
      if (f.hp > 0 && (f.x - ship.dx).abs() < 0.06 && (f.y - ship.dy).abs() < 0.06) {
        f.hp = 0;
        _boom(f.x, f.y, const Color(0xFFFF3D6E), 20);
        if (_shield <= 0) {
          _lives--;
          _hurt = 0.6;
          _shield = 1.5;
        }
      }
      if (f.hp > 0 && f.y > 1.08) f.hp = 0;
    }
    _foes.removeWhere((f) => f.hp <= 0);

    for (final p in _powers) {
      p.y += 0.2 * dt;
      if ((p.x - ship.dx).abs() < 0.07 && (p.y - ship.dy).abs() < 0.07) {
        p.y = 2;
        if (p.shield) {
          _shield = 6;
        } else {
          _triple = 8;
        }
        _score += 30;
      }
    }
    _powers.removeWhere((p) => p.y > 1.1);
    for (final s in _sparks) {
      s.life += dt;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
    }
    _sparks.removeWhere((s) => s.life > 0.6);

    if (_lives <= 0) {
      unawaited(_finish());
      return;
    }
    setState(() {});
  }

  TextStyle _arcade(double size, [Color color = Colors.white]) => TextStyle(
    fontFamily: 'VT323',
    fontSize: size,
    color: color,
    letterSpacing: 2,
    shadows: [Shadow(color: color.withValues(alpha: 0.8), blurRadius: 10)],
  );

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Space Blaster',
    colors: const [Color(0xFF1A1340), Color(0xFF3A2F7A)],
    onBack: widget.onBack,
    trailing: _playing
        ? ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.55),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('WAVE $_wave', style: _arcade(30, const Color(0xFF39D0FF))),
                  const SizedBox(width: 18),
                  Text(_score.toString().padLeft(5, '0'), style: _arcade(36, const Color(0xFFF3DA8A))),
                  const SizedBox(width: 18),
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.rocket_rounded, color: i < _lives ? const Color(0xFFFF3D6E) : Colors.white24, size: 28),
                    ),
                ],
              ),
            ),
          )
        : null,
    child: _over
        ? KidsResult(
            title: 'GAME OVER',
            detail: 'Score $_score · reached wave $_wave',
            stars: _score >= 1500 ? 3 : (_score >= 800 ? 2 : (_score >= 300 ? 1 : 0)),
            newBest: _newBest,
            onAgain: () => setState(() => _over = false),
          )
        : !_playing
        ? KidsStartPanel(
            icon: Icons.rocket_launch_rounded,
            pitch: _byHead
                ? 'Lean your head left and right to fly the ship. It shoots by itself: blast the space rocks and drones!'
                : 'Move your hand to fly the ship. It shoots by itself: blast the space rocks and drones!',
            best: KidsScores.best('blaster${_level + 1}').then((b) => b == null ? null : 'High score: $b'),
            options: Column(
              children: [
                kidsLevelChips(const ['Cadet', 'Pilot', 'Ace'], _level, (i) => setState(() => _level = i)),
                const SizedBox(height: 14),
                Text('Steer with', style: kidsText(18, weight: FontWeight.w700)),
                const SizedBox(height: 8),
                kidsLevelChips(const ['My head', 'My hand'], _byHead ? 0 : 1, (i) => setState(() => _byHead = i == 0)),
              ],
            ),
            onStart: _start,
          )
        : _arena(),
  );

  Widget _arena() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          Offset frac(Offset local) => Offset((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (d) => _hands.touch(frac(d.localPosition)),
            onPanUpdate: (d) => _hands.touch(frac(d.localPosition)),
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _SpacePainter(this))),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 14,
                  child: KidsHandHint(hands: _hands, visible: !_hands.handInView),
                ),
                if (_hands.camera)
                  Positioned(
                    right: 10,
                    top: 10,
                    child: IconButton(
                      tooltip: 'Swap left and right',
                      color: Colors.white70,
                      icon: const Icon(Icons.swap_horiz_rounded),
                      onPressed: () => _hands.flip = !_hands.flip,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _SpacePainter extends CustomPainter {
  _SpacePainter(this.g);
  final _SpaceBlasterState g;

  @override
  void paint(Canvas canvas, Size size) {
    final short = math.min(size.width, size.height);
    final cell = short / 90; // one "pixel" of the arcade art
    // Deep space with a faint scanline grid.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF05010F), Color(0xFF10082A), Color(0xFF1B0B3A)],
        ).createShader(Offset.zero & size),
    );
    final scan = Paint()..color = const Color(0x0DFFFFFF);
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), scan);
    }
    // Starfield in three layers, scrolling.
    final star = Paint();
    for (final (sx, sy, layer) in g._stars) {
      final y = ((sy + g._time * 0.05 * layer) % 1) * size.height;
      star.color = Colors.white.withValues(alpha: 0.25 + layer * 0.22);
      canvas.drawRect(Rect.fromLTWH(sx * size.width, y, layer * 1.5, layer * 1.5), star);
    }
    // Lasers.
    final laser = Paint()..color = const Color(0xFF39D0FF);
    final glow = Paint()
      ..color = const Color(0x6639D0FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    for (final s in g._shots) {
      final r = Rect.fromCenter(center: Offset(s.x * size.width, s.y * size.height), width: cell * 1.4, height: cell * 6);
      canvas.drawRect(r.inflate(cell), glow);
      canvas.drawRect(r, laser);
    }
    // Space rocks and drones.
    for (final f in g._foes) {
      final c = Offset(f.x * size.width, f.y * size.height);
      _drawPixels(canvas, f.drone ? _droneArt : _rockArt, c, cell * 1.3, tint: f.hit > 0 ? Colors.white : null);
    }
    // Power-ups: a pulsing gem.
    for (final p in g._powers) {
      final c = Offset(p.x * size.width, p.y * size.height);
      final pulse = 1 + 0.15 * math.sin(g._time * 10);
      final col = p.shield ? const Color(0xFF39D0FF) : const Color(0xFFF3DA8A);
      canvas.drawRect(Rect.fromCenter(center: c, width: cell * 7 * pulse, height: cell * 7 * pulse), Paint()..color = col);
      final tp = TextPainter(
        text: TextSpan(
          text: p.shield ? 'S' : '3',
          style: TextStyle(fontFamily: 'VT323', fontSize: cell * 8, color: const Color(0xFF1A1340)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
    // The ship (blinking right after a crash), its flame and shield.
    final ship = Offset(g._ship.dx * size.width, g._ship.dy * size.height);
    final flame = Paint()..color = Color.lerp(const Color(0xFFE7B663), const Color(0xFFFF3D6E), (math.sin(g._time * 30) + 1) / 2)!;
    canvas.drawRect(Rect.fromCenter(center: ship + Offset(0, cell * 7), width: cell * 2.5, height: cell * (3 + 2 * ((g._time * 20) % 1))), flame);
    if (g._hurt <= 0 || (g._time * 12).floor().isEven) _drawPixels(canvas, _shipArt, ship, cell * 1.4);
    if (g._shield > 0) {
      canvas.drawCircle(
        ship,
        cell * 10,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell
          ..color = const Color(0xFF39D0FF).withValues(alpha: 0.4 + 0.3 * math.sin(g._time * 8)),
      );
    }
    // Explosions: chunky pixels flying out.
    for (final s in g._sparks) {
      final a = (1 - s.life / 0.6).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(s.x * size.width, s.y * size.height), width: cell * 2, height: cell * 2),
        Paint()..color = s.color.withValues(alpha: a),
      );
    }
    if (g._triple > 0) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'TRIPLE SHOT',
          style: TextStyle(fontFamily: 'VT323', fontSize: 28, color: Color(0xFFF3DA8A)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(16, size.height - tp.height - 12));
    }
  }

  @override
  bool shouldRepaint(_SpacePainter old) => true;
}

// ── Steering by hand or head ──────────────────────────────────────────────

/// Which way a tracked point is pushed from the middle: (dx, dy) of the
/// stronger way, or null while it rests in the middle ([dead] each way).
(int, int)? steerFrom(Offset? p, {double dead = 0.14}) {
  if (p == null) return null;
  final dx = p.dx - 0.5, dy = p.dy - 0.5;
  if (dx.abs() < dead && dy.abs() < dead) return null;
  return dx.abs() >= dy.abs() ? (dx > 0 ? 1 : -1, 0) : (0, dy > 0 ? 1 : -1);
}

/// Turns a hand or head into steps: one step each time it leaves the
/// middle, then it must come back before the next (for hopping games).
class StepTrigger {
  bool _armed = true;

  /// The step to take now, if any.
  (int, int)? update(Offset? p, {double dead = 0.16}) {
    final s = steerFrom(p, dead: dead);
    if (s == null) {
      // Back in the middle (a little inside, so wobbles don't re-fire).
      if (steerFrom(p, dead: dead * 0.6) == null) _armed = true;
      return null;
    }
    if (!_armed) return null;
    _armed = false;
    return s;
  }
}

/// A little round pad showing where the hand or head is pushing: the dot
/// follows it, the ring lights the way it steers.
class KidsMotionStick extends StatelessWidget {
  const KidsMotionStick({super.key, required this.hands, this.size = 150});
  final KidsHands hands;
  final double size;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Offset?>(
    valueListenable: hands.point,
    builder: (context, p, _) => SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _StickPainter(p, hands.handInView, hands.head)),
    ),
  );
}

class _StickPainter extends CustomPainter {
  _StickPainter(this.p, this.live, this.head);
  final Offset? p;
  final bool live, head;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = Colors.white.withValues(alpha: 0.12));
    canvas.drawCircle(
      c,
      r - 1.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF39D0FF).withValues(alpha: live ? 0.9 : 0.35),
    );
    canvas.drawCircle(c, r * 0.28, Paint()..color = Colors.white.withValues(alpha: 0.1));
    final s = steerFrom(p);
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final on = s == (dx, dy);
      final tip = c + Offset(dx * r * 0.82, dy * r * 0.82);
      final side = Offset(-dy * r * 0.14, dx * r * 0.14);
      final back = c + Offset(dx * r * 0.6, dy * r * 0.6);
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(back.dx + side.dx, back.dy + side.dy)
          ..lineTo(back.dx - side.dx, back.dy - side.dy)
          ..close(),
        Paint()..color = on ? const Color(0xFFF3DA8A) : Colors.white24,
      );
    }
    final q = p;
    if (q != null) {
      final dot = c + Offset((q.dx - 0.5) * 2 * r * 0.8, (q.dy - 0.5) * 2 * r * 0.8);
      canvas.drawCircle(dot, r * 0.17, Paint()..color = live ? const Color(0xFFF3DA8A) : Colors.white38);
    }
    final icon = head ? Icons.face_rounded : Icons.back_hand_rounded;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: r * 0.3, color: Colors.white54),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_StickPainter old) => old.p != p || old.live != live;
}

/// How a step-at-a-time game is played: the arrow buttons, a hand or the
/// head.
Widget kidsPlayWithChips(int selected, ValueChanged<int> onPick) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    Text('Play with', style: kidsText(18, weight: FontWeight.w700)),
    const SizedBox(height: 8),
    kidsLevelChips(const ['Buttons', 'My hand', 'My head'], selected, onPick),
  ],
);

/// Starts tracking for [playWith] (1 hand, 2 head), or none for buttons.
KidsHands? kidsTrackerFor(AppContainer? container, int playWith) =>
    container == null || playWith == 0 ? null : KidsHands(container.motion, head: playWith == 2);

/// In place of the arrow buttons while a hand or the head steers: the
/// stick that shows where it pushes, a left-right swap and a hint.
class KidsMotionPanel extends StatefulWidget {
  const KidsMotionPanel({super.key, required this.hands, this.hint});
  final KidsHands hands;
  final String? hint;

  @override
  State<KidsMotionPanel> createState() => _KidsMotionPanelState();
}

class _KidsMotionPanelState extends State<KidsMotionPanel> {
  @override
  Widget build(BuildContext context) {
    final h = widget.hands;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KidsMotionStick(hands: h),
        const SizedBox(height: 8),
        SizedBox(
          width: 220,
          child: Text(
            !h.camera ? 'Camera is off: swipe on the game' : widget.hint ?? (h.head ? 'Lean your head the way to go' : 'Move your hand the way to go'),
            textAlign: TextAlign.center,
            style: kidsText(17, weight: FontWeight.w700),
          ),
        ),
        if (h.camera)
          TextButton.icon(
            onPressed: () => setState(() => h.flip = !h.flip),
            icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white70),
            label: Text(
              'Swap sides',
              style: kidsText(15, color: Colors.white70, weight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}
