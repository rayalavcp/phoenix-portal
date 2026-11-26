import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../managers/motion/motion_manager.dart';
import '../../managers/motion/native_motion.dart' show BodyPose, FacePreviewFrame;
import 'kids_motion.dart';

/// The child in the camera games, drawn as a body of glowing neon sparks
/// whose colours flow through it, the hands as the game's bubble cursors.
/// The body stands where the child stands; its arms reach out to the
/// cursors, so what the child sees their hands touch is what the game
/// counts. Nothing of the child's picture is used: only the 33 points the
/// pose model reports. The corner preview ([GameCameraPreview]) shows the
/// camera picture itself, dimmed, with what is being tracked.

/// One person's body as drawn: the pose points smoothed (fractions of the
/// picture, as the child sees it), how sure each is, and the picture's
/// height over its width.
class ShownBody {
  const ShownBody(this.slot, this.points, this.seen, this.aspect, this.width);
  final int slot;
  final List<Offset> points;
  final List<double> seen;
  final double aspect;

  /// Shoulder width, in widths of the picture.
  final double width;

  Offset operator [](int i) => points[i];
}

/// Smooths one person's 33 points over time (the One Euro filter, as the
/// cursors use), so the drawn body glides rather than shakes.
class BodySmoother {
  final _x = List.generate(33, (_) => OneEuro(minCutoff: 1.4, beta: 4));
  final _y = List.generate(33, (_) => OneEuro(minCutoff: 1.4, beta: 4));
  DateTime? _last;

  ShownBody shown(BodyPose p, BodyView v, int slot, DateTime now, {bool flip = false}) {
    final last = _last;
    final gap = last == null ? 1.0 : now.difference(last).inMicroseconds / 1e6;
    if (gap > 0.5) {
      for (final f in [..._x, ..._y]) {
        f.reset();
      }
    }
    final dt = gap > 0.5 ? 0.0 : gap.clamp(0.0, 0.25);
    _last = now;
    final pts = <Offset>[];
    final seen = <double>[];
    for (var i = 0; i < 33; i++) {
      final raw = p.point(i);
      final x = flip ? 1 - raw.dx : raw.dx;
      pts.add(Offset(_x[i].filter(x, dt), _y[i].filter(raw.dy, dt)));
      seen.add(p.seen(i));
    }
    return ShownBody(slot, pts, seen, p.aspect, v.width);
  }
}

/// Where a body is drawn: its scale (screen pixels per width of the camera
/// picture) and where its shoulders go, eased so the body does not jump.
class _Placement {
  double k = 0, cx = 0, top = 0;

  void follow(ShownBody b, Size size, {required bool people}) {
    final sure = 0.4;
    final nose = b[BodyPose.nose];
    // From the top of the head to the feet (or, legs out of view, to
    // where the feet would be), in heights of the picture.
    final head = nose.dy - b.width * 0.85 / b.aspect;
    // Feet in view: where they are; otherwise where they would be.
    var feet = nose.dy + b.width * 4.4 / b.aspect;
    final ankles = [for (final i in const [27, 28]) if (b.seen[i] >= sure) b[i].dy];
    if (ankles.isNotEmpty) feet = ankles.reduce(math.max) + b.width * 0.15 / b.aspect;
    final tall = math.max(0.05, feet - head);
    final slotWidth = people ? size.width / 2 : size.width;
    var k = size.height * 0.84 / (tall * b.aspect);
    // Arms out must fit across the screen (or the player's half).
    k = math.min(k, slotWidth * 0.92 / (b.width * 4.3));
    final shoulders = Offset.lerp(b[BodyPose.leftShoulder], b[BodyPose.rightShoulder], 0.5)!;
    final cx = people
        ? (b.slot + 0.5) / 2 * size.width + (shoulders.dx - (b.slot == 0 ? 0.25 : 0.75)) * size.width * 0.4
        : size.width * (0.5 + (shoulders.dx - 0.5) * 1.3).clamp(0.22, 0.78);
    final top = size.height * 0.07 + (shoulders.dy - head) * b.aspect * k;
    const ease = 0.18;
    if (this.k == 0) {
      this.k = k;
      this.cx = cx;
      this.top = top;
    } else {
      this.k += (k - this.k) * ease;
      this.cx += (cx - this.cx) * ease;
      this.top += (top - this.top) * ease;
    }
  }

