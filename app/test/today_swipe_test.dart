import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/app_container.dart';
import 'package:kiosk_satellite/ui/home/today_home.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only a quick right swipe away from the menu edge counts', () {
    expect(isSmartHomeSwipe(600, 900), isTrue);
    expect(isSmartHomeSwipe(10, 900), isFalse); // the menu's edge
    expect(isSmartHomeSwipe(600, -900), isFalse); // to the left
    expect(isSmartHomeSwipe(600, 100), isFalse); // too slow, a drag
    expect(isSmartHomeSwipe(null, 900), isFalse);
  });

  group('on the Today screen', () {
    late AppContainer c;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      c = AppContainer();
      await c.settings.init();
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TodayHome(container: c, onOpenMenu: () {}, onOpenSettings: () {}))));
      await tester.pump();
    }

    testWidgets('a right swipe opens Smart Home', (tester) async {
      await pump(tester);
      expect(c.phoenixHome.smartHomeOpen.value, isFalse);
      await tester.flingFrom(const Offset(400, 200), const Offset(400, 0), 1500);
      await tester.pump();
      expect(c.phoenixHome.smartHomeOpen.value, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a left swipe does not', (tester) async {
      await pump(tester);
      await tester.flingFrom(const Offset(800, 200), const Offset(-400, 0), 1500);
      await tester.pump();
      expect(c.phoenixHome.smartHomeOpen.value, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
