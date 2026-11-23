import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../app_container.dart';
import 'kids_activities.dart';
import 'kids_games.dart';
import 'kids_logic.dart';
import 'kids_more_logic.dart';
import 'kids_motion.dart' show KidsHands, KidsMotionPanel, kidsPlayWithChips, kidsTrackerFor, steerFrom;

/// The Kids Portal's play shelf: Tic-Tac-Toe, Snake, Simon Says, Pixel
/// Paint and the Piano.

/// Plays the Kids Portal's instruments. Every note is synthesized once (in
/// the background) into a WAV in the app's cache, then loaded into the
/// native instrument player (InstrumentBridge.kt, a SoundPool), which plays
/// a key the moment it is touched and lets notes ring together. Without the
/// native player (tests, an old build) it falls back to the app's sound
/// player.
class KidsTones {
  KidsTones(this._play);

  /// SoundManager.playFile: an id and a local file (the fallback).
  final Future<bool> Function(String id, String path) _play;
  static const _channel = MethodChannel('kiosk_satellite/instrument');

  final _paths = <KidsInstrument, List<String>>{};
  final _ids = <KidsInstrument, List<int>>{};
  final _ready = <KidsInstrument, Future<void>>{};
  int _n = 0;

  Future<void> _prepare(KidsInstrument instrument) async {
    final dir = await getTemporaryDirectory();
    final files = [for (var i = 0; i < kidsPianoNotes.length; i++) File('${dir.path}/phx_${instrument.name}_v2_$i.wav')];
    if (!files.every((f) => f.existsSync())) {
      final freqs = [for (final n in kidsPianoNotes) n.$2];
      final wavs = await compute(_renderAll, (freqs, instrument.index));
      for (var i = 0; i < files.length; i++) {
        await files[i].writeAsBytes(wavs[i], flush: true);
      }
    }
    _paths[instrument] = [for (final f in files) f.path];
    try {
      final ids = await _channel.invokeListMethod<int>('load', {'paths': _paths[instrument]});
      if (ids != null && ids.length == files.length) _ids[instrument] = ids;
    } on MissingPluginException {
      // No native player: the fallback plays the files.
    } on PlatformException {
      // Same.
    }
  }

  /// Get an instrument's notes ready ahead of the first key press.
  Future<void> warm([KidsInstrument instrument = KidsInstrument.piano]) => _ready[instrument] ??= _prepare(instrument).catchError((_) {});

