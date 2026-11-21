import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'kids_activities.dart';
import 'kids_games.dart';
import 'kids_logic.dart';
import 'kids_more_logic.dart';

/// The Kids Portal's learning quizzes: Times Tables, Telling the Time, Flag
/// Quiz and Patterns. One quiz frame runs them all: pick a mode, ten
/// questions with four big answers, stars at the end.

/// One question: what to show and the answers to pick from.
class QuizItem {
  const QuizItem({
    required this.prompt,
    required this.choices,
    required this.answer,
    this.explain,
  });

  final Widget prompt;
  final List<String> choices;
  final String answer;

  /// Shown after a wrong answer, so a miss still teaches.
  final String? explain;
}

class KidsQuiz extends StatefulWidget {
  const KidsQuiz({
    super.key,
    required this.title,
    required this.colors,
    required this.scoreKey,
    required this.icon,
    required this.pitch,
    required this.modes,
    required this.next,
    required this.onBack,
    this.count = 10,
  });

  final String title;
  final List<Color> colors;
  final String scoreKey;
  final IconData icon;
  final String pitch;

  /// The mode chips (a table, a level, flags or capitals).
  final List<String> modes;
  final QuizItem Function(int mode, int index, math.Random rng) next;
  final VoidCallback onBack;
  final int count;

  @override
  State<KidsQuiz> createState() => _KidsQuizState();
}

enum _QuizPhase { ready, playing, over }

class _KidsQuizState extends State<KidsQuiz> {
  final _rng = math.Random();
  _QuizPhase _phase = _QuizPhase.ready;
  int _mode = 0, _index = 0, _score = 0;
  late QuizItem _item;
  String? _picked;
  bool _newBest = false;

  int get _stars {
    final share = _score / widget.count;
    return share >= 0.9 ? 3 : (share >= 0.7 ? 2 : (share >= 0.5 ? 1 : 0));
  }

  void _start() => setState(() {
    _phase = _QuizPhase.playing;
    _index = 0;
    _score = 0;
    _picked = null;
    _item = widget.next(_mode, 0, _rng);
  });

  Future<void> _pick(String choice) async {
    if (_picked != null) return;
    final right = choice == _item.answer;
    setState(() {
      _picked = choice;
      if (right) _score++;
    });
    await Future<void>.delayed(Duration(milliseconds: right ? 650 : 1600));
    if (!mounted) return;
    if (_index + 1 >= widget.count) {
      final best = await KidsScores.offer(widget.scoreKey, _score);
      await KidsScores.addStars(_stars);
      await KidsScores.offerChallenge(widget.scoreKey, _score);
      if (mounted) {
        setState(() {
          _phase = _QuizPhase.over;
          _newBest = best;
        });
      }
      return;
    }
    setState(() {
      _index++;
      _picked = null;
      _item = widget.next(_mode, _index, _rng);
    });
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: widget.title,
    colors: widget.colors,
    onBack: widget.onBack,
    trailing: _phase == _QuizPhase.playing
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${_index + 1} / ${widget.count}', style: kidsText(28)),
              const SizedBox(width: 18),
              const Icon(Icons.star_rounded, color: Color(0xFFFFD27A), size: 32),
              Text('$_score', style: kidsText(28)),
            ],
          )
        : null,
    child: switch (_phase) {
      _QuizPhase.ready => _ready(),
      _QuizPhase.playing => _playing(),
      _QuizPhase.over => KidsResult(
        title: _stars == 3 ? 'Superstar!' : (_stars >= 1 ? 'Nice work!' : 'Keep practising!'),
        detail: '$_score of ${widget.count} right',
        stars: _stars,
        newBest: _newBest,
        onAgain: () => setState(() => _phase = _QuizPhase.ready),
      ),
    },
  );

  Widget _ready() => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: 96, color: Colors.white),
          const SizedBox(height: 8),
          Text(widget.pitch, textAlign: TextAlign.center, style: kidsText(26, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          FutureBuilder<int?>(
            future: KidsScores.best(widget.scoreKey),
            builder: (context, snap) => Text(
              snap.data == null ? 'No best yet' : 'Best: ${snap.data} of ${widget.count}',
              style: kidsText(20, color: Colors.white70, weight: FontWeight.w700),
            ),
          ),
          if (widget.modes.length > 1) ...[
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < widget.modes.length; i++)
                  KidsBounce(
                    onTap: () => setState(() => _mode = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: i == _mode ? Colors.white : Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        widget.modes[i],
                        style: kidsText(20, color: i == _mode ? const Color(0xFF1A1340) : Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          KidsButton('Start', icon: Icons.play_arrow_rounded, onTap: _start, size: 32),
        ],
      ),
    ),
  );

  Widget _playing() => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth > box.maxHeight;
      final prompt = Center(child: _item.prompt);
      final answers = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final choice in _item.choices)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: KidsBounce(
                onTap: () => unawaited(_pick(choice)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: _picked == null
                        ? Colors.white
                        : choice == _item.answer
                        ? const Color(0xFF52D69F)
                        : choice == _picked
                        ? const Color(0xFFFF8A8A)
                        : Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    choice,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: kidsText(26, color: const Color(0xFF1A1340)),
                  ),
                ),
              ),
            ),
          if (_picked != null && _picked != _item.answer && _item.explain != null)
            Text(_item.explain!, textAlign: TextAlign.center, style: kidsText(20, weight: FontWeight.w700)),
        ],
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
        child: wide
            ? Row(
                children: [
                  Expanded(flex: 5, child: prompt),
                  const SizedBox(width: 28),
                  Expanded(flex: 4, child: answers),
                ],
              )
            : Column(
                children: [
                  Expanded(child: prompt),
                  answers,
                ],
              ),
      );
    },
  );
}

