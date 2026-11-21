import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_container.dart';
import '../../managers/kids/kids_manager.dart';
import '../../managers/launcher/app_launcher_manager.dart';
import 'kids_activities.dart';
import 'kids_games.dart';
import 'kids_learn.dart';
import 'kids_logic.dart';
import 'kids_more_logic.dart';
import 'kids_play.dart';
import 'kids_puzzles.dart';

/// Phoenix Portal's Kids Portal: a full screen, child-safe home. Mounted by
/// the kiosk screen above the dashboard; shows whatever [KidsManager.screen]
/// says and nothing while it is [KidsScreen.hidden].
class KidsOverlay extends StatelessWidget {
  const KidsOverlay({super.key, required this.container});

  final AppContainer container;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<KidsScreen>(
    valueListenable: container.kids.screen,
    // A transparent Material: the text styles, ink and dialogs need one, and
    // the overlay sits outside any Scaffold.
    builder: (context, screen, _) => Material(
      type: MaterialType.transparency,
      child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.98, end: 1.0).animate(a), child: child),
      ),
      child: switch (screen) {
        KidsScreen.hidden => const SizedBox.shrink(key: ValueKey('hidden')),
        KidsScreen.play => _KidsHome(key: const ValueKey('play'), container: container),
        KidsScreen.done => _KidsDone(key: const ValueKey('done'), container: container),
        KidsScreen.bedtime => _KidsBedtime(key: const ValueKey('bedtime'), container: container),
      },
      ),
    ),
  );
}

/// The night-sky ground every Kids Portal screen sits on.
class _KidsGround extends StatelessWidget {
  const _KidsGround({super.key, required this.child, this.colors});
  final Widget child;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors ?? const [Color(0xFF1E2140), Color(0xFF161933), Color(0xFF101220)],
      ),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        // Soft color glows, painted once: depth without any animation cost.
        const _Glow(alignment: Alignment(-0.9, -0.8), color: Color(0x22F26A1B), size: 520),
        const _Glow(alignment: Alignment(1.0, 0.9), color: Color(0x225B6CFF), size: 620),
        const _Glow(alignment: Alignment(0.6, -1.1), color: Color(0x1552D69F), size: 420),
        child,
      ],
    ),
  );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.alignment, required this.color, required this.size});
  final Alignment alignment;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    ),
  );
}

// ── Home ───────────────────────────────────────────────────────────────

enum _Game {
  math, words, g2048, connect4, memory, draw,
  times, clock, flags, patterns,
  sudoku, maze, wordsearch, guess,
  ttt, snake, simon, pixel, piano,
  fractions, money, science, spelling, opposites, mole, lights,
}

/// The hub's cards: title, pitch, icon, colours, shelf and how the best
/// reads.
class _GameInfo {
  const _GameInfo(this.game, this.title, this.pitch, this.icon, this.colors, this.bestKey, this.bestText, {this.shelf = 'Play'});
  final _Game game;
  final String title;
  final String pitch;
  final IconData icon;
  final List<Color> colors;
  final String? bestKey;
  final String Function(int best)? bestText;

  /// Learn, Puzzles, Play or Create: the hub's rows.
  final String shelf;
}

String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

