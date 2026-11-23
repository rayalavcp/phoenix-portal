import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Phoenix Home's live weather over the wallpaper: rain and snow in two
/// depths, splashes, puffy drifting clouds, sun rays, fog banks, stars and a
/// moon glow at night, lightning bolts in a storm, plus a colour grade of the
/// whole picture (cold and dark in rain, warm in sun, deep blue at night).
/// One animation and plain shapes, no blur filters, so a Portal's GPU keeps
/// up.
class WeatherBackdrop extends StatefulWidget {
  const WeatherBackdrop({super.key, required this.code, required this.isDay, this.demo = '', this.sunrise, this.sunset});

  /// WMO weather code (Open-Meteo), null for no weather yet.
  final int? code;
  final bool isDay;

  /// A [WeatherFx] name to show instead of the real weather ('' for real).
  final String demo;

  /// Today's sunrise and sunset: the sun rises on the left, crosses the
  /// sky and sets on the right in between (6:30 to 18:30 when unknown).
  final DateTime? sunrise, sunset;

  @override
  State<WeatherBackdrop> createState() => _WeatherBackdropState();
}

/// How far through the day the sun is at [now]: 0 at sunrise, 0.5 at
/// midday, 1 at sunset (clamped), from today's [sunrise] and [sunset] or,
/// without them, 6:30 and 18:30.
double sunArc(DateTime now, DateTime? sunrise, DateTime? sunset) {
  final today = DateTime(now.year, now.month, now.day);
  final rise = sunrise ?? today.add(const Duration(hours: 6, minutes: 30));
  final set = sunset ?? today.add(const Duration(hours: 18, minutes: 30));
  final day = set.difference(rise).inSeconds;
  if (day <= 0) return 0.5;
  return (now.difference(rise).inSeconds / day).clamp(0.0, 1.0);
}

/// Where the sun is drawn for [arc] (see [sunArc]) on a screen of [size]:
/// a half sun sitting on the top edge, at the left at sunrise, in the
/// middle at noon and at the right at sunset. On the edge it never sits
/// over a wallpaper's hills or behind the tiles.
Offset sunPosition(double arc, Size size) => Offset(size.width * (0.04 + 0.92 * arc), 0);

enum WeatherFx { clear, clouds, fog, drizzle, rain, snow, storm }

WeatherFx weatherFx(int code) => switch (code) {
  0 || 1 => WeatherFx.clear,
  2 || 3 => WeatherFx.clouds,
  45 || 48 => WeatherFx.fog,
  51 || 53 || 55 || 56 || 57 => WeatherFx.drizzle,
  61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => WeatherFx.rain,
  71 || 73 || 75 || 77 || 85 || 86 => WeatherFx.snow,
  95 || 96 || 99 => WeatherFx.storm,
  _ => WeatherFx.clouds,
};

/// The colour laid over the wallpaper for the weather and time of day.
Color weatherGrade(WeatherFx fx, bool day) {
  if (!day) {
    return switch (fx) {
      WeatherFx.clear => const Color(0x55081430),
      WeatherFx.storm || WeatherFx.rain => const Color(0x7A050A18),
      _ => const Color(0x66091224),
    };
  }
  return switch (fx) {
    WeatherFx.clear => const Color(0x1AFFB35C),
    WeatherFx.clouds => const Color(0x22505A6E),
    WeatherFx.fog => const Color(0x40B4BCC8),
    WeatherFx.drizzle => const Color(0x3A324660),
    WeatherFx.rain => const Color(0x52223248),
    WeatherFx.snow => const Color(0x30C8D8F0),
    WeatherFx.storm => const Color(0x66141C2C),
  };
}

class _WeatherBackdropState extends State<WeatherBackdrop> with SingleTickerProviderStateMixin {
  // A long loop: every particle's motion is periodic in it, so the loop
  // never shows a seam.
  late final AnimationController _clock;
  final _seed = List.generate(400, (i) => math.Random(i * 7919 + 13).nextDouble());

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.code;
    if (code == null && widget.demo.isEmpty) return const SizedBox.shrink();
    final fx = WeatherFx.values.where((f) => f.name == widget.demo).firstOrNull ?? weatherFx(code ?? 0);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedContainer(duration: const Duration(seconds: 2), color: weatherGrade(fx, widget.isDay)),
          RepaintBoundary(
            child: CustomPaint(size: Size.infinite, painter: _WeatherPainter(_clock, fx, widget.isDay, _seed, widget.sunrise, widget.sunset)),
          ),
        ],
      ),
    );
  }
}

