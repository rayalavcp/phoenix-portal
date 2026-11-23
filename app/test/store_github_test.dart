import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/managers/store/store_manager.dart';

void main() {
  test('versions compare by their numbers', () {
    expect(newerVersion('1.10.0', '1.9.3'), isTrue);
    expect(newerVersion('v2.0', '1.99'), isTrue);
    expect(newerVersion('7.3.2', '7.3.2'), isFalse);
    expect(newerVersion('7.3.1', '7.3.2'), isFalse);
    expect(newerVersion('1.2', '1.2.0'), isFalse);
    expect(newerVersion('1.2.1', '1.2'), isTrue);
  });

  test('the right file is picked from a GitHub release', () {
    final release = {
      'tag_name': 'v1.4.2',
      'assets': [
        {'name': 'morphe-manager-1.4.2.apk.sig', 'browser_download_url': 'https://x/sig'},
        {'name': 'morphe-manager-1.4.2.apk', 'browser_download_url': 'https://x/apk'},
      ],
    };
    final r = githubRelease(release, r'^morphe-manager-.*\.apk$');
    expect(r.version, '1.4.2');
    expect(r.apk.toString(), 'https://x/apk');
    expect(githubRelease({'tag_name': '7.3.2', 'assets': <Object>[]}, r'\.apk$').apk, isNull);
  });

  test('an installed GitHub app knows when an update is out', () {
    const s = StoreItemState(version: '1.4.1', latest: '1.4.2');
    expect(s.updatable, isTrue);
    expect(const StoreItemState(version: '1.4.2', latest: '1.4.2').updatable, isFalse);
    expect(const StoreItemState(latest: '1.4.2').updatable, isFalse);
    expect(s.copyWith(phase: StorePhase.downloading).latest, '1.4.2');
  });

  test('the catalog lists Morphe and MicroG-RE from GitHub', () {
    final cat = parseStoreCatalog(File('assets/store/catalog.json').readAsStringSync());
    final morphe = cat.apps.firstWhere((a) => a.package == 'app.morphe.manager');
    expect(morphe.github, 'MorpheApp/morphe-manager');
    expect(RegExp(morphe.asset!).hasMatch('morphe-manager-1.4.2.apk'), isTrue);
    expect(RegExp(morphe.asset!).hasMatch('morphe-manager-1.4.2.apk.sig'), isFalse);
    final microg = cat.apps.firstWhere((a) => a.package == 'app.revanced.android.gms');
    expect(microg.github, 'MorpheApp/MicroG-RE');
    expect(RegExp(microg.asset!).hasMatch('microg-7.3.2.apk'), isTrue);
    expect(cat.categories, contains(morphe.category));
    // The F-Droid apps are unchanged.
    expect(cat.apps.where((a) => a.github == null).length, greaterThan(10));
  });
}