  Future<void> note(int index, {KidsInstrument instrument = KidsInstrument.piano, double volume = 1}) async {
    await warm(instrument);
    final ids = _ids[instrument];
    if (ids != null && index < ids.length) {
      try {
        final ok = await _channel.invokeMethod<bool>('play', {'id': ids[index], 'volume': volume});
        if (ok ?? false) return;
      } on MissingPluginException {
        // Fall back below.
      } on PlatformException {
        // Fall back below.
      }
    }
    final path = _paths[instrument]?.elementAtOrNull(index);
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

List<Uint8List> _renderAll((List<double>, int) job) => [for (final f in job.$1) wavBytes(instrumentNote(f, KidsInstrument.values[job.$2]))];

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
          // Side by side in landscape, stacked in portrait.
          final wide = box.maxWidth > box.maxHeight;
          final side = wide ? math.min(box.maxHeight - 24, box.maxWidth * 0.55) : math.min(box.maxWidth - 48, box.maxHeight * 0.6);
          return Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
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
                          decoration: BoxDecoration(color: line.contains(i) ? const Color(0xFFFFD27A) : Colors.white, borderRadius: BorderRadius.circular(24)),
                          alignment: Alignment.center,
                          child: Text(_board[i], style: kidsText(side / 5, color: _board[i] == 'X' ? const Color(0xFFE0446A) : const Color(0xFF5B6CFF))),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 32, height: 24),
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        r == null
                            ? (_thinking ? 'Hmm, thinking…' : 'Your turn! You are X')
                            : r == 'X'
                            ? 'You win!'
                            : r == 'O'
                            ? 'I win this time!'
                            : "It's a draw!",
                        style: kidsText(30),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisSize: MainAxisSize.min,
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
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Snake ─────────────────────────────────────────────────────────────────

/// Snake's stages, 20 × 13: '#' a wall. A new stage every [snakeApplesPerStage]
/// apples; after the last they come round again, faster.
const snakeStages = <(String, List<String>)>[
  ('Open field', []),
  ('Bars', ['.....####...........', '...........####.....']),
  (
    'Plus',
    [
      '..........#.........',
      '..........#.........',
      '..........#.........',
      '....................',
      '....###.......###...',
      '....................',
      '..........#.........',
      '..........#.........',
      '..........#.........',
    ],
  ),
  (
    'Corners',
    [
      '.###............###.',
      '.#................#.',
      '....................',
      '....................',
      '....................',
      '....................',
      '....................',
      '....................',
      '.#................#.',
      '.###............###.',
    ],
  ),
  (
    'Gates',
    [
      '......#......#......',
      '......#......#......',
      '......#......#......',
      '......#......#......',
      '....................',
      '....................',
      '....................',
      '......#......#......',
      '......#......#......',
      '......#......#......',
      '......#......#......',
    ],
  ),
];

/// Where each stage's rows start (the rest of the field is open).
const _snakeStageTop = [0, 3, 2, 1, 1];

const snakeApplesPerStage = 6;

/// The wall cells of [stage] (1-based, going round).
Set<(int, int)> snakeWalls(int stage) {
  final i = (stage - 1) % snakeStages.length;
  final rows = snakeStages[i].$2;
  final top = _snakeStageTop[i];
  final out = <(int, int)>{};
  for (var r = 0; r < rows.length; r++) {
    // 'Bars' has its two bars six rows apart.
    final y = i == 1 ? top + r * 6 : top + r;
    for (var x = 0; x < rows[r].length; x++) {
      if (rows[r][x] == '#') out.add((x, y));
    }
  }
  return out;
}

class SnakeGame extends StatefulWidget {
  const SnakeGame({super.key, required this.onBack, this.container});
  final VoidCallback onBack;

  /// For steering by hand or head (none: buttons and swipes only).
  final AppContainer? container;

  @override
  State<SnakeGame> createState() => _SnakeGameState();
}

class _SnakeGameState extends State<SnakeGame> {
  static const _w = 20, _h = 13;
  final _rng = math.Random();
  List<(int, int)> _snake = const [];
  (int, int) _dir = (1, 0), _nextDir = (1, 0);
  (int, int) _food = (10, 6);
  Timer? _timer, _steerTimer;
  KidsHands? _tracker;
  int _playWith = 0; // buttons, hand, head
  bool _playing = false, _over = false, _newBest = false;
  Set<(int, int)> _walls = const {};
  int _stage = 1, _apples = 0;
  double _banner = 0;

  /// Slow, Normal, Fast: milliseconds a step.
  static const _speeds = [270, 190, 120];
  int _level = 1;

  Duration get _period => Duration(milliseconds: math.max(70, (_speeds[_level] * math.pow(0.93, _stage - 1)).round()));

