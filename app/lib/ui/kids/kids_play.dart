import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'kids_activities.dart';
import 'kids_games.dart';
import 'kids_logic.dart';
import 'kids_more_logic.dart';

/// The Kids Portal's play shelf: Tic-Tac-Toe, Snake, Simon Says, Pixel
/// Paint and the Piano.

/// Plays the piano's tones through the app's own sound player. The notes
/// are synthesized once into small WAV files in the cache.
class KidsTones {
  KidsTones(this._play);

  /// SoundManager.playFile: an id and a local file.
  final Future<bool> Function(String id, String path) _play;

  final _paths = <int, String>{};
  int _n = 0;
  Future<void>? _ready;

  Future<void> _prepare() async {
    final dir = await getTemporaryDirectory();
    for (var i = 0; i < kidsPianoNotes.length; i++) {
      final file = File('${dir.path}/phx_note_$i.wav');
      if (!file.existsSync()) await file.writeAsBytes(toneWav(kidsPianoNotes[i].$2));
      _paths[i] = file.path;
    }
  }

  /// Get the files ready ahead of the first key press.
  Future<void> warm() => _ready ??= _prepare().catchError((_) {});

  Future<void> note(int index) async {
    await warm();
    final path = _paths[index];
    if (path == null) return;
    try {
      await _play('kidnote${_n++ % 8}', path);
    } on MissingPluginException {
      // No native player (tests): silence.
    } on PlatformException {
      // A busy or missing output: the key still lights up.
    }
  }
}

// ── Tic-Tac-Toe ───────────────────────────────────────────────────────────

