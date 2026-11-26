import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The clock faces the Today screen and the Phoenix Photo Frame can wear,
/// picked under Customize (or in the remote admin): the thin digits Phoenix
/// started with, bold digits, flip cards, a round analogue clock and a
/// word clock ("It's quarter past seven"). All change on the minute.
const clockFaces = {
  'classic': 'Classic',
  'bold': 'Bold',
  'flip': 'Flip cards',
  'analog': 'Analogue',
  'words': 'Words',
};

const _shadow = [Shadow(blurRadius: 18, color: Color(0x99000000))];

/// The time in words, to the nearest five minutes: "It's ten past four",
/// "It's quarter to nine", "It's twelve o'clock".
String clockWords(DateTime t) {
  const names = ['twelve', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven'];
  var five = ((t.minute + 2.5) / 5).floor() * 5;
  var hour = t.hour;
  if (five == 60) {
    five = 0;
    hour++;
  }
  final now = names[hour % 12];
  final next = names[(hour + 1) % 12];
  final words = switch (five) {
    0 => "$now o'clock",
    15 => 'quarter past $now',
    30 => 'half past $now',
    45 => 'quarter to $next',
    < 30 => '${_minuteWords(five)} past $now',
    _ => '${_minuteWords(60 - five)} to $next',
  };
  return "It's $words";
}

String _minuteWords(int m) => switch (m) {
  5 => 'five',
  10 => 'ten',
  20 => 'twenty',
  25 => 'twenty-five',
  _ => '$m',
};

/// One clock face. [size] is the classic digits' height; the other faces
/// keep about the same presence.
class ClockFace extends StatelessWidget {
  const ClockFace({super.key, required this.face, required this.now, required this.size, this.shadows = true});

  final String face;
  final DateTime now;
  final double size;
  final bool shadows;

  @override
  Widget build(BuildContext context) {
    final h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final time = DateFormat(h24 ? 'HH:mm' : 'h:mm').format(now);
    final period = h24 ? '' : DateFormat('a').format(now);
    final shadow = shadows ? _shadow : null;
    switch (face) {
      case 'analog':
        return SizedBox.square(dimension: size * 1.5, child: CustomPaint(painter: _AnalogPainter(now)));
      case 'words':
        final text = clockWords(now);
        final split = text.indexOf(' ', 5);
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: size * 4.2),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${text.substring(0, split)} ', style: const TextStyle(fontWeight: FontWeight.w300)),
                TextSpan(text: text.substring(split + 1), style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            style: TextStyle(color: Colors.white, fontSize: size * 0.42, height: 1.1, shadows: shadow),
          ),
        );
      case 'flip':
        final digits = time.replaceAll(':', '');
        Widget card(String d) => Container(
          margin: EdgeInsets.symmetric(horizontal: size * 0.03),
          padding: EdgeInsets.symmetric(horizontal: size * 0.08),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.12),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xE6262B35), Color(0xE61B1F27), Color(0xE6121418)],
              stops: [0, 0.5, 0.5],
            ),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Text(d, style: TextStyle(color: Colors.white, fontSize: size * 0.72, fontWeight: FontWeight.w600, height: 1.15)),
        );
        final split = digits.length - 2;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final d in digits.substring(0, split).split('')) card(d),
            SizedBox(width: size * 0.1),
            for (final d in digits.substring(split).split('')) card(d),
            if (period.isNotEmpty) ...[
              SizedBox(width: size * 0.1),
              Text(period, style: TextStyle(color: Colors.white70, fontSize: size * 0.22, fontWeight: FontWeight.w600, shadows: shadow)),
            ],
          ],
        );
      default:
        final bold = face == 'bold';
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              time,
              style: TextStyle(
                color: Colors.white,
                fontSize: bold ? size * 1.05 : size,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w200,
                letterSpacing: bold ? -2 : -4,
                height: 1.02,
                shadows: shadow,
              ),
            ),
            if (period.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(
                period,
                style: TextStyle(color: Colors.white70, fontSize: size * 0.24, fontWeight: FontWeight.w500, shadows: shadow),
              ),
            ],
          ],
        );
    }
  }
}

class _AnalogPainter extends CustomPainter {
  _AnalogPainter(this.now);
  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0x52101418));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.025
        ..color = Colors.white.withValues(alpha: 0.55),
    );
    for (var i = 0; i < 60; i++) {
      final a = i * math.pi / 30;
      final hour = i % 5 == 0;
      final dir = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(
        c + dir * r * (hour ? 0.8 : 0.88),
        c + dir * r * 0.93,
        Paint()
          ..color = Colors.white.withValues(alpha: hour ? 0.9 : 0.35)
          ..strokeWidth = hour ? r * 0.035 : r * 0.012
          ..strokeCap = StrokeCap.round,
      );
    }
    void hand(double turns, double length, double width, Color color) {
      final a = turns * 2 * math.pi;
      canvas.drawLine(
        c - Offset(math.sin(a), -math.cos(a)) * r * 0.1,
        c + Offset(math.sin(a), -math.cos(a)) * r * length,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    final minutes = now.minute + now.second / 60;
    hand(((now.hour % 12) + minutes / 60) / 12, 0.5, r * 0.07, Colors.white);
    hand(minutes / 60, 0.76, r * 0.045, Colors.white);
    canvas.drawCircle(c, r * 0.06, Paint()..color = const Color(0xFFF2CF6E));
  }

  @override
  bool shouldRepaint(_AnalogPainter old) => old.now.minute != now.minute || old.now.hour != now.hour;
}