  void _start() {
    _timer?.cancel();
    _steerTimer?.cancel();
    _tracker?.dispose();
    final tracker = _tracker = kidsTrackerFor(widget.container, _playWith);
    if (tracker != null) {
      _steerTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
        tracker.step(0.04);
        final s = steerFrom(tracker.point.value);
        if (s != null) _turn(s.$1, s.$2);
      });
    }
    setState(() {
      _snake = [(5, 6), (4, 6), (3, 6)];
      _dir = (1, 0);
      _nextDir = (1, 0);
      _stage = 1;
      _apples = 0;
      _walls = const {};
      _banner = 0;
      _placeFood();
      _playing = true;
      _over = false;
    });
    _timer = Timer.periodic(_period, (_) => _step());
  }

  void _placeFood() {
    do {
      _food = (_rng.nextInt(_w), _rng.nextInt(_h));
    } while (_snake.contains(_food) || _walls.contains(_food));
  }

  /// On to the next stage: its walls (never on the snake or just ahead of
  /// it) and a little more speed.
  void _nextStage() {
    _stage++;
    final head = _snake.first;
    final ahead = {for (var k = 1; k <= 4; k++) (head.$1 + _dir.$1 * k, head.$2 + _dir.$2 * k)};
    _walls = snakeWalls(_stage).where((c) => !_snake.contains(c) && !ahead.contains(c)).toSet();
    if (_walls.contains(_food)) _placeFood();
    _banner = 2;
    _timer?.cancel();
    _timer = Timer.periodic(_period, (_) => _step());
  }

  void _turn(int dx, int dy) {
    // No turning straight back into yourself.
    if (dx == -_dir.$1 && dy == -_dir.$2) return;
    _nextDir = (dx, dy);
  }

  Future<void> _step() async {
    _dir = _nextDir;
    final head = (_snake.first.$1 + _dir.$1, _snake.first.$2 + _dir.$2);
    _banner = math.max(0, _banner - _period.inMilliseconds / 1000);
    if (head.$1 < 0 || head.$2 < 0 || head.$1 >= _w || head.$2 >= _h || _snake.contains(head) || _walls.contains(head)) {
      _timer?.cancel();
      _steerTimer?.cancel();
      final length = _snake.length;
      final best = await KidsScores.offer('snake', length);
      await KidsScores.offerChallenge('snake', length);
      await KidsScores.addStars(length >= 20 ? 3 : (length >= 12 ? 2 : (length >= 7 ? 1 : 0)));
      if (mounted) {
        setState(() {
          _over = true;
          _playing = false;
          _newBest = best;
        });
      }
      return;
    }
    setState(() {
      _snake = [head, ..._snake];
      if (head == _food) {
        _apples++;
        if (_apples % snakeApplesPerStage == 0) _nextStage();
        _placeFood();
      } else {
        _snake.removeLast();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _steerTimer?.cancel();
    _tracker?.dispose();
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
    trailing: _playing ? Text('Stage $_stage  ·  Length ${_snake.length}', style: kidsText(28)) : null,
    child: _over
        ? KidsResult(
            title: 'Bonk!',
            detail: 'Your snake grew to ${_snake.length} · reached stage $_stage (${snakeStages[(_stage - 1) % snakeStages.length].$1})',
            stars: _snake.length >= 20 ? 3 : (_snake.length >= 12 ? 2 : (_snake.length >= 7 ? 1 : 0)),
            newBest: _newBest,
            onAgain: _start,
          )
        : !_playing
        ? KidsStartPanel(
            icon: Icons.gesture_rounded,
            pitch: 'Eat the apples, grow long, miss the walls!',
            best: KidsScores.best('snake').then((b) => b == null ? null : 'Longest: $b'),
            options: Column(
              children: [
                kidsLevelChips(const ['Slow', 'Normal', 'Fast'], _level, (i) => setState(() => _level = i)),
                if (widget.container != null) ...[const SizedBox(height: 14), kidsPlayWithChips(_playWith, (i) => setState(() => _playWith = i))],
              ],
            ),
            onStart: _start,
          )
        : LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight;
              final board = GestureDetector(
                onPanEnd: (d) {
                  final v = d.velocity.pixelsPerSecond;
                  if (v.distance < 80) return;
                  v.dx.abs() > v.dy.abs() ? _turn(v.dx > 0 ? 1 : -1, 0) : _turn(0, v.dy > 0 ? 1 : -1);
                },
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _w / _h,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 4),
                        boxShadow: const [BoxShadow(color: Color(0x40000000), offset: Offset(0, 8), blurRadius: 14)],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: CustomPaint(
                          painter: _SnakePainter(
                            _snake,
                            _food,
                            _w,
                            _h,
                            _walls,
                            _banner > 0 ? 'STAGE $_stage · ${snakeStages[(_stage - 1) % snakeStages.length].$1}' : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              final tracker = _tracker;
              final pad = tracker != null
                  ? KidsMotionPanel(hands: tracker)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _arrow(Icons.arrow_upward_rounded, 0, -1),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [_arrow(Icons.arrow_back_rounded, -1, 0), const SizedBox(width: 92), _arrow(Icons.arrow_forward_rounded, 1, 0)],
                        ),
                        const SizedBox(height: 10),
                        _arrow(Icons.arrow_downward_rounded, 0, 1),
                      ],
                    );
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: wide
                    ? Row(
                        children: [
                          Expanded(child: board),
                          const SizedBox(width: 20),
                          pad,
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: board),
                          const SizedBox(height: 16),
                          pad,
                        ],
                      ),
              );
            },
          ),
  );
}

