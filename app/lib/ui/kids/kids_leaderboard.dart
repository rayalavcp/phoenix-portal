import 'dart:async';

import 'package:flutter/material.dart';

import 'kids_activities.dart';
import 'kids_logic.dart';

/// The Kids Portal's arcade-style leaderboards: a score that makes a game's
/// top ten asks for a name, and the Leaderboard page lists every game's
/// top ten. Kept on the device, cleared with the scores from the remote
/// admin.

const _titles = {
  'math': 'Math Blitz',
  'words': 'Word Scramble',
  '2048': '2048',
  'maze': 'Maze', //
  'wordsearch': 'Word Search',
  'guess': 'Word Guess',
  'snake': 'Snake',
  'simon': 'Simon Says',
  'times': 'Times Tables',
  'clock': 'Telling the Time',
  'flags': 'Flag Quiz',
  'patterns': 'Patterns',
  'fractions': 'Fractions',
  'money': 'Money',
  'science': 'Science',
  'spelling': 'Spelling',
  'opposites': 'Opposites',
  'count': 'Count It',
  'letters': 'Letter Sounds',
  'placevalue': 'Place Value',
  'story': 'Story Sums',
  'telugu': 'Telugu Words',
  'sudoku': 'Sudoku',
  'memory': 'Memory Pro',
  'lights': 'Lights Out',
  'mole': 'Whack-a-Mole',
  'munch': 'Munch Maze',
  'bricks': 'Brick Bash',
  'hop': 'Hop Across',
  'sky': 'Sky Glide',
  'run': 'Fox Run',
  'bubbles': 'Bubble Pop',
  'catch': 'Fruit Catcher',
  'blaster': 'Space Blaster',
  'fingermath': 'Finger Math',
  'walls': 'Wall Dodge', 'trace': 'Air Trace', 'freeze': 'Freeze Dance',
};

const _maps = {'usa': 'USA Map', 'india': 'India Map', 'world': 'World Map'};

/// A leaderboard's name for score [key]: the game, and the level or size
/// when the key carries one ("Lights Out · 5×5", "Snake").
String boardTitle(String key) {
  if (key.startsWith('map_')) {
    final parts = key.split('_');
    final map = _maps[parts.length > 1 ? parts[1] : ''] ?? 'Map';
    if (parts.length < 3) return map;
    final m = RegExp(r'^([a-z]+)(\d*)$').firstMatch(parts[2]);
    final mode = m?.group(1) ?? parts[2];
    final label = switch (mode) {
      'find' => 'Find it',
      'name' => 'Name it',
      'capital' => 'Capitals',
      'continent' => 'Continents',
      'flag' => 'Flags',
      'fill' => 'Fill the map',
      'memory' => 'Shape memory',
      _ => mode,
    };
    final level = m?.group(2) ?? '';
    return '$map · $label${level.isEmpty ? '' : ' $level'}';
  }
  if (key == 'ttteasy' || key == 'ttthard') {
    return 'Tic-Tac-Toe · ${key.endsWith('hard') ? 'Hard' : 'Easy'}';
  }
  if (key == 'c4easy' || key == 'c4hard') {
    return 'Connect Four · ${key.endsWith('hard') ? 'Hard' : 'Easy'}';
  }
  // Quizzes: "times" is level 1, "times.2" level 3.
  final quiz = RegExp(r'^([a-z]+)\.(\d+)$').firstMatch(key);
  if (quiz != null && _titles.containsKey(quiz.group(1))) {
    return '${_titles[quiz.group(1)]} · Level ${int.parse(quiz.group(2)!) + 1}';
  }
  final m = RegExp(r'^([a-z]+)(\d+)$').firstMatch(key);
  if (m != null && _titles.containsKey(m.group(1))) {
    final base = m.group(1)!, n = m.group(2)!;
    final rest = switch (base) {
      'sudoku' || 'lights' => '$n×$n',
      'memory' => '$n pairs',
      _ => 'Stage $n',
    };
    return '${_titles[base]} · $rest';
  }
  if (key == 'memory') return 'Memory Pro · 8 pairs';
  return _titles[key] ?? key;
}

/// How a score on [key]'s leaderboard reads: a time, moves or points.
String boardScore(String key, int score) {
  final timed =
      key.startsWith('sudoku') ||
      key.startsWith('memory') ||
      key == 'maze' ||
      key == 'wordsearch';
  if (timed) return '${score ~/ 60}:${(score % 60).toString().padLeft(2, '0')}';
  if (key.startsWith('lights') ||
      (key.startsWith('map_') && key.contains('_memory'))) {
    return '$score moves';
  }
  return '$score';
}

/// Asks for the name of a player whose score made a top ten, arcade style.
/// Shown over the game when [KidsScores.pendingEntry] fills.
Future<void> askHighScoreName(BuildContext context) async {
  final entry = KidsScores.pendingEntry.value;
  if (entry == null) return;
  KidsScores.pendingEntry.value = null;
  final names = await KidsScores.recentNames();
  if (!context.mounted) return;
  final name = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => _NameDialog(entry: entry, names: names),
  );
  if (name == null) return;
  await KidsScores.addToBoard(
    entry.game,
    entry.score,
    name,
    lowerIsBetter: entry.lowerIsBetter,
  );
}

