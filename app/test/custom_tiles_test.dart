import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/managers/home/phoenix_home_manager.dart';
import 'package:kiosk_satellite/ui/home/custom_tiles.dart';

void main() {
  test('custom tiles decode and skip malformed ones', () {
    final raw = jsonEncode([
      {'id': 'c_1', 'kind': 'web', 'title': 'News', 'target': 'https://news.example'},
      {'id': 'c_2', 'kind': 'entity', 'title': '', 'target': 'sensor.outside'},
      {'id': 'x_3', 'kind': 'app', 'title': 'Bad id', 'target': 'com.example'},
      {'id': 'c_4', 'kind': 'web', 'title': 'No scheme', 'target': 'news.example'},
      {'id': 'c_5', 'kind': 'toaster', 'title': 'Bad kind', 'target': 'x'},
      {'id': 'c_1', 'kind': 'app', 'title': 'Duplicate', 'target': 'com.example'},
    ]);
    final tiles = decodeCustomTiles(raw);
    expect(tiles.map((t) => t.id), ['c_1', 'c_2']);
    // A tile without a name is named by what it shows.
    expect(tiles[1].title, 'sensor.outside');
    expect(decodeCustomTiles('not json'), isEmpty);
  });

  test('the layout keeps custom tiles and adds new ones at their size', () {
    const custom = [
      CustomTile(id: 'c_1', kind: 'camera', title: 'Door', target: 'camera.door'),
      CustomTile(id: 'c_2', kind: 'web', title: 'News', target: 'https://news.example'),
    ];
    final stored = jsonEncode([
      {'id': 'c_2', 'w': 3, 'h': 1, 'p': 1},
      {'id': 'c_9', 'w': 1, 'h': 1},
      {'id': 'kids', 'w': 2, 'h': 2},
    ]);
    final layout = decodeTileLayout(stored, custom: custom);
    expect(layout.first.id, 'c_2');
    expect(layout.first.w, 3);
    expect(layout.first.page, 1);
    // A tile that no longer exists is dropped; a new one comes at the end.
    expect(layout.any((t) => t.id == 'c_9'), isFalse);
    final door = layout.firstWhere((t) => t.id == 'c_1');
    expect((door.w, door.h), (2, 2));
  });

  test('entity states read the way people say them', () {
    expect(entityStateText('21.456', {'unit_of_measurement': '°C'}), '21.5 °C');
    expect(entityStateText('40', {'unit_of_measurement': '%'}), '40 %');
    expect(entityStateText('on', {}), 'On');
    expect(entityStateText('not_home', {}), 'Away');
    expect(entityStateText('heat_cool', {}), 'Heat cool');
    expect(entityStateText('', {}), '—');
  });
}
