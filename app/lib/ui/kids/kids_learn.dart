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
  const QuizItem({required this.prompt, required this.choices, required this.answer, this.explain});

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

/// Stars for [score] right out of [count]: 50%, 70%, 90%.
int quizStars(int score, int count) {
  final share = score / count;
  return share >= 0.9 ? 3 : (share >= 0.7 ? 2 : (share >= 0.5 ? 1 : 0));
}

/// The high-score key for a quiz's level (the first level keeps the
/// quiz's own key, so earlier bests stay).
String quizLevelKey(String key, int mode) => mode == 0 ? key : '$key.$mode';

final _decks = Expando<List<int>>();

/// The [index]th question of a round from [bank]: shuffled, and no
/// question again until every one has been asked.
T fromBank<T>(List<T> bank, int index, math.Random rng) {
  var order = _decks[bank];
  if (order == null || order.length != bank.length || index % bank.length == 0) {
    order = [for (var i = 0; i < bank.length; i++) i]..shuffle(rng);
    _decks[bank] = order;
  }
  return bank[order[index % bank.length]];
}

class _KidsQuizState extends State<KidsQuiz> {
  final _rng = math.Random();
  _QuizPhase _phase = _QuizPhase.ready;
  int _mode = 0, _index = 0, _score = 0;
  late QuizItem _item;
  String? _picked;
  bool _newBest = false;
  final _seen = <String>{};

  /// Stars already earned on each level (from its best round).
  final _levelStars = <int, int>{};

  int get _stars => quizStars(_score, widget.count);

  @visibleForTesting
  QuizItem get debugItem => _item;
  @visibleForTesting
  int get debugMode => _mode;

