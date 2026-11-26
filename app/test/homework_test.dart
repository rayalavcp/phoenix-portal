import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/app_container.dart';
import 'package:kiosk_satellite/managers/home/homework.dart';
import 'package:kiosk_satellite/ui/kids/kids_homework.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('spelling lists are tidied however they are typed', () {
    expect(HomeworkStore.parseWords('friend, because\npeople;  Friend  beauti-ful 12 don\'t'),
        ['friend', 'because', 'people', 'beauti-ful', "don't"]);
    final many = [for (var i = 0; i < 60; i++) 'word${String.fromCharCode(97 + i % 26)}${String.fromCharCode(97 + i ~/ 26)}'];
    expect(HomeworkStore.parseWords(many.join(' ')).length, 40);
  });

  test('answers count by day and old days are dropped', () async {
    SharedPreferences.setMockInitialValues({});
    final store = HomeworkStore(SharedPreferences.getInstance);
    final day = DateTime(2026, 3, 10);
    await store.record('spelling', true, now: day);
    await store.record('spelling', false, now: day);
    await store.record('times', true, now: day);
    final today = store.report(now: day).first;
    expect(today.$1, '2026-03-10');
    expect(today.$2.spelling, (2, 1));
    expect(today.$2.times, (1, 1));
    for (var i = 1; i <= 40; i++) {
      await store.record('times', true, now: day.add(Duration(days: i)));
    }
    expect(store.log.value.length, HomeworkStore.keepDays);
    // It survives a restart.
    final again = HomeworkStore(SharedPreferences.getInstance);
    await again.load();
    expect(again.log.value.length, HomeworkStore.keepDays);
  });

  test('a times round uses only the tables set', () {
    final round = timesRound([3, 7], math.Random(1));
    expect(round, hasLength(15));
    expect(round.every((q) => q.$1 == 3 || q.$1 == 7), isTrue);
    expect(spellingMatches(' Friend ', 'friend'), isTrue);
  });

  testWidgets('a child practises a spelling word and a times question', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = AppContainer();
    await c.settings.init();
    final hw = c.phoenixHome.homework;
    await hw.setWords(['cat']);
    await hw.setTables([2]);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomeworkGame(container: c, onBack: () {}))));
    await tester.pump();
    expect(find.textContaining('Spelling (1 words)'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Look and remember'), findsOneWidget);
    await tester.tap(find.text('I remember it!'));
    await tester.pump();
    for (final k in ['c', 'a', 't']) {
      await tester.tap(find.text(k));
      await tester.pump();
    }
    await tester.tap(find.text('Check'));
    await tester.pump();
    expect(find.text('Right!'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Homework done!'), findsOneWidget);
    expect(hw.report().first.$2.spelling, (1, 1));
  });

  testWidgets('without homework it asks a grown-up to set some', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = AppContainer();
    await c.settings.init();
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomeworkGame(container: c, onBack: () {}))));
    await tester.pump();
    expect(find.text('No homework yet!'), findsOneWidget);
    await tester.tap(find.text('Set homework (grown-ups)'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextField), 'dog, sun');
    await tester.tap(find.text('×5'));
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.phoenixHome.homework.words.value, ['dog', 'sun']);
    expect(c.phoenixHome.homework.tables.value, [5]);
  });
}