class _WeatherPainter extends CustomPainter {
  _WeatherPainter(this.clock, this.fx, this.day, this.seed, this.sunrise, this.sunset) : super(repaint: clock);

  final DateTime? sunrise, sunset;

  final Animation<double> clock;
  final WeatherFx fx;
  final bool day;
  final List<double> seed;

  double get t => clock.value * 60; // seconds into the loop
  double s(int i) => seed[i % seed.length];

  @override
  void paint(Canvas canvas, Size size) {
    switch (fx) {
      case WeatherFx.clear:
        if (day) {
          _sun(canvas, size);
        } else {
          _night(canvas, size);
        }
      case WeatherFx.clouds:
        if (day) {
          _sun(canvas, size, dim: 0.55);
        } else {
          _night(canvas, size, stars: 40);
        }
        _clouds(canvas, size, alpha: day ? 0.42 : 0.30, count: 7, grey: day ? 235 : 150);
      case WeatherFx.fog:
        _clouds(canvas, size, alpha: 0.25, count: 5, grey: 215);
        _fog(canvas, size);
      case WeatherFx.drizzle:
        _clouds(canvas, size, alpha: 0.38, count: 7, grey: 170);
        _rain(canvas, size, drops: 90, speed: 0.6, length: 12, alpha: 0.35, width: 1.1);
        _rain(canvas, size, drops: 40, speed: 0.8, length: 18, alpha: 0.5, width: 1.6, offset: 200);
      case WeatherFx.rain:
        _clouds(canvas, size, alpha: 0.48, count: 8, grey: 140);
        _rain(canvas, size, drops: 160, speed: 1, length: 20, alpha: 0.35, width: 1.2);
        _rain(canvas, size, drops: 70, speed: 1.35, length: 34, alpha: 0.6, width: 2, offset: 200);
        _splashes(canvas, size, 26);
      case WeatherFx.snow:
        _clouds(canvas, size, alpha: 0.35, count: 6, grey: 230);
        _snow(canvas, size, flakes: 110, near: false);
        _snow(canvas, size, flakes: 45, near: true);
      case WeatherFx.storm:
        _clouds(canvas, size, alpha: 0.6, count: 9, grey: 95);
        _rain(canvas, size, drops: 200, speed: 1.3, length: 26, alpha: 0.4, width: 1.3);
        _rain(canvas, size, drops: 90, speed: 1.7, length: 42, alpha: 0.65, width: 2.2, offset: 200);
        _splashes(canvas, size, 36);
        _lightning(canvas, size);
    }
  }

  void _sun(Canvas canvas, Size size, {double dim = 1}) {
    final arc = sunArc(DateTime.now(), sunrise, sunset);
    final c = sunPosition(arc, size);
    // Near the horizon the light is warmer and a little softer.
    final high = math.sin(math.pi * arc);
    final warm = Color.lerp(const Color(0xFFFFA24A), const Color(0xFFFFE7B0), high)!;
    final core = Color.lerp(const Color(0xFFFFD08A), const Color(0xFFFFFAEB), high)!;
    final short = size.shortestSide;
    Color tint(Color c, double a) => c.withValues(alpha: (a * dim).clamp(0.0, 1.0));

    // The sky's glow round the sun, breathing very slowly.
    final pulse = 0.96 + 0.04 * math.sin(t * 2 * math.pi / 12);
    final glow = short * 0.9 * pulse;
    canvas.drawCircle(
      c,
      glow,
      Paint()
        ..shader = RadialGradient(
          colors: [tint(core, 0.5), tint(warm, 0.2), tint(warm, 0.06), tint(warm, 0)],
          stops: const [0, 0.14, 0.45, 1],
        ).createShader(Rect.fromCircle(center: c, radius: glow)),
    );

    // Soft beams fanning out towards the middle of the screen. They do not
    // spin: each one gently brightens, fades and sways on its own.
    final rays = Paint()..blendMode = BlendMode.plus;
    final len = size.longestSide * 0.65;
    // Down into the picture, leaning a little towards the middle.
    final toward = math.atan2(size.height, (size.width * 0.5 - c.dx) * 0.6);
    const beams = 11;
    for (var i = 0; i < beams; i++) {
      final spreadAt = (i / (beams - 1) - 0.5) * 2.2; // about ±63 degrees
      final a = toward + spreadAt + 0.035 * math.sin(t * 2 * math.pi / (20 + 10 * s(i)) + s(i + 3) * 6);
      final width = 0.018 + 0.03 * s(i + 7);
      final shimmer = 0.5 + 0.5 * math.sin(t * 2 * math.pi / (9 + 8 * s(i + 11)) + s(i + 13) * 6);
      final alpha = (0.035 + 0.06 * shimmer) * (0.55 + 0.45 * high);
      final path = Path()
        ..moveTo(c.dx + math.cos(a - width) * short * 0.04, c.dy + math.sin(a - width) * short * 0.04)
        ..lineTo(c.dx + math.cos(a - width) * len, c.dy + math.sin(a - width) * len)
        ..lineTo(c.dx + math.cos(a + width) * len, c.dy + math.sin(a + width) * len)
        ..lineTo(c.dx + math.cos(a + width) * short * 0.04, c.dy + math.sin(a + width) * short * 0.04)
        ..close();
      rays.shader = RadialGradient(
        colors: [tint(core, alpha), tint(warm, alpha * 0.35), tint(warm, 0)],
        stops: const [0, 0.4, 1],
      ).createShader(Rect.fromCircle(center: c, radius: len));
      canvas.drawPath(path, rays);
    }

    // The sun itself: a bright half disc peeking over the top edge.
    final r = short * 0.07;
    canvas.drawCircle(
      c,
      r * 2.2,
      Paint()
        ..shader = RadialGradient(
          colors: [tint(core, 0.55), tint(warm, 0.18), tint(warm, 0)],
          stops: const [0.35, 0.6, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r * 2.2)),
    );
    canvas.drawCircle(c, r, Paint()..color = tint(core, 0.85));
  }

