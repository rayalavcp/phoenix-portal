import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/ui/home/home_themes.dart';

Uint8List _picture(List<(Color, int)> parts) {
  final out = <int>[];
  for (final (c, n) in parts) {
    for (var i = 0; i < n; i++) {
      out.addAll([(c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round(), 255]);
    }
  }
  return Uint8List.fromList(out);
}

void main() {
  test('the strongest colour of the wallpaper becomes the accent', () {
    final t = themeFromPixels(_picture([(const Color(0xFF1E7A2E), 900), (const Color(0xFFE0402A), 200), (const Color(0xFF202020), 400)]));
    expect(t.id, 'auto');
    final accentHue = HSVColor.fromColor(t.accent).hue;
    // Green covers most of the picture.
    expect(accentHue, inInclusiveRange(90, 160));
    expect(t.tiles.length, greaterThanOrEqualTo(4));
    // The red shows up among the tile colours.
    expect(t.tiles.any((g) => HSVColor.fromColor(g.last).hue < 30 || HSVColor.fromColor(g.last).hue > 330), isTrue);
  });

  test('a grey picture still gives distinct tile colours', () {
    final t = themeFromPixels(_picture([(const Color(0xFF808080), 500)]));
    expect(t.tiles.length, greaterThanOrEqualTo(4));
    expect({for (final g in t.tiles) g.first}.length, greaterThan(1));
  });

  test('From wallpaper falls back to the default colours until worked out', () {
    autoHomeTheme.value = null;
    expect(homeTheme('auto').id, 'auto');
    expect(homeTheme('nope').id, 'ember');
  });
}