final _games = <_GameInfo>[
  // Learn
  _GameInfo(_Game.math, 'Math Blitz', 'Beat the 60-second clock', Icons.calculate_rounded,
      const [Color(0xFFE0446A), Color(0xFFF28A1E)], 'math', (b) => 'Best: $b solved', shelf: 'Learn'),
  _GameInfo(_Game.times, 'Times Tables', 'Master ×2 to ×12', Icons.close_rounded,
      const [Color(0xFFD42A1A), Color(0xFFF5A623)], 'times', (b) => 'Best: $b of 20', shelf: 'Learn'),
  _GameInfo(_Game.clock, 'Telling the Time', 'Read the clock', Icons.schedule_rounded,
      const [Color(0xFF1C8ED6), Color(0xFF63C3FF)], 'clock', (b) => 'Best: $b of 10', shelf: 'Learn'),
  _GameInfo(_Game.flags, 'Flag Quiz', 'Flags and capitals', Icons.flag_rounded,
      const [Color(0xFF14A06B), Color(0xFF1C8ED6)], 'flags', (b) => 'Best: $b of 10', shelf: 'Learn'),
  _GameInfo(_Game.words, 'Word Scramble', 'Crack the mystery words', Icons.abc_rounded,
      const [Color(0xFF14A06B), Color(0xFF1C8ED6)], 'words', (b) => 'Best: $b pts', shelf: 'Learn'),
  _GameInfo(_Game.patterns, 'Patterns', 'What comes next?', Icons.auto_graph_rounded,
      const [Color(0xFF8C5BFF), Color(0xFFE0446A)], 'patterns', (b) => 'Best: $b of 10', shelf: 'Learn'),
  _GameInfo(_Game.fractions, 'Fractions', 'Slices of pie', Icons.pie_chart_rounded,
      const [Color(0xFF14A06B), Color(0xFFF5A623)], 'fractions', (b) => 'Best: $b of 10', shelf: 'Learn'),
  _GameInfo(_Game.money, 'Money', 'Count the coins', Icons.savings_rounded,
      const [Color(0xFF128A5A), Color(0xFF1F8A4C)], 'money', (b) => 'Best: $b of 10', shelf: 'Learn'),
  _GameInfo(_Game.science, 'Science', 'Plants, animals, space', Icons.science_rounded,
      const [Color(0xFF1C8ED6), Color(0xFF14A06B)], 'science', (b) => 'Best: $b of 10', shelf: 'Learn'),
  _GameInfo(_Game.spelling, 'Spelling', 'Spot the right spelling', Icons.spellcheck_rounded,
      const [Color(0xFFE08A00), Color(0xFF8C5BFF)], 'spelling', (b) => 'Best: $b of 10', shelf: 'Learn'),
  _GameInfo(_Game.opposites, 'Opposites', 'Hot and cold, up and down', Icons.compare_arrows_rounded,
      const [Color(0xFFE0446A), Color(0xFF1C8ED6)], 'opposites', (b) => 'Best: $b of 10', shelf: 'Learn'),
  // Puzzles
  _GameInfo(_Game.sudoku, 'Sudoku', '4×4, 6×6 or 9×9', Icons.grid_on_rounded,
      const [Color(0xFF283066), Color(0xFF5B6CFF)], 'sudoku4', (b) => '4×4 best: ${_mmss(b)}', shelf: 'Puzzles'),
  _GameInfo(_Game.maze, 'Maze', 'Find the way out', Icons.route_rounded,
      const [Color(0xFF128A5A), Color(0xFF52D69F)], 'maze', (b) => 'Fastest: ${_mmss(b)}', shelf: 'Puzzles'),
  _GameInfo(_Game.wordsearch, 'Word Search', 'Hidden words', Icons.manage_search_rounded,
      const [Color(0xFFE08A00), Color(0xFFE0446A)], 'wordsearch', (b) => 'Fastest: ${_mmss(b)}', shelf: 'Puzzles'),
  _GameInfo(_Game.guess, 'Word Guess', 'Save the balloons', Icons.spellcheck_rounded,
      const [Color(0xFF7B5CFF), Color(0xFF1C8ED6)], 'guess', (b) => 'Best streak: $b', shelf: 'Puzzles'),
  _GameInfo(_Game.memory, 'Memory Pro', 'Find all 8 pairs fast', Icons.psychology_rounded,
      const [Color(0xFF5B6CFF), Color(0xFF9A6BFF)], 'memory', (b) => 'Best: ${b}s', shelf: 'Puzzles'),
  _GameInfo(_Game.g2048, '2048', 'Slide, merge, reach 2048', Icons.grid_4x4_rounded,
      const [Color(0xFF8C5BFF), Color(0xFF5B6CFF)], '2048', (b) => 'Best: $b', shelf: 'Puzzles'),
  _GameInfo(_Game.lights, 'Lights Out', 'Turn every light off', Icons.lightbulb_rounded,
      const [Color(0xFF1A1340), Color(0xFF283066)], 'lights3', (b) => '3×3 best: $b moves', shelf: 'Puzzles'),
  // Play
  _GameInfo(_Game.snake, 'Snake', 'Eat, grow, dodge', Icons.gesture_rounded,
      const [Color(0xFF1F8A4C), Color(0xFF14A06B)], 'snake', (b) => 'Longest: $b'),
  _GameInfo(_Game.mole, 'Whack-a-Mole', 'Quick! Tap the moles', Icons.pest_control_rodent_rounded,
      const [Color(0xFF6B4E1F), Color(0xFF1F8A4C)], 'mole1', (b) => 'Easy best: $b'),
  _GameInfo(_Game.simon, 'Simon Says', 'Copy the lights', Icons.lightbulb_rounded,
      const [Color(0xFF283066), Color(0xFF7B5CFF)], 'simon', (b) => 'Best: level $b'),
  _GameInfo(_Game.ttt, 'Tic-Tac-Toe', 'Three in a row', Icons.tag_rounded,
      const [Color(0xFFE0446A), Color(0xFF8C5BFF)], 'ttthard', (b) => 'Hard wins: $b'),
  _GameInfo(_Game.connect4, 'Connect Four', 'Outsmart the computer', Icons.blur_circular_rounded,
      const [Color(0xFF1C8ED6), Color(0xFF283066)], 'c4hard', (b) => 'Hard wins: $b'),
  // Create
  const _GameInfo(_Game.draw, 'Draw Studio', 'Paint whatever you like', Icons.brush_rounded,
      [Color(0xFFD42A1A), Color(0xFFFF4D8D)], null, null, shelf: 'Create'),
  const _GameInfo(_Game.pixel, 'Pixel Paint', 'Colour by number', Icons.palette_rounded,
      [Color(0xFFE0446A), Color(0xFFF5A623)], null, null, shelf: 'Create'),
  const _GameInfo(_Game.piano, 'Piano', 'Play songs', Icons.piano_rounded,
      [Color(0xFF1A1340), Color(0xFF5B6CFF)], null, null, shelf: 'Create'),
];

