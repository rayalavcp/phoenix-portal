import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/managers/store/store_manager.dart';

void main() {
  test('the bundled catalog parses, every app is in a listed category', () {
    final catalog = parseStoreCatalog(File('assets/store/catalog.json').readAsStringSync());
    expect(catalog.apps, isNotEmpty);
    expect(catalog.categories, contains('Games'));
    for (final app in catalog.apps) {
      expect(catalog.categories, contains(app.category), reason: app.package);
      expect(app.package, matches(RegExp(r'^[a-zA-Z][\w]*(\.[\w]+)+$')), reason: app.package);
      expect(app.summary, isNotEmpty, reason: app.package);
    }
    expect(catalog.apps.map((a) => a.package).toSet().length, catalog.apps.length, reason: 'no duplicates');
  });

  test('every catalog icon has a glyph in the store screen', () {
    final catalog = parseStoreCatalog(File('assets/store/catalog.json').readAsStringSync());
    final screen = File('lib/ui/store/store_overlay.dart').readAsStringSync();
    for (final app in catalog.apps) {
      expect(screen, contains("'${app.icon}':"), reason: '${app.package} uses icon ${app.icon}');
    }
  });

  test('F-Droid APK URL from the package API', () {
    expect(
      fdroidApkUrl('org.tuxpaint', {'packageName': 'org.tuxpaint', 'suggestedVersionCode': 9350}).toString(),
      'https://f-droid.org/repo/org.tuxpaint_9350.apk',
    );
    expect(fdroidApkUrl('x.y', const {}), isNull);
  });

  test('item state: busy phases and installed versions', () {
    const s = StoreItemState();
    expect(s.installed, isFalse);
    expect(s.copyWith(phase: StorePhase.downloading).busy, isTrue);
    expect(s.copyWith(version: '1.0').installed, isTrue);
    expect(s.copyWith(version: '1.0').copyWith(clearVersion: true).installed, isFalse);
  });
}