class _SnakePainter extends CustomPainter {
  _SnakePainter(this.snake, this.food, this.w, this.h, this.walls, this.banner);
  final List<(int, int)> snake;
  final (int, int) food;
  final int w, h;
  final Set<(int, int)> walls;
  final String? banner;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / w;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)), Paint()..color = const Color(0xFF0E3B24));
    for (final (x, y) in walls) {
      final r = Rect.fromLTWH(x * c + 1, y * c + 1, c - 2, c - 2);
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(c * 0.15)), Paint()..color = const Color(0xFF8A6A4A));
      canvas.drawRect(Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.3), Paint()..color = const Color(0xFFB08A60));
    }
    canvas.drawCircle(Offset((food.$1 + 0.5) * c, (food.$2 + 0.5) * c), c * 0.4, Paint()..color = const Color(0xFFFF4D4D));
    for (var i = 0; i < snake.length; i++) {
      final (x, y) = snake[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x * c + 1.5, y * c + 1.5, c - 3, c - 3), Radius.circular(c * 0.3)),
        Paint()..color = i == 0 ? const Color(0xFFFFD27A) : Color.lerp(const Color(0xFF52D69F), const Color(0xFF14A06B), i / snake.length)!,
      );
    }
    final b = banner;
    if (b != null) {
      final tp = TextPainter(
        text: TextSpan(text: b, style: kidsText(c * 1.1)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height * 0.12));
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
    // Also ignore taps in the pause after a round is done, before the next
    // sequence shows (a quick extra tap there read past the sequence).
    if (_showing || _over || !_started || _input >= _seq.length) return;
    unawaited(_flash(pad, millis: 220));
    if (pad != _seq[_input]) {
      final level = _seq.length - 1;
      final best = await KidsScores.offer('simon', level);
      await KidsScores.offerChallenge('simon', level);
      await KidsScores.addStars(level >= 10 ? 3 : (level >= 6 ? 2 : (level >= 3 ? 1 : 0)));
      if (mounted) {
        setState(() {
          _over = true;
          _newBest = best;
        });
      }
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
                          if (!_started) KidsBigButton('Start', icon: Icons.play_arrow_rounded, onTap: _start, size: 30),
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
                            child: Text(
                              '$k',
                              style: kidsText(26, color: Colors.white).copyWith(shadows: const [Shadow(blurRadius: 4)]),
                            ),
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
  static const _keyColors = [
    Color(0xFFFF6B6B),
    Color(0xFFF28A1E),
    Color(0xFFFFD27A),
    Color(0xFF52D69F),
    Color(0xFF63C3FF),
    Color(0xFF5B6CFF),
    Color(0xFFB06BFF),
  ];
  static const _instruments = [
    (KidsInstrument.piano, 'Piano', Icons.piano_rounded),
    (KidsInstrument.xylophone, 'Xylophone', Icons.music_note_rounded),
    (KidsInstrument.musicBox, 'Music box', Icons.toys_rounded),
  ];

  KidsInstrument _instrument = KidsInstrument.piano;
  bool _letters = true;
  String? _song;
  int _step = 0;
  bool _listening = false;
  int _listenToken = 0;

  /// Keys down right now (for the glow), by pointer.
  final _down = <int, int>{};
  final _flash = <int>{};
  final _sparks = <_Spark>[];
  int _sparkId = 0;

  final _keysKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    unawaited(widget.tones.warm(_instrument));
  }

  @override
  void dispose() {
    _listenToken++;
    super.dispose();
  }

  List<(int, double)>? get _notes => _song == null ? null : kidsPianoSongs[_song];

  void _sound(int key, {bool byChild = true}) {
    unawaited(widget.tones.note(key, instrument: _instrument));
    setState(() {
      _flash.add(key);
      _sparks.add(_Spark(_sparkId++, key));
      if (_sparks.length > 12) _sparks.removeAt(0);
    });
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (mounted && !_down.containsValue(key)) setState(() => _flash.remove(key));
    });
    if (!byChild) return;
    final notes = _notes;
    if (notes != null && !_listening && notes[_step].$1 == key) {
      _step++;
      if (_step >= notes.length) {
        final done = _song;
        _step = 0;
        _song = null;
        unawaited(KidsScores.addStars(2));
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('You played $done! ⭐⭐')));
      }
    }
  }

  Future<void> _listen() async {
    final notes = _notes;
    if (notes == null) return;
    final token = ++_listenToken;
    setState(() {
      _listening = true;
      _step = 0;
    });
    for (final (key, beats) in notes) {
      if (!mounted || token != _listenToken) return;
      _sound(key, byChild: false);
      setState(() => _down[-1] = key);
      await Future<void>.delayed(Duration(milliseconds: (beats * 420).round()));
    }
    if (!mounted || token != _listenToken) return;
    setState(() {
      _down.remove(-1);
      _listening = false;
    });
  }

  /// Which key is under [global]: black keys sit on top of white ones.
  int? _keyAt(Offset global) {
    final box = _keysKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final p = box.globalToLocal(global);
    final size = box.size;
    if (p.dx < 0 || p.dy < 0 || p.dx > size.width || p.dy > size.height) return null;
    final whites = [
      for (var i = 0; i < kidsPianoNotes.length; i++)
        if (!kidsPianoNotes[i].$3) i,
    ];
    final w = size.width / whites.length;
    if (p.dy < size.height * 0.6) {
      for (var i = 0; i < kidsPianoNotes.length; i++) {
        if (!kidsPianoNotes[i].$3) continue;
        final left = whites.indexOf(i - 1) * w + w * 0.68;
        if (p.dx >= left && p.dx <= left + w * 0.64) return i;
      }
    }
    return whites[(p.dx / w).floor().clamp(0, whites.length - 1)];
  }

  void _pointer(PointerEvent e, {bool up = false}) {
    if (up) {
      final key = _down.remove(e.pointer);
      if (key != null) setState(() => _flash.remove(key));
      return;
    }
    final key = _keyAt(e.position);
    if (key == null || _down[e.pointer] == key) return;
    // A new key under this finger: a tap, or a slide across the keys.
    _down[e.pointer] = key;
    _sound(key);
  }

  @override
  Widget build(BuildContext context) {
    final notes = _notes;
    final hint = notes != null && !_listening ? notes[_step].$1 : null;
    return KidsActivityFrame(
      title: 'Piano',
      colors: const [Color(0xFF14102E), Color(0xFF3A2F7A)],
      onBack: widget.onBack,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (inst, label, icon) in _instruments)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: KidsBounce(
                onTap: () {
                  setState(() => _instrument = inst);
                  unawaited(widget.tones.warm(inst));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _instrument == inst ? Colors.white : Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 20, color: _instrument == inst ? const Color(0xFF1A1340) : Colors.white),
                      const SizedBox(width: 6),
                      Text(label, style: kidsText(16, color: _instrument == inst ? const Color(0xFF1A1340) : Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          children: [
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final name in kidsPianoSongs.keys)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: KidsBounce(
                        onTap: () => setState(() {
                          _listenToken++;
                          _listening = false;
                          _down.remove(-1);
                          _song = _song == name ? null : name;
                          _step = 0;
                        }),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: _song == name ? const Color(0xFFFFD27A) : Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(name, style: kidsText(17, color: _song == name ? const Color(0xFF1A1340) : Colors.white)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  Expanded(
                    child: notes == null
                        ? Text(
                            'Play anything — slide your finger across the keys!',
                            style: kidsText(18, color: Colors.white70, weight: FontWeight.w700),
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: _step / notes.length,
                                    minHeight: 12,
                                    backgroundColor: Colors.white12,
                                    color: const Color(0xFFFFD27A),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _listening ? 'Listen…' : 'Your turn: the glowing key',
                                style: kidsText(17, color: Colors.white, weight: FontWeight.w700),
                              ),
                            ],
                          ),
                  ),
                  if (notes != null) ...[
                    const SizedBox(width: 10),
                    KidsBounce(
                      onTap: _listening ? null : () => unawaited(_listen()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(color: const Color(0xFF52D69F), borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          children: [
                            const Icon(Icons.hearing_rounded, color: Color(0xFF0E3B2A), size: 20),
                            const SizedBox(width: 6),
                            Text('Listen', style: kidsText(16, color: const Color(0xFF0E3B2A))),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  KidsBounce(
                    onTap: () => setState(() => _letters = !_letters),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
                      child: Text(_letters ? 'A B C' : 'Colours', style: kidsText(16)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _pointer,
                onPointerMove: _pointer,
                onPointerUp: (e) => _pointer(e, up: true),
                onPointerCancel: (e) => _pointer(e, up: true),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _Keyboard(key: _keysKey, lit: {..._flash, ..._down.values}, hint: hint, letters: _letters, colors: _keyColors),
                    ),
                    for (final spark in _sparks) _SparkView(key: ValueKey(spark.id), spark: spark, keyboard: _keysKey),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gently bobs its child up and down: "press here".
class _Bob extends StatefulWidget {
  const _Bob({required this.child});
  final Widget child;

  @override
  State<_Bob> createState() => _BobState();
}

class _BobState extends State<_Bob> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) => Transform.translate(offset: Offset(0, -10 * Curves.easeInOut.transform(_c.value)), child: child),
    child: Padding(padding: const EdgeInsets.only(bottom: 8), child: widget.child),
  );
}

class _Spark {
  _Spark(this.id, this.key);
  final int id;
  final int key;
}

/// A little note that floats up from a key that was played.
class _SparkView extends StatelessWidget {
  const _SparkView({super.key, required this.spark, required this.keyboard});
  final _Spark spark;
  final GlobalKey keyboard;

  // It fills the keyboard's Stack and floats the note in a Stack of its own:
  // a Positioned has to sit right inside a Stack.
  @override
  Widget build(BuildContext context) => Positioned.fill(child: IgnorePointer(child: _note()));

  Widget _note() => LayoutBuilder(
    builder: (context, box) {
      final whites = [
        for (var i = 0; i < kidsPianoNotes.length; i++)
          if (!kidsPianoNotes[i].$3) i,
      ];
      final w = box.maxWidth / whites.length;
      final k = spark.key;
      final x = kidsPianoNotes[k].$3 ? (whites.indexOf(k - 1) + 1) * w : (whites.indexOf(k) + 0.5) * w;
      const symbols = ['♪', '♫', '♩', '♬'];
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        builder: (context, t, _) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: x - 14 + math.sin(t * 6 + spark.id) * 10,
              top: box.maxHeight * 0.35 - t * box.maxHeight * 0.45,
              child: IgnorePointer(
                child: Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: Text(
                    symbols[spark.id % symbols.length],
                    style: TextStyle(fontSize: 30, color: _KidsPianoState._keyColors[(k * 5) % 7], shadows: const [Shadow(blurRadius: 6)]),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// The keys: white keys side by side, black keys on top between them.
class _Keyboard extends StatelessWidget {
  const _Keyboard({super.key, required this.lit, required this.hint, required this.letters, required this.colors});

  final Set<int> lit;
  final int? hint;
  final bool letters;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final whites = [
        for (var i = 0; i < kidsPianoNotes.length; i++)
          if (!kidsPianoNotes[i].$3) i,
      ];
      final w = box.maxWidth / whites.length;
      final h = box.maxHeight;
      Color colorOf(int i) => colors[whites.indexOf(i) % 7];
      return Stack(
        children: [
          for (final (n, i) in whites.indexed)
            Positioned(
              left: n * w,
              top: 0,
              width: w,
              height: h,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 70),
                  transform: Matrix4.translationValues(0, lit.contains(i) ? 4 : 0, 0),
                  alignment: Alignment.bottomCenter,
                  padding: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: lit.contains(i)
                          ? [Color.lerp(Colors.white, colorOf(i), 0.55)!, colorOf(i)]
                          : hint == i
                          ? [Color.lerp(Colors.white, colorOf(i), 0.3)!, colorOf(i)]
                          : const [Color(0xFFF4F4F8), Colors.white],
                    ),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                    boxShadow: [
                      if (hint == i) BoxShadow(color: colorOf(i), blurRadius: 22, spreadRadius: 2),
                      if (!lit.contains(i)) const BoxShadow(color: Color(0x66000000), offset: Offset(0, 5), blurRadius: 2),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hint == i)
                        const _Bob(
                          child: Icon(Icons.touch_app_rounded, color: Colors.white, size: 40, shadows: [Shadow(blurRadius: 8)]),
                        ),
                      Container(
                        width: w * 0.62,
                        height: w * 0.62,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: colorOf(i), shape: BoxShape.circle),
                        child: letters ? Text(kidsPianoNotes[i].$1, style: kidsText(w * 0.32, color: Colors.white)) : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          for (var i = 0; i < kidsPianoNotes.length; i++)
            if (kidsPianoNotes[i].$3)
              Positioned(
                left: whites.indexOf(i - 1) * w + w * 0.68,
                top: 0,
                width: w * 0.64,
                height: h * 0.6,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 70),
                  transform: Matrix4.translationValues(0, lit.contains(i) ? 3 : 0, 0),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: lit.contains(i)
                          ? const [Color(0xFF5B6CFF), Color(0xFFB06BFF)]
                          : hint == i
                          ? const [Color(0xFF3A3F7A), Color(0xFFFFD27A)]
                          : const [Color(0xFF26262E), Color(0xFF0C0C10)],
                    ),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                    boxShadow: [
                      if (hint == i) const BoxShadow(color: Color(0xFFFFD27A), blurRadius: 18, spreadRadius: 1),
                      const BoxShadow(color: Color(0x88000000), offset: Offset(0, 4), blurRadius: 4),
                    ],
                  ),
                ),
              ),
        ],
      );
    },
  );
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
    if (mounted) {
      setState(() {
        _playing = false;
        _over = true;
        _newBest = best;
        _mole = null;
      });
    }
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
        ? KidsStartPanel(
            icon: Icons.pest_control_rodent_rounded,
            pitch: 'Tap the moles before they hide!',
            best: KidsScores.best('mole${_level + 1}').then((b) => b == null ? null : 'Best: $b moles'),
            options: kidsLevelChips(const ['Easy', 'Medium', 'Hard'], _level, (i) => setState(() => _level = i)),
            onStart: _start,
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
                    children:
                        [
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
                            ]
                            .asMap()
                            .entries
                            .map(
                              (e) => _bonked == e.key
                                  ? Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        e.value,
                                        const Icon(Icons.star_rounded, size: 70, color: Color(0xFFFFD27A)),
                                      ],
                                    )
                                  : e.value,
                            )
                            .toList(),
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
      if (mounted) {
        setState(() {
          _won = true;
          _newBest = best;
        });
      }
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
          ? KidsStartPanel(
              icon: Icons.lightbulb_rounded,
              pitch: 'Turn every light off. A tap flips its neighbours too!',
              options: kidsLevelChips(const ['3×3 Easy', '4×4 Medium', '5×5 Hard'], _level, (i) => setState(() => _level = i)),
              onStart: _start,
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