const _shelves = ['Learn', 'Puzzles', 'Play', 'Create'];

class _KidsHome extends StatefulWidget {
  const _KidsHome({super.key, required this.container});
  final AppContainer container;

  @override
  State<_KidsHome> createState() => _KidsHomeState();
}

class _KidsHomeState extends State<_KidsHome> {
  _Game? _game;
  late final _tones = KidsTones(widget.container.sound.playFile);

  KidsManager get kids => widget.container.kids;

  void _back() => setState(() => _game = null);

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 360),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, a) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
    ),
    child: switch (_game) {
      _Game.math => MathBlitz(key: const ValueKey('math'), onBack: _back),
      _Game.words => WordScramble(key: const ValueKey('words'), onBack: _back),
      _Game.g2048 => Game2048(key: const ValueKey('2048'), onBack: _back),
      _Game.connect4 => ConnectFour(key: const ValueKey('c4'), onBack: _back),
      _Game.memory => MemoryPro(key: const ValueKey('memory'), onBack: _back),
      _Game.draw => KidsDraw(key: const ValueKey('draw'), onBack: _back),
      _Game.times => TimesTables(key: const ValueKey('times'), onBack: _back),
      _Game.clock => TellingTime(key: const ValueKey('clock'), onBack: _back),
      _Game.flags => FlagQuiz(key: const ValueKey('flags'), onBack: _back),
      _Game.patterns => PatternsGame(key: const ValueKey('patterns'), onBack: _back),
      _Game.sudoku => SudokuGame(key: const ValueKey('sudoku'), onBack: _back),
      _Game.maze => MazeGame(key: const ValueKey('maze'), onBack: _back),
      _Game.wordsearch => WordSearchGame(key: const ValueKey('wordsearch'), onBack: _back),
      _Game.guess => WordGuess(key: const ValueKey('guess'), onBack: _back),
      _Game.ttt => TicTacToe(key: const ValueKey('ttt'), onBack: _back),
      _Game.snake => SnakeGame(key: const ValueKey('snake'), onBack: _back),
      _Game.simon => SimonSays(key: const ValueKey('simon'), onBack: _back, tones: _tones),
      _Game.pixel => PixelPaint(key: const ValueKey('pixel'), onBack: _back),
      _Game.piano => KidsPiano(key: const ValueKey('piano'), onBack: _back, tones: _tones),
      _Game.fractions => FractionsQuiz(key: const ValueKey('fractions'), onBack: _back),
      _Game.money => MoneyQuiz(key: const ValueKey('money'), onBack: _back),
      _Game.science => ScienceQuiz(key: const ValueKey('science'), onBack: _back),
      _Game.spelling => SpellingQuiz(key: const ValueKey('spelling'), onBack: _back),
      _Game.opposites => OppositesQuiz(key: const ValueKey('opposites'), onBack: _back),
      _Game.mole => WhackAMole(key: const ValueKey('mole'), onBack: _back),
      _Game.lights => LightsOut(key: const ValueKey('lights'), onBack: _back),
      null => _home(context),
    },
  );

  /// The apps a child may open: the ones a parent added from Phoenix Home,
  /// then the launcher's kiosk-allowed apps.
  List<LauncherApp> get _apps {
    final c = widget.container;
    final seen = <String>{};
    return [
      for (final a in [...c.phoenixHome.kidsAppList, ...c.launcher.kioskApps])
        if (seen.add(a.package)) a,
    ];
  }

  /// The shelf on screen: one at a time keeps the hub calm.
  String _shelf = 'Learn';

  Widget _home(BuildContext context) {
    final name = kids.childName;
    final apps = _apps;
    final challenge = dailyChallenge(DateTime.now());
    final shelves = [..._shelves, if (apps.isNotEmpty) 'My apps'];
    final shelf = shelves.contains(_shelf) ? _shelf : shelves.first;
    final games = _games.where((g) => g.shelf == shelf).toList();
    return _KidsGround(
      key: const ValueKey('home'),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 22, 72, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Home and the parent lock sit on the left: the right edge can
              // be under the Portal's own floating menu.
              Row(
                children: [
                  if (!kids.locked) ...[
                    KidsBounce(
                      onTap: () => kids.closeIfFree(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.home_rounded, color: Colors.white, size: 26),
                            const SizedBox(width: 6),
                            Text('Home', style: kidsText(18)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  _ParentLock(container: widget.container),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      name.isEmpty ? 'Hi there!' : 'Hi $name!',
                      style: kidsText(34),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const _StarsPill(),
                  const SizedBox(width: 10),
                  _TimeLeftPill(kids: kids),
                ],
              ),
              const SizedBox(height: 14),
              _ChallengeCard(
                challenge: challenge,
                onPlay: () {
                  for (final g in _games) {
                    if (g.bestKey == challenge.game) {
                      setState(() => _game = g.game);
                      return;
                    }
                  }
                },
              ),
              const SizedBox(height: 18),
              // The shelves as quiet tabs.
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final s in shelves)
                    KidsBounce(
                      onTap: () => setState(() => _shelf = s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: s == shelf ? Colors.white : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Text(
                          s,
                          style: kidsText(19, color: s == shelf ? const Color(0xFF1E2140) : Colors.white70),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: shelf == 'My apps'
                      ? GridView.builder(
                          key: const ValueKey('My apps'),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 150,
                            mainAxisExtent: 140,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                          ),
                          itemCount: apps.length,
                          itemBuilder: (context, i) => _AppTile(container: widget.container, app: apps[i]),
                        )
                      : GridView.builder(
                          key: ValueKey(shelf),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 260,
                            mainAxisExtent: 150,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                          ),
                          itemCount: games.length,
                          itemBuilder: (context, i) => _GameCard(
                            info: games[i],
                            onTap: () => setState(() => _game = games[i].game),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's challenge: one game, one target, three bonus stars once won.
/// A quiet line, not a banner.
class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.challenge, required this.onPlay});
  final DailyChallenge challenge;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: KidsScores.changes,
    builder: (context, _, _) => FutureBuilder<bool>(
      future: KidsScores.challengeDone(),
      builder: (context, snap) {
        final done = snap.data ?? false;
        return KidsBounce(
          onTap: done ? null : onPlay,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              children: [
                Icon(done ? Icons.emoji_events_rounded : Icons.wb_sunny_rounded,
                    color: const Color(0xFFFFD27A), size: 28),
                const SizedBox(width: 12),
                Text(done ? 'Challenge done: ' : "Today's challenge: ",
                    style: kidsText(18, color: Colors.white60, weight: FontWeight.w700)),
                Expanded(
                  child: Text(challenge.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: kidsText(18)),
                ),
                Text(done ? '+3 stars' : '3 stars', style: kidsText(16, color: const Color(0xFFFFD27A))),
                if (!done) ...[
                  const SizedBox(width: 10),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white60),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.info, required this.onTap});
  final _GameInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The game's colour as a soft tint on the dark ground: calm, but each
    // game still has its own hue.
    final tint = Color.lerp(info.colors.first, const Color(0xFF1E2140), 0.62)!;
    final accent = Color.lerp(info.colors.first, Colors.white, 0.35)!;
    return KidsBounce(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(info.icon, color: accent, size: 34),
            const Spacer(),
            Text(info.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: kidsText(22)),
            const SizedBox(height: 2),
            if (info.bestKey != null)
              ValueListenableBuilder<int>(
                valueListenable: KidsScores.changes,
                builder: (context, _, _) => FutureBuilder<int?>(
                  future: KidsScores.best(info.bestKey!),
                  builder: (context, snap) => Text(
                    snap.data == null ? info.pitch : info.bestText!(snap.data!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kidsText(15, color: Colors.white60, weight: FontWeight.w700),
                  ),
                ),
              )
            else
              Text(info.pitch, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: kidsText(15, color: Colors.white60, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _StarsPill extends StatelessWidget {
  const _StarsPill();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: KidsScores.changes,
    builder: (context, _, _) => FutureBuilder<int>(
      future: KidsScores.starsToday(),
      builder: (context, snap) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(40)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFFD27A), size: 28),
            const SizedBox(width: 6),
            Text('${snap.data ?? 0} today', style: kidsText(20)),
          ],
        ),
      ),
    ),
  );
}

class _AppTile extends StatelessWidget {
  const _AppTile({required this.container, required this.app});
  final AppContainer container;
  final LauncherApp app;

  @override
  Widget build(BuildContext context) => KidsBounce(
    onTap: () => unawaited(container.commands.execute('launchApp', {'package': app.package})),
    child: Container(
      width: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Expanded(
            child: FutureBuilder<Uint8List?>(
              future: container.launcher.icon(app.package),
              initialData: container.launcher.cachedIcon(app.package),
              builder: (context, snap) => snap.data == null
                  ? const Icon(Icons.videogame_asset_rounded, color: Colors.white, size: 56)
                  : Image.memory(snap.data!, gaplessPlayback: true),
            ),
          ),
          const SizedBox(height: 6),
          Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: kidsText(16, weight: FontWeight.w700)),
        ],
      ),
    ),
  );
}

class _TimeLeftPill extends StatelessWidget {
  const _TimeLeftPill({required this.kids});
  final KidsManager kids;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int?>(
    valueListenable: kids.secondsLeft,
    builder: (context, left, _) {
      if (left == null) return const SizedBox.shrink();
      final minutes = (left / 60).ceil();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_bottom_rounded, color: Color(0xFFFFD27A), size: 26),
            const SizedBox(width: 8),
            Text('$minutes min', style: kidsText(22)),
          ],
        ),
      );
    },
  );
}

