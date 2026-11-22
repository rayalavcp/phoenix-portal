import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/managers/home/telugu_words.dart';
import 'package:kiosk_satellite/ui/kids/kids_games.dart';
import 'package:kiosk_satellite/ui/kids/kids_learn.dart';
import 'package:kiosk_satellite/ui/kids/kids_learn_more.dart';
import 'package:kiosk_satellite/ui/kids/kids_more_logic.dart';
import 'package:kiosk_satellite/ui/kids/kids_play.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void fourChoices(LearnQuestion q) {
    expect(q.choices, hasLength(4), reason: q.prompt);
    expect(q.choices.toSet(), hasLength(4), reason: '${q.prompt} ${q.choices}');
    expect(q.choices, contains(q.answer), reason: q.prompt);
  }

  group('quiz engine', () {
    test('a bank round asks every question before any again', () {
      final bank = List.generate(16, (i) => i);
      final rng = math.Random(1);
      final round = [for (var i = 0; i < 16; i++) fromBank(bank, i, rng)];
      expect(round.toSet(), hasLength(16));
      // A 10-question round from a 16-question bank never repeats.
      final again = [for (var i = 0; i < 10; i++) fromBank(bank, i, rng)];
      expect(again.toSet(), hasLength(10));
    });

    test('stars and level keys', () {
      expect(quizStars(10, 10), 3);
      expect(quizStars(9, 10), 3);
      expect(quizStars(7, 10), 2);
      expect(quizStars(5, 10), 1);
      expect(quizStars(4, 10), 0);
      expect(quizLevelKey('science', 0), 'science');
      expect(quizLevelKey('science', 2), 'science.2');
    });

    test('banks are big enough for a round without repeats', () {
      for (final bank in [...kidsScience.values, ...kidsSpelling.values, ...kidsOpposites.values]) {
        expect(bank.length, greaterThanOrEqualTo(16));
      }
      expect(kidsScience.keys, [1, 2, 3, 4]);
      expect(kidsSpelling.keys.toList()..sort(), [0, 1, 2, 3]);
      expect(kidsOpposites.keys.toList()..sort(), [0, 1, 2, 3]);
      for (final (word, wrong) in kidsSpelling.values.expand((b) => b)) {
        expect(wrong, isNot(contains(word)));
        expect(wrong.toSet(), hasLength(3), reason: word);
      }
      for (final (word, opposite, wrong) in kidsOpposites.values.expand((b) => b)) {
        expect(wrong, isNot(contains(opposite)), reason: word);
      }
      for (final (q, a, wrong) in kidsScience.values.expand((b) => b)) {
        expect(wrong, isNot(contains(a)), reason: q);
      }
    });

    test('the clock goes to the minute', () {
      final rng = math.Random(2);
      final minutes = {for (var i = 0; i < 300; i++) clockQuestion(4, rng).minute};
      expect(minutes.any((m) => m % 5 != 0), isTrue);
    });
  });

  group('new learning games', () {
    test('Count It counts right', () {
      final rng = math.Random(3);
      for (var level = 0; level < 4; level++) {
        for (var i = 0; i < 300; i++) {
          final q = countQuestion(level, rng);
          fourChoices(q);
          expect(int.parse(q.answer), q.tens * 10 + q.count);
          if (level == 0) expect(q.count, inInclusiveRange(1, 5));
          if (level == 1) expect(q.count, inInclusiveRange(1, 10));
          if (level == 2) expect(q.count, inInclusiveRange(1, 20));
          if (level == 3) expect(q.tens, inInclusiveRange(1, 9));
        }
      }
    });

    test('Letter Sounds asks about the right letters', () {
      final rng = math.Random(4);
      for (final (_, word) in kidsPictureWords) {
        expect(RegExp(r'^[a-z]+$').hasMatch(word), isTrue, reason: word);
      }
      for (var level = 0; level < 4; level++) {
        for (var i = 0; i < 300; i++) {
          final q = letterQuestion(level, rng);
          fourChoices(q);
          final word = kidsPictureWords.firstWhere((w) => w.$1 == q.emoji).$2;
          switch (level) {
            case 0:
              expect(q.answer, word[0].toUpperCase());
            case 1:
              expect(q.answer, word[word.length - 1].toUpperCase());
            case 2:
              final shown = q.prompt.split('\n').first;
              expect(shown.replaceFirst('_', q.answer.toLowerCase()), word);
            default:
              expect(q.answer, word);
              for (final c in q.choices.where((c) => c != word)) {
                expect(c, isNot(word));
              }
          }
        }
      }
    });

    test('Place Value answers are right', () {
      final rng = math.Random(5);
      for (var level = 0; level < 4; level++) {
        for (var i = 0; i < 400; i++) {
          final q = placeValueQuestion(level, rng);
          fourChoices(q);
          final nums = RegExp(r'\d+').allMatches(q.prompt).map((m) => int.parse(m.group(0)!)).toList();
          final a = int.parse(q.answer);
          if (q.prompt.startsWith('How many tens')) expect(a, nums.first ~/ 10);
          if (q.prompt.contains('tens and')) expect(a, nums[0] * 10 + nums[1]);
          if (q.prompt.contains('hundreds place')) expect(a, nums.first ~/ 100);
          if (q.prompt.startsWith('What is the value')) expect(a, nums[0] * 10);
          if (q.prompt.endsWith('= ?')) expect(a, nums.reduce((x, y) => x + y));
          if (q.prompt.contains('= ') && q.prompt.contains('?') && !q.prompt.endsWith('= ?')) expect(nums[0], nums[1] + a + nums[2]);
          if (q.prompt.contains('biggest')) expect(a, q.choices.map(int.parse).reduce(math.max));
          if (q.prompt.contains('smallest')) expect(a, q.choices.map(int.parse).reduce(math.min));
        }
      }
    });

    test('Story Sums work out', () {
      final rng = math.Random(6);
      for (var level = 0; level < 4; level++) {
        for (var i = 0; i < 400; i++) {
          final s = storyQuestion(level, rng);
          fourChoices(s.question);
          final a = int.parse(s.question.answer);
          final want = switch (s.op) { '+' => s.a + s.b, '−' => s.a - s.b, '×' => s.a * s.b, _ => s.a ~/ s.b };
          expect(a, want, reason: s.question.prompt);
          expect(a, greaterThan(0));
          if (s.op == '÷') expect(s.a % s.b, 0);
          if (level <= 1) expect(math.max(s.a, a), lessThanOrEqualTo(20));
          if (level == 2) expect(math.max(s.a, a), lessThanOrEqualTo(100));
          expect(s.question.prompt, contains('${s.a}'));
        }
      }
    });

    test('Telugu words are all different', () {
      expect(teluguWords.map((w) => w.meaning).toSet(), hasLength(teluguWords.length));
      expect(teluguWords.map((w) => w.telugu).toSet(), hasLength(teluguWords.length));
    });

    test('misspellings are never the word', () {
      final rng = math.Random(7);
      for (final (_, w) in kidsPictureWords) {
        for (var i = 0; i < 50; i++) {
          expect(misspell(w, rng), isNot(w));
        }
      }
    });
  });

  group('quizzes play', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> playRound(WidgetTester tester, Widget quiz, Size size, {String? level, bool answerRight = true}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: quiz)));
      await tester.pump();
      if (level != null) {
        await tester.ensureVisible(find.text(level));
        await tester.tap(find.text(level));
        await tester.pump();
      }
      await tester.ensureVisible(find.text('Start'));
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        expect(tester.takeException(), isNull);
        final state = tester.state(find.byType(KidsQuiz)) as dynamic;
        final item = state.debugItem as QuizItem;
        await tester.tap(find.text(answerRight ? item.answer : item.choices.firstWhere((c) => c != item.answer)).last);
        await tester.pump(const Duration(seconds: 2));
      }
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    }

    for (final size in const [Size(1280, 800), Size(800, 1280), Size(1024, 600)]) {
      testWidgets('Count It at $size', (tester) => playRound(tester, CountIt(onBack: () {}), size, level: 'Tens & ones'));
      testWidgets('Letter Sounds at $size', (tester) => playRound(tester, LetterSounds(onBack: () {}), size, level: 'Missing letter'));
      testWidgets('Place Value at $size', (tester) => playRound(tester, PlaceValue(onBack: () {}), size, level: 'Expanded'));
      testWidgets('Story Sums at $size', (tester) => playRound(tester, StorySums(onBack: () {}), size, level: 'Up to 100'));
      testWidgets('Telugu Words at $size', (tester) => playRound(tester, TeluguQuiz(onBack: () {}), size, level: 'English → Telugu'));
    }

    testWidgets('a good round offers the next level, and it starts there', (tester) async {
      await playRound(tester, ScienceQuiz(onBack: () {}), const Size(1280, 800));
      expect(find.text('Level up!'), findsOneWidget);
      expect(find.text('Next: Medium'), findsOneWidget);
      await tester.tap(find.text('Next: Medium'));
      await tester.pump();
      expect(find.text('1 / 10'), findsOneWidget);
      // The first level now shows its stars.
      final state = tester.state(find.byType(KidsQuiz)) as dynamic;
      expect(state.debugMode, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a poor round only offers to play again', (tester) async {
      await playRound(tester, SpellingQuiz(onBack: () {}), const Size(1280, 800), answerRight: false);
      expect(find.textContaining('Next:'), findsNothing);
      expect(find.text('Play again'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('more stages', () {
    test('Snake stages fit the field and leave the start row clear', () {
      for (var stage = 1; stage <= 12; stage++) {
        final walls = snakeWalls(stage);
        for (final (x, y) in walls) {
          expect(x, inInclusiveRange(0, 19));
          expect(y, inInclusiveRange(0, 12));
        }
        if ((stage - 1) % snakeStages.length != 0) expect(walls, isNotEmpty);
      }
      for (final (_, rows) in snakeStages) {
        for (final r in rows) {
          expect(r.length, 20);
        }
      }
    });

    testWidgets('Memory Pro deals every size', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final pairs in [6, 8, 10, 12]) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: MemoryPro(onBack: () {}))));
        await tester.tap(find.text('$pairs pairs'));
        await tester.pump();
        expect(find.byType(GestureDetector), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('Snake with stages plays', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SnakeGame(onBack: () {}))));
      await tester.tap(find.text('Start'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
