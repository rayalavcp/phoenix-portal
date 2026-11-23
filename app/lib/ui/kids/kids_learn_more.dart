import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../managers/home/telugu_words.dart';
import 'kids_activities.dart';
import 'kids_learn.dart';

/// More of the Learn shelf, pitched at early grades: Count It, Letter
/// Sounds, Place Value, Story Sums and Telugu Words. Each is a KidsQuiz
/// with levels; the questions come from the functions here (tested).

/// A question with four answers to pick from.
@immutable
class LearnQuestion {
  const LearnQuestion(this.prompt, this.answer, this.choices, {this.explain, this.emoji, this.count = 0, this.tens = 0});
  final String prompt;
  final String answer;
  final List<String> choices;
  final String? explain;

  /// A picture for the prompt (Letter Sounds, Count It, Story Sums).
  final String? emoji;

  /// Count It: how many pictures, or ten-rods and ones.
  final int count, tens;
}

/// [answer] and three other numbers close to it (all above zero).
List<String> nearNumbers(int answer, math.Random rng, {int spread = 3}) {
  final out = <int>{answer};
  for (var guard = 0; out.length < 4; guard++) {
    final n = guard > 40 ? answer + out.length * 5 : answer + (1 + rng.nextInt(spread)) * (rng.nextBool() ? 1 : -1);
    if (n > 0) out.add(n);
  }
  return [for (final n in out.toList()..shuffle(rng)) '$n'];
}

// ── Count It ──────────────────────────────────────────────────────────────

const _countThings = ['🍎', '⭐', '🐟', '🌸', '🚗', '🎈', '🐞', '🍓', '⚽', '🐥'];

/// Level 0 counts up to 5, 1 up to 10, 2 up to 20, 3 tens and ones.
LearnQuestion countQuestion(int level, math.Random rng) {
  final emoji = _countThings[rng.nextInt(_countThings.length)];
  if (level >= 3) {
    final tens = 1 + rng.nextInt(9), ones = rng.nextInt(10);
    final n = tens * 10 + ones;
    return LearnQuestion(
      'How many blocks?',
      '$n',
      nearNumbers(n, rng, spread: 11),
      explain: '$tens tens and $ones ones make $n',
      count: ones,
      tens: tens,
    );
  }
  final n = switch (level) {
    0 => 1 + rng.nextInt(5),
    1 => 3 + rng.nextInt(8),
    _ => 8 + rng.nextInt(13),
  };
  return LearnQuestion('How many?', '$n', nearNumbers(n, rng, spread: level == 0 ? 2 : 3), explain: 'There are $n', emoji: emoji, count: n);
}

// ── Letter Sounds ─────────────────────────────────────────────────────────

/// Pictures and their words, for phonics (emoji every Portal shows).
const kidsPictureWords = <(String, String)>[
  ('🍎', 'apple'), ('🐻', 'bear'), ('🐱', 'cat'), ('🐶', 'dog'), ('🥚', 'egg'), ('🐟', 'fish'),
  ('🍇', 'grapes'), ('🎩', 'hat'), ('🦁', 'lion'), ('🌙', 'moon'), ('👃', 'nose'), ('🐙', 'octopus'),
  ('🐷', 'pig'), ('👑', 'crown'), ('🌈', 'rainbow'), ('🐯', 'tiger'), ('☂️', 'umbrella'), ('🎻', 'violin'),
  ('🐳', 'whale'), ('🦊', 'fox'), ('🦓', 'zebra'), ('🚗', 'car'), ('🐸', 'frog'), ('🍌', 'banana'),
  ('⭐', 'star'), ('🌳', 'tree'), ('⚽', 'ball'), ('🦆', 'duck'), ('🐴', 'horse'), ('🚌', 'bus'),
  ('🎂', 'cake'), ('🐮', 'cow'), ('🦉', 'owl'), ('🐝', 'bee'), ('🐜', 'ant'), ('🤖', 'robot'),
  ('🚀', 'rocket'), ('🏠', 'house'), ('📖', 'book'), ('👟', 'shoe'), ('🐦', 'bird'), ('🐍', 'snake'),
  ('🐢', 'turtle'), ('🐧', 'penguin'), ('🚂', 'train'), ('⛵', 'boat'), ('🔑', 'key'), ('🎁', 'gift'),
  ('🍕', 'pizza'), ('🍞', 'bread'), ('🧀', 'cheese'), ('🌽', 'corn'), ('🥕', 'carrot'), ('🍋', 'lemon'),
  ('🥛', 'milk'), ('🐰', 'rabbit'), ('🐭', 'mouse'), ('🐘', 'elephant'), ('🌵', 'cactus'), ('🐒', 'monkey'),
  ('🦀', 'crab'), ('🎈', 'balloon'), ('☀️', 'sun'), ('🐑', 'sheep'),
];

