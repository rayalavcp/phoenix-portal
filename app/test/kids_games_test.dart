import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/ui/kids/kids_activities.dart';
import 'package:kiosk_satellite/ui/kids/kids_games.dart';
import 'package:kiosk_satellite/ui/kids/kids_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget host(Widget child) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(size: Size(1280, 800)),
    child: Material(child: child),
  ),
);

Future<void> sized(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Math Blitz starts, answers and counts the score', (tester) async {
    await sized(tester);
    await tester.pumpWidget(host(MathBlitz(onBack: () {})));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    final problem = tester.widget<Text>(find.textContaining('= ?')).data!;
    final [a, op, b, _, _] = problem.split(' ');
    final x = int.parse(a), y = int.parse(b);
    final answer = switch (op) { '+' => x + y, '−' => x - y, '×' => x * y, _ => x ~/ y };
    await tester.tap(find.text('$answer').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1'), findsWidgets); // the score
    // Run the clock out: the result card and the saved best follow.
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('Play again'), findsOneWidget);
    expect(await KidsScores.best('math'), 1);
  });

  testWidgets('Word Scramble: the hint solves a word letter by letter', (tester) async {
    await sized(tester);
    await tester.pumpWidget(host(WordScramble(onBack: () {})));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Word 1/10'), findsOneWidget);
    for (var i = 0; i < 8 && find.textContaining('Word 1/10').evaluate().isNotEmpty; i++) {
      await tester.tap(find.text('Hint'));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Word 2/10'), findsOneWidget);
  });

  testWidgets('2048 swipes move the tiles', (tester) async {
    await sized(tester);
    await tester.pumpWidget(host(Game2048(onBack: () {})));
    await tester.pumpAndSettle();
    expect(find.textContaining('Score'), findsOneWidget);
    int tiles() => find.byWidgetPredicate((w) => w is Text && RegExp(r'^\d+$').hasMatch(w.data ?? '')).evaluate().length;
    final start = tiles(); // two tiles, plus the 2048 title
    // Slow drags (no fling velocity), as a slow Portal reports them.
    for (final offset in const [Offset(-300, 0), Offset(0, 300), Offset(300, 0), Offset(0, -300)]) {
      await tester.timedDrag(find.byType(Game2048), offset, const Duration(seconds: 2));
      await tester.pumpAndSettle();
    }
    // Every move spawns a tile (merges can take some away again).
    expect(tiles(), greaterThan(start));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Connect Four: a tap drops a disc and the computer answers', (tester) async {
    await sized(tester);
    await tester.pumpWidget(host(ConnectFour(onBack: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Your turn: tap a column'), findsOneWidget);
    final board = find.byWidgetPredicate(
      (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color == const Color(0xFF2B48C8),
    );
    await tester.tapAt(tester.getCenter(board)); // the middle column
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Your turn'), findsOneWidget);
  });

  testWidgets('Memory Pro deals sixteen cards and flips them', (tester) async {
    await sized(tester);
    await tester.pumpWidget(host(MemoryPro(onBack: () {})));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.question_mark_rounded), findsNWidgets(16));
    await tester.tap(find.byIcon(Icons.question_mark_rounded).first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.question_mark_rounded), findsNWidgets(15));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('Draw Studio paints and clears', (tester) async {
    await sized(tester);
    await tester.pumpWidget(host(KidsDraw(onBack: () {})));
    await tester.dragFrom(const Offset(300, 300), const Offset(300, 100));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
