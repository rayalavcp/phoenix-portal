import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/ui/kids/kids_maps.dart';
import 'package:shared_preferences/shared_preferences.dart';

KidsMapData _file(String key) => KidsMapData.parse(key, File('assets/maps/$key.json').readAsStringSync());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('map data', () {
    test('the USA has its 50 states, each with a capital and region', () {
      final m = _file('usa');
      expect(m.asked, hasLength(50));
      expect(m.regions.map((r) => r.name), contains('District of Columbia'));
      for (final r in m.asked) {
        expect(r.capital, isNotNull, reason: r.name);
        expect(r.id, hasLength(2));
        expect(['Northeast', 'Midwest', 'South', 'West'], contains(r.group));
      }
      expect(m.asked.firstWhere((r) => r.name == 'Texas').capital, 'Austin');
    });

    test('India has 28 states and 8 union territories, Ladakh among them', () {
      final m = _file('india');
      expect(m.asked, hasLength(36));
      expect(m.asked.where((r) => r.group == 'State'), hasLength(28));
      expect(m.asked.where((r) => r.group == 'Union territory'), hasLength(8));
      final names = m.asked.map((r) => r.name).toSet();
      expect(names, containsAll(['Ladakh', 'Jammu and Kashmir', 'Telangana', 'Andhra Pradesh', 'Dadra and Nagar Haveli and Daman and Diu']));
      expect(m.asked.firstWhere((r) => r.name == 'Telangana').capital, 'Hyderabad');
    });

    test('the world has its continents and plenty of countries', () {
      final m = _file('world');
      expect(m.asked.length, greaterThan(150));
      for (final c in worldContinents) {
        expect(m.asked.where((r) => r.group == c), isNotEmpty, reason: c);
      }
      expect(mapPool(m, MapMode.capital, 1).length, greaterThanOrEqualTo(30));
      expect(mapPool(m, MapMode.flag, 1).length, greaterThan(140));
      expect(m.asked.firstWhere((r) => r.name == 'India').group, 'Asia');
    });

    test('tapping a place\'s label finds that place', () {
      for (final key in ['usa', 'india', 'world']) {
        final m = _file(key);
        var hits = 0;
        for (final r in m.asked) {
          if (m.hit(r.label) == r) hits++;
        }
        expect(hits, m.asked.length, reason: key);
      }
    });

    test('choices are four different answers with the right one', () {
      final rng = math.Random(1);
      for (final key in ['usa', 'india', 'world']) {
        final m = _file(key);
        for (final mode in [MapMode.name, MapMode.capital]) {
          final pool = mapPool(m, mode, 1);
          for (final r in pool) {
            String text(MapRegion x) => mode == MapMode.name ? x.name : ((key == 'world' ? x.worldCapital : x.capital) ?? '');
            final c = mapChoices(r, pool, text, rng);
            expect(c.toSet(), hasLength(4), reason: '${r.name} $c');
            expect(c, contains(text(r)));
          }
        }
      }
    });

    test('every world fill level has countries', () {
      final m = _file('world');
      for (var i = 0; i < worldContinents.length; i++) {
        expect(mapPool(m, MapMode.fill, i), isNotEmpty);
      }
    });
  });

  group('map games play', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<dynamic> open(WidgetTester tester, String key, Size size, String mode, {String? level}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => KidsMapData.load(key));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapQuest(mapKey: key, onBack: () {}))));
      await tester.pump();
      await tester.pump();
      await tester.ensureVisible(find.text(mode));
      await tester.pump();
      await tester.tap(find.text(mode));
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
      return tester.state(find.byType(MapQuest));
    }

    Future<void> tapRegion(WidgetTester tester, KidsMapData map, MapRegion r) async {
      final box = tester.getRect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_MapPainter'));
      final k = box.width / map.size.width;
      await tester.tapAt(box.topLeft + r.label * k);
    }

    for (final size in const [Size(1280, 800), Size(800, 1280), Size(1024, 600)]) {
      testWidgets('USA find it at $size', (tester) async {
        final map = _file('usa');
        final s = await open(tester, 'usa', size, 'Find it');
        for (var i = 0; i < 10; i++) {
          final t = s.debugTarget as MapRegion;
          await tapRegion(tester, map, map.regions.firstWhere((r) => r.name == t.name));
          await tester.pump(const Duration(seconds: 2));
        }
        await tester.pump(const Duration(seconds: 1));
        expect(find.textContaining('right first time'), findsOneWidget);
        expect(find.text('10 of 10 right first time'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('India name it at $size', (tester) async {
        final s = await open(tester, 'india', size, 'Name it');
        for (var i = 0; i < 10; i++) {
          final t = s.debugTarget as MapRegion;
          await tester.ensureVisible(find.text(t.name).last);
          await tester.tap(find.text(t.name).last);
          await tester.pump(const Duration(seconds: 3));
        }
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('10 of 10 right first time'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('World continents at $size', (tester) async {
        final map = _file('world');
        final s = await open(tester, 'world', size, 'Continents');
        for (var i = 0; i < 10; i++) {
          final c = s.debugContinent as String;
          final r = KidsMapData.bigOnes(map.asked.where((r) => r.group == c).toList()).first;
          await tapRegion(tester, map, r);
          await tester.pump(const Duration(seconds: 2));
        }
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('10 of 10 right first time'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('fill the whole India map', (tester) async {
      final map = _file('india');
      final s = await open(tester, 'india', const Size(1280, 800), 'Fill the map');
      for (var i = 0; i < 36; i++) {
        final t = s.debugTarget as MapRegion;
        await tapRegion(tester, map, map.regions.firstWhere((r) => r.name == t.name));
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Map complete!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wrong tap says where you are, three show the answer', (tester) async {
      final map = _file('usa');
      final s = await open(tester, 'usa', const Size(1280, 800), 'Find it');
      final t = s.debugTarget as MapRegion;
      final other = map.asked.firstWhere((r) => r.name != t.name && r.area > 2000);
      await tapRegion(tester, map, other);
      await tester.pump();
      expect(find.text('That is ${other.name}'), findsOneWidget);
      await tapRegion(tester, map, other);
      await tapRegion(tester, map, other);
      await tester.pump();
      expect(find.text('Here it is: ${t.name}'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('world flags and capitals, and shape memory, start', (tester) async {
      for (final mode in ['Flags', 'Capitals', 'Shape memory']) {
        final s = await open(tester, 'world', const Size(1280, 800), mode);
        if (mode == 'Capitals') expect((s.debugChoices as List).length, 4);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      }
    });
  });
}