const _alphabet = 'abcdefghijklmnopqrstuvwxyz';

/// [word] with one letter changed, swapped, doubled or dropped: a
/// believable misspelling, never the word itself.
String misspell(String word, math.Random rng) {
  for (var guard = 0; guard < 30; guard++) {
    final i = rng.nextInt(word.length);
    final out = switch (rng.nextInt(4)) {
      0 => word.replaceRange(i, i + 1, _alphabet[rng.nextInt(26)]),
      1 when i + 1 < word.length => word.replaceRange(i, i + 2, '${word[i + 1]}${word[i]}'),
      2 => word.replaceRange(i, i + 1, '${word[i]}${word[i]}'),
      _ when word.length > 3 => word.replaceRange(i, i + 1, ''),
      _ => word.replaceRange(i, i + 1, 'aeiou'[rng.nextInt(5)]),
    };
    if (out != word) return out;
  }
  return '${word}e';
}

/// Level 0 the first letter, 1 the last, 2 a missing letter, 3 the spelling.
LearnQuestion letterQuestion(int level, math.Random rng) {
  final (emoji, word) = kidsPictureWords[rng.nextInt(kidsPictureWords.length)];
  List<String> letters(String answer) {
    final out = <String>{answer};
    while (out.length < 4) {
      out.add(_alphabet[rng.nextInt(26)].toUpperCase());
    }
    return out.toList()..shuffle(rng);
  }

  switch (level) {
    case 0:
      final a = word[0].toUpperCase();
      return LearnQuestion('What does it start with?', a, letters(a), explain: '${word[0].toUpperCase()}${word.substring(1)} starts with $a', emoji: emoji);
    case 1:
      final a = word[word.length - 1].toUpperCase();
      return LearnQuestion('What does it end with?', a, letters(a), explain: '${word[0].toUpperCase()}${word.substring(1)} ends with $a', emoji: emoji);
    case 2:
      final i = rng.nextInt(word.length);
      final a = word[i].toUpperCase();
      final shown = '${word.substring(0, i)}_${word.substring(i + 1)}';
      return LearnQuestion('$shown\nWhich letter is missing?', a, letters(a), explain: 'It is spelled $word', emoji: emoji);
    default:
      final out = <String>{word};
      while (out.length < 4) {
        out.add(misspell(word, rng));
      }
      return LearnQuestion('How do you spell it?', word, out.toList()..shuffle(rng), explain: 'It is spelled $word', emoji: emoji);
  }
}

// ── Place Value ───────────────────────────────────────────────────────────

