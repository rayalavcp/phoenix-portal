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

    for (final size in const [Size(1280, 800), Size(800, 1280), Size(1024, 600)]) {
      testWidgets('lays out without Home Assistant at $size', (tester) async {
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
