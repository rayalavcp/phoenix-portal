import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/app_container.dart';
import 'package:kiosk_satellite/managers/home/phoenix_home_manager.dart';
import 'package:kiosk_satellite/ui/home/photo_frame.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the scenic landscapes are the credited 4K photos, from main', () {
    expect(scenicWallpapers.length, greaterThanOrEqualTo(10));
    expect(scenicWallpapers.every((w) => w.$3.isNotEmpty), isTrue);
    for (final w in scenicWallpapers) {
      final urls = builtinWallpaperUrls(w.$1);
      expect(urls.single.toString(), contains('/phoenix-portal/main/wallpapers/'));
    }
  });

  testWidgets('with no photos set up the frame goes scenic, not to a setup message', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = AppContainer();
    await c.settings.init();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    expect(c.phoenixHome.photos.configured, isFalse);
    await tester.pumpWidget(MaterialApp(home: PhoenixPhotoFrame(container: c, seconds: 10)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Set up photos on Phoenix Home'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