// ── The four quizzes ─────────────────────────────────────────────────────

class TimesTables extends StatelessWidget {
  const TimesTables({super.key, required this.onBack});
  final VoidCallback onBack;

  static const _tables = [null, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

  @override
  Widget build(BuildContext context) => KidsQuiz(
    title: 'Times Tables',
    colors: const [Color(0xFFD42A1A), Color(0xFFF5A623)],
    scoreKey: 'times',
    icon: Icons.close_rounded,
    pitch: 'Pick a table, or Mixed for all of them',
    modes: [for (final t in _tables) t == null ? 'Mixed' : '×$t'],
    count: 20,
    onBack: onBack,
    next: (mode, _, rng) {
      final q = timesQuestion(_tables[mode], rng);
      final wrong = <int>{};
      for (var guard = 0; wrong.length < 3; guard++) {
        final near = q.answer + (rng.nextBool() ? 1 : -1) * (rng.nextBool() ? q.a : 1 + rng.nextInt(4));
        if (near > 0 && near != q.answer) wrong.add(near);
        if (guard > 40) wrong.add(q.answer + 10 + guard);
      }
      return QuizItem(
        prompt: Text(q.text, style: kidsText(96)),
        choices: ([q.answer, ...wrong].map((n) => '$n').toList()..shuffle(rng)),
        answer: '${q.answer}',
        explain: '${q.text} = ${q.answer}',
      );
    },
  );
}

class TellingTime extends StatelessWidget {
  const TellingTime({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => KidsQuiz(
    title: 'Telling the Time',
    colors: const [Color(0xFF1C8ED6), Color(0xFF63C3FF)],
    scoreKey: 'clock',
    icon: Icons.schedule_rounded,
    pitch: 'Read the clock and pick the time',
    modes: const ['Half hours', 'Quarters', '5 minutes'],
    onBack: onBack,
    next: (mode, _, rng) {
      final q = clockQuestion(mode + 1, rng);
      return QuizItem(
        prompt: AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(painter: KidsClockPainter(q.hour, q.minute)),
        ),
        choices: q.choices,
        answer: q.answer,
        explain: 'It is ${q.answer}',
      );
    },
  );
}

/// A friendly clock face: big numbers, a short thick hour hand and a long
/// minute hand.
class KidsClockPainter extends CustomPainter {
  const KidsClockPainter(this.hour, this.minute);
  final int hour;
  final int minute;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 * 0.95;
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = const Color(0xFF1A1340)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05,
    );
    for (var i = 0; i < 60; i++) {
      final a = i * math.pi / 30 - math.pi / 2;
      final long = i % 5 == 0;
      final p1 = c + Offset(math.cos(a), math.sin(a)) * r * (long ? 0.86 : 0.9);
      final p2 = c + Offset(math.cos(a), math.sin(a)) * r * 0.95;
      canvas.drawLine(p1, p2, Paint()..color = const Color(0xFF1A1340)..strokeWidth = long ? r * 0.025 : r * 0.01);
    }
    for (var n = 1; n <= 12; n++) {
      final a = n * math.pi / 6 - math.pi / 2;
      final tp = TextPainter(
        text: TextSpan(text: '$n', style: kidsText(r * 0.17, color: const Color(0xFF1A1340))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c + Offset(math.cos(a), math.sin(a)) * r * 0.7 - Offset(tp.width / 2, tp.height / 2));
    }
    void hand(double angle, double length, double width, Color color) {
      canvas.drawLine(
        c,
        c + Offset(math.cos(angle), math.sin(angle)) * r * length,
        Paint()
          ..color = color
          ..strokeWidth = r * width
          ..strokeCap = StrokeCap.round,
      );
    }

    hand(((hour % 12) + minute / 60) * math.pi / 6 - math.pi / 2, 0.45, 0.07, const Color(0xFF1A1340));
    hand(minute * math.pi / 30 - math.pi / 2, 0.75, 0.04, const Color(0xFFE0303C));
    canvas.drawCircle(c, r * 0.05, Paint()..color = const Color(0xFF1A1340));
  }