// ── Parent gate ────────────────────────────────────────────────────────

/// The lock in the corner: with a parent PIN, a tap asks for it; without
/// one, a three-second press-and-hold fills the ring and unlocks.
class _ParentLock extends StatefulWidget {
  const _ParentLock({required this.container});
  final AppContainer container;

  @override
  State<_ParentLock> createState() => _ParentLockState();
}

class _ParentLockState extends State<_ParentLock> with SingleTickerProviderStateMixin {
  late final _hold = AnimationController(vsync: this, duration: const Duration(seconds: 3))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _unlock();
    });

  KidsManager get kids => widget.container.kids;

  Future<void> _unlock() async {
    _hold.reset();
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => _ParentMenu(kids: kids),
    );
    if (choice == null) return;
    if (choice == 'leave') {
      await kids.leave();
    } else if (choice.startsWith('add:')) {
      await kids.addMinutes(int.parse(choice.substring(4)));
    }
  }

  bool _hint = false;
  Timer? _hintTimer;

  Future<void> _tap() async {
    if (!kids.hasPin) {
      // No PIN: the gate is a three-second hold. Say so to the grown-up who
      // just tapped, then fade the hint away.
      setState(() => _hint = true);
      _hintTimer?.cancel();
      _hintTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _hint = false);
      });
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _PinPad(check: kids.checkPin),
    );
    if (ok == true) await _unlock();
  }

  @override
  void dispose() {
    _hold.dispose();
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: _tap,
    onLongPressStart: kids.hasPin ? null : (_) => _hold.forward(from: 0),
    onLongPressEnd: kids.hasPin ? null : (_) {
      if (!_hold.isCompleted) _hold.reverse();
    },
    child: SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), shape: BoxShape.circle),
          ),
          AnimatedBuilder(
            animation: _hold,
            builder: (context, _) => CircularProgressIndicator(
              value: _hold.value,
              strokeWidth: 5,
              color: const Color(0xFFF5A623),
              backgroundColor: Colors.transparent,
            ),
          ),
          const Icon(Icons.lock_rounded, color: Colors.white, size: 30),
          Positioned(
            top: 70,
            right: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _hint ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Parents: press and hold',
                    style: kidsText(16, weight: FontWeight.w700),
                    softWrap: false,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ParentMenu extends StatelessWidget {
  const _ParentMenu({required this.kids});
  final KidsManager kids;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget action(IconData icon, String label, String value) => ListTile(
      leading: Icon(icon, color: scheme.primary),
      title: Text(label),
      onTap: () => Navigator.of(context).pop(value),
    );
    return AlertDialog(
      title: const Text('Parent options'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          action(Icons.exit_to_app_rounded, kids.locked ? 'Leave Kids Portal (Family profile)' : 'Leave Kids Portal', 'leave'),
          if (kids.secondsLeft.value != null) ...[
            action(Icons.more_time_rounded, 'Add 15 minutes', 'add:15'),
            action(Icons.more_time_rounded, 'Add 30 minutes', 'add:30'),
          ],
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
    );
  }
}

class _PinPad extends StatefulWidget {
  const _PinPad({required this.check});
  final bool Function(String) check;

  @override
  State<_PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<_PinPad> {
  String _entry = '';
  bool _wrong = false;

  void _press(String key) {
    setState(() {
      _wrong = false;
      if (key == '⌫') {
        if (_entry.isNotEmpty) _entry = _entry.substring(0, _entry.length - 1);
      } else if (_entry.length < 8) {
        _entry += key;
      }
    });
  }

  void _submit() {
    if (widget.check(_entry)) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _wrong = true;
        _entry = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String k) => Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: 76,
        height: 64,
        child: FilledButton.tonal(
          onPressed: () => _press(k),
          style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
          child: Text(k, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
        ),
      ),
    );
    return AlertDialog(
      title: const Text('Parent PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _wrong ? 'Wrong PIN, try again' : (_entry.isEmpty ? 'Enter the PIN' : '•' * _entry.length),
            style: TextStyle(fontSize: 24, letterSpacing: 4, color: _wrong ? scheme.error : scheme.onSurface),
          ),
          const SizedBox(height: 16),
          for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['⌫', '0']])
            Row(mainAxisSize: MainAxisSize.min, children: [for (final k in row) key(k)]),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: _entry.isEmpty ? null : _submit, child: const Text('Unlock')),
      ],
    );
  }
}

