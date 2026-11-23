import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/app_container.dart';
import 'package:kiosk_satellite/managers/home/phoenix_home_manager.dart';
import 'package:kiosk_satellite/ui/home/home_tiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('in edit mode a tile resizes by dragging its corner and hides with ×', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = AppContainer();
    await c.settings.init();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await c.phoenixHome.setTiles(const [HomeTileSpec('apps', 1, 1), HomeTileSpec('settings', 1, 1)]);
    c.phoenixHome.editing.value = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomeTileGrid(container: c, onOpenSettings: () {}))));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // One column is a sixth of 1280 px: drag the corner a column and a row.
    final handle = find.byTooltip('Drag to resize').first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(22, 14));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    final apps = c.phoenixHome.tiles.value.firstWhere((t) => t.id == 'apps');
    expect(apps.w, 2);
    expect(apps.h, 2);

    await tester.tap(find.byTooltip('Hide tile').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.phoenixHome.hiddenTiles.value, contains('settings'));
    c.phoenixHome.editing.value = false;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('in edit mode a tile moves by dragging it onto another', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = AppContainer();
    await c.settings.init();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await c.phoenixHome.setTiles(const [HomeTileSpec('apps', 1, 1), HomeTileSpec('settings', 1, 1), HomeTileSpec('store', 1, 1)]);
    c.phoenixHome.editing.value = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomeTileGrid(container: c, onOpenSettings: () {}))));
    await tester.pump(const Duration(milliseconds: 400));
    // Drag the first tile two columns right, onto the third.
    final gesture = await tester.startGesture(const Offset(100, 60));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(21, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect([for (final t in c.phoenixHome.tiles.value.take(3)) t.id], ['settings', 'store', 'apps']);
    c.phoenixHome.editing.value = false;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
