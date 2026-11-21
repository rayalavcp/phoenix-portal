import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/managers/home/panchang.dart';
import 'package:kiosk_satellite/managers/home/phoenix_home_manager.dart';

// The Telugu calendar is computed on the device. These pin it to 2026's
// published dates. Festival days follow local sunrise, so they hold for
// whatever timezone the tests run in.
void main() {
  final p = PanchangCalculator(33.1507, -96.8236); // Frisco, Texas

  bool on(int y, int m, int d, String festival) =>
      p.day(DateTime(y, m, d)).festivals.any((f) => f.contains(festival));

  test('2026 festivals land on their days', () {
    expect(on(2026, 1, 14, 'Sankranti'), isTrue);
    expect(on(2026, 2, 15, 'Shivaratri'), isTrue);
    expect(on(2026, 3, 19, 'Ugadi'), isTrue);
    expect(on(2026, 3, 26, 'Rama Navami'), isTrue);
    expect(on(2026, 9, 14, 'Vinayaka Chavithi'), isTrue);
    expect(on(2026, 10, 20, 'Dasara'), isTrue);
    expect(on(2026, 11, 8, 'Deepavali'), isTrue);
    expect(on(2026, 11, 24, 'Kartika Pournami'), isTrue);
  });

  test('the day names follow the lunar month', () {
    final day = p.day(DateTime(2026, 11, 24));
    expect(day.pournami, isTrue);
    expect(day.masaNameEn, 'Kartika');
    expect(day.samvatsaraName, 'Parabhava');
    expect(day.sunrise.isBefore(day.sunset), isTrue);
    final (rahuStart, rahuEnd) = day.rahuKalam;
    expect(rahuEnd.difference(rahuStart), day.sunset.difference(day.sunrise) ~/ 8);
  });

  test('moon and sun longitudes stay in range and move', () {
    final jd = julianDay(DateTime.utc(2026, 11, 21));
    for (var i = 0; i < 30; i++) {
      final m = moonLongitude(jd + i), s = sunLongitude(jd + i);
      expect(m, inInclusiveRange(0, 360));
      expect(s, inInclusiveRange(0, 360));
    }
    // The Moon gains about 12.2° a day on the Sun.
    final gain = (elongation(jd + 1) - elongation(jd) + 360) % 360;
    expect(gain, inInclusiveRange(10, 15));
  });

  test('tiles pack into the first free spot', () {
    final spots = packTiles([(2, 1), (2, 2), (2, 2), (2, 1), (1, 1), (1, 1)], 6);
    expect(spots, [(0, 0), (2, 0), (4, 0), (0, 1), (0, 2), (1, 2)]);
    // Wider than the grid: clamped to it.
    expect(packTiles([(9, 1)], 4), [(0, 0)]);
  });

  test('a stored layout keeps known tiles and adds new ones', () {
    final layout = decodeTileLayout('[{"id":"kids","w":3,"h":2},{"id":"nope"},{"id":"kids"}]');
    expect(layout.first.id, 'kids');
    expect(layout.first.w, 3);
    expect(layout.map((t) => t.id).toSet().length, defaultHomeTiles.length);
    expect(decodeTileLayout('junk').length, defaultHomeTiles.length);
  });
}
