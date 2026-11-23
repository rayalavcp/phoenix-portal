import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Phoenix Home's colour themes: the background and the tile colours. The
/// tiles take the theme's gradients in turn, so neighbours differ.
@immutable
class HomeTheme {
  const HomeTheme(this.id, this.name, this.background, this.tiles, this.accent);

  final String id;
  final String name;

  /// Radial background: glow, middle, edge.
  final List<Color> background;
  final List<List<Color>> tiles;
  final Color accent;

  List<Color> tile(int i) => tiles[i % tiles.length];
}

const homeThemes = <HomeTheme>[
  // Colours picked from the wallpaper (see [autoHomeTheme]); until they
  // are worked out, Ember's.
  HomeTheme('auto', 'From wallpaper', [Color(0xFF3A1A0E), Color(0xFF14161C), Color(0xFF0B0D10)], [
    [Color(0xFF7B5CFF), Color(0xFFB06BFF)],
    [Color(0xFFD42A1A), Color(0xFFF07A1A)],
    [Color(0xFF14A06B), Color(0xFF52D69F)],
  ], Color(0xFFF26A1B)),
  HomeTheme('ember', 'Ember', [Color(0xFF3A1A0E), Color(0xFF14161C), Color(0xFF0B0D10)], [
    [Color(0xFF7B5CFF), Color(0xFFB06BFF)],
    [Color(0xFFD42A1A), Color(0xFFF07A1A)],
    [Color(0xFF14A06B), Color(0xFF52D69F)],
    [Color(0xFF283066), Color(0xFF5B6CFF)],
    [Color(0xFFE08A00), Color(0xFFF7B733)],
    [Color(0xFF1C8ED6), Color(0xFF63C3FF)],
    [Color(0xFFE0446A), Color(0xFFFF8FA3)],
    [Color(0xFF282D37), Color(0xFF3E4552)],
  ], Color(0xFFF26A1B)),
  HomeTheme('ocean', 'Ocean', [Color(0xFF0E2A3A), Color(0xFF0C1620), Color(0xFF070B10)], [
    [Color(0xFF0B6E99), Color(0xFF2BB3D9)],
    [Color(0xFF14527A), Color(0xFF3A8FD1)],
    [Color(0xFF0F7C76), Color(0xFF34C2B3)],
    [Color(0xFF223A7A), Color(0xFF5B7CFF)],
    [Color(0xFF0E5E6F), Color(0xFF4FB6C9)],
    [Color(0xFF2A3F5F), Color(0xFF6C8EBF)],
  ], Color(0xFF2BB3D9)),
  HomeTheme('forest', 'Forest', [Color(0xFF16301A), Color(0xFF101812), Color(0xFF080C09)], [
    [Color(0xFF1F6B3A), Color(0xFF4CAF6E)],
    [Color(0xFF4B6B1F), Color(0xFF9BC53D)],
    [Color(0xFF16594F), Color(0xFF3FA796)],
    [Color(0xFF6B4E1F), Color(0xFFC79A3D)],
    [Color(0xFF2F5E2F), Color(0xFF7DBE6A)],
    [Color(0xFF3A4A2A), Color(0xFF6E8B4E)],
  ], Color(0xFF9BC53D)),
  HomeTheme('midnight', 'Midnight', [Color(0xFF221A44), Color(0xFF110F1E), Color(0xFF07060D)], [
    [Color(0xFF3B2A8C), Color(0xFF7A5CFF)],
    [Color(0xFF5A2A8C), Color(0xFFB06BFF)],
    [Color(0xFF1E2A6B), Color(0xFF4F6BFF)],
    [Color(0xFF6B2A6B), Color(0xFFD16BD1)],
    [Color(0xFF2A3A5A), Color(0xFF6A84B8)],
    [Color(0xFF2B2440), Color(0xFF4A3F70)],
  ], Color(0xFFB06BFF)),
  HomeTheme('sunset', 'Sunset', [Color(0xFF4A1A2A), Color(0xFF1C1018), Color(0xFF0D080C)], [
    [Color(0xFFE0446A), Color(0xFFFF8FA3)],
    [Color(0xFFD42A1A), Color(0xFFF5A623)],
    [Color(0xFF8C2A6B), Color(0xFFE05AA8)],
    [Color(0xFFE08A00), Color(0xFFFFD27A)],
    [Color(0xFFB0303C), Color(0xFFFF6B6B)],
    [Color(0xFF5A2A4A), Color(0xFF9A5A80)],
  ], Color(0xFFFF8FA3)),
  HomeTheme('graphite', 'Graphite', [Color(0xFF26282E), Color(0xFF15161A), Color(0xFF0B0C0E)], [
    [Color(0xFF2E3138), Color(0xFF4A4F5A)],
    [Color(0xFF34373F), Color(0xFF555B68)],
    [Color(0xFF2A2D33), Color(0xFF444954)],
    [Color(0xFF3A3D45), Color(0xFF60667A)],
  ], Color(0xFFF26A1B)),
];

