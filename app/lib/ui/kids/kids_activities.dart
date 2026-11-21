import 'package:flutter/material.dart';

/// The Kids Portal's built-in activities. Everything here is offline and
/// drawn by Flutter itself: no assets, no network, no ads.

/// The playful face the Kids Portal speaks in: Nunito, rounded and friendly,
/// bundled in the APK.
const kidsFont = 'Nunito';

TextStyle kidsText(double size, {Color color = Colors.white, FontWeight weight = FontWeight.w800}) =>
    TextStyle(fontFamily: kidsFont, fontSize: size, fontWeight: weight, color: color, height: 1.15);

/// A big round button with a press-down squish, used across the portal.
class KidsBounce extends StatefulWidget {
  const KidsBounce({super.key, required this.child, required this.onTap, this.onLongPress});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<KidsBounce> createState() => _KidsBounceState();
}

class _KidsBounceState extends State<KidsBounce> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) => setState(() => _down = true),
    onTapCancel: () => setState(() => _down = false),
    onTapUp: (_) => setState(() => _down = false),
    onTap: widget.onTap,
    onLongPress: widget.onLongPress,
    child: AnimatedScale(
      scale: _down ? 0.94 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}

/// The shared frame of an activity: a back button, a title and the body.
class KidsActivityFrame extends StatelessWidget {
  const KidsActivityFrame({
    super.key,
    required this.title,
    required this.colors,
    required this.onBack,
    required this.child,
    this.trailing,
  });

  final String title;
  final List<Color> colors;
  final VoidCallback onBack;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ),
    ),
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                KidsBounce(
                  onTap: onBack,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 36),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(title, style: kidsText(34))),
                ?trailing,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

// ── Draw ───────────────────────────────────────────────────────────────

class _Stroke {
  _Stroke(this.color, this.width);
  final Color color;
  final double width;
  final points = <Offset>[];
}

/// Finger painting: eight bright colors, three brush sizes, undo and clear.
class KidsDraw extends StatefulWidget {
  const KidsDraw({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<KidsDraw> createState() => _KidsDrawState();
}

class _KidsDrawState extends State<KidsDraw> {
  static const _palette = [
    Color(0xFFFF4D4D), Color(0xFFFF9F1C), Color(0xFFFFD60A), Color(0xFF3CCB8C),
    Color(0xFF1C8ED6), Color(0xFF8C5BFF), Color(0xFFFF6FB5), Color(0xFF2B2B2B),
    Colors.white, // the eraser
  ];
  static const _sizes = [8.0, 16.0, 30.0];

  final _strokes = <_Stroke>[];
  Color _color = _palette[0];
  double _size = _sizes[1];
  int _version = 0;

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Draw Studio',
    colors: const [Color(0xFFF26A1B), Color(0xFFFF4D8D)],
    onBack: widget.onBack,
    trailing: Row(
      children: [
        _toolButton(Icons.undo_rounded, () {
          if (_strokes.isNotEmpty) setState(() { _strokes.removeLast(); _version++; });
        }),
        const SizedBox(width: 12),
        _toolButton(Icons.delete_outline_rounded, () => setState(() { _strokes.clear(); _version++; })),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: ColoredBox(
                color: Colors.white,
                child: GestureDetector(
                  onPanStart: (d) => setState(() {
                    _strokes.add(_Stroke(_color, _size)..points.add(d.localPosition));
                    _version++;
                  }),
                  onPanUpdate: (d) => setState(() {
                    _strokes.last.points.add(d.localPosition);
                    _version++;
                  }),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _DrawPainter(_strokes, _version),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 92,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final c in _palette)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: KidsBounce(
                        onTap: () => setState(() => _color = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: c == Colors.white ? const Color(0xFFFF4D8D) : Colors.white,
                              width: c == _color ? 6 : 2,
                            ),
                          ),
                          child: c == Colors.white
                              ? const Icon(Icons.auto_fix_normal_rounded, color: Color(0xFFFF4D8D), size: 30)
                              : null,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  for (final s in _sizes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: KidsBounce(
                        onTap: () => setState(() => _size = s),
                        child: Container(
                          width: 64,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: s == _size ? 0.45 : 0.18),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          alignment: Alignment.center,
                          child: Container(
                            width: s,
                            height: s,
                            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _toolButton(IconData icon, VoidCallback onTap) => KidsBounce(
    onTap: onTap,
    child: Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 34),
    ),
  );
}

class _DrawPainter extends CustomPainter {
  _DrawPainter(this.strokes, this.version);
  final List<_Stroke> strokes;
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (s.points.length == 1) {
        canvas.drawCircle(s.points.first, s.width / 2, paint..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (var i = 1; i < s.points.length; i++) {
        final a = s.points[i - 1], b = s.points[i];
        // Midpoint smoothing keeps fast finger strokes round, not jagged.
        path.quadraticBezierTo(a.dx, a.dy, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_DrawPainter old) => old.version != version;
}
