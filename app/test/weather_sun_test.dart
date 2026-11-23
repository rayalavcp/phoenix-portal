import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/managers/home/phoenix_home_manager.dart';
import 'package:kiosk_satellite/ui/home/weather_backdrop.dart';

void main() {
  final rise = DateTime(2026, 6, 1, 6), set = DateTime(2026, 6, 1, 20);
  test('the sun moves along the top edge from left at sunrise to right at sunset', () {
    const size = Size(1000, 600);
    final morning = sunPosition(sunArc(DateTime(2026, 6, 1, 6, 30), rise, set), size);
    final noon = sunPosition(sunArc(DateTime(2026, 6, 1, 13), rise, set), size);
    final evening = sunPosition(sunArc(DateTime(2026, 6, 1, 19, 30), rise, set), size);
    expect(morning.dx, lessThan(200));
    expect(evening.dx, greaterThan(800));
    expect(noon.dx, closeTo(500, 1));
    // A half sun on the top edge all day.
    expect([morning.dy, noon.dy, evening.dy], everyElement(0));
  });

  test('before sunrise and after sunset it stays at the horizon', () {
    expect(sunArc(DateTime(2026, 6, 1, 4), rise, set), 0);
    expect(sunArc(DateTime(2026, 6, 1, 22), rise, set), 1);
    // Unknown times: 6:30 to 18:30.
    expect(sunArc(DateTime(2026, 6, 1, 12, 30), null, null), closeTo(0.5, 0.001));
  });

  test('the forecast carries today\'s sunrise and sunset', () {
    final w = parseOpenMeteo(
      {
        'current': {'temperature_2m': 20, 'weather_code': 0, 'is_day': 1},
        'daily': {
          'time': ['2026-06-01'],
          'weather_code': [0],
          'temperature_2m_max': [25],
          'temperature_2m_min': [15],
          'sunrise': ['2026-06-01T06:21'],
          'sunset': ['2026-06-01T20:31'],
        },
      },
      place: 'Here',
      fahrenheit: false,
    )!;
    expect(w.sunrise, DateTime(2026, 6, 1, 6, 21));
    expect(w.sunset, DateTime(2026, 6, 1, 20, 31));
  });
}
