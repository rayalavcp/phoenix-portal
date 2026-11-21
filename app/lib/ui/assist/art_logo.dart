import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'assist_art.dart';

/// The Voice Only skin's indicator: the Phoenix Portal flame phoenix
/// (assets/branding/mark.png) filling its box, with an ember glow behind
/// it. The glow brightens and the bird swells a little with the voice, so
/// the mark itself shows listening, thinking and speaking.
class LogoArt extends StatefulWidget {
  const LogoArt({
    super.key,
    required this.mode,
    required this.reactive,
    required this.level,
    required this.clock,
    this.fade,
  });

  final ArtMode mode;

  /// Listening or speaking with the reactive bar on: the glow follows
  /// [level]. Otherwise it runs the mode's own animation.
  final bool reactive;
  final ValueListenable<double> level;
  final ArtClock clock;

  /// 1 down to 0 as a docked conversation ends: the mark fades with it.
  final ValueListenable<double>? fade;

  @override
  State<LogoArt> createState() => _LogoArtState();
}

class _LogoArtState extends State<LogoArt> {
  /// The glow's strength as drawn, 0 to 1, eased toward its target every
  /// frame so a change of mode glides instead of jumping.
  double _energy = 0;
  double _last = -1;

  /// The loudest recent level while listening and while speaking, each
  /// decaying: the microphone's level is boosted and curved, playback's
  /// is near linear and runs well below it, so each is scaled against its
  /// own peak to move the mark as far.
  double _micPeak = 0;
  double _playPeak = 0;

  static const _mark = Image(
    image: AssetImage('assets/branding/mark.png'),
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    semanticLabel: 'Phoenix Portal',
  );

  /// The level against its source's recent peak: a peak decays to half in
  /// about two seconds, and the gain stops at 4x so room noise stays low.
  double _scaled(double dt) {
    final l = widget.level.value.clamp(0.0, 1.0);
    final decay = math.exp(-0.35 * dt);
    final speaking = widget.mode == ArtMode.speaking;
    final peak = math.max(l, (speaking ? _playPeak : _micPeak) * decay);
    if (speaking) {
      _playPeak = peak;
    } else {
      _micPeak = peak;
    }
    return (l * math.min(4.0, 0.9 / math.max(peak, 0.1))).clamp(0.0, 1.0);
  }

  double _target(double t, double l) {
    switch (widget.mode) {
      case ArtMode.idle:
        return 0.1;
      case ArtMode.thinking:
        return keyframes(t, 0.9, const [(0, 0.2), (0.5, 0.65), (1, 0.2)]);
      case ArtMode.listening || ArtMode.speaking when widget.reactive:
        // A slow breath keeps the mark alive while the room is quiet.
        final breath = 0.12 + 0.08 * (1 + math.sin(2 * math.pi * t / 2.4));
        return (breath + l * 0.9).clamp(0.0, 1.0);
      case ArtMode.speaking:
        return keyframes(t, 1.2, const [(0, 0.3), (0.5, 0.8), (1, 0.3)]);
      case ArtMode.listening:
        return keyframes(t, 2.4, const [(0, 0.15), (0.5, 0.45), (1, 0.15)]);
    }
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: Listenable.merge([widget.level, widget.clock, widget.fade]),
      builder: (context, child) {
        final t = widget.clock.seconds;
        final dt = _last < 0 ? 1.0 : (t - _last).clamp(0.0, 0.1);
        _last = t;
        final l = widget.reactive ? _scaled(dt) : 0.0;
        // About 40 ms to most of a step: quick enough to keep up with speech.
        _energy += (_target(t, l) - _energy) * (1 - math.exp(-25 * dt));
        final alpha = widget.fade == null
            ? 1.0
            : 0.35 + 0.65 * widget.fade!.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: alpha,
          child: CustomPaint(
            painter: _GlowPainter(_energy),
            child: Transform.scale(scale: 0.88 + 0.12 * _energy, child: child),
          ),
        );
      },
      child: _mark,
    ),
  );
}

/// The ember glow behind the phoenix: brighter and wider with [energy].
class _GlowPainter extends CustomPainter {
  _GlowPainter(this.energy);

  final double energy;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2;
    if (r <= 0) return;
    final c = size.center(Offset.zero);
    final radius = r * (0.7 + 0.35 * energy);
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFF27A1A).withValues(alpha: 0.18 + 0.42 * energy),
            const Color(0xFFC41C1C).withValues(alpha: 0.08 + 0.2 * energy),
            const Color(0x00C41C1C),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.energy != energy;
}
