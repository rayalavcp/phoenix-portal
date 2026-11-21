import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Phoenix Home's background weather: rain, drizzle, snow, drifting clouds,
/// fog, a warm sun glow, twinkling stars at night and the odd lightning
/// flash, from the current WMO weather code. One animation, a few dozen
/// shapes, no blur filters: cheap enough for a 2018 Portal's GPU.
class WeatherBackdrop extends StatefulWidget {
  const WeatherBackdrop({super.key, required this.code, required this.isDay});

  /// WMO weather code (Open-Meteo), null for no weather yet.
  final int? code;
  final bool isDay;

  @override
  State<WeatherBackdrop> createState() => _WeatherBackdropState();
}

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

class _WeatherBackdropState extends State<WeatherBackdrop> with SingleTickerProviderStateMixin {
  // A long loop: every particle's motion is periodic in it, so the loop
  // never shows a seam.
  late final AnimationController _clock;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  }
  final _seed = List.generate(120, (i) => math.Random(i * 7919).nextDouble());

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.code;
    if (code == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _WeatherPainter(_clock, weatherFx(code), widget.isDay, _seed),
        ),
      ),
    );
  }
}

class _WeatherPainter extends CustomPainter {
  _WeatherPainter(this.clock, this.fx, this.day, this.seed) : super(repaint: clock);

  final Animation<double> clock;
  final WeatherFx fx;
  final bool day;
  final List<double> seed;

  double get t => clock.value * 60; // seconds into the loop

  @override
  void paint(Canvas canvas, Size size) {
    switch (fx) {
      case WeatherFx.clear:
        if (day) {
          _sun(canvas, size);
        } else {
          _stars(canvas, size);
        }
      case WeatherFx.clouds:
        if (day) {
          _sun(canvas, size, dim: 0.5);
        } else {
          _stars(canvas, size, count: 30);
        }
        _clouds(canvas, size, 0.10);
      case WeatherFx.fog:
        _fog(canvas, size);
      case WeatherFx.drizzle:
        _clouds(canvas, size, 0.12);
        _rain(canvas, size, drops: 45, speed: 0.55, length: 10, alpha: 0.25);
      case WeatherFx.rain:
        _clouds(canvas, size, 0.14);
        _rain(canvas, size, drops: 90, speed: 1, length: 22, alpha: 0.32);
      case WeatherFx.snow:
        _clouds(canvas, size, 0.10);
        _snow(canvas, size);
      case WeatherFx.storm:
        _clouds(canvas, size, 0.18);
        _rain(canvas, size, drops: 110, speed: 1.25, length: 26, alpha: 0.36);
        _lightning(canvas, size);
    }
  }

  void _sun(Canvas canvas, Size size, {double dim = 1}) {
    final c = Offset(size.width * 0.82, size.height * 0.05);
    final pulse = 0.85 + 0.15 * math.sin(t * 2 * math.pi / 12);
    final r = size.shortestSide * 0.7 * pulse;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          Color.fromRGBO(255, 190, 90, 0.20 * dim),
          Color.fromRGBO(255, 140, 50, 0.07 * dim),
          const Color(0x00FF8C32),
        ], stops: const [0, 0.45, 1]).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  void _stars(Canvas canvas, Size size, {int count = 70}) {
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final x = seed[i] * size.width, y = seed[(i * 3) % seed.length] * size.height * 0.6;
      final twinkle = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 2 * math.pi / (3 + seed[(i * 5) % seed.length] * 4) + i));
      paint.color = Color.fromRGBO(255, 255, 255, 0.55 * twinkle);
      canvas.drawCircle(Offset(x, y), 0.8 + seed[(i * 7) % seed.length] * 1.2, paint);
    }
  }

  void _clouds(Canvas canvas, Size size, double alpha) {
    for (var i = 0; i < 6; i++) {
      final speed = 6 + seed[i] * 8; // px a second
      final w = size.width * (0.35 + seed[i + 10] * 0.3);
      final travel = size.width + w * 2;
      final x = ((seed[i + 20] * travel + t * speed) % travel) - w;
      final y = size.height * (0.02 + seed[i + 30] * 0.4);
      final rect = Rect.fromLTWH(x, y, w, w * 0.32);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(colors: [
            Color.fromRGBO(220, 228, 240, alpha),
            Color.fromRGBO(220, 228, 240, alpha * 0.4),
            const Color(0x00DCE4F0),
          ]).createShader(rect),
      );
    }
  }

  void _fog(Canvas canvas, Size size) {
    for (var i = 0; i < 5; i++) {
      final y = size.height * (0.15 + i * 0.18);
      final dx = math.sin(t * 2 * math.pi / 30 + i) * size.width * 0.08;
      final rect = Rect.fromLTWH(-size.width * 0.2 + dx, y, size.width * 1.4, size.height * 0.22);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(colors: [
            const Color.fromRGBO(200, 205, 215, 0.10),
            const Color(0x00C8CDD7),
          ]).createShader(rect),
      );
    }
  }

  void _rain(Canvas canvas, Size size, {required int drops, required double speed, required double length, required double alpha}) {
    final paint = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = Color.fromRGBO(170, 200, 255, alpha);
    const slant = 0.18;
    for (var i = 0; i < drops; i++) {
      final fall = (size.height + length) * (0.9 + seed[i % seed.length] * 0.6) * speed / 1.4;
      // Each drop falls the screen in about 1.4 s, staggered by its seed.
      final y = ((seed[(i * 11) % seed.length] * (size.height + length) + t * fall) % (size.height + length)) - length;
      final x = seed[(i * 13) % seed.length] * (size.width + 100) - y * slant;
      canvas.drawLine(Offset(x, y), Offset(x + length * slant, y + length), paint);
    }
  }

  void _snow(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color.fromRGBO(255, 255, 255, 0.7);
    for (var i = 0; i < 60; i++) {
      final speed = 18 + seed[i] * 30;
      final y = ((seed[(i * 17) % seed.length] * size.height + t * speed) % (size.height + 10)) - 5;
      final sway = math.sin(t * 2 * math.pi / (5 + seed[(i * 3) % seed.length] * 4) + i) * 18;
      final x = seed[(i * 19) % seed.length] * size.width + sway;
      canvas.drawCircle(Offset(x, y), 1.4 + seed[(i * 23) % seed.length] * 2.4, paint);
    }
  }

  void _lightning(Canvas canvas, Size size) {
    // Two flashes a minute, each a quick double blink.
    final phase = t % 30;
    final flash = (phase > 12.0 && phase < 12.12) || (phase > 12.25 && phase < 12.33) ? 0.16 : 0.0;
    if (flash > 0) canvas.drawRect(Offset.zero & size, Paint()..color = Color.fromRGBO(220, 230, 255, flash));
  }

  @override
  bool shouldRepaint(_WeatherPainter old) => old.fx != fx || old.day != day;
}
