import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'kids_activities.dart';
import 'kids_logic.dart';

/// The Kids Portal's games for 9-year-olds: Math Blitz, Word Scramble, 2048,
/// Connect Four against the computer and Memory Pro. Offline and drawn by
/// Flutter; the rules live in kids_logic.dart.

// ── Shared ─────────────────────────────────────────────────────────────

/// A big pill button.
class KidsButton extends StatelessWidget {
  const KidsButton(this.label, {super.key, required this.onTap, this.color = Colors.white, this.ink, this.icon, this.size = 28});
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final Color? ink;
  final IconData? icon;
  final double size;

  @override
  Widget build(BuildContext context) => KidsBounce(
    onTap: onTap,
    child: AnimatedOpacity(
      opacity: onTap == null ? 0.45 : 1,
      duration: const Duration(milliseconds: 150),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: size * 1.1, vertical: size * 0.55),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 2)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, color: ink ?? const Color(0xFF1A1340), size: size * 1.1), SizedBox(width: size * 0.35)],
            Text(label, style: kidsText(size, color: ink ?? const Color(0xFF1A1340))),
          ],
        ),
      ),
    ),
  );
}

/// The end-of-round card: the result, a new-best badge, stars earned and
/// Play again.
class KidsResult extends StatelessWidget {
  const KidsResult({super.key, required this.title, required this.detail, required this.stars, required this.newBest, required this.onAgain});
  final String title;
  final String detail;
  final int stars;
  final bool newBest;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) => Center(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.star_rounded,
                    size: i == 1 ? 110 : 84,
                    color: i < stars ? const Color(0xFFFFD27A) : Colors.white.withValues(alpha: 0.2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: kidsText(48)),
          const SizedBox(height: 6),
          Text(detail, style: kidsText(24, color: Colors.white70, weight: FontWeight.w700)),
          if (newBest) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFFFD27A), borderRadius: BorderRadius.circular(20)),
              child: Text('NEW BEST!', style: kidsText(20, color: const Color(0xFF5A3300))),
            ),
          ],
          const SizedBox(height: 26),
          KidsButton('Play again', icon: Icons.replay_rounded, onTap: onAgain),
        ],
      ),
    ),
  );
}

/// A start card: the game's idea in one line, the best score, and Go.
class _StartCard extends StatelessWidget {
  const _StartCard({super.key, required this.icon, required this.text, required this.bestLabel, required this.game, required this.onStart, this.extra});
  final IconData icon;
  final String text;
  final String bestLabel;
  final String game;
  final VoidCallback onStart;
  final Widget? extra;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 110, color: Colors.white),
        const SizedBox(height: 10),
        Text(text, textAlign: TextAlign.center, style: kidsText(28, weight: FontWeight.w700)),
        const SizedBox(height: 10),
        FutureBuilder<int?>(
          future: KidsScores.best(game),
          builder: (context, snap) => Text(
            snap.data == null ? 'No best yet' : '$bestLabel: ${snap.data}',
            style: kidsText(22, color: Colors.white70, weight: FontWeight.w700),
          ),
        ),
        if (extra != null) ...[const SizedBox(height: 18), extra!],
        const SizedBox(height: 24),
        KidsButton('Start', icon: Icons.play_arrow_rounded, onTap: onStart, size: 32),
      ],
    ),
  );
}

// ── Math Blitz ─────────────────────────────────────────────────────────

