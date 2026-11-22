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
    child: AnimatedScale(scale: _down ? 0.94 : 1, duration: const Duration(milliseconds: 140), curve: Curves.easeOutCubic, child: widget.child),
  );
}

/// The shared frame of an activity: its colour world with playful shapes
/// floating in it, a big back button, the title, and the body.
class KidsActivityFrame extends StatelessWidget {
  const KidsActivityFrame({super.key, required this.title, required this.colors, required this.onBack, required this.child, this.trailing});

  final String title;
  final List<Color> colors;
  final VoidCallback onBack;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: KidsDecorPainter(seed: title.hashCode)),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 20, 8),
                child: Row(
                  children: [
                    KidsBounce(
                      onTap: onBack,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Color(0x40000000), offset: Offset(0, 4), blurRadius: 8)],
                        ),
                        child: Icon(Icons.arrow_back_rounded, color: colors.first, size: 34),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kidsText(34).copyWith(
                          shadows: const [Shadow(color: Color(0x55000000), offset: Offset(0, 3), blurRadius: 6)],
                        ),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Soft bubbles, rings and sparkles scattered over an activity's colours:
/// painted once, no animation, so it costs nothing while playing.
class KidsDecorPainter extends CustomPainter {
  const KidsDecorPainter({required this.seed});
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    var x = seed & 0x7fffffff;
    double rnd() {
      x = (x * 1103515245 + 12345) & 0x7fffffff;
      return x / 0x7fffffff;
    }

    final fill = Paint();
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    for (var i = 0; i < 14; i++) {
      final c = Offset(rnd() * size.width, rnd() * size.height);
      final r = 20 + rnd() * 90;
      switch (i % 3) {
        case 0:
          fill.color = Colors.white.withValues(alpha: 0.05 + rnd() * 0.05);
          canvas.drawCircle(c, r, fill);
        case 1:
          ring.color = Colors.white.withValues(alpha: 0.07 + rnd() * 0.05);
          canvas.drawCircle(c, r * 0.6, ring);
        default:
          // A four-point sparkle.
          final k = 8 + rnd() * 16;
          final path = Path()
            ..moveTo(c.dx, c.dy - k)
            ..quadraticBezierTo(c.dx, c.dy, c.dx + k, c.dy)
            ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + k)
            ..quadraticBezierTo(c.dx, c.dy, c.dx - k, c.dy)
            ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - k);
          fill.color = Colors.white.withValues(alpha: 0.16 + rnd() * 0.12);
          canvas.drawPath(path, fill);
      }
    }
  }

  @override
  bool shouldRepaint(KidsDecorPainter old) => old.seed != seed;
}

/// Every game's start screen: a big friendly card with the game's idea, the
/// best score, its levels and a big Start button.
class KidsStartPanel extends StatelessWidget {
  const KidsStartPanel({super.key, required this.icon, required this.pitch, required this.onStart, this.best, this.options});

  final IconData icon;
  final String pitch;
  final VoidCallback onStart;

  /// The best-score line, e.g. "Best: 12 solved" (null: none yet).
  final Future<String?>? best;

  /// Levels or modes to pick from.
  final Widget? options;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 30),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Float(
                child: Container(
                  width: 128,
                  height: 128,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Color(0xFFFFF1C2)]),
                    boxShadow: [BoxShadow(color: Color(0x40000000), offset: Offset(0, 8), blurRadius: 16)],
                  ),
                  child: Icon(icon, size: 72, color: const Color(0xFF3B2F8F)),
                ),
              ),
              const SizedBox(height: 18),
              Text(pitch, textAlign: TextAlign.center, style: kidsText(30)),
              if (best != null) ...[
                const SizedBox(height: 12),
                FutureBuilder<String?>(
                  future: best,
                  builder: (context, snap) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD23F), size: 22),
                        const SizedBox(width: 6),
                        Text(snap.data ?? 'No best yet: be the first!', style: kidsText(19, weight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
              if (options != null) ...[const SizedBox(height: 20), options!],
              const SizedBox(height: 26),
              KidsBigButton('Start', icon: Icons.play_arrow_rounded, onTap: onStart),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A big, bright, 3D button: the one thing to press.
class KidsBigButton extends StatelessWidget {
  const KidsBigButton(this.label, {super.key, required this.onTap, this.icon, this.size = 32, this.colors = const [Color(0xFFFFE066), Color(0xFFFFB627)]});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => KidsBounce(
    onTap: onTap,
    child: AnimatedOpacity(
      opacity: onTap == null ? 0.45 : 1,
      duration: const Duration(milliseconds: 150),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: size * 1.3, vertical: size * 0.55),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
          borderRadius: BorderRadius.circular(size * 2),
          boxShadow: [
            BoxShadow(color: Color.lerp(colors.last, Colors.black, 0.35)!, offset: const Offset(0, 6)),
            const BoxShadow(color: Color(0x33000000), offset: Offset(0, 10), blurRadius: 14),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, color: const Color(0xFF4A2A00), size: size * 1.15), SizedBox(width: size * 0.3)],
            Text(label, style: kidsText(size, color: const Color(0xFF4A2A00))),
          ],
        ),
      ),
    ),
  );
}

/// Gently floats its child up and down.
class _Float extends StatefulWidget {
  const _Float({required this.child});
  final Widget child;

  @override
  State<_Float> createState() => _FloatState();
}

class _FloatState extends State<_Float> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) => Transform.translate(offset: Offset(0, -8 * Curves.easeInOut.transform(_c.value)), child: child),
    child: widget.child,
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
          if (_strokes.isNotEmpty) {
            setState(() {
              _strokes.removeLast();
              _version++;
            });
          }
        }),
        const SizedBox(width: 12),
        _toolButton(
          Icons.delete_outline_rounded,
          () => setState(() {
            _strokes.clear();
            _version++;
          }),
        ),
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
                    child: CustomPaint(painter: _DrawPainter(_strokes, _version), size: Size.infinite),
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
                            border: Border.all(color: c == Colors.white ? const Color(0xFFFF4D8D) : Colors.white, width: c == _color ? 6 : 2),
                          ),
                          child: c == Colors.white ? const Icon(Icons.auto_fix_normal_rounded, color: Color(0xFFFF4D8D), size: 30) : null,
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

/// The level picker every game shares: Easy / Medium / Hard and the like.
Widget kidsLevelChips(List<String> labels, int selected, ValueChanged<int> onPick) => Wrap(
  alignment: WrapAlignment.center,
  spacing: 12,
  runSpacing: 12,
  children: [
    for (var i = 0; i < labels.length; i++)
      KidsBounce(
        onTap: () => onPick(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: i == selected ? Colors.white : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: i == selected ? 1 : 0.35), width: 2),
            boxShadow: i == selected ? const [BoxShadow(color: Color(0x33000000), offset: Offset(0, 4), blurRadius: 6)] : null,
          ),
          child: Text(labels[i], style: kidsText(21, color: i == selected ? const Color(0xFF2A1F6B) : Colors.white)),
        ),
      ),
  ],
);
