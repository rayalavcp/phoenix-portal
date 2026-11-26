import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/ui/home/clock_faces.dart';

void main() {
  DateTime at(int h, int m) => DateTime(2026, 1, 1, h, m);

  test('the word clock rounds to five minutes', () {
    expect(clockWords(at(7, 0)), "It's seven o'clock");
    expect(clockWords(at(7, 2)), "It's seven o'clock");
    expect(clockWords(at(7, 13)), "It's quarter past seven");
    expect(clockWords(at(7, 30)), "It's half past seven");
    expect(clockWords(at(7, 41)), "It's twenty to eight");
    expect(clockWords(at(7, 45)), "It's quarter to eight");
    expect(clockWords(at(7, 58)), "It's eight o'clock");
    expect(clockWords(at(23, 25)), "It's twenty-five past eleven");
    expect(clockWords(at(0, 10)), "It's ten past twelve");
    expect(clockWords(at(11, 58)), "It's twelve o'clock");
  });

  for (final face in clockFaces.keys) {
    testWidgets('the $face face lays out', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: ClockFace(face: face, now: at(9, 41), size: 120)),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      if (face == 'words') expect(find.textContaining('twenty to ten', findRichText: true), findsOneWidget);
    });
  }
}