  @override
  bool shouldRepaint(KidsClockPainter old) => old.hour != hour || old.minute != minute;
}

class FlagQuiz extends StatelessWidget {
  const FlagQuiz({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => KidsQuiz(
    title: 'Flag Quiz',
    colors: const [Color(0xFF14A06B), Color(0xFF1C8ED6)],
    scoreKey: 'flags',
    icon: Icons.flag_rounded,
    pitch: 'Flags of the world, and their capitals',
    modes: const ['Flags', 'Capitals'],
    onBack: onBack,
    next: (mode, _, rng) {
      final q = flagQuestion(rng, capitals: mode == 1);
      return QuizItem(
        prompt: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(flagEmoji(q.code), style: const TextStyle(fontSize: 150)),
            const SizedBox(height: 8),
            Text(q.prompt, textAlign: TextAlign.center, style: kidsText(28)),
          ],
        ),
        choices: q.choices,
        answer: q.answer,
        explain: 'It is ${q.answer}',
      );
    },
  );
}

class PatternsGame extends StatelessWidget {
  const PatternsGame({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => KidsQuiz(
    title: 'Patterns',
    colors: const [Color(0xFF8C5BFF), Color(0xFFE0446A)],
    scoreKey: 'patterns',
    icon: Icons.auto_graph_rounded,
    pitch: 'What comes next? Spot the rule.',
    modes: const ['Easy', 'Medium', 'Hard'],
    onBack: onBack,
    next: (mode, index, rng) {
      // The questions get harder within a round too.
      final q = patternQuestion(mode + 1 + (index >= 7 ? 1 : 0), rng);
      return QuizItem(
        prompt: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final n in q.shown)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(18)),
                child: Text('$n', style: kidsText(44)),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: Text('?', style: kidsText(44, color: const Color(0xFF8C5BFF))),
            ),
          ],
        ),
        choices: [for (final c in q.choices) '$c'],
        answer: '${q.answer}',
        explain: q.rule,
      );
    },
  );
}
