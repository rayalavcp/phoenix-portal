import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_container.dart';
import '../../managers/home/homework.dart';
import 'kids_activities.dart';
import 'kids_games.dart';
import 'kids_logic.dart' show KidsScores;
import 'kids_overlay.dart' show askKidsParentPin;

/// Homework: the spelling list and times tables a grown-up set (on the
/// Portal behind the parent PIN, or in the remote admin), practised the
/// way school does it. Spelling is Look, Cover, Write, Check: the word
/// shows, hides, the child types it, then sees how it went; a word spelled
/// wrong comes back once at the end. Times tables are typed answers on a
/// number pad. Every answer goes into the day's report.

/// A spelling answer counts when it matches, ignoring case and spaces.
bool spellingMatches(String typed, String word) => typed.trim().toLowerCase() == word.trim().toLowerCase();

/// A round of times questions from [tables]: each table's 1 to 12 once,
/// shuffled, at most [count].
List<(int, int)> timesRound(List<int> tables, math.Random rng, {int count = 15}) {
  final all = [
    for (final t in tables)
      for (var n = 1; n <= 12; n++) (t, n),
  ]..shuffle(rng);
  return all.take(count).toList();
}

class HomeworkGame extends StatefulWidget {
  const HomeworkGame({super.key, required this.container, required this.onBack});
  final AppContainer container;
  final VoidCallback onBack;

  @override
  State<HomeworkGame> createState() => _HomeworkGameState();
}

enum _Phase { start, look, write, check, done }

class _HomeworkGameState extends State<HomeworkGame> {
  final _rng = math.Random();
  HomeworkStore get _hw => widget.container.phoenixHome.homework;

  _Phase _phase = _Phase.start;
  int _mode = 0; // 0 spelling, 1 times
  final _queue = <String>[];
  final _retried = <String>{};
  List<(int, int)> _sums = const [];
  int _at = 0, _right = 0, _asked = 0;
  String _typed = '';
  bool _wasRight = false;
  Timer? _lookTimer;

  bool get _spelling => _mode == 0;
  String get _word => _queue[_at];

  @override
  void dispose() {
    _lookTimer?.cancel();
    super.dispose();
  }

  List<int> get _modes => [if (_hw.words.value.isNotEmpty) 0, if (_hw.tables.value.isNotEmpty) 1];

  void _start() {
    final modes = _modes;
    if (modes.isEmpty) return;
    if (!modes.contains(_mode)) _mode = modes.first;
    setState(() {
      _at = 0;
      _right = 0;
      _asked = 0;
      _typed = '';
      _retried.clear();
      _queue
        ..clear()
        ..addAll([..._hw.words.value]..shuffle(_rng));
      _sums = timesRound(_hw.tables.value, _rng);
    });
    _spelling ? _look() : setState(() => _phase = _Phase.write);
  }

  void _look() {
    setState(() {
      _phase = _Phase.look;
      _typed = '';
    });
    _lookTimer?.cancel();
    _lookTimer = Timer(Duration(milliseconds: 2500 + _word.length * 250), _cover);
  }

  void _cover() {
    _lookTimer?.cancel();
    if (mounted && _phase == _Phase.look) setState(() => _phase = _Phase.write);
  }

  Future<void> _checkAnswer() async {
    if (_typed.isEmpty) return;
    final right = _spelling
        ? spellingMatches(_typed, _word)
        : int.tryParse(_typed) == _sums[_at].$1 * _sums[_at].$2;
    _asked++;
    if (right) _right++;
    if (_spelling && !right && _retried.add(_word)) _queue.add(_word);
    unawaited(_hw.record(_spelling ? 'spelling' : 'times', right));
    setState(() {
      _wasRight = right;
      _phase = _Phase.check;
    });
  }

  Future<void> _next() async {
    final total = _spelling ? _queue.length : _sums.length;
    if (_at + 1 >= total) {
      final stars = _stars;
      await KidsScores.addStars(stars);
      if (mounted) setState(() => _phase = _Phase.done);
      return;
    }
    setState(() {
      _at++;
      _typed = '';
    });
    _spelling ? _look() : setState(() => _phase = _Phase.write);
  }

  int get _stars {
    if (_asked == 0) return 0;
    final share = _right / _asked;
    return share >= 0.9 ? 3 : (share >= 0.7 ? 2 : (share >= 0.4 ? 1 : 0));
  }

