import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/ui/kids/kids_leaderboard.dart';
import 'package:kiosk_satellite/ui/kids/kids_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    KidsScores.pendingEntry.value = null;
  });

  test('a top ten keeps the ten best, ties below the earlier score', () {
    var board = <KidsBoardEntry>[];
    for (var i = 1; i <= 12; i++) {
      board = boardInsert(board, KidsBoardEntry('P$i', i * 10, DateTime(2026)));
    }
    expect(board.length, 10);
    expect(board.first.score, 120);
    expect(board.last.score, 30);
    expect(boardPlace(board, 20), isNull);
    expect(boardPlace(board, 120), 2);
    expect(boardPlace(board, 999), 1);
  });

  test('times count lower as better', () {
    var board = <KidsBoardEntry>[];
    for (final t in [90, 45, 60]) {
      board = boardInsert(board, KidsBoardEntry('t$t', t, DateTime(2026)), lowerIsBetter: true);
    }
    expect([for (final e in board) e.score], [45, 60, 90]);
  });

  test('a qualifying score waits for a name, then lands on the board', () async {
    await KidsScores.offer('snake', 12);
    final pending = KidsScores.pendingEntry.value!;
    expect(pending.place, 1);
    expect(await KidsScores.addToBoard(pending.game, pending.score, 'Maya'), 1);
    expect(await KidsScores.addToBoard('snake', 20, 'Leo'), 1);
    final board = await KidsScores.leaderboard('snake');
    expect([for (final e in board) e.name], ['Leo', 'Maya']);
    expect(await KidsScores.recentNames(), ['Leo', 'Maya']);
    expect(await KidsScores.boardGames(), ['snake']);
  });

  test('leaderboards name the game and level, and times read as times', () {
    expect(boardTitle('lights5'), 'Lights Out · 5×5');
    expect(boardTitle('munch2'), 'Munch Maze · Stage 2');
    expect(boardTitle('times.2'), 'Times Tables · Level 3');
    expect(boardTitle('map_usa_find'), 'USA Map · Find it');
    expect(boardTitle('ttthard'), 'Tic-Tac-Toe · Hard');
    expect(boardTitle('memory'), 'Memory Pro · 8 pairs');
    expect(boardScore('sudoku4', 83), '1:23');
    expect(boardScore('snake', 9), '9');
  });

  testWidgets('a top ten score asks for a name and the page lists it', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var board = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, set) => KidsHighScoreListener(
              child: board ? KidsLeaderboard(onBack: () {}) : TextButton(onPressed: () => set(() => board = true), child: const Text('open')),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => KidsScores.offer('2048', 512));
    await tester.pumpAndSettle();
    expect(find.text('New high score!'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Maya');
    await tester.tap(find.text('Save'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('2048'), findsOneWidget);
    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('512'), findsOneWidget);
  });
}