/// Level 0 tens and ones, 1 hundreds, 2 expanded form, 3 biggest and
/// smallest.
LearnQuestion placeValueQuestion(int level, math.Random rng) {
  switch (level) {
    case 0:
      final t = 1 + rng.nextInt(9), o = rng.nextInt(10), n = t * 10 + o;
      return rng.nextBool()
          ? LearnQuestion('How many tens are in $n?', '$t', nearNumbers(t, rng, spread: 2), explain: '$n is $t tens and $o ones')
          : LearnQuestion('$t tens and $o ones make…', '$n', nearNumbers(n, rng, spread: 10), explain: '$t tens and $o ones make $n');
    case 1:
      final h = 1 + rng.nextInt(9), t = rng.nextInt(10), o = rng.nextInt(10), n = h * 100 + t * 10 + o;
      if (rng.nextBool()) {
        final digits = <String>{'$h'};
        for (final d in ['$t', '$o', '${(h + 1) % 10}', '${(h + 5) % 10}']) {
          if (digits.length < 4) digits.add(d);
        }
        while (digits.length < 4) {
          digits.add('${rng.nextInt(10)}');
        }
        return LearnQuestion('Which digit is in the hundreds place in $n?', '$h', digits.toList()..shuffle(rng), explain: '$n has $h hundreds');
      }
      // The value of the tens digit (pick a number whose tens digit is not 0).
      final tt = 1 + rng.nextInt(9), nn = h * 100 + tt * 10 + o;
      final value = tt * 10;
      final choices = <String>{'$value', '$tt', '${tt * 100}', '${tt + 10}'};
      while (choices.length < 4) {
        choices.add('${(1 + rng.nextInt(9)) * 10}');
      }
      return LearnQuestion('What is the value of the $tt in $nn?', '$value', choices.toList()..shuffle(rng), explain: 'The $tt is in the tens place: $value');
    case 2:
      final h = 1 + rng.nextInt(9), t = 1 + rng.nextInt(9), o = rng.nextInt(10), n = h * 100 + t * 10 + o;
      if (rng.nextBool()) {
        final choices = {n, h * 100 + o * 10 + t, t * 100 + h * 10 + o, n + 100, n + 10, n - 1};
        final four = ({n}..addAll(choices.where((c) => c != n).take(3))).toList()..shuffle(rng);
        return LearnQuestion('${h * 100} + ${t * 10} + $o = ?', '$n', [for (final c in four) '$c'], explain: '${h * 100} + ${t * 10} + $o = $n');
      }
      return LearnQuestion('$n = ${h * 100} + ? + $o', '${t * 10}', [for (final c in {t * 10, t, t * 100, (t + 1) * 10}.toList()..shuffle(rng)) '$c'], explain: '$n = ${h * 100} + ${t * 10} + $o');
    default:
      final digits = <int>{1 + rng.nextInt(9)};
      while (digits.length < 3) {
        digits.add(rng.nextInt(10));
      }
      final d = digits.toList();
      final nums = <int>{};
      for (final p in [
        [0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0],
      ]..shuffle(rng)) {
        final n = d[p[0]] * 100 + d[p[1]] * 10 + d[p[2]];
        if (n >= 100 && nums.length < 4) nums.add(n);
      }
      while (nums.length < 4) {
        nums.add(100 + rng.nextInt(900));
      }
      final biggest = rng.nextBool();
      final list = nums.toList()..shuffle(rng);
      final a = biggest ? list.reduce(math.max) : list.reduce(math.min);
      return LearnQuestion(biggest ? 'Which number is the biggest?' : 'Which number is the smallest?', '$a', [for (final n in list) '$n'], explain: '$a is the ${biggest ? 'biggest' : 'smallest'}');
  }
}

// ── Story Sums ────────────────────────────────────────────────────────────

const _storyNames = ['Maya', 'Leo', 'Aria', 'Sam', 'Noah', 'Zoe', 'Ravi', 'Mia', 'Ben', 'Ivy', 'Arjun', 'Lily'];
const _storyThings = [
  ('apples', '🍎'), ('stickers', '⭐'), ('marbles', '🔵'), ('books', '📚'),
  ('crayons', '🖍️'), ('shells', '🐚'), ('cookies', '🍪'), ('balloons', '🎈'),
];