  /// A point of [b] on the screen.
  Offset at(ShownBody b, int i) {
    final shoulders = Offset.lerp(b[BodyPose.leftShoulder], b[BodyPose.rightShoulder], 0.5)!;
    final p = b[i];
    return Offset(cx + (p.dx - shoulders.dx) * k, top + (p.dy - shoulders.dy) * b.aspect * k);
  }
}

/// A spark pinned to the body: on a limb (from joint a to b, [t] along,
/// [u] across), in the torso ([t], [u] across and down) or round the head.
class _Spark {
  const _Spark(this.kind, this.a, this.b, this.w, this.t, this.u, this.hot, this.phase, this.big);
  final int kind; // 0 limb, 1 torso, 2 head
  final int a, b;
  final double w, t, u, phase;
  final bool hot, big;
}

class _Ember {
  _Ember(this.p, this.v, this.hue);
  Offset p;
  final Offset v;
  final double hue;
  double life = 1;
}

/// The spark body: its sparks, embers and placements, kept across frames.
class SparkBody {
  SparkBody({int count = 1600}) : _sparks = _makeSparks(count);

  final List<_Spark> _sparks;
  final _placements = [_Placement(), _Placement()];
  final _embers = <_Ember>[];
  final _rng = math.Random(11);
  DateTime _last = DateTime.now();

  static const limbs = <(int, int, double)>[
    (11, 13, 0.30), (13, 15, 0.24), (12, 14, 0.30), (14, 16, 0.24), // arms
    (23, 25, 0.40), (25, 27, 0.32), (24, 26, 0.40), (26, 28, 0.32), // legs
  ];

  static List<_Spark> _makeSparks(int count) {
    final rng = math.Random(7);
    final out = <_Spark>[];
    for (var n = 0; n < count; n++) {
      final r = rng.nextDouble();
      final hot = rng.nextDouble() < 0.16;
      final big = rng.nextDouble() < 0.35;
      final phase = rng.nextDouble() * 6.28;
      if (r < 0.58) {
        final (a, b, w) = limbs[rng.nextInt(limbs.length)];
        var u = rng.nextDouble() * 2 - 1;
        // A little denser at the outline, like a figure of light.
        if (u.abs() < 0.6 && rng.nextDouble() < 0.45) u = (rng.nextBool() ? 1 : -1) * (0.6 + rng.nextDouble() * 0.4);
        out.add(_Spark(0, a, b, w, rng.nextDouble(), u, hot, phase, big));
      } else if (r < 0.88) {
        var t = rng.nextDouble();
        if (rng.nextDouble() < 0.5) t = rng.nextBool() ? rng.nextDouble() * 0.12 : 0.88 + rng.nextDouble() * 0.12;
        out.add(_Spark(1, 0, 0, 0, t, rng.nextDouble(), hot, phase, big));
      } else {
        var rr = math.sqrt(rng.nextDouble());
        if (rng.nextDouble() < 0.5) rr = 0.8 + rng.nextDouble() * 0.2;
        out.add(_Spark(2, 0, 0, 0, rng.nextDouble() * 6.283, rr, hot, phase, big));
      }
    }
    return out;
  }

  /// The flowing colour at [p] on a screen of [size] at time [t].
  static double hueAt(Offset p, Size size, double t) => (p.dy / size.height * 0.9 + p.dx / size.width * 0.35 - t * 0.25) % 1;

