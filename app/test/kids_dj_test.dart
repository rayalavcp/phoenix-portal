import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/ui/kids/kids_dj.dart';

void main() {
  test('every song parses into whole four-bar phrases', () {
    for (final (name, tune) in djSongs) {
      final notes = djParse(tune);
      final end = notes.last.at + notes.last.beats;
      expect(end % 16, 0, reason: name);
      expect(notes.where((n) => n.midi > 0).length, greaterThan(10), reason: name);
      for (final n in notes) {
        if (n.midi > 0) expect(n.midi, inInclusiveRange(52, 76), reason: name);
      }
    }
  });

  test('notes read right', () {
    final n = djParse('C4 F#4:2 R:0.5 Bb3');
    expect(n.map((x) => x.midi).take(4), [60, 66, 0, 58]);
    expect(n[1].beats, 2);
    expect(n[3].at, 3.5);
  });

  test('the chords follow the tune', () {
    expect(djChord(djParse('C4 E4 G4 C4'), 0).$1, 0);
    expect(djChord(djParse('F4 A4 C4 F4'), 0).$1, 5);
    expect(djChord(djParse('G4 B4 D4 G4'), 0).$1, 7);
  });

  test('a set is an intro, the song, then the drop', () {
    final notes = djParse(djSongs.first.$2);
    final set = djArrangement(notes);
    expect(set.first.intro, isTrue);
    expect(set.where((p) => p.drop).length, set.where((p) => !p.drop && !p.intro).length);
  });

  test('every phrase is four bars long, loud enough and never clipping', () {
    final notes = djParse(djSongs[4].$2);
    for (final p in djArrangement(notes).take(3)) {
      final pcm = djRender(notes, p);
      expect(pcm.length, closeTo(djPhraseSeconds * djRate, 2));
      var peak = 0.0;
      for (final v in pcm) {
        if (v.abs() > peak) peak = v.abs();
      }
      expect(peak, greaterThan(0.3));
      expect(peak, lessThanOrEqualTo(0.9));
    }
    final s = djScratch();
    expect(s.every((v) => v.abs() <= 1), isTrue);
  });
}
