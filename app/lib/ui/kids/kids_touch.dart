import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'kids_activities.dart';
import 'kids_arcade.dart' show arcadeText;
import 'kids_arcade2.dart' show arcadeHud;
import 'kids_games.dart';
import 'kids_logic.dart' show KidsScores;

/// Touch games for the Play shelf: Star Swipe (swipe through the stars,
/// miss the storm clouds) and Stack Up (drop each block on the tower).

void _say(Canvas canvas, String text, Offset centre, double size, Color color) {
  final tp = TextPainter(text: TextSpan(text: text, style: arcadeText(size, color)), textDirection: TextDirection.ltr)..layout();
  tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
}

/// Whether the swipe from [a] to [b] passes within [r] of [c].
bool swipeHits(Offset a, Offset b, Offset c, double r) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  final t = len2 == 0 ? 0.0 : (((c - a).dx * ab.dx + (c - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (a + ab * t - c).distance <= r;
}

// ── Star Swipe ────────────────────────────────────────────────────────────

class SwipeThing {
  SwipeThing(this.pos, this.vel, this.r, this.kind, this.hue);
  Offset pos; // pixels
  Offset vel; // pixels a second
  final double r;

  /// 0 star, 1 planet (3 points), 2 storm cloud (lose a life).
  final int kind;
  final double hue;
  double hit = -1; // seconds since swiped, -1 while whole
  double spin = 0;
}

/// Stars are tossed up into the night sky: swipe through them to burst
/// them, but don't touch the storm clouds. Three clouds and it's over.
class StarSwipe extends StatefulWidget {
  const StarSwipe({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<StarSwipe> createState() => _StarSwipeState();
}

class _StarSwipeState extends State<StarSwipe> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _rng = math.Random();
  final things = <SwipeThing>[];
  final trail = <(Offset, double)>[]; // point, age
  Offset? _finger;
  Size size = Size.zero;
  Duration _last = Duration.zero;
  double _spawn = 0, time = 0, flash = 0;
  int level = 0, score = 0, lives = 3, combo = 0;
  bool playing = false, over = false, newBest = false;
  String message = '';

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  int _stars(int s) => s >= 120 ? 3 : (s >= 60 ? 2 : (s >= 20 ? 1 : 0));

  void _start() {
    setState(() {
      things.clear();
      trail.clear();
      score = 0;
      lives = 3;
      combo = 0;
      time = 0;
      _spawn = 0.6;
      playing = true;
      over = false;
      _last = Duration.zero;
    });
    _ticker.start();
  }

  Future<void> _finish() async {
    if (!_ticker.isActive) return;
    _ticker.stop();
    final best = await KidsScores.offer('swipe${level + 1}', score);
    await KidsScores.addStars(_stars(score));
    if (mounted) {
      setState(() {
        playing = false;
        over = true;
        newBest = best;
      });
    }
  }

  void _toss() {
    if (size == Size.zero) return;
    final short = math.min(size.width, size.height);
    final x = size.width * (0.15 + _rng.nextDouble() * 0.7);
    // Up to about three quarters of the way, drifting towards the middle.
    final g = _gravity;
    final rise = size.height * (0.55 + _rng.nextDouble() * 0.3);
    final vy = -math.sqrt(2 * g * rise);
    final vx = (size.width / 2 - x) * (0.25 + _rng.nextDouble() * 0.3);
    final roll = _rng.nextDouble();
    final cloudChance = const [0.1, 0.16, 0.22][level] + math.min(0.08, time / 600);
    final kind = roll < cloudChance ? 2 : (roll < cloudChance + 0.15 ? 1 : 0);
    things.add(SwipeThing(
      Offset(x, size.height + short * 0.08),
      Offset(vx, vy),
      short * (kind == 1 ? 0.07 : (kind == 2 ? 0.08 : 0.055)),
      kind,
      _rng.nextDouble() * 360,
    ));
  }

  double get _gravity => size.height * const [0.9, 1.1, 1.3][level];

  void _tick(Duration now) {
    final dt = math.min(0.05, _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6);
    _last = now;
    time += dt;
    flash = math.max(0, flash - dt);
    _spawn -= dt;
    if (_spawn <= 0) {
      final burst = 1 + (_rng.nextDouble() < 0.25 + level * 0.1 ? _rng.nextInt(2 + level) : 0);
      for (var i = 0; i < burst; i++) {
        _toss();
      }
      _spawn = math.max(0.45, const [1.3, 1.05, 0.85][level] - time / 120);
    }
    for (final t in things) {
      if (t.hit >= 0) {
        t.hit += dt;
        continue;
      }
      t.vel += Offset(0, _gravity * dt);
      t.pos += t.vel * dt;
      t.spin += dt * 2;
    }
    // A star that falls back unswiped breaks the combo, nothing worse.
    things.removeWhere((t) {
      final gone = t.hit > 0.5 || (t.hit < 0 && t.vel.dy > 0 && t.pos.dy > size.height + t.r * 2);
      if (gone && t.hit < 0 && t.kind != 2) combo = 0;
      return gone;
    });
    for (var i = 0; i < trail.length; i++) {
      trail[i] = (trail[i].$1, trail[i].$2 + dt);
    }
    trail.removeWhere((p) => p.$2 > 0.18);
    setState(() {});
  }

  void _swipe(Offset to) {
    final from = _finger;
    _finger = to;
    trail.add((to, 0));
    if (from == null || !playing) return;
    for (final t in things) {
      if (t.hit >= 0 || !swipeHits(from, to, t.pos, t.r * 1.15)) continue;
      t.hit = 0;
      if (t.kind == 2) {
        combo = 0;
        lives--;
        message = 'ZAP!';
        flash = 0.8;
        if (lives <= 0) {
          unawaited(_finish());
          return;
        }
      } else {
        combo++;
        final points = (t.kind == 1 ? 3 : 1) + (combo >= 5 ? 1 : 0);
        score += points;
        if (combo == 5 || combo == 10 || combo == 20) {
          message = 'COMBO x$combo!';
          flash = 1;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Star Swipe',
    colors: const [Color(0xFF14123A), Color(0xFF4B3A9A)],
    onBack: widget.onBack,
    trailing: playing ? arcadeHud(context, 'SCORE', score, lives, Icons.thunderstorm_rounded, const Color(0xFF9FB4FF)) : null,
    child: over
        ? KidsResult(
            title: 'STARRY!',
            detail: 'Score $score',
            stars: _stars(score),
            newBest: newBest,
            onAgain: () => setState(() => over = false),
          )
        : !playing
        ? KidsStartPanel(
            icon: Icons.auto_awesome_rounded,
            pitch: 'Stars fly up into the sky. Swipe your finger through them to make them burst! Planets are worth 3. Don\'t touch the storm clouds.',
            best: KidsScores.best('swipe${level + 1}').then((b) => b == null ? null : 'High score: $b'),
            options: kidsLevelChips(const ['Easy', 'Medium', 'Hard'], level, (i) => setState(() => level = i)),
            onStart: _start,
          )
        : LayoutBuilder(
            builder: (context, box) {
              size = Size(box.maxWidth, box.maxHeight);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) {
                  _finger = null;
                  _swipe(d.localPosition);
                },
                onPanUpdate: (d) => _swipe(d.localPosition),
                onPanEnd: (_) => _finger = null,
                child: CustomPaint(size: size, painter: _SwipePainter(this)),
              );
            },
          ),
  );
}

class _SwipePainter extends CustomPainter {
  _SwipePainter(this.g);
  final _StarSwipeState g;

  @override
  void paint(Canvas canvas, Size size) {
    final short = math.min(size.width, size.height);
    final rng = math.Random(11);
    for (var i = 0; i < 50; i++) {
      final twinkle = 0.3 + 0.3 * math.sin(g.time * 2 + i);
      canvas.drawCircle(Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height), 1 + rng.nextDouble() * 1.5,
          Paint()..color = Colors.white.withValues(alpha: twinkle));
    }
    for (final t in g.things) {
      if (t.hit >= 0) {
        final k = t.hit / 0.5;
        final color = t.kind == 2 ? const Color(0xFFFFE066) : HSVColor.fromAHSV(1, t.hue, 0.5, 1).toColor();
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4 + t.hue;
          canvas.drawCircle(t.pos + Offset(math.cos(a), math.sin(a)) * t.r * (1 + k * 2.5), t.r * 0.18 * (1 - k),
              Paint()..color = color.withValues(alpha: 1 - k));
        }
        continue;
      }
      switch (t.kind) {
        case 0:
          _star(canvas, t.pos, t.r, t.spin, HSVColor.fromAHSV(1, 40 + (t.hue % 40), 0.65, 1).toColor());
        case 1:
          final c = HSVColor.fromAHSV(1, t.hue, 0.45, 0.95).toColor();
          canvas.drawCircle(t.pos, t.r, Paint()..color = c);
          canvas.drawCircle(t.pos - Offset(t.r * 0.3, t.r * 0.3), t.r * 0.35, Paint()..color = Colors.white24);
          canvas.save();
          canvas.translate(t.pos.dx, t.pos.dy);
          canvas.rotate(-0.4);
          canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: t.r * 3, height: t.r * 0.7), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = t.r * 0.14
            ..color = Colors.white70);
          canvas.restore();
        default:
          final grey = Paint()..color = const Color(0xFF5B6478);
          for (final (dx, dy, rr) in const [(-0.5, 0.1, 0.55), (0.0, -0.2, 0.7), (0.55, 0.1, 0.5), (0.0, 0.25, 0.6)]) {
            canvas.drawCircle(t.pos + Offset(dx, dy) * t.r, rr * t.r, grey);
          }
          final bolt = Path()
            ..moveTo(t.pos.dx + t.r * 0.1, t.pos.dy + t.r * 0.4)
            ..lineTo(t.pos.dx - t.r * 0.2, t.pos.dy + t.r * 0.95)
            ..lineTo(t.pos.dx + t.r * 0.05, t.pos.dy + t.r * 0.9)
            ..lineTo(t.pos.dx - t.r * 0.1, t.pos.dy + t.r * 1.35)
            ..lineTo(t.pos.dx + t.r * 0.3, t.pos.dy + t.r * 0.75)
            ..lineTo(t.pos.dx + t.r * 0.05, t.pos.dy + t.r * 0.8)
            ..close();
          canvas.drawPath(bolt, Paint()..color = const Color(0xFFFFE066));
      }
    }
    // The finger's glowing trail.
    for (var i = 1; i < g.trail.length; i++) {
      final (a, age) = g.trail[i - 1];
      final (b, _) = g.trail[i];
      final k = 1 - age / 0.18;
      canvas.drawLine(a, b, Paint()
        ..color = const Color(0xFFBFE9FF).withValues(alpha: k.clamp(0.0, 1.0))
        ..strokeWidth = 3 + 9 * k
        ..strokeCap = StrokeCap.round);
    }
    if (g.flash > 0) {
      _say(canvas, g.message, Offset(size.width / 2, size.height * 0.12), short * 0.09,
          (g.message == 'ZAP!' ? const Color(0xFFFF6B6B) : const Color(0xFFF3DA8A)).withValues(alpha: g.flash.clamp(0.0, 1.0)));
    }
  }

  void _star(Canvas canvas, Offset c, double r, double spin, Color color) {
    final path = Path();
    for (var i = 0; i <= 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5 + spin;
      final rr = i.isEven ? r : r * 0.45;
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawCircle(c, r * 1.3, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SwipePainter old) => true;
}

// ── Stack Up ──────────────────────────────────────────────────────────────

/// One block of the tower: its left edge and width, in fractions of the
/// play area's width.
class StackBlock {
  const StackBlock(this.left, this.width, this.hue);
  final double left, width, hue;
  double get right => left + width;
}

/// Drops [moving] on [top]: the part hanging over is cut off. Returns the
/// block that stays (null: it missed) and whether it was a perfect drop
/// (lined up within [snap], which then snaps it exactly).
(StackBlock?, bool) stackDrop(StackBlock top, StackBlock moving, {double snap = 0.012}) {
  if ((moving.left - top.left).abs() <= snap) return (StackBlock(top.left, top.width, moving.hue), true);
  final left = math.max(top.left, moving.left), right = math.min(top.right, moving.right);
  if (right <= left) return (null, false);
  return (StackBlock(left, right - left, moving.hue), false);
}

/// A block slides back and forth over the tower: tap to drop it. What
/// hangs over the edge falls off, so line them up to build high.
class StackUp extends StatefulWidget {
  const StackUp({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<StackUp> createState() => _StackUpState();
}

class _StackUpState extends State<StackUp> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final tower = <StackBlock>[];
  final falling = <(StackBlock, int, double)>[]; // block, row, seconds falling
  StackBlock? moving;
  double dir = 1, time = 0, flash = 0, view = 0;
  int level = 0, score = 0, perfects = 0;
  bool playing = false, over = false, newBest = false;
  String message = '';
  Duration _last = Duration.zero;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  int _stars(int s) => s >= 30 ? 3 : (s >= 18 ? 2 : (s >= 8 ? 1 : 0));

  double get _speed => const [0.35, 0.5, 0.65][level] + math.min(0.5, tower.length * 0.015);

  void _start() {
    setState(() {
      tower
        ..clear()
        ..add(const StackBlock(0.3, 0.4, 200));
      falling.clear();
      score = 0;
      perfects = 0;
      view = 0;
      playing = true;
      over = false;
      _last = Duration.zero;
      _next();
    });
    _ticker.start();
  }

  void _next() {
    final top = tower.last;
    dir = tower.length.isEven ? 1 : -1;
    // In view from the start, at the side it slides away from.
    moving = StackBlock(dir > 0 ? 0.0 : 1.0 - top.width, top.width, (top.hue + 18) % 360);
  }

  Future<void> _finish() async {
    if (!_ticker.isActive) return;
    _ticker.stop();
    final best = await KidsScores.offer('stack${level + 1}', score);
    await KidsScores.addStars(_stars(score));
    if (mounted) {
      setState(() {
        playing = false;
        over = true;
        newBest = best;
      });
    }
  }

  void _tick(Duration now) {
    final dt = math.min(0.05, _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6);
    _last = now;
    time += dt;
    flash = math.max(0, flash - dt);
    final m = moving;
    if (m != null) {
      var left = m.left + dir * _speed * dt;
      if (left + m.width > 1.15) dir = -1;
      if (left < -0.15) dir = 1;
      left = left.clamp(-0.2, 1.2 - m.width);
      moving = StackBlock(left, m.width, m.hue);
    }
    for (var i = 0; i < falling.length; i++) {
      falling[i] = (falling[i].$1, falling[i].$2, falling[i].$3 + dt);
    }
    falling.removeWhere((f) => f.$3 > 1.5);
    // The view climbs with the tower.
    final want = math.max(0.0, tower.length - 7.0);
    view += (want - view) * math.min(1, dt * 4);
    setState(() {});
  }

  void _drop() {
    final m = moving;
    if (!playing || m == null) return;
    final (kept, perfect) = stackDrop(tower.last, m, snap: const [0.02, 0.014, 0.01][level]);
    if (kept == null) {
      falling.add((m, tower.length, 0));
      moving = null;
      unawaited(_finish());
      return;
    }
    // What hung over falls off.
    if (!perfect) {
      if (m.left < kept.left) falling.add((StackBlock(m.left, kept.left - m.left, m.hue), tower.length, 0));
      if (m.right > kept.right) falling.add((StackBlock(kept.right, m.right - kept.right, m.hue), tower.length, 0));
    }
    tower.add(kept);
    score++;
    if (perfect) {
      perfects++;
      score++;
      message = 'PERFECT! +2';
      flash = 0.9;
    }
    _next();
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Stack Up',
    colors: const [Color(0xFF1E3A5F), Color(0xFFFF8A65)],
    onBack: widget.onBack,
    trailing: playing ? Text('Height ${tower.length - 1}   Score $score', style: kidsText(26)) : null,
    child: over
        ? KidsResult(
            title: 'WHAT A TOWER!',
            detail: '${tower.length - 1} blocks high · $perfects perfect drops',
            stars: _stars(score),
            newBest: newBest,
            onAgain: () => setState(() => over = false),
          )
        : !playing
        ? KidsStartPanel(
            icon: Icons.layers_rounded,
            pitch: 'Build the tallest tower! A block slides across: tap anywhere to drop it. Anything hanging over the edge falls off, so line them up.',
            best: KidsScores.best('stack${level + 1}').then((b) => b == null ? null : 'High score: $b'),
            options: kidsLevelChips(const ['Easy', 'Medium', 'Hard'], level, (i) => setState(() => level = i)),
            onStart: _start,
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _drop(),
            child: CustomPaint(size: Size.infinite, painter: _StackPainter(this)),
          ),
  );
}

class _StackPainter extends CustomPainter {
  _StackPainter(this.g);
  final _StackUpState g;

  @override
  void paint(Canvas canvas, Size size) {
    final short = math.min(size.width, size.height);
    final rowH = size.height / 10;
    final ground = size.height - rowH * 0.6;
    // Row r's top edge on screen, with the view scrolled up the tower.
    double rowTop(num r) => ground - (r + 1 - g.view) * rowH;
    // Sky gets darker and starrier the higher you build.
    final k = (g.view / 40).clamp(0.0, 1.0);
    canvas.drawRect(Offset.zero & size, Paint()..color = Color.lerp(const Color(0x00000000), const Color(0x88000022), k)!);
    if (k > 0.2) {
      final rng = math.Random(5);
      for (var i = 0; i < 40; i++) {
        canvas.drawCircle(Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height), 1.5,
            Paint()..color = Colors.white.withValues(alpha: (k - 0.2) * 1.2));
      }
    }
    canvas.drawRect(Rect.fromLTRB(0, rowTop(-1), size.width, size.height), Paint()..color = const Color(0xFF3F7D4E));
    void block(StackBlock b, double top, [double alpha = 1]) {
      final r = Rect.fromLTWH(b.left * size.width, top, b.width * size.width, rowH);
      final c = HSVColor.fromAHSV(1, b.hue, 0.45, 0.95).toColor();
      canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(1), const Radius.circular(6)), Paint()..color = c.withValues(alpha: alpha));
      canvas.drawRect(Rect.fromLTWH(r.left + 4, r.top + 4, r.width - 8, rowH * 0.18), Paint()..color = Colors.white.withValues(alpha: 0.25 * alpha));
    }

    for (var i = 0; i < g.tower.length; i++) {
      final top = rowTop(i);
      if (top > size.height || top < -rowH) continue;
      block(g.tower[i], top);
    }
    for (final (b, row, t) in g.falling) {
      block(b, rowTop(row) + 0.5 * size.height * 1.6 * t * t, (1 - t / 1.5).clamp(0.0, 1.0));
    }
    final m = g.moving;
    if (m != null) block(m, rowTop(g.tower.length));
    if (g.flash > 0) {
      _say(canvas, g.message, Offset(size.width / 2, size.height * 0.1), short * 0.09,
          const Color(0xFFF3DA8A).withValues(alpha: g.flash.clamp(0.0, 1.0)));
    }
  }

  @override
  bool shouldRepaint(_StackPainter old) => true;
}