/// Every game's top ten, medals for the first three.
class KidsLeaderboard extends StatefulWidget {
  const KidsLeaderboard({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<KidsLeaderboard> createState() => _KidsLeaderboardState();
}

class _KidsLeaderboardState extends State<KidsLeaderboard> {
  late Future<List<(String, List<KidsBoardEntry>)>> _boards = _load();

  Future<List<(String, List<KidsBoardEntry>)>> _load() async {
    final games = await KidsScores.boardGames();
    final boards =
        [
            for (final g in games) (g, await KidsScores.leaderboard(g)),
          ].where((b) => b.$2.isNotEmpty).toList()
          ..sort((a, b) => boardTitle(a.$1).compareTo(boardTitle(b.$1)));
    return boards;
  }

  @override
  void initState() {
    super.initState();
    KidsScores.changes.addListener(_reload);
  }

  void _reload() => setState(() => _boards = _load());

  @override
  void dispose() {
    KidsScores.changes.removeListener(_reload);
    super.dispose();
  }

  // Gold, silver and bronze trophies (icons, so they look the same on
  // every screen, emoji font or not).
  static const _medals = [Color(0xFFF2CF6E), Color(0xFFD5DAE3), Color(0xFFD9A07A)];

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Leaderboard',
    colors: const [Color(0xFF3B2A8C), Color(0xFFB06BFF)],
    onBack: widget.onBack,
    child: FutureBuilder<List<(String, List<KidsBoardEntry>)>>(
      future: _boards,
      builder: (context, snap) {
        final boards = snap.data;
        if (boards == null) return const SizedBox.shrink();
        if (boards.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No high scores yet.\nPlay a game: a top ten score asks for your name!',
                textAlign: TextAlign.center,
                style: kidsText(24),
              ),
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth > 1100 ? 3 : (box.maxWidth > 700 ? 2 : 1);
            final w = (box.maxWidth - 32 - 16 * (cols - 1)) / cols;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final (game, entries) in boards)
                    SizedBox(
                      width: w,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              boardTitle(game),
                              style: kidsText(20),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            for (var i = 0; i < entries.length; i++)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 38,
                                      child: i < 3
                                          ? Align(
                                              alignment: Alignment.centerLeft,
                                              child: Icon(
                                                Icons.emoji_events_rounded,
                                                color: _medals[i],
                                                size: 24,
                                              ),
                                            )
                                          : Text(
                                              '${i + 1}.',
                                              style: kidsText(
                                                17,
                                                color: Colors.white60,
                                              ),
                                            ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        entries[i].name,
                                        style: kidsText(18),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      boardScore(game, entries[i].score),
                                      style: kidsText(
                                        18,
                                        color: const Color(0xFFF2CF6E),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}

/// The trophy button on the hub that opens the leaderboard.
class KidsLeaderboardButton extends StatelessWidget {
  const KidsLeaderboardButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KidsBounce(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_rounded, color: Color(0xFFF2CF6E), size: 24),
          const SizedBox(width: 6),
          Text('Top 10', style: kidsText(18)),
        ],
      ),
    ),
  );
}

/// Shows [askHighScoreName] whenever a score makes a top ten while [child]
/// (the Kids Portal) is up.
class KidsHighScoreListener extends StatefulWidget {
  const KidsHighScoreListener({super.key, required this.child});
  final Widget child;

  @override
  State<KidsHighScoreListener> createState() => _KidsHighScoreListenerState();
}

class _KidsHighScoreListenerState extends State<KidsHighScoreListener> {
  @override
  void initState() {
    super.initState();
    KidsScores.pendingEntry.addListener(_ask);
  }

  void _ask() {
    if (KidsScores.pendingEntry.value == null) return;
    // After the frame: the game is still drawing its result.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(askHighScoreName(context));
    });
  }

  @override
  void dispose() {
    KidsScores.pendingEntry.removeListener(_ask);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.entry, required this.names});
  final ({String game, int score, bool lowerIsBetter, int place}) entry;
  final List<String> names;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _field = TextEditingController(
    text: widget.names.isEmpty ? '' : widget.names.first,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF1B1E33),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    title: Row(
      children: [
        const Icon(Icons.emoji_events_rounded, color: Color(0xFFF2CF6E), size: 36),
        const SizedBox(width: 10),
        Expanded(child: Text('New high score!', style: kidsText(28))),
      ],
    ),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '#${widget.entry.place} in ${boardTitle(widget.entry.game)}: ${boardScore(widget.entry.game, widget.entry.score)}',
            style: kidsText(18, color: const Color(0xFFF2CF6E)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _field,
            autofocus: true,
            maxLength: 12,
            textCapitalization: TextCapitalization.words,
            style: kidsText(24),
            decoration: InputDecoration(
              hintText: 'Your name',
              hintStyle: kidsText(22, color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              counterStyle: const TextStyle(color: Colors.white54),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          if (widget.names.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in widget.names)
                  ActionChip(
                    label: Text(n, style: kidsText(16)),
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    side: BorderSide.none,
                    onPressed: () => Navigator.pop(context, n),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('Skip', style: kidsText(18, color: Colors.white70)),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE7B663),
          foregroundColor: const Color(0xFF2A1A00),
        ),
        onPressed: () => Navigator.pop(context, _field.text),
        child: Text(
          'Save',
          style: kidsText(18, color: const Color(0xFF2A1A00)),
        ),
      ),
    ],
  );
}