class MathBlitz extends StatefulWidget {
  const MathBlitz({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<MathBlitz> createState() => _MathBlitzState();
}

enum _Phase { ready, playing, over }

class _MathBlitzState extends State<MathBlitz> {
  static const _seconds = 60;
  final _rng = math.Random();
  _Phase _phase = _Phase.ready;
  late MathProblem _problem;
  int _score = 0, _streak = 0, _left = _seconds;
  int? _wrong;
  bool _newBest = false;
  Timer? _timer;

  void _start() {
    _timer?.cancel();
    setState(() {
      _phase = _Phase.playing;
      _score = 0;
      _streak = 0;
      _left = _seconds;
      _wrong = null;
      _problem = mathProblem(1, _rng);
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_left <= 1) {
        _finish();
      } else {
        setState(() => _left--);
      }
    });
  }

  Future<void> _finish() async {
    _timer?.cancel();
    final best = await KidsScores.offer('math', _score);
    await KidsScores.addStars(_stars);
    if (mounted) setState(() { _phase = _Phase.over; _newBest = best; });
  }

  int get _stars => _score >= 25 ? 3 : (_score >= 15 ? 2 : (_score >= 6 ? 1 : 0));

  void _answer(int n) {
    if (n == _problem.answer) {
      setState(() {
        _score++;
        _streak++;
        // A streak of five is worth three bonus seconds.
        if (_streak % 5 == 0) _left = math.min(_seconds, _left + 3);
        _wrong = null;
        _problem = mathProblem(mathLevel(_score), _rng);
      });
    } else {
      setState(() {
        _wrong = n;
        _streak = 0;
        _left = math.max(1, _left - 2);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Math Blitz',
    colors: const [Color(0xFFE0446A), Color(0xFFFF8A3D)],
    onBack: widget.onBack,
    trailing: _phase == _Phase.playing
        ? Row(children: [
            Text('Level ${mathLevel(_score)}', style: kidsText(24, color: Colors.white70)),
            const SizedBox(width: 18),
            const Icon(Icons.bolt_rounded, color: Color(0xFFFFF3B0), size: 34),
            Text('$_score', style: kidsText(34)),
          ])
        : null,
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (_phase) {
        _Phase.ready => _StartCard(
          key: const ValueKey('ready'),
          icon: Icons.calculate_rounded,
          text: 'Solve as many as you can in 60 seconds.\nIt gets harder as you go!',
          bestLabel: 'Best',
          game: 'math',
          onStart: _start,
        ),
        _Phase.over => KidsResult(
          key: const ValueKey('over'),
          title: '$_score solved!',
          detail: 'You reached level ${mathLevel(_score)}',
          stars: _stars,
          newBest: _newBest,
          onAgain: _start,
        ),
        _Phase.playing => Column(
          key: const ValueKey('playing'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: _left / _seconds),
                  duration: const Duration(milliseconds: 600),
                  builder: (context, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 16,
                    backgroundColor: Colors.white24,
                    color: _left <= 10 ? const Color(0xFFFFF3B0) : Colors.white,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                  child: Text('${_problem.text} = ?', key: ValueKey(_problem.text + '$_score'), style: kidsText(96)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 32),
              child: Row(
                children: [
                  for (final c in _problem.choices)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: KidsBounce(
                          onTap: () => _answer(c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 130,
                            decoration: BoxDecoration(
                              color: c == _wrong ? Colors.white24 : Colors.white,
                              borderRadius: BorderRadius.circular(32),
                            ),
                            alignment: Alignment.center,
                            child: Text('$c', style: kidsText(56, color: c == _wrong ? Colors.white : const Color(0xFFC2185B))),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      },
    ),
  );
}

// ── Word Scramble ──────────────────────────────────────────────────────

class WordScramble extends StatefulWidget {
  const WordScramble({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<WordScramble> createState() => _WordScrambleState();
}

class _WordScrambleState extends State<WordScramble> {
  static const _rounds = 10;
  final _rng = math.Random();
  _Phase _phase = _Phase.ready;
  late String _category, _word;
  late List<String> _tiles; // scrambled letters
  final _picked = <int>[]; // indexes into _tiles, in answer order
  int _round = 0, _score = 0, _hints = 0;
  bool _shake = false, _solved = false, _newBest = false;
  final _used = <String>{};

  void _start() {
    setState(() {
      _phase = _Phase.playing;
      _round = 0;
      _score = 0;
      _used.clear();
    });
    _next();
  }

  void _next() {
    if (_round >= _rounds) {
      unawaited(_finish());
      return;
    }
    final cats = scrambleWords.keys.toList();
    String cat, word;
    do {
      cat = cats[_rng.nextInt(cats.length)];
      final words = scrambleWords[cat]!;
      word = words[_rng.nextInt(words.length)];
    } while (_used.contains(word));
    _used.add(word);
    setState(() {
      _round++;
      _category = cat;
      _word = word;
      _tiles = scramble(word, _rng);
      _picked.clear();
      _hints = 0;
      _solved = false;
    });
  }

  Future<void> _finish() async {
    final best = await KidsScores.offer('words', _score);
    await KidsScores.addStars(_stars);
    if (mounted) setState(() { _phase = _Phase.over; _newBest = best; });
  }

  int get _stars => _score >= 85 ? 3 : (_score >= 60 ? 2 : (_score >= 30 ? 1 : 0));

  Future<void> _check() async {
    if (_picked.length != _word.length) return;
    if (_picked.map((i) => _tiles[i]).join() == _word) {
      setState(() {
        _solved = true;
        _score += math.max(2, 10 - _hints * 3);
      });
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) _next();
    } else {
      setState(() => _shake = true);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (mounted) setState(() { _shake = false; _picked.clear(); });
    }
  }

  void _tapTile(int i) {
    if (_solved || _picked.contains(i)) return;
    setState(() => _picked.add(i));
    unawaited(_check());
  }

  void _hint() {
    if (_solved) return;
    // Keep the correct prefix, then place the next right letter.
    var keep = 0;
    while (keep < _picked.length && _tiles[_picked[keep]] == _word[keep]) {
      keep++;
    }
    setState(() {
      _picked.removeRange(keep, _picked.length);
      if (keep >= _word.length) return;
      final want = _word[keep];
      final i = List.generate(_tiles.length, (k) => k).firstWhere((k) => !_picked.contains(k) && _tiles[k] == want);
      _picked.add(i);
      _hints++;
    });
    unawaited(_check());
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Word Scramble',
    colors: const [Color(0xFF14A06B), Color(0xFF1C8ED6)],
    onBack: widget.onBack,
    trailing: _phase == _Phase.playing
        ? Text('Word $_round/$_rounds   ·   $_score pts', style: kidsText(24))
        : null,
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (_phase) {
        _Phase.ready => _StartCard(
          key: const ValueKey('ready'),
          icon: Icons.abc_rounded,
          text: 'Unscramble 10 words about animals,\nspace, sports and science.',
          bestLabel: 'Best',
          game: 'words',
          onStart: _start,
        ),
        _Phase.over => KidsResult(
          key: const ValueKey('over'),
          title: '$_score points!',
          detail: '10 words unscrambled',
          stars: _stars,
          newBest: _newBest,
          onAgain: _start,
        ),
        _Phase.playing => Column(
          key: ValueKey('round$_round'),
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
              child: Text(_category, style: kidsText(22)),
            ),
            Expanded(
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: _shake ? 1 : 0),
                  duration: const Duration(milliseconds: 400),
                  builder: (context, t, child) => Transform.translate(offset: Offset(math.sin(t * math.pi * 6) * 14, 0), child: child),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var k = 0; k < _word.length; k++)
                        GestureDetector(
                          onTap: k < _picked.length && !_solved ? () => setState(() => _picked.removeRange(k, _picked.length)) : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: 84,
                            height: 96,
                            decoration: BoxDecoration(
                              color: _solved ? const Color(0xFF3CCB8C) : (k < _picked.length ? Colors.white : Colors.white12),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white54, width: 3),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              k < _picked.length ? _tiles[_picked[k]] : '',
                              style: kidsText(52, color: _solved ? Colors.white : const Color(0xFF0F5E7A)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Wrap(
              spacing: 14,
              children: [
                for (var i = 0; i < _tiles.length; i++)
                  KidsBounce(
                    onTap: () => _tapTile(i),
                    child: AnimatedOpacity(
                      opacity: _picked.contains(i) ? 0.15 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(color: const Color(0xFFFFF3B0), borderRadius: BorderRadius.circular(20)),
                        alignment: Alignment.center,
                        child: Text(_tiles[i], style: kidsText(46, color: const Color(0xFF6A4A00))),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 22, 0, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  KidsButton('Hint', icon: Icons.lightbulb_rounded, size: 22, onTap: _solved ? null : _hint),
                  const SizedBox(width: 16),
                  KidsButton('Skip', icon: Icons.skip_next_rounded, size: 22, color: Colors.white24, ink: Colors.white, onTap: _solved ? null : _next),
                ],
              ),
            ),
          ],
        ),
      },
    ),
  );
}

// ── 2048 ───────────────────────────────────────────────────────────────

class Game2048 extends StatefulWidget {
  const Game2048({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<Game2048> createState() => _Game2048State();
}

class _Game2048State extends State<Game2048> {
  final _rng = math.Random();
  late List<List<int>> _board;
  int _score = 0;
  (int, int)? _fresh;
  bool _over = false, _newBest = false;
  int _awarded = 0;
  Offset _drag = Offset.zero;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _board = List.generate(4, (_) => List.filled(4, 0));
    spawnTile(_board, _rng);
    _fresh = spawnTile(_board, _rng);
    _score = 0;
    _over = false;
    _awarded = 0;
  }

  int get _top => _board.expand((r) => r).fold(0, math.max);

  Future<void> _move(Dir dir) async {
    if (_over) return;
    final res = slideBoard(_board, dir);
    if (!res.moved) return;
    setState(() {
      _board = res.board;
      _score += res.gained;
      _fresh = spawnTile(_board, _rng);
    });
    final stars = _top >= 2048 ? 3 : (_top >= 1024 ? 2 : (_top >= 512 ? 1 : 0));
    if (stars > _awarded) {
      await KidsScores.addStars(stars - _awarded);
      _awarded = stars;
    }
    if (!canMove(_board)) {
      final best = await KidsScores.offer('2048', _score);
      if (mounted) setState(() { _over = true; _newBest = best; });
    }
  }

  static const _tileColors = <int, (Color, Color)>{
    2: (Color(0xFFFFF4E6), Color(0xFF6B4A2B)),
    4: (Color(0xFFFFE7C2), Color(0xFF6B4A2B)),
    8: (Color(0xFFFFB86B), Colors.white),
    16: (Color(0xFFFF9A4D), Colors.white),
    32: (Color(0xFFFF7A3D), Colors.white),
    64: (Color(0xFFFF4D2E), Colors.white),
    128: (Color(0xFFFFD27A), Colors.white),
    256: (Color(0xFFFFC861), Colors.white),
    512: (Color(0xFFFFB547), Colors.white),
    1024: (Color(0xFF8C9BFF), Colors.white),
    2048: (Color(0xFF3CCB8C), Colors.white),
  };

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: '2048',
    colors: const [Color(0xFF8C5BFF), Color(0xFF5B6CFF)],
    onBack: widget.onBack,
    trailing: Text('Score $_score', style: kidsText(30)),
    child: _over
        ? KidsResult(
            title: 'Top tile $_top',
            detail: 'Score $_score',
            stars: _top >= 2048 ? 3 : (_top >= 1024 ? 2 : (_top >= 512 ? 1 : 0)),
            newBest: _newBest,
            onAgain: () => setState(_reset),
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Direction from the distance travelled, not the release velocity:
            // a slow device's velocity tracker can read a real swipe as zero.
            onPanStart: (_) => _drag = Offset.zero,
            onPanUpdate: (d) => _drag += d.delta,
            onPanEnd: (_) {
              final v = _drag;
              if (v.distance < 40) return;
              unawaited(_move(v.dx.abs() > v.dy.abs() ? (v.dx > 0 ? Dir.right : Dir.left) : (v.dy > 0 ? Dir.down : Dir.up)));
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    final side = math.min(box.maxHeight - 24, 640.0);
                    final cell = (side - 5 * 12) / 4;
                    return Container(
                      width: side,
                      height: side,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(28)),
                      child: Column(
                        children: [
                          for (var r = 0; r < 4; r++)
                            Padding(
                              padding: EdgeInsets.only(top: r == 0 ? 0 : 12),
                              child: Row(
                                children: [
                                  for (var c = 0; c < 4; c++)
                                    Padding(
                                      padding: EdgeInsets.only(left: c == 0 ? 0 : 12),
                                      child: _Tile(
                                        key: ValueKey('$r-$c-${_board[r][c]}-${_fresh == (r, c)}'),
                                        value: _board[r][c],
                                        size: cell,
                                        isNew: _fresh == (r, c),
                                        colors: _tileColors[_board[r][c]] ?? (const Color(0xFF1A1340), Colors.white),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 40),
                SizedBox(
                  width: 260,
                  child: Text('Swipe to slide the tiles.\nMatching numbers join.\nReach 2048!', style: kidsText(24, weight: FontWeight.w700)),
                ),
              ],
            ),
          ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.value, required this.size, required this.isNew, required this.colors});
  final int value;
  final double size;
  final bool isNew;
  final (Color, Color) colors;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: value == 0 ? Colors.white.withValues(alpha: 0.12) : colors.$1,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: value == 0
          ? null
          : FittedBox(child: Padding(padding: const EdgeInsets.all(10), child: Text('$value', style: kidsText(54, color: colors.$2)))),
    );
    if (value == 0) return box;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: isNew ? 0.4 : 1.12, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: box,
    );
  }
}

// ── Connect Four ───────────────────────────────────────────────────────

class ConnectFour extends StatefulWidget {
  const ConnectFour({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<ConnectFour> createState() => _ConnectFourState();
}

class _ConnectFourState extends State<ConnectFour> {
  C4 _board = C4();
  bool _hard = false, _thinking = false, _over = false;
  List<(int, int)>? _line;
  (int, int)? _last;
  String _message = 'Your turn: tap a column';
  int _wins = 0;

  void _reset() => setState(() {
    _board = C4();
    _over = false;
    _line = null;
    _last = null;
    _message = 'Your turn: tap a column';
  });

  Future<void> _play(int col) async {
    if (_over || _thinking || !_board.canDrop(col)) return;
    setState(() {
      final r = _board.drop(col, 1)!;
      _last = (r, col);
    });
    if (await _ended()) return;
    setState(() { _thinking = true; _message = 'Thinking…'; });
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final ai = c4AiMove(_board, hard: _hard);
    if (!mounted) return;
    setState(() {
      final r = _board.drop(ai, 2)!;
      _last = (r, ai);
      _thinking = false;
      _message = 'Your turn';
    });
    await _ended();
  }

  Future<bool> _ended() async {
    final line = _board.winLine();
    if (line != null) {
      final youWon = _board.cells[line.first.$1][line.first.$2] == 1;
      setState(() {
        _line = line;
        _over = true;
        _message = youWon ? 'You win!' : 'The computer wins this time';
      });
      if (youWon) {
        _wins++;
        await KidsScores.addStars(_hard ? 3 : 2);
        await KidsScores.offer(_hard ? 'c4hard' : 'c4easy', _wins);
      }
      return true;
    }
    if (_board.full) {
      setState(() { _over = true; _message = "It's a draw!"; });
      await KidsScores.addStars(1);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Connect Four',
    colors: const [Color(0xFF1C8ED6), Color(0xFF283066)],
    onBack: widget.onBack,
    trailing: Row(
      children: [
        _ModeChip(label: 'Easy', on: !_hard, onTap: () { _hard = false; _reset(); }),
        const SizedBox(width: 8),
        _ModeChip(label: 'Hard', on: _hard, onTap: () { _hard = true; _reset(); }),
      ],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final cell = math.min((box.maxHeight - 40) / c4Rows, 92.0);
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF2B48C8), borderRadius: BorderRadius.circular(26)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var c = 0; c < c4Cols; c++)
                    GestureDetector(
                      onTap: () => _play(c),
                      child: Column(
                        children: [
                          for (var r = 0; r < c4Rows; r++)
                            _Disc(
                              size: cell,
                              who: _board.cells[r][c],
                              glow: _line?.contains((r, c)) ?? false,
                              dropFrom: _last == (r, c) ? r + 1 : 0,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 36),
        SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Legend(color: Color(0xFFFF4D6D), label: 'You'),
              const SizedBox(height: 10),
              const _Legend(color: Color(0xFFFFD60A), label: 'Computer'),
              const SizedBox(height: 26),
              Text(_message, style: kidsText(30)),
              const SizedBox(height: 10),
              Text('Wins this session: $_wins', style: kidsText(20, color: Colors.white70, weight: FontWeight.w700)),
              if (_over) ...[
                const SizedBox(height: 22),
                KidsButton('New game', icon: Icons.replay_rounded, size: 24, onTap: _reset),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _Disc extends StatelessWidget {
  const _Disc({required this.size, required this.who, required this.glow, required this.dropFrom});
  final double size;
  final int who;
  final bool glow;

  /// Rows the newest disc falls before landing here (0: no animation).
  final int dropFrom;

  @override
  Widget build(BuildContext context) {
    final color = switch (who) {
      1 => const Color(0xFFFF4D6D),
      2 => const Color(0xFFFFD60A),
      _ => const Color(0xFF14204F),
    };
    final disc = Container(
      width: size - 10,
      height: size - 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: glow ? Border.all(color: Colors.white, width: 5) : null,
        boxShadow: glow ? [const BoxShadow(color: Colors.white70, blurRadius: 16)] : null,
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: dropFrom == 0 || who == 0
            ? disc
            : TweenAnimationBuilder<double>(
                key: ValueKey('drop$who$dropFrom'),
                tween: Tween(begin: -dropFrom * size, end: 0),
                duration: Duration(milliseconds: 120 + dropFrom * 45),
                curve: Curves.bounceOut,
                builder: (context, y, child) => Transform.translate(offset: Offset(0, y), child: child),
                child: disc,
              ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(width: 30, height: 30, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 12),
      Text(label, style: kidsText(24)),
    ],
  );
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KidsBounce(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: on ? Colors.white : Colors.white24,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: kidsText(20, color: on ? const Color(0xFF1C3D9E) : Colors.white)),
    ),
  );
}

// ── Memory Pro ─────────────────────────────────────────────────────────

/// Sixteen cards, eight pairs, against the clock.
class MemoryPro extends StatefulWidget {
  const MemoryPro({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<MemoryPro> createState() => _MemoryProState();
}

class _MemoryProState extends State<MemoryPro> {
  static const _faces = <(IconData, Color)>[
    (Icons.rocket_launch_rounded, Color(0xFF5B6CFF)),
    (Icons.sports_soccer_rounded, Color(0xFF14A06B)),
    (Icons.pets_rounded, Color(0xFFFF8A3D)),
    (Icons.music_note_rounded, Color(0xFFE04FD8)),
    (Icons.bolt_rounded, Color(0xFFFFB300)),
    (Icons.anchor_rounded, Color(0xFF1C8ED6)),
    (Icons.diamond_rounded, Color(0xFF0FA3B1)),
    (Icons.cruelty_free_rounded, Color(0xFF8C5BFF)),
    (Icons.sports_esports_rounded, Color(0xFFFF4D6D)),
    (Icons.public_rounded, Color(0xFF2E7D32)),
    (Icons.local_fire_department_rounded, Color(0xFFFF4D2E)),
    (Icons.headphones_rounded, Color(0xFF455A64)),
  ];
  final _rng = math.Random();
  late List<(IconData, Color)> _cards;
  final _open = <int>{}, _matched = <int>{};
  bool _busy = false, _done = false, _newBest = false;
  int _moves = 0, _seconds = 0;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _deal();
  }

  void _deal() {
    final picks = (List.of(_faces)..shuffle(_rng)).take(8).toList();
    _cards = [...picks, ...picks]..shuffle(_rng);
    _open.clear();
    _matched.clear();
    _moves = 0;
    _seconds = 0;
    _done = false;
    _clock?.cancel();
    _clock = null;
  }

  Future<void> _flip(int i) async {
    if (_busy || _open.contains(i) || _matched.contains(i)) return;
    _clock ??= Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _seconds++));
    setState(() => _open.add(i));
    if (_open.length < 2) return;
    _moves++;
    final [a, b] = _open.toList();
    if (_cards[a] == _cards[b]) {
      setState(() { _matched.addAll(_open); _open.clear(); });
      if (_matched.length == _cards.length) {
        _clock?.cancel();
        final best = await KidsScores.offer('memory', _seconds, lowerIsBetter: true);
        await KidsScores.addStars(_stars);
        if (mounted) setState(() { _done = true; _newBest = best; });
      }
      return;
    }
    _busy = true;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() { _open.clear(); _busy = false; });
  }

  int get _stars => _moves <= 12 ? 3 : (_moves <= 18 ? 2 : 1);

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Memory Pro',
    colors: const [Color(0xFF5B6CFF), Color(0xFF9A6BFF)],
    onBack: widget.onBack,
    trailing: Text('${_seconds}s   ·   $_moves moves', style: kidsText(24)),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: _done
          ? KidsResult(
              key: const ValueKey('done'),
              title: 'All pairs in ${_seconds}s!',
              detail: '$_moves moves',
              stars: _stars,
              newBest: _newBest,
              onAgain: () => setState(_deal),
            )
          : Padding(
              key: const ValueKey('grid'),
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, box) {
                  const n = 4, gap = 14.0;
                  final side = math.min((box.maxWidth - gap * 3) / n, (box.maxHeight - gap * 3) / n);
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var r = 0; r < n; r++) ...[
                          if (r > 0) const SizedBox(height: gap),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var c = 0; c < n; c++) ...[
                                if (c > 0) const SizedBox(width: gap),
                                SizedBox(
                                  width: side,
                                  height: side,
                                  child: _Card(
                                    face: _cards[r * n + c],
                                    open: _open.contains(r * n + c) || _matched.contains(r * n + c),
                                    matched: _matched.contains(r * n + c),
                                    onTap: () => _flip(r * n + c),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.face, required this.open, required this.matched, required this.onTap});
  final (IconData, Color) face;
  final bool open;
  final bool matched;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KidsBounce(
    onTap: onTap,
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: open ? 1 : 0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        final showFace = t >= 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(math.pi * t),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(showFace ? math.pi : 0),
            child: Container(
              decoration: BoxDecoration(
                color: showFace ? (matched ? const Color(0xFFDFFBEA) : Colors.white) : Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 3),
              ),
              alignment: Alignment.center,
              child: showFace
                  ? FittedBox(child: Padding(padding: const EdgeInsets.all(12), child: Icon(face.$1, color: face.$2, size: 64)))
                  : const Icon(Icons.question_mark_rounded, color: Colors.white70, size: 40),
            ),
          ),
        );
      },
    ),
  );
}