  Future<void> _setHomework() async {
    if (!await askKidsParentPin(context, widget.container.kids)) return;
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (_) => HomeworkEditor(store: _hw));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => KidsActivityFrame(
    title: 'Homework',
    colors: const [Color(0xFF2F6F5E), Color(0xFF5B8DEF)],
    onBack: widget.onBack,
    trailing: _phase == _Phase.start || _phase == _Phase.done
        ? null
        : Text(
            '${_at + 1} of ${_spelling ? _queue.length : _sums.length}   Right $_right',
            style: kidsText(24),
          ),
    child: switch (_phase) {
      _Phase.start => _startPanel(),
      _Phase.done => KidsResult(
        title: _stars >= 2 ? 'Homework done!' : 'Good practice!',
        detail: '$_right of $_asked right',
        stars: _stars,
        newBest: false,
        onAgain: () => setState(() => _phase = _Phase.start),
      ),
      _ => _spelling ? _spellingView() : _timesView(),
    },
  );

  Widget _startPanel() {
    final modes = _modes;
    final setButton = TextButton.icon(
      onPressed: () => unawaited(_setHomework()),
      icon: const Icon(Icons.edit_note_rounded, color: Colors.white70),
      label: Text('Set homework (grown-ups)', style: kidsText(16, color: Colors.white70, weight: FontWeight.w600)),
    );
    if (modes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_rounded, size: 80, color: Colors.white),
            const SizedBox(height: 12),
            Text('No homework yet!', style: kidsText(30)),
            const SizedBox(height: 6),
            Text(
              'A grown-up can add spelling words and times tables here,\nor in the remote admin (Phoenix > Kids Portal).',
              textAlign: TextAlign.center,
              style: kidsText(18, weight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            setButton,
          ],
        ),
      );
    }
    final labels = [
      if (modes.contains(0)) 'Spelling (${_hw.words.value.length} words)',
      if (modes.contains(1)) 'Times tables (${_hw.tables.value.map((t) => '×$t').join(' ')})',
    ];
    final picked = modes.indexOf(_mode).clamp(0, modes.length - 1);
    return KidsStartPanel(
      icon: Icons.menu_book_rounded,
      pitch: 'Practise this week\'s homework. Spelling: look at the word, remember it, then type it.',
      options: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          kidsLevelChips(labels, picked, (i) => setState(() => _mode = modes[i])),
          const SizedBox(height: 6),
          setButton,
        ],
      ),
      onStart: _start,
    );
  }

  Widget _spellingView() {
    final word = _word;
    final Widget top = switch (_phase) {
      _Phase.look => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Look and remember', style: kidsText(24, weight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(word, style: kidsText(72)),
          const SizedBox(height: 10),
          FilledButton(onPressed: _cover, child: const Text('I remember it!')),
        ],
      ),
      _Phase.check => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_wasRight ? Icons.check_circle_rounded : Icons.highlight_off_rounded, size: 56, color: _wasRight ? const Color(0xFF7CE38B) : const Color(0xFFFF9A8B)),
          Text(_wasRight ? 'Right!' : 'Nearly! It is spelled', style: kidsText(26)),
          Text(word, style: kidsText(64, color: const Color(0xFFF3DA8A))),
          if (!_wasRight) Text('You wrote: $_typed', style: kidsText(20, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          FilledButton(onPressed: () => unawaited(_next()), child: const Text('Next')),
        ],
      ),
      _ => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Now write it', style: kidsText(24, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          _Slots(text: _typed, length: math.max(word.length, _typed.length)),
        ],
      ),
    };
    return LayoutBuilder(
      builder: (context, box) => Column(
        children: [
          Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: top))),
          if (_phase == _Phase.write)
            _Keyboard(
              maxHeight: box.maxHeight * 0.45,
              onKey: (k) => setState(() => _typed += k),
              onBack: () => setState(() => _typed = _typed.isEmpty ? '' : _typed.substring(0, _typed.length - 1)),
              onDone: () => unawaited(_checkAnswer()),
            ),
        ],
      ),
    );
  }

  Widget _timesView() {
    final (a, b) = _sums[_at];
    final top = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$a × $b = ${_phase == _Phase.check ? a * b : (_typed.isEmpty ? '?' : _typed)}', style: kidsText(80)),
        if (_phase == _Phase.check) ...[
          Icon(_wasRight ? Icons.check_circle_rounded : Icons.highlight_off_rounded, size: 48, color: _wasRight ? const Color(0xFF7CE38B) : const Color(0xFFFF9A8B)),
          if (!_wasRight) Text('You wrote $_typed', style: kidsText(20, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          FilledButton(onPressed: () => unawaited(_next()), child: const Text('Next')),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, box) => Column(
        children: [
          Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: top))),
          if (_phase == _Phase.write)
            _NumberPad(
              maxHeight: box.maxHeight * 0.5,
              onKey: (k) => setState(() => _typed = (_typed + k).length > 3 ? _typed : _typed + k),
              onBack: () => setState(() => _typed = _typed.isEmpty ? '' : _typed.substring(0, _typed.length - 1)),
              onDone: () => unawaited(_checkAnswer()),
            ),
        ],
      ),
    );
  }
}

