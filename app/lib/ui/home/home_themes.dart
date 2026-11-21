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

HomeTheme homeTheme(String id) => homeThemes.firstWhere((t) => t.id == id, orElse: () => homeThemes.first);
