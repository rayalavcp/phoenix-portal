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
  HomeTheme('auto', 'From wallpaper', [Color(0xFF3A2118), Color(0xFF16171C), Color(0xFF0C0E10)], [
    [Color(0xFF8872E4), Color(0xFFAD7DE4)],
    [Color(0xFFCE4D41), Color(0xFFE48C45)],
    [Color(0xFF319B73), Color(0xFF6CD0A6)],
  ], Color(0xFFE48046)),
  HomeTheme('ember', 'Ember', [Color(0xFF3A2118), Color(0xFF16171C), Color(0xFF0C0E10)], [
    [Color(0xFF8872E4), Color(0xFFAD7DE4)],
    [Color(0xFFCE4D41), Color(0xFFE48C45)],
    [Color(0xFF319B73), Color(0xFF6CD0A6)],
    [Color(0xFF363C66), Color(0xFF717DE4)],
    [Color(0xFFD99830), Color(0xFFE4B657)],
    [Color(0xFF4399D0), Color(0xFF77BAE4)],
    [Color(0xFFD96380), Color(0xFFE496A4)],
    [Color(0xFF2B2F37), Color(0xFF424852)],
  ], Color(0xFFE48046)),
  HomeTheme('ocean', 'Ocean', [Color(0xFF182E3A), Color(0xFF101820), Color(0xFF090C10)], [
    [Color(0xFF297494), Color(0xFF4FB6D2)],
    [Color(0xFF2A5B7A), Color(0xFF5899CB)],
    [Color(0xFF277C77), Color(0xFF51BCB1)],
    [Color(0xFF35487A), Color(0xFF7188E4)],
    [Color(0xFF23626F), Color(0xFF67B5C3)],
    [Color(0xFF36465F), Color(0xFF7A94B9)],
  ], Color(0xFF4FB6D2)),
  HomeTheme('forest', 'Forest', [Color(0xFF1C301F), Color(0xFF121813), Color(0xFF090C0A)], [
    [Color(0xFF306B45), Color(0xFF5FAA79)],
    [Color(0xFF526B30), Color(0xFF9FBF58)],
    [Color(0xFF255951), Color(0xFF53A295)],
    [Color(0xFF6B5430), Color(0xFFC19F59)],
    [Color(0xFF395E39), Color(0xFF87B879)],
    [Color(0xFF3E4A31), Color(0xFF718759)],
  ], Color(0xFF9FBF58)),
  HomeTheme('midnight', 'Midnight', [Color(0xFF292344), Color(0xFF14121E), Color(0xFF08080D)], [
    [Color(0xFF4B3E88), Color(0xFF8772E4)],
    [Color(0xFF623E88), Color(0xFFAD7DE4)],
    [Color(0xFF2F386B), Color(0xFF697DE4)],
    [Color(0xFF6B386B), Color(0xFFCB7ECB)],
    [Color(0xFF35415A), Color(0xFF778BB2)],
    [Color(0xFF302A40), Color(0xFF524A70)],
  ], Color(0xFFAD7DE4)),
  HomeTheme('sunset', 'Sunset', [Color(0xFF4A2531), Color(0xFF1C1319), Color(0xFF0D090C)], [
    [Color(0xFFD96380), Color(0xFFE496A4)],
    [Color(0xFFCE4D41), Color(0xFFE4AA4B)],
    [Color(0xFF883E6F), Color(0xFFD974AF)],
    [Color(0xFFD99830), Color(0xFFE4C487)],
    [Color(0xFFAB4A53), Color(0xFFE47D7D)],
    [Color(0xFF5A354E), Color(0xFF956582)],
  ], Color(0xFFE496A4)),
  HomeTheme('graphite', 'Graphite', [Color(0xFF28292E), Color(0xFF16171A), Color(0xFF0C0C0E)], [
    [Color(0xFF303338), Color(0xFF4E515A)],
    [Color(0xFF36393F), Color(0xFF595E68)],
    [Color(0xFF2C2E33), Color(0xFF484B54)],
    [Color(0xFF3C3F45), Color(0xFF666A7A)],
  ], Color(0xFFE48046)),
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
      if (weight[b] > 0) (b * 30.0 + 15, (satSum[b] / weight[b]).clamp(0.35, 0.62)),
  ];
  // A grey picture: soft blues and slates, so the tiles still differ.
  if (hues.isEmpty) hues.addAll(const [(215.0, 0.45), (200.0, 0.35), (230.0, 0.4)]);
  while (hues.length < 4) {
    final (h, sat) = hues[hues.length % hues.length];
    hues.add(((h + 40 * hues.length) % 360, sat));
  }
  List<Color> gradient((double, double) hs) => [
    HSVColor.fromAHSV(1, hs.$1, hs.$2, 0.55).toColor(),
    HSVColor.fromAHSV(1, hs.$1, (hs.$2 * 0.85).clamp(0.0, 1.0), 0.85).toColor(),
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
    HSVColor.fromAHSV(1, hues.first.$1, hues.first.$2.clamp(0.45, 0.65), 0.88).toColor(),
  );
}
