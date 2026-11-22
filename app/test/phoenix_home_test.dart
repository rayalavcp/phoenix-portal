import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/app_container.dart';
import 'package:kiosk_satellite/managers/browser/dashboard_page.dart';
import 'package:kiosk_satellite/managers/home/phoenix_home_manager.dart';
import 'package:kiosk_satellite/managers/settings/definitions.dart' as defs;
import 'package:kiosk_satellite/ui/home/phoenix_home.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Phoenix Home is the launcher home screen: it must run with no Home
// Assistant at all, and only load the dashboard page while it is opened.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dashboard page', () {
    late AppContainer c;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      c = AppContainer();
      await c.settings.init();
    });
    tearDown(() async {
      await c.settings.dispose();
      await c.bus.dispose();
      await c.log.dispose();
    });

    test('Phoenix Home is the default and needs no dashboard page', () {
      expect(c.settings.get(defs.homeScreen), 'phoenix');
      expect(dashboardPageNeeded(c.settings), isFalse);
    });

    test('opening the dashboard loads the page', () {
      expect(dashboardPageNeeded(c.settings, dashboardOpen: true), isTrue);
    });

    test('the dashboard home screen always has the page', () async {
      await c.settings.set(defs.homeScreen, 'dashboard');
      expect(dashboardPageNeeded(c.settings), isTrue);
    });

    test('voice in the dashboard keeps the page under Phoenix Home', () async {
      await c.settings.set(defs.voiceRuntime, 'dashboard');
      expect(dashboardPageNeeded(c.settings), isTrue);
    });
  });

  group('weather parsing', () {
    test('Open-Meteo current and daily', () {
      final w = parseOpenMeteo(
        {
          'current': {'temperature_2m': 68.4, 'weather_code': 2, 'is_day': 1},
          'daily': {
            'time': ['2026-11-21', '2026-11-22'],
            'weather_code': [2, 61],
            'temperature_2m_max': [70.1, 64.0],
            'temperature_2m_min': [50.2, 48.9],
          },
        },
        place: 'Austin',
        fahrenheit: true,
      )!;
      expect(w.temperature, 68.4);
      expect(w.code, 2);
      expect(w.isDay, isTrue);
      expect(w.days, hasLength(2));
      expect(w.days[1].code, 61);
      expect(w.place, 'Austin');
    });

    test('missing current conditions is no weather', () {
      expect(
        parseOpenMeteo({'daily': {}}, place: '', fahrenheit: true),
        isNull,
      );
    });

    test('geocoding picks the hinted country', () {
      final data = {
        'results': [
          {'name': 'Paris', 'latitude': 48.8, 'longitude': 2.3, 'country_code': 'FR'},
          {'name': 'Paris', 'latitude': 33.6, 'longitude': -95.5, 'country_code': 'US', 'admin1': 'Texas'},
        ],
      };
      expect(pickGeocodeResult(data, null)!.lat, 48.8);
      expect(pickGeocodeResult(data, 'US')!.lat, 33.6);
      expect(pickGeocodeResult(data, 'texas')!.lat, 33.6);
      expect(pickGeocodeResult({'results': []}, null), isNull);
    });

    test('stored usage survives junk', () {
      expect(decodeUsage(null), isEmpty);
      expect(decodeUsage('not json'), isEmpty);
      final usage = decodeUsage(
        jsonEncode({
          'com.a': {'c': 3, 'l': 10},
          'com.b': {'c': 'x'},
        }),
      );
      expect(usage.keys, ['com.a']);
      expect(usage['com.a']!.count, 3);
    });
  });

  group('entity state', () {
    HomeEntity e(String domain, String state) =>
        HomeEntity(id: '$domain.x', name: 'X', state: state, domain: domain);

    test('on, open, unlocked and playing are active', () {
      expect(e('light', 'on').active, isTrue);
      expect(e('light', 'off').active, isFalse);
      expect(e('cover', 'open').active, isTrue);
      expect(e('lock', 'unlocked').active, isTrue);
      expect(e('lock', 'locked').active, isFalse);
      expect(e('climate', 'heat').active, isTrue);
      expect(e('climate', 'off').active, isFalse);
      expect(e('media_player', 'playing').active, isTrue);
    });

    test('scenes and scripts run', () {
      expect(e('scene', '').runs, isTrue);
      expect(e('script', '').runs, isTrue);
      expect(e('light', 'on').runs, isFalse);
    });
  });

  group('remote admin', () {
    late AppContainer c;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      c = AppContainer();
      await c.settings.init();
    });
    tearDown(() async {
      await c.settings.dispose();
      await c.bus.dispose();
      await c.log.dispose();
    });

    test('applies tiles, theme, apps and school, and reads them back', () async {
      final home = c.phoenixHome;
      await home.applyRemote({
        'tiles': [
          {'id': 'school', 'w': 3, 'h': 2},
          {'id': 'nope', 'w': 1, 'h': 1},
        ],
        'hiddenTiles': ['store'],
        'theme': 'ocean',
        'weatherEffects': false,
        'favorites': ['com.a', 'com.b'],
        'kidsApps': ['com.kids'],
        'hiddenApps': ['com.hidden'],
        'school': {'schoolName': 'Miller Elementary', 'start': '7:45'},
        'photos': {'source': 'folder', 'folder': 'http://tower/photos/', 'seconds': 20},
      });
      final state = home.remoteState();
      final tiles = state['tiles'] as List;
      expect((tiles.first as Map)['id'], 'school');
      expect((tiles.first as Map)['w'], 3);
      expect(tiles.length, defaultHomeTiles.length);
      expect(tiles.any((t) => (t as Map)['id'] == 'store' && t['hidden'] == true), isTrue);
      expect(state['theme'], 'ocean');
      expect(state['weatherEffects'], false);
      expect(state['favorites'], ['com.a', 'com.b']);
      expect(state['kidsApps'], ['com.kids']);
      expect(state['hiddenApps'], ['com.hidden']);
      expect((state['school'] as Map)['start'], '7:45');
      expect((state['photos'] as Map)['seconds'], 20);
      expect(home.photos.configured, isTrue);
    });

    test('layout and camera round-trip; unknown layouts mean Today', () async {
      final home = c.phoenixHome;
      await home.applyRemote({'layout': 'tiles', 'camera': ' camera.front_door '});
      expect(home.remoteState()['layout'], 'tiles');
      expect(home.remoteState()['camera'], 'camera.front_door');
      await home.applyRemote({'layout': 'weird'});
      expect(home.layout.value, 'today');
    });

    test('cameras, doorbell and menu items from the admin portal', () async {
      final home = c.phoenixHome;
      await home.applyRemote({
        'cameras': ['camera.front_door', ' camera.driveway ', 'not_a_camera', 'camera.front_door'],
        'doorbell': {'trigger': 'binary_sensor.front_door_ding', 'seconds': 45},
      });
      final state = home.remoteState();
      expect(state['cameras'], ['camera.front_door', 'camera.driveway']);
      expect(state['camera'], 'camera.front_door');
      expect((state['doorbell'] as Map)['trigger'], 'binary_sensor.front_door_ding');
      expect((state['doorbell'] as Map)['seconds'], 45);
      expect(state.containsKey('menuItems'), isTrue);
      // The old single camera still works.
      await home.applyRemote({'camera': 'camera.porch'});
      expect(home.cameraEntities.value, ['camera.porch']);
      // No camera set up in this test: the ring says so instead of failing loud.
      await home.applyRemote({'cameras': <String>[]});
      expect((await home.ringDoorbell()).ok, isFalse);
    });

    test('what counts as a doorbell ring', () {
      expect(isDoorbellRing('binary_sensor.front_door_ding', 'on'), isTrue);
      expect(isDoorbellRing('binary_sensor.front_door_ding', 'off'), isFalse);
      expect(isDoorbellRing('event.front_door_ding', '2026-11-22T10:00:00.000+00:00'), isTrue);
      expect(isDoorbellRing('event.front_door_ding', 'unavailable'), isFalse);
      expect(isDoorbellRing('button.doorbell', 'unknown'), isFalse);
    });

    test('Kids Portal settings from the admin portal', () async {
      final home = c.phoenixHome;
      SharedPreferences.setMockInitialValues({'phx.kids.best.math': 12, 'phx.kids.stars': '2026-11-22:5', 'other': 1});
      await home.applyRemote({
        'kids': {'name': ' Ria ', 'minutes': '45', 'bedtime': '20:30', 'wake': '06:30', 'pin': '2468', 'hiddenGames': ['snake', 'mole', 'snake'], 'resetScores': true},
      });
      final k = home.remoteState()['kids'] as Map;
      expect(k['name'], 'Ria');
      expect(k['minutes'], '45');
      expect(k['bedtime'], '20:30');
      expect(k['wake'], '06:30');
      expect(k['hasPin'], isTrue);
      expect(k['hiddenGames'], unorderedEquals(['snake', 'mole']));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('phx.kids.best.math'), isNull);
      expect(prefs.getString('phx.kids.stars'), isNull);
      expect(prefs.getInt('other'), 1);
      expect(home.kidsScoresReset.value, 1);
    });

    test('glass, Smart Home button and built-in wallpapers', () async {
      final home = c.phoenixHome;
      expect(home.smartHomeTarget.value, 'ha');
      await home.applyRemote({'glass': 0.7, 'smartHome': 'phoenix'});
      expect(home.remoteState()['glass'], 0.7);
      expect(home.smartHomeTarget.value, 'phoenix');
      await home.applyRemote({'glass': 5});
      expect(home.glassOpacity.value, 1.0);
      // No Home Assistant page yet: the button opens Phoenix's own page.
      await home.setSmartHomeTarget('ha');
      home.openSmartHomeButton();
      expect(home.smartHomeOpen.value, isTrue);
      expect(home.dashboardOpen.value, isFalse);
      expect(builtinWallpapers.where((w) => w.$3.isNotEmpty).length, greaterThanOrEqualTo(10));
    });

    test('ignores an unknown theme', () async {
      await c.phoenixHome.applyRemote({'theme': 'neon'});
      expect(c.phoenixHome.theme.value, 'ember');
    });
  });

  group('home screen', () {
    late AppContainer c;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      c = AppContainer();
      await c.settings.init();
    });
    tearDown(() async {
      await c.settings.dispose();
      await c.bus.dispose();
      await c.log.dispose();
    });

    Future<void> pump(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhoenixHome(
              container: c,
              onOpenMenu: () {},
              onOpenSettings: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final size in const [Size(1280, 800), Size(800, 1280), Size(1024, 600), Size(800, 600)]) {
      testWidgets('the Today screen lays out without Home Assistant at $size', (tester) async {
        expect(c.phoenixHome.layout.value, 'today');
        await pump(tester, size);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Good '), findsOneWidget);
        if (size.width >= 860) expect(find.text('TELUGU WORD OF THE DAY'), findsOneWidget);
        expect(find.byTooltip('Kids Portal'), findsOneWidget);
        expect(find.byTooltip('Smart Home'), findsOneWidget);
        expect(find.byTooltip('Night mode'), findsOneWidget);
      });

      testWidgets('the tile layout lays out without Home Assistant at $size', (tester) async {
        c.phoenixHome.layout.value = 'tiles';
        await pump(tester, size);
        expect(tester.takeException(), isNull);
        expect(find.text('Kids Portal'), findsOneWidget);
        expect(find.text('Smart Home'), findsOneWidget);
        expect(find.text('All apps'), findsWidgets);
      });
    }

    testWidgets('Smart Home without Home Assistant explains, not blocks', (
      tester,
    ) async {
      await pump(tester, const Size(1280, 800));
      await tester.tap(find.text('Smart Home'));
      await tester.pumpAndSettle();
      expect(find.text('Home Assistant is optional'), findsOneWidget);
      expect(c.phoenixHome.smartHomeOpen.value, isTrue);
      c.phoenixHome.goHome();
      await tester.pumpAndSettle();
      expect(find.text('Home Assistant is optional'), findsNothing);
    });

    testWidgets('the dashboard shows only a way home', (tester) async {
      await pump(tester, const Size(1280, 800));
      c.phoenixHome.openDashboard();
      await tester.pump();
      expect(find.text('Kids Portal'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pump();
      expect(c.phoenixHome.dashboardOpen.value, isFalse);
    });

    testWidgets('the app drawer opens and closes', (tester) async {
      await pump(tester, const Size(1280, 800));
      c.phoenixHome.appsOpen.value = true;
      await tester.pumpAndSettle();
      expect(find.text('Search apps'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(c.phoenixHome.appsOpen.value, isFalse);
    });
  });
}
