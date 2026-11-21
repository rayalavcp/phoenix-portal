import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'kids_activities.dart';
import 'kids_games.dart';
import 'kids_logic.dart';
import 'kids_more_logic.dart';

/// The Kids Portal's puzzles: Sudoku, Maze, Word Search and Word Guess.

/// A ticking stopwatch in whole seconds, for the timed puzzles.
mixin _Stopwatch<T extends StatefulWidget> on State<T> {
  int seconds = 0;
  Timer? _tick;

  void startClock() {
    _tick?.cancel();
    seconds = 0;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => seconds++);
    });
  }

  void stopClock() => _tick?.cancel();

  String get clock => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}

Widget _choiceChips(List<String> labels, int selected, ValueChanged<int> onPick) => Wrap(
  alignment: WrapAlignment.center,
  spacing: 10,
  runSpacing: 10,
  children: [
    for (var i = 0; i < labels.length; i++)
      KidsBounce(
        onTap: () => onPick(i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: i == selected ? Colors.white : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(labels[i], style: kidsText(20, color: i == selected ? const Color(0xFF1A1340) : Colors.white)),
        ),
      ),
  ],
);

Widget _startScreen({
  required IconData icon,
  required String pitch,
  required Future<int?> best,
  required String Function(int) bestText,
  required Widget options,
  required VoidCallback onStart,
}) => Center(
  child: SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 96, color: Colors.white),
        const SizedBox(height: 8),
        Text(pitch, textAlign: TextAlign.center, style: kidsText(26, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        FutureBuilder<int?>(
          future: best,
          builder: (context, snap) => Text(
            snap.data == null ? 'No best yet' : bestText(snap.data!),
            style: kidsText(20, color: Colors.white70, weight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 18),
        options,
        const SizedBox(height: 24),
        KidsButton('Start', icon: Icons.play_arrow_rounded, onTap: onStart, size: 32),
      ],
    ),
  ),
);

String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

// ── Sudoku ────────────────────────────────────────────────────────────────

