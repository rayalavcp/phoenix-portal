import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/app_container.dart';
import 'package:kiosk_satellite/ui/kids/kids_activities.dart';
import 'package:kiosk_satellite/ui/kids/kids_arcade.dart';
import 'package:kiosk_satellite/ui/kids/kids_arcade2.dart';
import 'package:kiosk_satellite/ui/kids/kids_games.dart';
import 'package:kiosk_satellite/ui/kids/kids_learn.dart';
import 'package:kiosk_satellite/ui/kids/kids_learn_more.dart';
import 'package:kiosk_satellite/ui/kids/kids_maps.dart';
import 'package:kiosk_satellite/ui/kids/kids_motion.dart';
import 'package:kiosk_satellite/ui/kids/kids_motion2.dart';
import 'package:kiosk_satellite/ui/kids/kids_touch.dart';
import 'package:kiosk_satellite/ui/kids/kids_homework.dart';
import 'package:kiosk_satellite/ui/kids/kids_play.dart';
import 'package:kiosk_satellite/ui/kids/kids_puzzles.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every Kids Portal game, at every Portal screen size: it opens, starts,
/// takes some taps and drags, and leaves, with no error and nothing
/// overflowing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppContainer c;
  final tones = KidsTones((_, _) async => true);
  void back() {}

  final games = <String, Widget Function()>{
    'Math Blitz': () => MathBlitz(onBack: back),
    'Times Tables': () => TimesTables(onBack: back),
    'Telling the Time': () => TellingTime(onBack: back),
    'Flag Quiz': () => FlagQuiz(onBack: back),
    'Word Scramble': () => WordScramble(onBack: back),
    'Patterns': () => PatternsGame(onBack: back),
    'Fractions': () => FractionsQuiz(onBack: back),
    'Money': () => MoneyQuiz(onBack: back),
    'Science': () => ScienceQuiz(onBack: back),
    'Spelling': () => SpellingQuiz(onBack: back),
    'Opposites': () => OppositesQuiz(onBack: back),
    'Count It': () => CountIt(onBack: back),
    'Letter Sounds': () => LetterSounds(onBack: back),
    'Place Value': () => PlaceValue(onBack: back),
    'Story Sums': () => StorySums(onBack: back),
    'Telugu Words': () => TeluguQuiz(onBack: back),
    'USA Map': () => MapQuest(mapKey: 'usa', onBack: back),
    'India Map': () => MapQuest(mapKey: 'india', onBack: back),
    'World Map': () => MapQuest(mapKey: 'world', onBack: back),
    'Sudoku': () => SudokuGame(onBack: back),
    'Maze': () => MazeGame(onBack: back),
    'Word Search': () => WordSearchGame(onBack: back),
    'Word Guess': () => WordGuess(onBack: back),
    'Memory Pro': () => MemoryPro(onBack: back),
    '2048': () => Game2048(onBack: back),
    'Lights Out': () => LightsOut(onBack: back),
    'Snake': () => SnakeGame(onBack: back, container: c),
    'Whack-a-Mole': () => WhackAMole(onBack: back),
    'Simon Says': () => SimonSays(onBack: back, tones: tones),
    'Tic-Tac-Toe': () => TicTacToe(onBack: back),
    'Connect Four': () => ConnectFour(onBack: back),
    'Munch Maze': () => MunchMaze(onBack: back, container: c),
    'Brick Bash': () => BrickBash(container: c, onBack: back),
    'Hop Across': () => HopAcross(onBack: back, container: c),
    'Sky Glide': () => SkyGlide(container: c, onBack: back),
    'Fox Run': () => FoxRun(container: c, onBack: back),
    'Space Blaster': () => SpaceBlaster(container: c, onBack: back),
    'Bubble Pop': () => BubblePop(container: c, onBack: back),
    'Fruit Catcher': () => FruitCatcher(container: c, onBack: back),
    'Finger Math': () => FingerMath(container: c, onBack: back),
    'Wall Dodge': () => WallDodge(container: c, onBack: back),
    'Air Trace': () => AirTrace(container: c, onBack: back),
    'Freeze Dance': () => FreezeDance(container: c, onBack: back, tones: tones),
    'Goalie': () => GoalieGame(container: c, onBack: back),
    'Window Wipe': () => WindowWipe(container: c, onBack: back),
    'Star Swipe': () => StarSwipe(onBack: back),
    'Stack Up': () => StackUp(onBack: back),
    'Homework': () => HomeworkGame(container: c, onBack: back),
    'Pose Match': () => PoseMatch(container: c, onBack: back),
    'Simon Poses': () => SimonPoses(container: c, onBack: back),
    'Pop Duel': () => PopDuel(container: c, onBack: back),
    'Critter Bop': () => CritterBop(container: c, onBack: back),
    'Target Strike': () => TargetStrike(container: c, onBack: back),
    'Draw Studio': () => KidsDraw(onBack: back),
    'Pixel Paint': () => PixelPaint(onBack: back),
    'Piano': () => KidsPiano(onBack: back, tones: tones),
  };

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    c = AppContainer();
    await c.settings.init();
  });

  for (final size in const [Size(1280, 800), Size(800, 1280), Size(1024, 600)]) {
    for (final entry in games.entries) {
      testWidgets('${entry.key} at ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        if (entry.key.endsWith(' Map')) {
          await tester.runAsync(() => KidsMapData.load(switch (entry.key) { 'USA Map' => 'usa', 'India Map' => 'india', _ => 'world' }));
        }
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: KidsBackdrop(photo: null, child: entry.value()))));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'opening');
        final start = find.text('Start');
        if (start.evaluate().isNotEmpty) {
          await tester.ensureVisible(start);
          await tester.pump();
          await tester.tap(start);
          await tester.pump();
        }
        expect(tester.takeException(), isNull, reason: 'starting');
        // Taps and drags around the screen for a few seconds.
        final w = size.width, h = size.height;
        for (var i = 0; i < 12; i++) {
          final at = Offset(w * (0.15 + (i * 0.37) % 0.7), h * (0.2 + (i * 0.29) % 0.7));
          await tester.tapAt(at);
          await tester.pump(const Duration(milliseconds: 150));
          await tester.dragFrom(at, Offset(i.isEven ? 60 : -60, i % 3 == 0 ? 40 : -40));
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(tester.takeException(), isNull, reason: 'playing');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
        expect(tester.takeException(), isNull, reason: 'leaving');
      });
    }
  }
}