/// The letters typed so far, one box each.
class _Slots extends StatelessWidget {
  const _Slots({required this.text, required this.length});
  final String text;
  final int length;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < length; i++)
        Container(
          width: 52,
          height: 64,
          margin: const EdgeInsets.all(4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: i == text.length ? Colors.white : Colors.white30, width: 2),
          ),
          child: Text(i < text.length ? text[i] : '', style: kidsText(36)),
        ),
    ],
  );
}

Widget _key(String label, VoidCallback onTap, {double flex = 1, Color? color, IconData? icon}) => Expanded(
  flex: (flex * 10).round(),
  child: Padding(
    padding: const EdgeInsets.all(3),
    child: Material(
      color: color ?? Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: icon != null
              ? Icon(icon, color: Colors.white, size: 30, semanticLabel: label)
              : FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: kidsText(26))),
        ),
      ),
    ),
  ),
);

/// A big a-to-z keyboard.
class _Keyboard extends StatelessWidget {
  const _Keyboard({required this.maxHeight, required this.onKey, required this.onBack, required this.onDone});
  final double maxHeight;
  final ValueChanged<String> onKey;
  final VoidCallback onBack, onDone;

  static const _rows = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];

  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.min(maxHeight, 260),
    child: Column(
      children: [
        for (final (i, row) in _rows.indexed)
          Expanded(
            child: Row(
              children: [
                if (i == 1) const Spacer(flex: 5),
                if (i == 2) _key('Delete', onBack, flex: 1.5, icon: Icons.backspace_outlined),
                for (final k in row.split('')) _key(k, () => onKey(k)),
                if (i == 2) _key('Check', onDone, flex: 2, color: const Color(0xFF2F9E6B)),
                if (i == 1) const Spacer(flex: 5),
              ],
            ),
          ),
      ],
    ),
  );
}

/// A big 0-to-9 pad.
class _NumberPad extends StatelessWidget {
  const _NumberPad({required this.maxHeight, required this.onKey, required this.onBack, required this.onDone});
  final double maxHeight;
  final ValueChanged<String> onKey;
  final VoidCallback onBack, onDone;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.min(maxHeight, 280),
    child: Center(
      child: SizedBox(
        width: 420,
        child: Column(
          children: [
            for (final row in const ['123', '456', '789'])
              Expanded(child: Row(children: [for (final k in row.split('')) _key(k, () => onKey(k))])),
            Expanded(
              child: Row(
                children: [
                  _key('Delete', onBack, icon: Icons.backspace_outlined),
                  _key('0', () => onKey('0')),
                  _key('Check', onDone, color: const Color(0xFF2F9E6B)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Where a grown-up sets the spelling words and times tables.
class HomeworkEditor extends StatefulWidget {
  const HomeworkEditor({super.key, required this.store});
  final HomeworkStore store;

  @override
  State<HomeworkEditor> createState() => _HomeworkEditorState();
}

class _HomeworkEditorState extends State<HomeworkEditor> {
  late final _words = TextEditingController(text: widget.store.words.value.join(', '));
  late final _tables = {...widget.store.tables.value};

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set homework'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _words,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Spelling words',
                hintText: 'friend, because, people, beautiful',
                helperText: 'Separate them with commas or new lines (up to 40)',
              ),
            ),
            const SizedBox(height: 16),
            const Text('Times tables'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var t = 1; t <= 12; t++)
                  FilterChip(
                    label: Text('×$t'),
                    selected: _tables.contains(t),
                    onSelected: (on) => setState(() => on ? _tables.add(t) : _tables.remove(t)),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () async {
          await widget.store.setWords(HomeworkStore.parseWords(_words.text));
          await widget.store.setTables(_tables.toList());
          if (context.mounted) Navigator.pop(context);
        },
        child: const Text('Save'),
      ),
    ],
  );
}