class SudokuGame extends StatefulWidget {
  const SudokuGame({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<SudokuGame> createState() => _SudokuGameState();
}

class _SudokuGameState extends State<SudokuGame> with _Stopwatch {
  static const _sizes = [4, 6, 9];
  static const _blanks = {4: 9, 6: 20, 9: 45};
  int _sizeIndex = 0;
  SudokuPuzzle? _puzzle;
  late List<int> _cells;
  int? _selected;
  bool _done = false, _newBest = false;

  int get _size => _sizes[_sizeIndex];
  String get _key => 'sudoku$_size';

  void _start() {
    final p = makeSudoku(_size, _blanks[_size]!, math.Random());
    setState(() {
      _puzzle = p;
      _cells = [...p.puzzle];
      _selected = null;
      _done = false;
    });
    startClock();
  }

  Future<void> _put(int value) async {
    final i = _selected;
    final p = _puzzle;
    if (i == null || p == null || p.puzzle[i] != 0) return;
    setState(() => _cells[i] = value);
    if (!_cells.contains(0) && [for (var k = 0; k < _cells.length; k++) _cells[k] == p.solution[k]].every((e) => e)) {
      stopClock();
      final best = await KidsScores.offer(_key, seconds, lowerIsBetter: true);
      await KidsScores.addStars(_size == 4 ? 1 : (_size == 6 ? 2 : 3));
      if (mounted) setState(() { _done = true; _newBest = best; });
    }
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Sudoku',
    colors: const [Color(0xFF283066), Color(0xFF5B6CFF)],
    onBack: widget.onBack,
    trailing: _puzzle != null && !_done ? Text(clock, style: kidsText(30)) : null,
    child: _puzzle == null
        ? _startScreen(
            icon: Icons.grid_on_rounded,
            pitch: 'Every row, column and box gets each number once',
            best: KidsScores.best(_key),
            bestText: (b) => 'Best $_size×$_size: ${_mmss(b)}',
            options: _choiceChips(const ['4×4 Easy', '6×6 Medium', '9×9 Hard'], _sizeIndex, (i) => setState(() => _sizeIndex = i)),
            onStart: _start,
          )
        : _done
        ? KidsResult(
            title: 'Solved!',
            detail: '$_size×$_size in $clock',
            stars: _size == 4 ? 1 : (_size == 6 ? 2 : 3),
            newBest: _newBest,
            onAgain: () => setState(() => _puzzle = null),
          )
        : _board(),
  );

  Widget _board() {
    final p = _puzzle!;
    final (bh, bw) = sudokuBox(_size);
    return LayoutBuilder(
      builder: (context, box) {
        final side = math.min(box.maxHeight - 24, box.maxWidth * 0.62);
        final cell = side / _size;
        final grid = SizedBox(
          width: side,
          height: side,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1A1340), width: 3),
            ),
            child: Stack(
              children: [
                for (var i = 0; i < _size * _size; i++)
                  Positioned(
                    left: (i % _size) * cell,
                    top: (i ~/ _size) * cell,
                    width: cell,
                    height: cell,
                    child: GestureDetector(
                      onTap: p.puzzle[i] == 0 ? () => setState(() => _selected = i) : null,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == _selected
                              ? const Color(0xFFFFE08A)
                              : (_selected != null &&
                                    (i ~/ _size == _selected! ~/ _size || i % _size == _selected! % _size))
                              ? const Color(0xFFEFF1FF)
                              : null,
                          border: Border(
                            right: BorderSide(
                              color: const Color(0xFF1A1340),
                              width: (i % _size) % bw == bw - 1 && i % _size != _size - 1 ? 2.5 : 0.5,
                            ),
                            bottom: BorderSide(
                              color: const Color(0xFF1A1340),
                              width: (i ~/ _size) % bh == bh - 1 && i ~/ _size != _size - 1 ? 2.5 : 0.5,
                            ),
                          ),
                        ),
                        child: _cells[i] == 0
                            ? null
                            : Text(
                                '${_cells[i]}',
                                style: kidsText(
                                  cell * 0.55,
                                  color: p.puzzle[i] != 0
                                      ? const Color(0xFF1A1340)
                                      : (_cells[i] == p.solution[i] ? const Color(0xFF3A52E0) : const Color(0xFFE0303C)),
                                ),
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
        final pad = Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var v = 1; v <= _size; v++)
              KidsBounce(
                onTap: () => unawaited(_put(v)),
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Text('$v', style: kidsText(36, color: const Color(0xFF283066))),
                ),
              ),
            KidsBounce(
              onTap: () {
                final i = _selected;
                if (i != null && p.puzzle[i] == 0) setState(() => _cells[i] = 0);
              },
              child: Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.backspace_rounded, color: Colors.white, size: 34),
              ),
            ),
          ],
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
          child: Row(
            children: [
              grid,
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Tap a square, then a number', textAlign: TextAlign.center, style: kidsText(20, weight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    pad,
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Maze ──────────────────────────────────────────────────────────────────

class MazeGame extends StatefulWidget {
  const MazeGame({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<MazeGame> createState() => _MazeGameState();
}

class _MazeGameState extends State<MazeGame> with _Stopwatch {
  static const _sizes = [(8, 6), (12, 8), (18, 12)];
  int _sizeIndex = 0;
  Maze? _maze;
  int _x = 0, _y = 0;
  bool _done = false, _newBest = false;
  final _trail = <int>{};

  void _start() {
    final (w, h) = _sizes[_sizeIndex];
    setState(() {
      _maze = makeMaze(w, h, math.Random());
      _x = 0;
      _y = 0;
      _done = false;
      _trail
        ..clear()
        ..add(0);
    });
    startClock();
  }

  Future<void> _move(int dx, int dy) async {
    final m = _maze;
    if (m == null || _done) return;
    // Slide along a corridor until a junction: fewer taps for small hands.
    var x = _x, y = _y, moved = false;
    while (m.open(x, y, dx, dy)) {
      x += dx;
      y += dy;
      moved = true;
      _trail.add(y * m.width + x);
      final exits = [(0, -1), (1, 0), (0, 1), (-1, 0)].where((d) => m.open(x, y, d.$1, d.$2)).length;
      if (exits != 2 || (x == m.width - 1 && y == m.height - 1)) break;
      // Keep going straight only while the corridor does.
      if (!m.open(x, y, dx, dy)) break;
    }
    if (!moved) return;
    setState(() {
      _x = x;
      _y = y;
    });
    if (x == m.width - 1 && y == m.height - 1) {
      stopClock();
      final best = await KidsScores.offer('maze', seconds, lowerIsBetter: true);
      await KidsScores.offerChallenge('maze', seconds);
      await KidsScores.addStars(_sizeIndex + 1);
      if (mounted) setState(() { _done = true; _newBest = best; });
    }
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Maze',
    colors: const [Color(0xFF128A5A), Color(0xFF52D69F)],
    onBack: widget.onBack,
    trailing: _maze != null && !_done ? Text(clock, style: kidsText(30)) : null,
    child: _maze == null
        ? _startScreen(
            icon: Icons.route_rounded,
            pitch: 'Lead the star to the flag. Swipe or use the arrows.',
            best: KidsScores.best('maze'),
            bestText: (b) => 'Fastest: ${_mmss(b)}',
            options: _choiceChips(const ['Small', 'Medium', 'Big'], _sizeIndex, (i) => setState(() => _sizeIndex = i)),
            onStart: _start,
          )
        : _done
        ? KidsResult(
            title: 'You escaped!',
            detail: 'in $clock',
            stars: _sizeIndex + 1,
            newBest: _newBest,
            onAgain: () => setState(() => _maze = null),
          )
        : _board(),
  );

  Widget _arrow(IconData icon, int dx, int dy) => KidsBounce(
    onTap: () => unawaited(_move(dx, dy)),
    child: Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Icon(icon, size: 52, color: const Color(0xFF128A5A)),
    ),
  );

  Widget _board() {
    final m = _maze!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onPanEnd: (d) {
                final v = d.velocity.pixelsPerSecond;
                if (v.distance < 100) return;
                if (v.dx.abs() > v.dy.abs()) {
                  unawaited(_move(v.dx > 0 ? 1 : -1, 0));
                } else {
                  unawaited(_move(0, v.dy > 0 ? 1 : -1));
                }
              },
              child: Center(
                child: AspectRatio(
                  aspectRatio: m.width / m.height,
                  child: CustomPaint(painter: _MazePainter(m, _x, _y, _trail)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _arrow(Icons.arrow_upward_rounded, 0, -1),
              const SizedBox(height: 10),
              Row(
                children: [
                  _arrow(Icons.arrow_back_rounded, -1, 0),
                  const SizedBox(width: 92),
                  _arrow(Icons.arrow_forward_rounded, 1, 0),
                ],
              ),
              const SizedBox(height: 10),
              _arrow(Icons.arrow_downward_rounded, 0, 1),
            ],
          ),
        ],
      ),
    );
  }
}

class _MazePainter extends CustomPainter {
  _MazePainter(this.maze, this.x, this.y, this.trail);
  final Maze maze;
  final int x, y;
  final Set<int> trail;

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / maze.width, ch = size.height / maze.height;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)), Paint()..color = Colors.white);
    final trailPaint = Paint()..color = const Color(0xFFFFE08A);
    for (final t in trail) {
      canvas.drawRect(Rect.fromLTWH((t % maze.width) * cw + cw * 0.2, (t ~/ maze.width) * ch + ch * 0.2, cw * 0.6, ch * 0.6), trailPaint);
    }
    final wall = Paint()
      ..color = const Color(0xFF1A1340)
      ..strokeWidth = math.max(2, cw * 0.1)
      ..strokeCap = StrokeCap.round;
    for (var j = 0; j < maze.height; j++) {
      for (var i = 0; i < maze.width; i++) {
        final w = maze.walls[j * maze.width + i];
        final l = i * cw, t = j * ch, r = l + cw, b = t + ch;
        if (w & 1 != 0) canvas.drawLine(Offset(l, t), Offset(r, t), wall);
        if (w & 2 != 0) canvas.drawLine(Offset(r, t), Offset(r, b), wall);
        if (w & 4 != 0) canvas.drawLine(Offset(l, b), Offset(r, b), wall);
        if (w & 8 != 0) canvas.drawLine(Offset(l, t), Offset(l, b), wall);
      }
    }
    void glyph(IconData icon, int gx, int gy, Color color) {
      final tp = TextPainter(
        text: TextSpan(text: String.fromCharCode(icon.codePoint), style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: math.min(cw, ch) * 0.8, color: color)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(gx * cw + (cw - tp.width) / 2, gy * ch + (ch - tp.height) / 2));
    }

    glyph(Icons.flag_rounded, maze.width - 1, maze.height - 1, const Color(0xFFE0303C));
    glyph(Icons.star_rounded, x, y, const Color(0xFFF28A1E));
  }