/// A word problem: level 0 adding to 20, 1 taking away within 20, 2 adding
/// or taking away to 100, 3 equal groups (times and sharing).
({LearnQuestion question, int a, int b, String op}) storyQuestion(int level, math.Random rng) {
  final name = _storyNames[rng.nextInt(_storyNames.length)];
  final (thing, emoji) = _storyThings[rng.nextInt(_storyThings.length)];
  late final int a, b, answer;
  late final String op, text;
  switch (level) {
    case 0:
      a = 2 + rng.nextInt(10);
      b = 1 + rng.nextInt(20 - a);
      answer = a + b;
      op = '+';
      text = '$name has $a $thing and gets $b more. How many $thing now?';
    case 1:
      a = 8 + rng.nextInt(13);
      b = 1 + rng.nextInt(a - 2);
      answer = a - b;
      op = '−';
      text = '$name has $a $thing and gives $b away. How many are left?';
    case 2:
      if (rng.nextBool()) {
        a = 12 + rng.nextInt(50);
        b = 8 + rng.nextInt(100 - a - 8);
        answer = a + b;
        op = '+';
        text = 'The class has $a $thing. $b more come in a box. How many $thing in all?';
      } else {
        a = 40 + rng.nextInt(60);
        b = 6 + rng.nextInt(a - 12);
        answer = a - b;
        op = '−';
        text = 'There are $a $thing. $b get used. How many are left?';
      }
    default:
      final groups = 2 + rng.nextInt(5), each = 2 + rng.nextInt(6);
      if (rng.nextBool()) {
        a = groups;
        b = each;
        answer = groups * each;
        op = '×';
        text = 'There are $groups bags with $each $thing in each bag. How many $thing in all?';
      } else {
        a = groups * each;
        b = groups;
        answer = each;
        op = '÷';
        text = '$name shares $a $thing equally with $groups friends. How many does each friend get?';
      }
  }
  final explain = '$a $op $b = $answer';
  return (question: LearnQuestion(text, '$answer', nearNumbers(answer, rng, spread: level >= 2 ? 10 : 3), explain: explain, emoji: emoji), a: a, b: b, op: op);
}

// ── The games ─────────────────────────────────────────────────────────────

Widget _promptText(String text, {double size = 34}) => Text(text, textAlign: TextAlign.center, style: kidsText(size));

Widget _withEmoji(LearnQuestion q, {double emoji = 120, double text = 34}) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    if (q.emoji != null) Text(q.emoji!, style: TextStyle(fontSize: emoji)),
    const SizedBox(height: 8),
    _promptText(q.prompt, size: text),
  ],
);

QuizItem _item(LearnQuestion q, Widget prompt) => QuizItem(prompt: prompt, choices: q.choices, answer: q.answer, explain: q.explain);

class CountIt extends StatelessWidget {
  const CountIt({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => KidsQuiz(
    title: 'Count It',
    colors: const [Color(0xFFFF7A3D), Color(0xFFE7B663)],
    scoreKey: 'count',
    icon: Icons.format_list_numbered_rounded,
    pitch: 'Count the pictures and pick the number',
    modes: const ['Up to 5', 'Up to 10', 'Up to 20', 'Tens & ones'],
    onBack: onBack,
    next: (mode, _, rng) {
      final q = countQuestion(mode, rng);
      final Widget picture;
      if (q.tens > 0 || mode >= 3) {
        picture = Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 6,
          runSpacing: 10,
          children: [
            for (var i = 0; i < q.tens; i++) const _Rod(),
            const SizedBox(width: 10),
            for (var i = 0; i < q.count; i++) const _Cube(),
          ],
        );
      } else {
        final size = q.count <= 5 ? 64.0 : (q.count <= 10 ? 54.0 : 40.0);
        picture = Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [for (var i = 0; i < q.count; i++) Text(q.emoji!, style: TextStyle(fontSize: size))],
        );
      }
      return _item(
        q,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: picture))),
            const SizedBox(height: 10),
            _promptText(q.prompt),
          ],
        ),
      );
    },
  );
}

/// A ten-rod: ten cubes stacked.
class _Rod extends StatelessWidget {
  const _Rod();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [for (var i = 0; i < 10; i++) Container(width: 22, height: 14, margin: const EdgeInsets.only(bottom: 1), color: const Color(0xFF39D0FF))],
  );
}