  void paint(Canvas canvas, Size size, KidsHands hands) {
    final bodies = hands.bodies.value;
    final now = DateTime.now();
    final dt = (now.difference(_last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    final t = now.millisecondsSinceEpoch / 1000.0 % 1000;
    // Bucket the sparks by colour (12 hues) and size, white-hot ones apart,
    // so the whole body is a couple of dozen draw calls.
    final buckets = List.generate(48, (_) => <double>[]);
    final glow = Paint();
    for (final b in bodies) {
      final place = _placements[b.slot]..follow(b, size, people: hands.people);
      Offset at(int i) => place.at(b, i);
      final sw = b.width * place.k;
      // Where each hand is drawn: on the game's cursor when it has one.
      Offset handAt(int side) {
        for (final track in const [0, 1]) {
          final owner = hands.trackOwner[track];
          final c = hands.shown[track];
          if (owner != null && c != null && owner.$1 == b.slot && owner.$2 == side) {
            return Offset(c.dx * size.width, c.dy * size.height);
          }
        }
        final wrist = side == 0 ? BodyPose.leftWrist : BodyPose.rightWrist;
        return at(wrist);
      }

      final joints = <int, Offset>{
        for (final i in const [0, 7, 8, 11, 12, 13, 14, 23, 24, 25, 26, 27, 28]) i: at(i),
        BodyPose.leftWrist: handAt(0),
        BodyPose.rightWrist: handAt(1),
      };
      bool shows(int i) => i == 15 || i == 16 || b.seen[i] >= 0.4;
      // A soft glow under the sparks, in the flowing colours.
      for (final (a, c, w) in limbs) {
        if (!shows(a) || !shows(c)) continue;
        final pa = joints[a]!, pc = joints[c]!;
        glow
          ..color = HSVColor.fromAHSV(0.32, hueAt(Offset.lerp(pa, pc, 0.5)!, size, t) * 360, 0.85, 1).toColor()
          ..strokeWidth = sw * w * 1.5
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sw * 0.25);
        canvas.drawLine(pa, pc, glow);
      }
      final torso = [joints[11]!, joints[12]!, joints[24]!, joints[23]!];
      final mid = (torso[0] + torso[1] + torso[2] + torso[3]) / 4;
      canvas.drawPath(
        Path()..addPolygon(torso, true),
        Paint()
          ..color = HSVColor.fromAHSV(0.28, hueAt(mid, size, t) * 360, 0.85, 1).toColor()
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sw * 0.3),
      );
      final ears = Offset.lerp(joints[7]!, joints[8]!, 0.5)!;
      final headC = Offset(ears.dx, (joints[0]!.dy + joints[7]!.dy) / 2 - sw * 0.05);
      final headR = sw * 0.36;
      canvas.drawCircle(
        headC,
        headR,
        Paint()
          ..color = HSVColor.fromAHSV(0.3, hueAt(headC, size, t) * 360, 0.85, 1).toColor()
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sw * 0.25),
      );
      // The sparks.
      for (final s in _sparks) {
        Offset p;
        switch (s.kind) {
          case 0:
            if (!shows(s.a) || !shows(s.b)) continue;
            final pa = joints[s.a]!, pb = joints[s.b]!;
            final d = pb - pa;
            final len = d.distance;
            if (len < 1) continue;
            final n = Offset(-d.dy / len, d.dx / len);
            p = pa + d * s.t + n * (s.u * sw * s.w / 2);
          case 1:
            final top = Offset.lerp(torso[0], torso[1], s.u)!;
            final bottom = Offset.lerp(torso[3], torso[2], s.u)!;
            p = Offset.lerp(top, bottom, s.t)!;
            p = Offset(p.dx + (p.dx - mid.dx) * 0.2, p.dy);
          default:
            p = headC + Offset(math.cos(s.t) * headR * 0.85 * s.u, math.sin(s.t) * headR * s.u);
        }
        final twinkle = 0.55 + 0.45 * math.sin(t * 9 + s.phase);
        if (twinkle < 0.25 && !s.hot) continue;
        final hueBucket = s.hot ? 12 : (hueAt(p, size, t) * 12).floor() % 12;
        final bucket = (s.big ? 24 : 0) + (s.hot ? 12 + (hueBucket % 12) : hueBucket);
        buckets[bucket % 48]
          ..add(p.dx)
          ..add(p.dy);
        // Embers drift off now and then, mostly from the hands.
        if (_rng.nextDouble() < 0.0025) {
          _embers.add(_Ember(p, Offset(_rng.nextDouble() * 30 - 15, -30 - _rng.nextDouble() * 50), hueAt(p, size, t)));
        }
      }
    }
    final dot = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 48; i++) {
      final pts = buckets[i];
      if (pts.isEmpty) continue;
      final big = i >= 24;
      final hot = (i % 24) >= 12;
      final hue = (i % 12) / 12;
      dot
        ..strokeWidth = big ? 5.0 : 3.0
        ..color = hot
            ? const Color(0xF2FFF8E6)
            : HSVColor.fromAHSV(0.95, hue * 360, 0.82, 1).toColor();
      canvas.drawRawPoints(ui.PointMode.points, Float32List.fromList(pts), dot);
    }
    // Embers rise and fade.
    for (final e in _embers) {
      e.p += e.v * dt;
      e.life -= dt * 0.9;
    }
    _embers.removeWhere((e) => e.life <= 0);
    if (_embers.length > 160) _embers.removeRange(0, _embers.length - 160);
    for (final e in _embers) {
      canvas.drawCircle(e.p, 1.6, Paint()..color = HSVColor.fromAHSV(e.life.clamp(0.0, 1.0), e.hue * 360, 0.8, 1).toColor());
    }
  }
}