  void _night(Canvas canvas, Size size, {int stars = 110}) {
    final paint = Paint();
    for (var i = 0; i < stars; i++) {
      final x = s(i) * size.width, y = s(i * 3 + 1) * size.height * 0.65;
      final twinkle = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(t * 2 * math.pi / (2.5 + s(i * 5) * 4) + i));
      final r = 0.7 + s(i * 7) * 1.6;
      paint.color = Color.fromRGBO(255, 255, 255, 0.85 * twinkle);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
    // A shooting star now and then.
    final phase = t % 20;
    if (phase < 0.9) {
      final k = phase / 0.9;
      final start = Offset(size.width * (0.15 + 0.5 * s(((t ~/ 20)) + 9)), size.height * 0.08);
      final head = start + Offset(size.width * 0.25 * k, size.height * 0.12 * k);
      canvas.drawLine(
        head - Offset(size.width * 0.06, size.height * 0.03),
        head,
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors: [const Color(0x00FFFFFF), Color.fromRGBO(255, 255, 255, 0.9 * (1 - k))],
          ).createShader(Rect.fromPoints(head - Offset(size.width * 0.06, size.height * 0.03), head)),
      );
    }
    // Moon glow.
    final m = Offset(size.width * 0.86, size.height * 0.1);
    final r = size.shortestSide * 0.45;
    canvas.drawCircle(
      m,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x40DCE6FF), Color(0x14B4C8FF), Color(0x00B4C8FF)],
          stops: [0, 0.3, 1],
        ).createShader(Rect.fromCircle(center: m, radius: r)),
    );
  }

  /// Puffy clouds: each is a cluster of soft blobs drifting across.
  void _clouds(Canvas canvas, Size size, {required double alpha, required int count, required int grey}) {
    for (var i = 0; i < count; i++) {
      final speed = 8 + s(i) * 14; // px a second
      final w = size.width * (0.35 + s(i + 10) * 0.35);
      final travel = size.width + w * 2;
      final x = ((s(i + 20) * travel + t * speed) % travel) - w;
      final y = size.height * (-0.06 + s(i + 30) * 0.38);
      final depth = 0.6 + 0.4 * s(i + 40);
      for (var b = 0; b < 6; b++) {
        final bx = x + w * (0.1 + 0.8 * (b / 5)) + (s(i * 6 + b) - 0.5) * w * 0.1;
        final by = y + w * 0.12 * math.sin(b / 5 * math.pi) * -1 + w * 0.12;
        final r = w * (0.16 + 0.12 * math.sin(b / 5 * math.pi) + 0.05 * s(i * 6 + b + 50));
        final rect = Rect.fromCircle(center: Offset(bx, by), radius: r);
        canvas.drawCircle(
          Offset(bx, by),
          r,
          Paint()
            ..shader = RadialGradient(
              colors: [
                Color.fromRGBO(grey, grey, (grey + 12).clamp(0, 255), alpha * depth),
                Color.fromRGBO(grey, grey, (grey + 12).clamp(0, 255), alpha * depth * 0.45),
                Color.fromRGBO(grey, grey, grey, 0),
              ],
              stops: const [0, 0.55, 1],
            ).createShader(rect),
        );
      }
    }
  }

  void _fog(Canvas canvas, Size size) {
    for (var i = 0; i < 7; i++) {
      final y = size.height * (0.05 + i * 0.14);
      final dx = math.sin(t * 2 * math.pi / (25 + i * 4) + i) * size.width * 0.15;
      final rect = Rect.fromLTWH(-size.width * 0.3 + dx, y, size.width * 1.6, size.height * 0.3);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color.fromRGBO(220, 225, 232, 0.32), Color.fromRGBO(220, 225, 232, 0.12), Color(0x00DCE1E8)],
            stops: [0, 0.5, 1],
          ).createShader(rect),
      );
    }
  }

  void _rain(
    Canvas canvas,
    Size size, {
    required int drops,
    required double speed,
    required double length,
    required double alpha,
    required double width,
    int offset = 0,
  }) {
    const slant = 0.2;
    final paint = Paint()
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.fromRGBO(190, 215, 255, alpha * 0.3), Color.fromRGBO(210, 230, 255, alpha)],
      ).createShader(Offset.zero & size);
    final span = size.height + length;
    for (var i = 0; i < drops; i++) {
      final j = i + offset;
      // Each drop falls the screen in about a second, staggered by its seed.
      final v = span * (1.0 + s(j) * 0.5) * speed;
      final y = ((s(j * 11) * span + t * v) % span) - length;
      final x = s(j * 13) * (size.width + size.height * slant) - y * slant;
      canvas.drawLine(Offset(x, y), Offset(x + length * slant, y + length), paint);
    }
  }

  void _splashes(Canvas canvas, Size size, int count) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < count; i++) {
      final period = 0.6 + s(i + 300) * 0.6;
      final k = ((t + s(i + 310) * period) % period) / period;
      final x = s(i + 320) * size.width;
      final y = size.height * (0.82 + s(i + 330) * 0.17);
      paint.color = Color.fromRGBO(220, 235, 255, 0.45 * (1 - k));
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 4 + 22 * k, height: 2 + 6 * k), paint);
    }
  }

  void _snow(Canvas canvas, Size size, {required int flakes, required bool near}) {
    for (var i = 0; i < flakes; i++) {
      final j = near ? i + 200 : i;
      final speed = (near ? 45 : 20) + s(j) * (near ? 40 : 25);
      final y = ((s(j * 17) * size.height + t * speed) % (size.height + 20)) - 10;
      final sway = math.sin(t * 2 * math.pi / (4 + s(j * 3) * 4) + i) * (near ? 30 : 16);
      final x = s(j * 19) * size.width + sway;
      final r = near ? 3 + s(j * 23) * 4 : 1.2 + s(j * 23) * 2;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [Color.fromRGBO(255, 255, 255, near ? 0.95 : 0.8), const Color(0x00FFFFFF)],
          ).createShader(Rect.fromCircle(center: Offset(x, y), radius: r)),
      );
    }
  }

  void _lightning(Canvas canvas, Size size) {
    // Three strikes a minute: a flash and a jagged bolt.
    final phase = t % 20;
    final strike = t ~/ 20;
    final on = (phase > 9.0 && phase < 9.14) || (phase > 9.28 && phase < 9.4);
    if (!on) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color.fromRGBO(225, 235, 255, 0.28));
    final rnd = math.Random(strike * 31 + 7);
    var p = Offset(size.width * (0.2 + 0.6 * rnd.nextDouble()), 0);
    final bolt = Path()..moveTo(p.dx, p.dy);
    while (p.dy < size.height * 0.7) {
      p = p + Offset((rnd.nextDouble() - 0.5) * size.width * 0.08, size.height * (0.04 + rnd.nextDouble() * 0.06));
      bolt.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      bolt,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..color = const Color.fromRGBO(170, 190, 255, 0.25),
    );
    canvas.drawPath(
      bolt,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color.fromRGBO(255, 255, 255, 0.95),
    );
  }

  @override
  bool shouldRepaint(_WeatherPainter old) => old.fx != fx || old.day != day;
}