  bool get _hasNext => _mode + 1 < widget.modes.length;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStars());
  }

  Future<void> _loadStars() async {
    for (var m = 0; m < widget.modes.length; m++) {
      final best = await KidsScores.best(quizLevelKey(widget.scoreKey, m));
      if (best != null) _levelStars[m] = quizStars(best, widget.count);
    }
    if (mounted) setState(() {});
  }

  /// The next question, not one already asked this round (when it can).
  QuizItem _fresh(int index) {
    var item = widget.next(_mode, index, _rng);
    for (var guard = 0; guard < 8 && !_seen.add(item.explain ?? item.answer); guard++) {
      item = widget.next(_mode, index, _rng);
    }
    return item;
  }

  void _start() => setState(() {
    _phase = _QuizPhase.playing;
    _index = 0;
    _score = 0;
    _picked = null;
    _seen.clear();
    _item = _fresh(0);
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
      final best = await KidsScores.offer(quizLevelKey(widget.scoreKey, _mode), _score);
      _levelStars[_mode] = math.max(_levelStars[_mode] ?? 0, _stars);
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
      _item = _fresh(_index);
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
        title: _stars >= 2 && _hasNext ? 'Level up!' : (_stars == 3 ? 'Superstar!' : (_stars >= 1 ? 'Nice work!' : 'Keep practising!')),
        detail: '$_score of ${widget.count} right · ${widget.modes[_mode]}',
        stars: _stars,
        newBest: _newBest,
        onAgain: _start,
        onNext: _stars >= 2 && _hasNext
            ? () {
                _mode++;
                _start();
              }
            : null,
        nextLabel: _hasNext ? 'Next: ${widget.modes[_mode + 1]}' : null,
      ),
    },
  );

  Widget _ready() => KidsStartPanel(
    icon: widget.icon,
    pitch: widget.pitch,
    best: KidsScores.best(quizLevelKey(widget.scoreKey, _mode)).then((b) => b == null ? null : 'Best: $b of ${widget.count}'),
    options: widget.modes.length > 1
        ? kidsLevelChips(
            [
              for (var m = 0; m < widget.modes.length; m++)
                (_levelStars[m] ?? 0) > 0 ? '${widget.modes[m]} ${'★' * _levelStars[m]!}' : widget.modes[m],
            ],
            _mode,
            (i) => setState(() => _mode = i),
          )
        : null,
    onStart: _start,
  );

  static const _answerColors = [
    [Color(0xFFFF6B8B), Color(0xFFE8456B)],
    [Color(0xFF4FC3F7), Color(0xFF2196F3)],
    [Color(0xFFFFD54F), Color(0xFFFFB300)],
    [Color(0xFF81C784), Color(0xFF43A047)],
  ];

  Widget _answer(int i, String choice) {
    final done = _picked != null;
    final right = choice == _item.answer;
    final accent = _answerColors[i % 4].last;
    final Color fill;
    final Color edge;
    final Color ink;
    if (!done) {
      fill = Colors.white.withValues(alpha: 0.94);
      edge = accent;
      ink = const Color(0xFF1E2A44);
    } else if (right) {
      fill = const Color(0xFF2FB872);
      edge = Colors.white;
      ink = Colors.white;
    } else if (choice == _picked) {
      fill = const Color(0xFFE0525A);
      edge = Colors.white;
      ink = Colors.white;
    } else {
      fill = Colors.white.withValues(alpha: 0.35);
      edge = Colors.white.withValues(alpha: 0.3);
      ink = const Color(0xFF1E2A44).withValues(alpha: 0.6);
    }
    return KidsBounce(
      onTap: done ? null : () => unawaited(_pick(choice)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(26),
          border: Border(
            top: BorderSide(color: edge, width: 3),
            left: BorderSide(color: edge, width: 3),
            right: BorderSide(color: edge, width: 3),
            bottom: BorderSide(color: edge, width: 9),
          ),
          boxShadow: const [BoxShadow(color: Color(0x33000000), offset: Offset(0, 6), blurRadius: 10)],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (done && right) ...[const Icon(Icons.check_circle_rounded, color: Colors.white, size: 40), const SizedBox(width: 8)],
            if (done && !right && choice == _picked) ...[const Icon(Icons.cancel_rounded, color: Colors.white, size: 40), const SizedBox(width: 8)],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(choice, textAlign: TextAlign.center, maxLines: 2, style: kidsText(44, color: ink)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playing() => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth > box.maxHeight;
      final prompt = Center(child: _item.prompt);
      final choices = _item.choices;
      final grid = Column(
        children: [
          for (var row = 0; row < (choices.length + 1) ~/ 2; row++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var col = 0; col < 2; col++) ...[
                      if (col == 1) const SizedBox(width: 14),
                      Expanded(child: row * 2 + col < choices.length ? _answer(row * 2 + col, choices[row * 2 + col]) : const SizedBox()),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
      final explain = _picked != null && _picked != _item.answer && _item.explain != null
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _item.explain!,
                textAlign: TextAlign.center,
                style: kidsText(26, weight: FontWeight.w700),
              ),
            )
          : const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
        child: wide
            ? Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Container(
                      decoration: BoxDecoration(color: const Color(0xFF101828).withValues(alpha: 0.45), borderRadius: BorderRadius.circular(36), border: Border.all(color: Colors.white.withValues(alpha: 0.18))),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Expanded(child: prompt),
                          explain,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(flex: 5, child: grid),
                ],
              )
            : Column(
                children: [
                  Expanded(
                    flex: 5,
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(color: const Color(0xFF101828).withValues(alpha: 0.45), borderRadius: BorderRadius.circular(36), border: Border.all(color: Colors.white.withValues(alpha: 0.18))),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Expanded(child: prompt),
                          explain,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(flex: 4, child: grid),
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
    modes: const ['Half hours', 'Quarters', '5 minutes', 'Any minute'],
    onBack: onBack,
    next: (mode, _, rng) {
      final q = clockQuestion(mode + 1, rng);
      return QuizItem(
        prompt: AspectRatio(aspectRatio: 1, child: CustomPaint(painter: KidsClockPainter(q.hour, q.minute))),
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
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = const Color(0xFF1A1340)
          ..strokeWidth = long ? r * 0.025 : r * 0.01,
      );
    }
    for (var n = 1; n <= 12; n++) {
      final a = n * math.pi / 6 - math.pi / 2;
      final tp = TextPainter(
        text: TextSpan(
          text: '$n',
          style: kidsText(r * 0.17, color: const Color(0xFF1A1340)),
        ),
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
            Text(q.prompt, textAlign: TextAlign.center, style: kidsText(34)),
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

// ── More quizzes, each with three levels ─────────────────────────────────

const _levels = ['Easy', 'Medium', 'Hard'];

QuizItem _bankItem(String prompt, String answer, List<String> wrong, math.Random rng, {double size = 34}) => QuizItem(
  prompt: Text(prompt, textAlign: TextAlign.center, style: kidsText(size)),
  choices: ([answer, ...wrong]..shuffle(rng)),
  answer: answer,
  explain: 'It is $answer',
);

class FractionsQuiz extends StatelessWidget {
  const FractionsQuiz({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => KidsQuiz(
    title: 'Fractions',
    colors: const [Color(0xFF14A06B), Color(0xFFF5A623)],
    scoreKey: 'fractions',
    icon: Icons.pie_chart_rounded,
    pitch: 'How much of the pie is coloured?',
    modes: _levels,
    onBack: onBack,
    next: (mode, _, rng) {
      final q = fractionQuestion(mode + 1, rng);
      return QuizItem(
        prompt: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 260, height: 260, child: CustomPaint(painter: _PiePainter(q.parts, q.shaded))),
            const SizedBox(height: 12),
            Text(q.prompt, textAlign: TextAlign.center, style: kidsText(34)),
          ],
        ),
        choices: q.choices,
        answer: q.answer,
        explain: '${q.shaded} of ${q.parts} parts is ${q.answer}',
      );
    },
  );
}

class _PiePainter extends CustomPainter {
  const _PiePainter(this.parts, this.shaded);
  final int parts;
  final int shaded;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final sweep = 2 * math.pi / parts;
    for (var i = 0; i < parts; i++) {
      canvas.drawArc(rect.deflate(4), -math.pi / 2 + i * sweep, sweep, true, Paint()..color = i < shaded ? const Color(0xFFFFD27A) : Colors.white);
      canvas.drawArc(
        rect.deflate(4),
        -math.pi / 2 + i * sweep,
        sweep,
        true,
        Paint()
          ..color = const Color(0xFF1A1340)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) => old.parts != parts || old.shaded != shaded;
}

class MoneyQuiz extends StatelessWidget {
  const MoneyQuiz({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => KidsQuiz(
    title: 'Money',
    colors: const [Color(0xFF128A5A), Color(0xFF1F8A4C)],
    scoreKey: 'money',
    icon: Icons.savings_rounded,
    pitch: 'Count the coins',
    modes: _levels,
    onBack: onBack,
    next: (mode, _, rng) {
      final q = moneyQuestion(mode + 1, rng);
      return QuizItem(
        prompt: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [for (final c in q.coins) _Coin(c)]),
            const SizedBox(height: 16),
            Text(q.prompt, textAlign: TextAlign.center, style: kidsText(34)),
          ],
        ),
        choices: q.choices,
        answer: q.answer,
        explain: 'It is ${q.answer}',
      );
    },
  );
}

/// A coin, sized and coloured like the real one, with its value.
class _Coin extends StatelessWidget {
  const _Coin(this.value);
  final int value;

  @override
  Widget build(BuildContext context) {
    final (size, color, label) = switch (value) {
      1 => (96.0, const Color(0xFFC77B42), '1¢'),
      5 => (112.0, const Color(0xFFB8BCC4), '5¢'),
      10 => (90.0, const Color(0xFFD5D8DE), '10¢'),
      _ => (124.0, const Color(0xFFC9CDD4), '25¢'),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.black26, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26, offset: Offset(0, 3))],
      ),
      child: Text(label, style: kidsText(size * 0.3, color: const Color(0xFF2A2A2A))),
    );
  }
}

class ScienceQuiz extends StatelessWidget {
  const ScienceQuiz({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => KidsQuiz(
    title: 'Science',
    colors: const [Color(0xFF1C8ED6), Color(0xFF14A06B)],
    scoreKey: 'science',
    icon: Icons.science_rounded,
    pitch: 'Plants, animals, space and more',
    modes: const ['Easy', 'Medium', 'Hard', 'Expert'],
    onBack: onBack,
    next: (mode, index, rng) {
      final (q, a, wrong) = fromBank(kidsScience[mode + 1]!, index, rng);
      return _bankItem(q, a, wrong, rng, size: 32);
    },
  );
}

class SpellingQuiz extends StatelessWidget {
  const SpellingQuiz({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => KidsQuiz(
    title: 'Spelling',
    colors: const [Color(0xFFE08A00), Color(0xFF8C5BFF)],
    scoreKey: 'spelling',
    icon: Icons.spellcheck_rounded,
    pitch: 'Pick the word spelled right',
    modes: const ['Starter', 'Easy', 'Medium', 'Hard'],
    onBack: onBack,
    next: (mode, index, rng) {
      final (word, wrong) = fromBank(kidsSpelling[mode]!, index, rng);
      return QuizItem(
        prompt: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.spellcheck_rounded, size: 96, color: Colors.white),
            Text('Which spelling is right?', style: kidsText(32)),
          ],
        ),
        choices: [word, ...wrong]..shuffle(rng),
        answer: word,
        explain: 'It is spelled $word',
      );
    },
  );
}

class OppositesQuiz extends StatelessWidget {
  const OppositesQuiz({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => KidsQuiz(
    title: 'Opposites',
    colors: const [Color(0xFFE0446A), Color(0xFF1C8ED6)],
    scoreKey: 'opposites',
    icon: Icons.compare_arrows_rounded,
    pitch: 'Find the word that means the opposite',
    modes: const ['Starter', 'Easy', 'Medium', 'Hard'],
    onBack: onBack,
    next: (mode, index, rng) {
      final (word, opposite, wrong) = fromBank(kidsOpposites[mode]!, index, rng);
      return _bankItem('The opposite of\n"$word" is…', opposite, wrong, rng, size: 40);
    },
  );
}