class _Cube extends StatelessWidget {
  const _Cube();

  @override
  Widget build(BuildContext context) => Container(width: 22, height: 14, color: const Color(0xFFFFD93D));
}

class LetterSounds extends StatelessWidget {
  const LetterSounds({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => KidsQuiz(
    title: 'Letter Sounds',
    colors: const [Color(0xFF8E44FF), Color(0xFFFF6B9A)],
    scoreKey: 'letters',
    icon: Icons.abc_rounded,
    pitch: 'Look at the picture: what sound, which letter?',
    modes: const ['First letter', 'Last letter', 'Missing letter', 'Spell it'],
    onBack: onBack,
    next: (mode, _, rng) {
      final q = letterQuestion(mode, rng);
      return _item(q, _withEmoji(q, text: mode == 2 ? 40 : 34));
    },
  );
}

class PlaceValue extends StatelessWidget {
  const PlaceValue({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => KidsQuiz(
    title: 'Place Value',
    colors: const [Color(0xFF1C8ED6), Color(0xFF6A4CFF)],
    scoreKey: 'placevalue',
    icon: Icons.pin_rounded,
    pitch: 'Ones, tens and hundreds',
    modes: const ['Tens & ones', 'Hundreds', 'Expanded', 'Compare'],
    onBack: onBack,
    next: (mode, _, rng) {
      final q = placeValueQuestion(mode, rng);
      return _item(q, _promptText(q.prompt, size: 42));
    },
  );
}

class StorySums extends StatelessWidget {
  const StorySums({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => KidsQuiz(
    title: 'Story Sums',
    colors: const [Color(0xFF14A06B), Color(0xFF1C8ED6)],
    scoreKey: 'story',
    icon: Icons.menu_book_rounded,
    pitch: 'Read the story and work out the answer',
    modes: const ['Adding', 'Taking away', 'Up to 100', 'Groups'],
    onBack: onBack,
    next: (mode, _, rng) {
      final q = storyQuestion(mode, rng).question;
      return _item(q, _withEmoji(q, emoji: 72, text: 30));
    },
  );
}

/// Telugu Words: match the word to its meaning, or the meaning to the
/// word (the same words as the Today screen's word of the day).
class TeluguQuiz extends StatelessWidget {
  const TeluguQuiz({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => KidsQuiz(
    title: 'Telugu Words',
    colors: const [Color(0xFFE0446A), Color(0xFFF5A623)],
    scoreKey: 'telugu',
    icon: Icons.translate_rounded,
    pitch: 'Learn Telugu words: what do they mean?',
    modes: const ['Telugu → English', 'English → Telugu'],
    onBack: onBack,
    next: (mode, index, rng) {
      final w = fromBank(teluguWords, index, rng);
      final others = <TeluguWord>{w};
      while (others.length < 4) {
        others.add(teluguWords[rng.nextInt(teluguWords.length)]);
      }
      final shuffled = others.toList()..shuffle(rng);
      if (mode == 0) {
        return QuizItem(
          prompt: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(w.telugu, textAlign: TextAlign.center, style: const TextStyle(fontSize: 72, color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('“${w.say}”', style: kidsText(30, color: Colors.white70)),
            ],
          ),
          choices: [for (final o in shuffled) o.meaning],
          answer: w.meaning,
          explain: '${w.telugu} (${w.say}) means ${w.meaning}',
        );
      }
      String label(TeluguWord o) => '${o.telugu}\n${o.say}';
      return QuizItem(
        prompt: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('How do you say', style: kidsText(28, color: Colors.white70)),
            const SizedBox(height: 6),
            _promptText(w.meaning, size: 48),
            Text('in Telugu?', style: kidsText(28, color: Colors.white70)),
          ],
        ),
        choices: [for (final o in shuffled) label(o)],
        answer: label(w),
        explain: '${w.meaning} is ${w.telugu} (${w.say})',
      );
    },
  );
}