// ── Done and bedtime ───────────────────────────────────────────────────

class _KidsDone extends StatelessWidget {
  const _KidsDone({super.key, required this.container});
  final AppContainer container;

  @override
  Widget build(BuildContext context) => _KidsGround(
    colors: const [Color(0xFF3B1E6B), Color(0xFF1A1340), Color(0xFF0F1115)],
    child: SafeArea(
      child: Stack(
        children: [
          Positioned(top: 20, right: 28, child: _ParentLock(container: container)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, color: Color(0xFFFFD27A), size: 160),
                const SizedBox(height: 12),
                Text('Great playing today!', style: kidsText(52)),
                const SizedBox(height: 12),
                Text(
                  'Screen time is all done. Time for something else!',
                  style: kidsText(26, color: Colors.white70, weight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _KidsBedtime extends StatefulWidget {
  const _KidsBedtime({super.key, required this.container});
  final AppContainer container;

  @override
  State<_KidsBedtime> createState() => _KidsBedtimeState();
}

class _KidsBedtimeState extends State<_KidsBedtime> {
  late Timer _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.container.kids.childName;
    final h = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final time = '$h:${_now.minute.toString().padLeft(2, '0')}';
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1030), Color(0xFF070912)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: CustomPaint(painter: _StarsPainter())),
          SafeArea(
            child: Stack(
              children: [
                Positioned(top: 20, right: 28, child: _ParentLock(container: widget.container)),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.nightlight_round, color: Color(0xFFFFE9A8), size: 120),
                      Text(time, style: kidsText(120, color: const Color(0xFFDDE3FF), weight: FontWeight.w300)),
                      Text(
                        name.isEmpty ? 'Sweet dreams' : 'Sweet dreams, $name',
                        style: kidsText(40, color: const Color(0xFFB8C2FF)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StarsPainter extends CustomPainter {
  const _StarsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < 90; i++) {
      final o = Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height);
      paint.color = Colors.white.withValues(alpha: 0.25 + rng.nextDouble() * 0.6);
      canvas.drawCircle(o, 0.8 + rng.nextDouble() * 1.8, paint);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) => false;
}