HomeTheme homeTheme(String id) {
  if (id == 'auto') return autoHomeTheme.value ?? homeThemes.first;
  return homeThemes.firstWhere((t) => t.id == id, orElse: () => homeThemes[1]);
}

/// The From wallpaper theme for the wallpaper on screen (null until one
/// has been read). Widgets that colour by the theme listen to it.
final autoHomeTheme = ValueNotifier<HomeTheme?>(null);

int? _autoFor;

/// Works out [autoHomeTheme] from [wallpaper]'s bytes, once per picture.
void updateAutoHomeTheme(Uint8List? wallpaper) {
  if (wallpaper == null) return;
  final id = identityHashCode(wallpaper);
  if (_autoFor == id) return;
  _autoFor = id;
  unawaited(() async {
    try {
      final codec = await ui.instantiateImageCodec(wallpaper, targetWidth: 48);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      codec.dispose();
      if (data == null || _autoFor != id) return;
      autoHomeTheme.value = themeFromPixels(data.buffer.asUint8List());
    } catch (_) {
      // Not a picture Flutter can read: keep the colours there are.
    }
  }());
}

/// A theme from RGBA [pixels]: the picture's most colourful hues, each
/// as a tile gradient (deep to bright), the strongest one the accent, and
/// a dark background tinted by the picture's overall tone.
HomeTheme themeFromPixels(Uint8List pixels) {
  // Twelve hue buckets, weighted by how colourful and how bright a pixel is.
  final weight = List<double>.filled(12, 0);
  final satSum = List<double>.filled(12, 0);
  var r0 = 0.0, g0 = 0.0, b0 = 0.0, n = 0;
  for (var i = 0; i + 3 < pixels.length; i += 4) {
    final c = Color.fromARGB(255, pixels[i], pixels[i + 1], pixels[i + 2]);
    final hsv = HSVColor.fromColor(c);
    r0 += pixels[i];
    g0 += pixels[i + 1];
    b0 += pixels[i + 2];
    n++;
    if (hsv.saturation < 0.18 || hsv.value < 0.18) continue;
    final bucket = (hsv.hue / 30).floor() % 12;
    final w = hsv.saturation * hsv.value;
    weight[bucket] += w;
    satSum[bucket] += hsv.saturation * w;
  }
  final ranked = [for (var b = 0; b < 12; b++) b]..sort((a, b) => weight[b].compareTo(weight[a]));
  final hues = <(double, double)>[
    for (final b in ranked)
      if (weight[b] > 0) (b * 30.0 + 15, (satSum[b] / weight[b]).clamp(0.45, 0.85)),
  ];
  // A grey picture: soft blues and slates, so the tiles still differ.
  if (hues.isEmpty) hues.addAll(const [(215.0, 0.45), (200.0, 0.35), (230.0, 0.4)]);
  while (hues.length < 4) {
    final (h, sat) = hues[hues.length % hues.length];
    hues.add(((h + 40 * hues.length) % 360, sat));
  }
  List<Color> gradient((double, double) hs) => [
    HSVColor.fromAHSV(1, hs.$1, hs.$2, 0.55).toColor(),
    HSVColor.fromAHSV(1, hs.$1, (hs.$2 * 0.85).clamp(0.0, 1.0), 0.92).toColor(),
  ];
  final avg = n == 0 ? const Color(0xFF14161C) : Color.fromARGB(255, (r0 / n).round(), (g0 / n).round(), (b0 / n).round());
  final tone = HSVColor.fromColor(avg);
  return HomeTheme(
    'auto',
    'From wallpaper',
    [
      tone.withSaturation((tone.saturation * 0.8).clamp(0.0, 0.6)).withValue(0.22).toColor(),
      tone.withSaturation((tone.saturation * 0.5).clamp(0.0, 0.4)).withValue(0.10).toColor(),
      const Color(0xFF0B0D10),
    ],
    [for (final hs in hues.take(6)) gradient(hs)],
    HSVColor.fromAHSV(1, hues.first.$1, hues.first.$2.clamp(0.6, 0.9), 0.95).toColor(),
  );
}