  @override
  bool shouldRepaint(_MazePainter old) => true;
}

// ── Word Search ───────────────────────────────────────────────────────────

class WordSearchGame extends StatefulWidget {
  const WordSearchGame({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<WordSearchGame> createState() => _WordSearchGameState();
}

class _WordSearchGameState extends State<WordSearchGame> with _Stopwatch {
  int _theme = 0;
  WordSearch? _ws;
  final _found = <String>{};
  int? _from;
  List<int> _drag = const [];
  bool _done = false, _newBest = false;

  void _start() {
    final theme = kidsWordThemes.keys.elementAt(_theme);
    setState(() {
      _ws = makeWordSearch(kidsWordThemes[theme]!, 10, 6, math.Random());
      _found.clear();
      _done = false;
    });
    startClock();
  }

  int? _cellAt(Offset p, double side) {
    final ws = _ws!;
    final cell = side / ws.size;
    final x = (p.dx / cell).floor(), y = (p.dy / cell).floor();
    if (x < 0 || y < 0 || x >= ws.size || y >= ws.size) return null;
    return y * ws.size + x;
  }

  Future<void> _release() async {
    final ws = _ws!;
    final picked = _drag;
    setState(() {
      _from = null;
      _drag = const [];
    });
    for (final e in ws.places.entries) {
      if (_found.contains(e.key)) continue;
      final cells = e.value;
      if (picked.length == cells.length &&
          (List.generate(cells.length, (i) => picked[i] == cells[i]).every((x) => x) ||
              List.generate(cells.length, (i) => picked[i] == cells[cells.length - 1 - i]).every((x) => x))) {
        setState(() => _found.add(e.key));
      }
    }
    if (_found.length == ws.words.length) {
      stopClock();
      final best = await KidsScores.offer('wordsearch', seconds, lowerIsBetter: true);
      await KidsScores.addStars(seconds < 120 ? 3 : (seconds < 240 ? 2 : 1));
      if (mounted) setState(() { _done = true; _newBest = best; });
    }
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Word Search',
    colors: const [Color(0xFFE08A00), Color(0xFFE0446A)],
    onBack: widget.onBack,
    trailing: _ws != null && !_done ? Text(clock, style: kidsText(30)) : null,
    child: _ws == null
        ? _startScreen(
            icon: Icons.manage_search_rounded,
            pitch: 'Find the hidden words. Drag across the letters.',
            best: KidsScores.best('wordsearch'),
            bestText: (b) => 'Fastest: ${_mmss(b)}',
            options: _choiceChips(kidsWordThemes.keys.toList(), _theme, (i) => setState(() => _theme = i)),
            onStart: _start,
          )
        : _done
        ? KidsResult(
            title: 'All found!',
            detail: 'in $clock',
            stars: seconds < 120 ? 3 : (seconds < 240 ? 2 : 1),
            newBest: _newBest,
            onAgain: () => setState(() => _ws = null),
          )
        : _board(),
  );

  Widget _board() {
    final ws = _ws!;
    final foundCells = {for (final w in _found) ...ws.places[w]!};
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: LayoutBuilder(
        builder: (context, box) {
          final side = math.min(box.maxHeight, box.maxWidth * 0.62);
          final cell = side / ws.size;
          return Row(
            children: [
              GestureDetector(
                onPanStart: (d) {
                  final c = _cellAt(d.localPosition, side);
                  if (c != null) setState(() { _from = c; _drag = [c]; });
                },
                onPanUpdate: (d) {
                  final c = _cellAt(d.localPosition, side);
                  if (c != null && _from != null) setState(() => _drag = wordSearchLine(ws.size, _from!, c));
                },
                onPanEnd: (_) => unawaited(_release()),
                child: Container(
                  width: side,
                  height: side,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Stack(
                    children: [
                      for (var i = 0; i < ws.size * ws.size; i++)
                        Positioned(
                          left: (i % ws.size) * cell,
                          top: (i ~/ ws.size) * cell,
                          width: cell,
                          height: cell,
                          child: Container(
                            margin: const EdgeInsets.all(2),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _drag.contains(i)
                                  ? const Color(0xFFFFE08A)
                                  : foundCells.contains(i)
                                  ? const Color(0xFF8FE3B8)
                                  : null,
                              borderRadius: BorderRadius.circular(cell / 2),
                            ),
                            child: Text(ws.letters[i], style: kidsText(cell * 0.5, color: const Color(0xFF1A1340))),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${_found.length} of ${ws.words.length} found', style: kidsText(24)),
                    const SizedBox(height: 12),
                    for (final w in ws.words)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(_found.contains(w) ? Icons.check_circle_rounded : Icons.circle_outlined, color: Colors.white, size: 26),
                            const SizedBox(width: 10),
                            Text(
                              w,
                              style: kidsText(24, color: _found.contains(w) ? Colors.white54 : Colors.white).copyWith(
                                decoration: _found.contains(w) ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Word Guess ────────────────────────────────────────────────────────────

class WordGuess extends StatefulWidget {
  const WordGuess({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<WordGuess> createState() => _WordGuessState();
}

class _WordGuessState extends State<WordGuess> {
  static const _lives = 7;
  final _rng = math.Random();
  late String _word;
  final _guessed = <String>{};
  int _streak = 0;
  bool _over = false, _won = false, _newBest = false;

  int get _misses => _guessed.where((l) => !_word.contains(l)).length;

  @override
  void initState() {
    super.initState();
    _next();
  }

  void _next() => setState(() {
    _word = kidsGuessWords[_rng.nextInt(kidsGuessWords.length)];
    _guessed.clear();
    _over = false;
  });

  Future<void> _guess(String letter) async {
    if (_over || _guessed.contains(letter)) return;
    setState(() => _guessed.add(letter));
    final won = _word.split('').every(_guessed.contains);
    if (won || _misses >= _lives) {
      if (won) _streak++;
      final best = won ? await KidsScores.offer('guess', _streak) : false;
      if (won) await KidsScores.addStars(_misses <= 2 ? 2 : 1);
      if (mounted) {
        setState(() {
          _over = true;
          _won = won;
          _newBest = best;
          if (!won) _streak = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Word Guess',
    colors: const [Color(0xFF7B5CFF), Color(0xFF1C8ED6)],
    onBack: widget.onBack,
    trailing: Text('Streak $_streak', style: kidsText(28)),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        children: [
          // One balloon floats away per miss.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _lives; i++)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: i < _lives - _misses ? 1 : 0.15,
                  child: Icon(Icons.circle, size: 40, color: [const Color(0xFFFF6B6B), const Color(0xFFFFD27A), const Color(0xFF52D69F), const Color(0xFF63C3FF), const Color(0xFFB06BFF)][i % 5]),
                ),
            ],
          ),
          Text('${_lives - _misses} balloons left', style: kidsText(18, color: Colors.white70)),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _over ? _word.split('').join(' ') : maskedWord(_word, _guessed),
              style: kidsText(64),
            ),
          ),
          const Spacer(),
          if (_over)
            Column(
              children: [
                Text(_won ? 'You got it!' : 'The word was $_word', style: kidsText(32)),
                if (_newBest)
                  Text('New best streak!', style: kidsText(22, color: const Color(0xFFFFD27A))),
                const SizedBox(height: 12),
                KidsButton('Next word', icon: Icons.arrow_forward_rounded, onTap: _next),
              ],
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''))
                  KidsBounce(
                    onTap: _guessed.contains(l) ? null : () => unawaited(_guess(l)),
                    child: Container(
                      width: 62,
                      height: 62,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: !_guessed.contains(l)
                            ? Colors.white
                            : _word.contains(l)
                            ? const Color(0xFF52D69F)
                            : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(l, style: kidsText(28, color: const Color(0xFF1A1340))),
                    ),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}