class SparkBodyPainter extends CustomPainter {
  SparkBodyPainter(this.hands, this.body) : super(repaint: hands.points);
  final KidsHands hands;
  final SparkBody body;

  @override
  void paint(Canvas canvas, Size size) => body.paint(canvas, size, hands);

  @override
  bool shouldRepaint(SparkBodyPainter old) => true;
}

/// The camera picture in a corner while a camera game runs: dimmed, with
/// the body the game follows drawn over it, so a child (or a parent) can
/// see whether they are in view.
class GameCameraPreview extends StatefulWidget {
  const GameCameraPreview({super.key, required this.motion, this.width = 220});
  final MotionManager motion;
  final double width;

  @override
  State<GameCameraPreview> createState() => _GameCameraPreviewState();
}

class _GameCameraPreviewState extends State<GameCameraPreview> {
  ui.Image? _image;
  int _rotation = 0;
  bool _mirror = false;
  bool _decoding = false;

  @override
  void initState() {
    super.initState();
    widget.motion.gamePreview.addListener(_frame);
    widget.motion.gamePoses.addListener(_poses);
  }

  @override
  void dispose() {
    widget.motion.gamePreview.removeListener(_frame);
    widget.motion.gamePoses.removeListener(_poses);
    _image?.dispose();
    super.dispose();
  }

  void _poses() {
    if (mounted) setState(() {});
  }

  Future<void> _frame() async {
    final FacePreviewFrame? f = widget.motion.gamePreview.value;
    if (f == null || _decoding) return;
    _decoding = true;
    try {
      final codec = await ui.instantiateImageCodec(f.jpeg);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      if (!mounted) {
        image.dispose();
        return;
      }
      final old = _image;
      setState(() {
        _image = image;
        _rotation = f.rotation;
        _mirror = f.mirror;
      });
      old?.dispose();
    } catch (_) {
      // A bad frame is skipped.
    } finally {
      _decoding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.shrink();
    final turned = _rotation % 180 != 0;
    final iw = (turned ? image.height : image.width).toDouble();
    final ih = (turned ? image.width : image.height).toDouble();
    final w = widget.width, h = w * ih / iw;
    return IgnorePointer(
      child: Container(
        width: w + 6,
        height: h + 6,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: iw,
                  height: ih,
                  child: Transform.flip(
                    flipX: _mirror,
                    child: RotatedBox(
                      quarterTurns: (_rotation ~/ 90) % 4,
                      child: RawImage(image: image, filterQuality: FilterQuality.low),
                    ),
                  ),
                ),
              ),
              // Dimmed, so the tracking lines stand out.
              const ColoredBox(color: Color(0x880A0E1E)),
              CustomPaint(painter: _TrackingPainter(widget.motion.gamePoses.value)),
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xCC101828), borderRadius: BorderRadius.circular(10)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Color(0xFFFF4D6D), size: 9),
                      SizedBox(width: 5),
                      Text('Camera', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tracked body over the camera picture: lines between the joints,
/// dots on them, the hands as the cursors' colours.
class _TrackingPainter extends CustomPainter {
  _TrackingPainter(this.poses);
  final List<BodyPose> poses;

  static const _lines = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16), (11, 23), (12, 24), (23, 24),
    (23, 25), (25, 27), (24, 26), (26, 28),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFFF3DA8A)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = const Color(0xFFF3DA8A);
    for (final p in poses) {
      Offset at(int i) => Offset(p.point(i).dx * size.width, p.point(i).dy * size.height);
      bool ok(int i) => p.seen(i) >= 0.4;
      for (final (a, b) in _lines) {
        if (ok(a) && ok(b)) canvas.drawLine(at(a), at(b), line);
      }
      for (final i in const [11, 12, 13, 14, 23, 24, 25, 26, 27, 28]) {
        if (ok(i)) canvas.drawCircle(at(i), 3, dot);
      }
      for (final (i, color) in const [(15, Color(0xFFFF9EC7)), (16, Color(0xFF8FD8FF))]) {
        if (!ok(i)) continue;
        canvas.drawCircle(at(i), 6, Paint()..color = color);
        canvas.drawCircle(
          at(i),
          6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.white,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TrackingPainter old) => !identical(old.poses, poses);
}