class TicTacToe extends StatefulWidget {
  const TicTacToe({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<TicTacToe> createState() => _TicTacToeState();
}

class _TicTacToeState extends State<TicTacToe> {
  final _rng = math.Random();
  var _board = List<String>.filled(9, '');
  bool _hard = false, _thinking = false;
  int _wins = 0, _draws = 0, _losses = 0;

  String? get _result => tttWinner(_board);

  Future<void> _tap(int i) async {
    if (_board[i].isNotEmpty || _result != null || _thinking) return;
    setState(() => _board[i] = 'X');
    if (_result == null) {
      setState(() => _thinking = true);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      setState(() {
        _board[tttMove(_board, _hard, _rng)] = 'O';
        _thinking = false;
      });
    }
    final r = _result;
    if (r == null) return;
    setState(() {
      if (r == 'X') _wins++;
      if (r == 'O') _losses++;
      if (r == 'draw') _draws++;
    });
    if (r == 'X') {
      await KidsScores.offer(_hard ? 'ttthard' : 'ttteasy', _wins);
      await KidsScores.addStars(_hard ? 3 : 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final line = tttLine(_board) ?? const [];
    final r = _result;
    return KidsActivityFrame(
      title: 'Tic-Tac-Toe',
      colors: const [Color(0xFFE0446A), Color(0xFF8C5BFF)],
      onBack: widget.onBack,
      trailing: Text('You $_wins · Draw $_draws · Me $_losses', style: kidsText(24)),
      child: LayoutBuilder(
        builder: (context, box) {
          final side = math.min(box.maxHeight - 24, box.maxWidth * 0.55);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: side,
                height: side,
                child: GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (var i = 0; i < 9; i++)
                      KidsBounce(
                        onTap: () => unawaited(_tap(i)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: line.contains(i) ? const Color(0xFFFFD27A) : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _board[i],
                            style: kidsText(side / 5, color: _board[i] == 'X' ? const Color(0xFFE0446A) : const Color(0xFF5B6CFF)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    r == null
                        ? (_thinking ? 'Hmm, thinking…' : 'Your turn! You are X')
                        : r == 'X'
                        ? 'You win!'
                        : r == 'O'
                        ? 'I win this time!'
                        : "It's a draw!",
                    style: kidsText(30),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      for (final (label, hard) in const [('Easy', false), ('Hard', true)])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: KidsBounce(
                            onTap: () => setState(() {
                              _hard = hard;
                              _board = List.filled(9, '');
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                color: _hard == hard ? Colors.white : Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Text(label, style: kidsText(22, color: _hard == hard ? const Color(0xFF1A1340) : Colors.white)),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  KidsButton('New game', icon: Icons.replay_rounded, onTap: () => setState(() => _board = List.filled(9, ''))),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Snake ─────────────────────────────────────────────────────────────────

class SnakeGame extends StatefulWidget {
  const SnakeGame({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<SnakeGame> createState() => _SnakeGameState();
}

class _SnakeGameState extends State<SnakeGame> {
  static const _w = 20, _h = 13;
  final _rng = math.Random();
  List<(int, int)> _snake = const [];
  (int, int) _dir = (1, 0), _nextDir = (1, 0);
  (int, int) _food = (10, 6);
  Timer? _timer;
  bool _playing = false, _over = false, _newBest = false;

  /// Slow, Normal, Fast: milliseconds a step.
  static const _speeds = [270, 190, 120];
  int _level = 1;

  void _start() {
    _timer?.cancel();
    setState(() {
      _snake = [(5, 6), (4, 6), (3, 6)];
      _dir = (1, 0);
      _nextDir = (1, 0);
      _placeFood();
      _playing = true;
      _over = false;
    });
    _timer = Timer.periodic(Duration(milliseconds: _speeds[_level]), (_) => _step());
  }

  void _placeFood() {
    do {
      _food = (_rng.nextInt(_w), _rng.nextInt(_h));
    } while (_snake.contains(_food));
  }

  void _turn(int dx, int dy) {
    // No turning straight back into yourself.
    if (dx == -_dir.$1 && dy == -_dir.$2) return;
    _nextDir = (dx, dy);
  }

  Future<void> _step() async {
    _dir = _nextDir;
    final head = (_snake.first.$1 + _dir.$1, _snake.first.$2 + _dir.$2);
    if (head.$1 < 0 || head.$2 < 0 || head.$1 >= _w || head.$2 >= _h || _snake.contains(head)) {
      _timer?.cancel();
      final length = _snake.length;
      final best = await KidsScores.offer('snake', length);
      await KidsScores.offerChallenge('snake', length);
      await KidsScores.addStars(length >= 20 ? 3 : (length >= 12 ? 2 : (length >= 7 ? 1 : 0)));
      if (mounted) setState(() { _over = true; _playing = false; _newBest = best; });
      return;
    }
    setState(() {
      _snake = [head, ..._snake];
      if (head == _food) {
        _placeFood();
      } else {
        _snake.removeLast();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _arrow(IconData icon, int dx, int dy) => KidsBounce(
    onTap: () => _turn(dx, dy),
    child: Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Icon(icon, size: 52, color: const Color(0xFF128A5A)),
    ),
  );

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Snake',
    colors: const [Color(0xFF1F8A4C), Color(0xFF14A06B)],
    onBack: widget.onBack,
    trailing: _playing ? Text('Length ${_snake.length}', style: kidsText(30)) : null,
    child: _over
        ? KidsResult(
            title: 'Bonk!',
            detail: 'Your snake grew to ${_snake.length}',
            stars: _snake.length >= 20 ? 3 : (_snake.length >= 12 ? 2 : (_snake.length >= 7 ? 1 : 0)),
            newBest: _newBest,
            onAgain: _start,
          )
        : !_playing
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gesture_rounded, size: 96, color: Colors.white),
                Text('Eat the apples, grow long, miss the walls!', style: kidsText(26, weight: FontWeight.w700)),
                const SizedBox(height: 8),
                FutureBuilder<int?>(
                  future: KidsScores.best('snake'),
                  builder: (context, snap) => Text(snap.data == null ? 'No best yet' : 'Longest: ${snap.data}', style: kidsText(20, color: Colors.white70)),
                ),
                const SizedBox(height: 18),
                kidsLevelChips(const ['Slow', 'Normal', 'Fast'], _level, (i) => setState(() => _level = i)),
                const SizedBox(height: 24),
                KidsButton('Start', icon: Icons.play_arrow_rounded, onTap: _start, size: 32),
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onPanEnd: (d) {
                      final v = d.velocity.pixelsPerSecond;
                      if (v.distance < 80) return;
                      v.dx.abs() > v.dy.abs() ? _turn(v.dx > 0 ? 1 : -1, 0) : _turn(0, v.dy > 0 ? 1 : -1);
                    },
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _w / _h,
                        child: CustomPaint(painter: _SnakePainter(_snake, _food, _w, _h)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _arrow(Icons.arrow_upward_rounded, 0, -1),
                    const SizedBox(height: 10),
                    Row(children: [
                      _arrow(Icons.arrow_back_rounded, -1, 0),
                      const SizedBox(width: 92),
                      _arrow(Icons.arrow_forward_rounded, 1, 0),
                    ]),
                    const SizedBox(height: 10),
                    _arrow(Icons.arrow_downward_rounded, 0, 1),
                  ],
                ),
              ],
            ),
          ),
  );
}

class _SnakePainter extends CustomPainter {
  _SnakePainter(this.snake, this.food, this.w, this.h);
  final List<(int, int)> snake;
  final (int, int) food;
  final int w, h;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / w;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)), Paint()..color = const Color(0xFF0E3B24));
    canvas.drawCircle(Offset((food.$1 + 0.5) * c, (food.$2 + 0.5) * c), c * 0.4, Paint()..color = const Color(0xFFFF4D4D));
    for (var i = 0; i < snake.length; i++) {
      final (x, y) = snake[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x * c + 1.5, y * c + 1.5, c - 3, c - 3), Radius.circular(c * 0.3)),
        Paint()..color = i == 0 ? const Color(0xFFFFD27A) : Color.lerp(const Color(0xFF52D69F), const Color(0xFF14A06B), i / snake.length)!,
      );
    }
  }

  @override
  bool shouldRepaint(_SnakePainter old) => true;
}

// ── Simon Says ────────────────────────────────────────────────────────────

class SimonSays extends StatefulWidget {
  const SimonSays({super.key, required this.onBack, required this.tones});
  final VoidCallback onBack;
  final KidsTones tones;

  @override
  State<SimonSays> createState() => _SimonSaysState();
}

class _SimonSaysState extends State<SimonSays> {
  static const _colors = [Color(0xFF52D69F), Color(0xFFFF6B6B), Color(0xFFFFD27A), Color(0xFF63C3FF)];
  static const _notes = [0, 2, 4, 7];
  final _rng = math.Random();
  final _seq = <int>[];
  int _input = 0;
  int? _lit;
  bool _showing = false, _over = false, _started = false, _newBest = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.tones.warm());
  }

  Future<void> _flash(int pad, {int millis = 420}) async {
    setState(() => _lit = pad);
    unawaited(widget.tones.note(_notes[pad]));
    await Future<void>.delayed(Duration(milliseconds: millis));
    if (mounted) setState(() => _lit = null);
    await Future<void>.delayed(const Duration(milliseconds: 160));
  }

  Future<void> _nextRound() async {
    _seq.add(_rng.nextInt(4));
    _input = 0;
    setState(() => _showing = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    for (final p in _seq) {
      if (!mounted) return;
      await _flash(p, millis: math.max(220, 480 - _seq.length * 15));
    }
    if (mounted) setState(() => _showing = false);
  }

  void _start() {
    _seq.clear();
    setState(() {
      _started = true;
      _over = false;
    });
    unawaited(_nextRound());
  }

  Future<void> _tap(int pad) async {
    if (_showing || _over || !_started) return;
    unawaited(_flash(pad, millis: 220));
    if (pad != _seq[_input]) {
      final level = _seq.length - 1;
      final best = await KidsScores.offer('simon', level);
      await KidsScores.offerChallenge('simon', level);
      await KidsScores.addStars(level >= 10 ? 3 : (level >= 6 ? 2 : (level >= 3 ? 1 : 0)));
      if (mounted) setState(() { _over = true; _newBest = best; });
      return;
    }
    _input++;
    if (_input == _seq.length) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (mounted) unawaited(_nextRound());
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = math.max(0, _seq.length - (_over ? 1 : 0));
    return KidsActivityFrame(
      title: 'Simon Says',
      colors: const [Color(0xFF283066), Color(0xFF7B5CFF)],
      onBack: widget.onBack,
      trailing: _started ? Text('Level $level', style: kidsText(30)) : null,
      child: _over
          ? KidsResult(
              title: 'Great memory!',
              detail: 'You remembered $level in a row',
              stars: level >= 10 ? 3 : (level >= 6 ? 2 : (level >= 3 ? 1 : 0)),
              newBest: _newBest,
              onAgain: _start,
            )
          : LayoutBuilder(
              builder: (context, box) {
                final side = math.min(box.maxHeight - 24, box.maxWidth * 0.55);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: side,
                      height: side,
                      child: GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (var i = 0; i < 4; i++)
                            GestureDetector(
                              onTapDown: (_) => unawaited(_tap(i)),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 90),
                                decoration: BoxDecoration(
                                  color: _lit == i ? Colors.white : _colors[i].withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(36),
                                  boxShadow: _lit == i ? [BoxShadow(color: _colors[i], blurRadius: 40, spreadRadius: 6)] : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 32),
                    SizedBox(
                      width: 280,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            !_started ? 'Watch the lights, then copy them!' : (_showing ? 'Watch…' : 'Your turn!'),
                            textAlign: TextAlign.center,
                            style: kidsText(30),
                          ),
                          const SizedBox(height: 20),
                          if (!_started) KidsButton('Start', icon: Icons.play_arrow_rounded, onTap: _start, size: 30),
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

// ── Pixel Paint ───────────────────────────────────────────────────────────

class PixelPaint extends StatefulWidget {
  const PixelPaint({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<PixelPaint> createState() => _PixelPaintState();
}

class _PixelPaintState extends State<PixelPaint> {
  String _picture = kidsPixelArt.keys.first;
  int _color = 1;
  late List<int> _painted;
  bool _celebrated = false;

  (List<int>, List<String>) get _art => kidsPixelArt[_picture]!;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    final rows = _art.$2;
    _painted = List<int>.filled(rows.length * rows.first.length, 0);
    _celebrated = false;
  }

  bool get _complete {
    final rows = _art.$2;
    final w = rows.first.length;
    for (var i = 0; i < _painted.length; i++) {
      final want = int.parse(rows[i ~/ w][i % w]);
      if (want != 0 && _painted[i] != want) return false;
    }
    return true;
  }

  Future<void> _paint(int i) async {
    final rows = _art.$2;
    final w = rows.first.length;
    if (int.parse(rows[i ~/ w][i % w]) == 0) return;
    setState(() => _painted[i] = _color);
    if (_complete && !_celebrated) {
      _celebrated = true;
      await KidsScores.addStars(1);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Beautiful $_picture! ⭐')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final (palette, rows) = _art;
    final w = rows.first.length, h = rows.length;
    return KidsActivityFrame(
      title: 'Pixel Paint',
      colors: const [Color(0xFFE0446A), Color(0xFFF5A623)],
      onBack: widget.onBack,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
        child: Row(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: w / h,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final cell = box.maxWidth / w;
                      return Container(
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                        child: Stack(
                          children: [
                            for (var i = 0; i < w * h; i++)
                              if (int.parse(rows[i ~/ w][i % w]) != 0)
                                Positioned(
                                  left: (i % w) * cell,
                                  top: (i ~/ w) * cell,
                                  width: cell,
                                  height: cell,
                                  child: GestureDetector(
                                    onTap: () => unawaited(_paint(i)),
                                    child: Container(
                                      margin: const EdgeInsets.all(1),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: _painted[i] == 0 ? const Color(0xFFF1F2F6) : Color(palette[_painted[i]]),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: _painted[i] == int.parse(rows[i ~/ w][i % w])
                                          ? null
                                          : Text(rows[i ~/ w][i % w], style: kidsText(cell * 0.4, color: const Color(0xFF8A8FA3))),
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 24),
            SizedBox(
              width: 260,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Colour by number', style: kidsText(26)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var k = 1; k < palette.length; k++)
                        KidsBounce(
                          onTap: () => setState(() => _color = k),
                          child: Container(
                            width: 64,
                            height: 64,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Color(palette[k]),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: _color == k ? 6 : 2),
                            ),
                            child: Text('$k', style: kidsText(26, color: Colors.white).copyWith(shadows: const [Shadow(blurRadius: 4)])),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final name in kidsPixelArt.keys)
                        KidsBounce(
                          onTap: () => setState(() {
                            _picture = name;
                            _color = 1;
                            _reset();
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: _picture == name ? Colors.white : Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(name, style: kidsText(18, color: _picture == name ? const Color(0xFF1A1340) : Colors.white)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Piano ─────────────────────────────────────────────────────────────────

class KidsPiano extends StatefulWidget {
  const KidsPiano({super.key, required this.onBack, required this.tones});
  final VoidCallback onBack;
  final KidsTones tones;

  @override
  State<KidsPiano> createState() => _KidsPianoState();
}

class _KidsPianoState extends State<KidsPiano> {
  /// Songs as key indexes into kidsPianoNotes.
  static const _songs = <String, List<int>>{
    'Twinkle Twinkle': [0, 0, 4, 4, 5, 5, 4, 3, 3, 2, 2, 1, 1, 0],
    'Mary Had a Little Lamb': [2, 1, 0, 1, 2, 2, 2, 1, 1, 1, 2, 4, 4],
    'Ode to Joy': [2, 2, 3, 4, 4, 3, 2, 1, 0, 0, 1, 2, 2, 1, 1],
    'Happy Birthday': [0, 0, 1, 0, 3, 2, 0, 0, 1, 0, 4, 3],
  };
  static const _keyColors = [
    Color(0xFFFF6B6B), Color(0xFFF28A1E), Color(0xFFFFD27A), Color(0xFF52D69F),
    Color(0xFF63C3FF), Color(0xFF5B6CFF), Color(0xFFB06BFF),
  ];

  String? _song;
  int _step = 0;
  int? _pressed;

  @override
  void initState() {
    super.initState();
    unawaited(widget.tones.warm());
  }

  void _press(int i) {
    unawaited(widget.tones.note(i));
    setState(() {
      _pressed = i;
      final song = _song == null ? null : _songs[_song];
      if (song != null && song[_step] == i) {
        _step++;
        if (_step >= song.length) {
          _step = 0;
          unawaited(KidsScores.addStars(1));
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('You played $_song! ⭐')));
          _song = null;
        }
      }
    });
    Future<void>.delayed(const Duration(milliseconds: 160), () {
      if (mounted && _pressed == i) setState(() => _pressed = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final song = _song == null ? null : _songs[_song];
    final hint = song?[_step];
    return KidsActivityFrame(
      title: 'Piano',
      colors: const [Color(0xFF1A1340), Color(0xFF5B6CFF)],
      onBack: widget.onBack,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in _songs.keys)
                  KidsBounce(
                    onTap: () => setState(() {
                      _song = _song == name ? null : name;
                      _step = 0;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _song == name ? Colors.white : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(name, style: kidsText(18, color: _song == name ? const Color(0xFF1A1340) : Colors.white)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              song == null ? 'Play anything, or pick a song and follow the glowing key' : 'Next: the glowing key (${_step + 1} of ${song.length})',
              style: kidsText(18, color: Colors.white70, weight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < kidsPianoNotes.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: GestureDetector(
                          onTapDown: (_) => _press(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 90),
                            alignment: Alignment.bottomCenter,
                            padding: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: _pressed == i
                                  ? _keyColors[i % 7]
                                  : hint == i
                                  ? Color.lerp(Colors.white, _keyColors[i % 7], 0.45)
                                  : Colors.white,
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                              border: Border(bottom: BorderSide(color: _keyColors[i % 7], width: 10)),
                            ),
                            child: Text(kidsPianoNotes[i].$1, style: kidsText(22, color: const Color(0xFF1A1340))),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Whack-a-Mole ──────────────────────────────────────────────────────────

class WhackAMole extends StatefulWidget {
  const WhackAMole({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<WhackAMole> createState() => _WhackAMoleState();
}

class _WhackAMoleState extends State<WhackAMole> {
  /// Easy, Medium, Hard: how long a mole stays up, in milliseconds.
  static const _upFor = [1400, 950, 600];
  static const _seconds = 30;
  final _rng = math.Random();
  int _level = 0, _score = 0, _left = _seconds;
  int? _mole, _bonked;
  bool _playing = false, _over = false, _newBest = false;
  Timer? _clock, _pop;

  void _start() {
    _clock?.cancel();
    setState(() {
      _playing = true;
      _over = false;
      _score = 0;
      _left = _seconds;
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_left <= 1) {
        unawaited(_finish());
      } else {
        setState(() => _left--);
      }
    });
    _next();
  }

  void _next() {
    _pop?.cancel();
    if (!_playing) return;
    setState(() {
      _bonked = null;
      _mole = _rng.nextInt(9);
    });
    _pop = Timer(Duration(milliseconds: _upFor[_level]), _next);
  }

  void _whack(int hole) {
    if (!_playing || hole != _mole) return;
    setState(() {
      _score++;
      _bonked = hole;
      _mole = null;
    });
    _pop?.cancel();
    _pop = Timer(const Duration(milliseconds: 250), _next);
  }

  Future<void> _finish() async {
    _clock?.cancel();
    _pop?.cancel();
    final key = 'mole${_level + 1}';
    final best = await KidsScores.offer(key, _score);
    await KidsScores.addStars(_score >= 25 ? 3 : (_score >= 15 ? 2 : (_score >= 8 ? 1 : 0)));
    if (mounted) setState(() { _playing = false; _over = true; _newBest = best; _mole = null; });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pop?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Whack-a-Mole',
    colors: const [Color(0xFF6B4E1F), Color(0xFF1F8A4C)],
    onBack: widget.onBack,
    trailing: _playing ? Text('$_left s   Score $_score', style: kidsText(28)) : null,
    child: _over
        ? KidsResult(
            title: 'Bonk-tastic!',
            detail: 'You whacked $_score moles',
            stars: _score >= 25 ? 3 : (_score >= 15 ? 2 : (_score >= 8 ? 1 : 0)),
            newBest: _newBest,
            onAgain: () => setState(() => _over = false),
          )
        : !_playing
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pest_control_rodent_rounded, size: 96, color: Colors.white),
                Text('Tap the moles before they hide!', style: kidsText(26, weight: FontWeight.w700)),
                const SizedBox(height: 18),
                kidsLevelChips(const ['Easy', 'Medium', 'Hard'], _level, (i) => setState(() => _level = i)),
                const SizedBox(height: 24),
                KidsButton('Start', icon: Icons.play_arrow_rounded, onTap: _start, size: 32),
              ],
            ),
          )
        : LayoutBuilder(
            builder: (context, box) {
              final side = math.min(box.maxHeight - 24, box.maxWidth * 0.6);
              return Center(
                child: SizedBox(
                  width: side,
                  height: side,
                  child: GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (var i = 0; i < 9; i++)
                        GestureDetector(
                          onTapDown: (_) => _whack(i),
                          child: Container(
                            decoration: const BoxDecoration(color: Color(0xFF3E2A12), shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: AnimatedScale(
                              scale: _mole == i ? 1 : 0,
                              duration: const Duration(milliseconds: 120),
                              child: const Icon(Icons.pest_control_rodent_rounded, size: 90, color: Color(0xFFC79A6B)),
                            ),
                          ),
                        ),
                    ].asMap().entries.map((e) => _bonked == e.key
                        ? Stack(alignment: Alignment.center, children: [e.value, const Icon(Icons.star_rounded, size: 70, color: Color(0xFFFFD27A))])
                        : e.value).toList(),
                  ),
                ),
              );
            },
          ),
  );
}

// ── Lights Out ────────────────────────────────────────────────────────────

class LightsOut extends StatefulWidget {
  const LightsOut({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<LightsOut> createState() => _LightsOutState();
}

class _LightsOutState extends State<LightsOut> {
  static const _sizes = [3, 4, 5];
  final _rng = math.Random();
  int _level = 0, _moves = 0;
  List<bool>? _board;
  bool _won = false, _newBest = false;

  int get _n => _sizes[_level];

  void _start() => setState(() {
    _board = lightsOutPuzzle(_n, 3 + _level * 3, _rng);
    _moves = 0;
    _won = false;
  });

  Future<void> _press(int i) async {
    final b = _board;
    if (b == null || _won) return;
    setState(() {
      lightsOutPress(b, _n, i);
      _moves++;
    });
    if (!b.contains(true)) {
      final best = await KidsScores.offer('lights$_n', _moves, lowerIsBetter: true);
      await KidsScores.addStars(_level + 1);
      if (mounted) setState(() { _won = true; _newBest = best; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _board;
    return KidsActivityFrame(
      title: 'Lights Out',
      colors: const [Color(0xFF1A1340), Color(0xFF283066)],
      onBack: widget.onBack,
      trailing: b != null && !_won ? Text('Moves $_moves', style: kidsText(28)) : null,
      child: _won
          ? KidsResult(
              title: 'All dark!',
              detail: 'Solved in $_moves moves',
              stars: _level + 1,
              newBest: _newBest,
              onAgain: () => setState(() => _board = null),
            )
          : b == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lightbulb_rounded, size: 96, color: Color(0xFFFFD27A)),
                  Text('Turn every light off. A tap flips its neighbours too!', textAlign: TextAlign.center, style: kidsText(26, weight: FontWeight.w700)),
                  const SizedBox(height: 18),
                  kidsLevelChips(const ['3×3 Easy', '4×4 Medium', '5×5 Hard'], _level, (i) => setState(() => _level = i)),
                  const SizedBox(height: 24),
                  KidsButton('Start', icon: Icons.play_arrow_rounded, onTap: _start, size: 32),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, box) {
                final side = math.min(box.maxHeight - 24, box.maxWidth * 0.6);
                return Center(
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: GridView.count(
                      crossAxisCount: _n,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        for (var i = 0; i < _n * _n; i++)
                          KidsBounce(
                            onTap: () => unawaited(_press(i)),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              decoration: BoxDecoration(
                                color: b[i] ? const Color(0xFFFFD27A) : const Color(0xFF2A2F45),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: b[i] ? const [BoxShadow(color: Color(0xAAFFD27A), blurRadius: 18)] : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
