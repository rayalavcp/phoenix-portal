import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'kids_more_logic.dart' show wavBytes;

/// Freeze Dance's DJ: dance remixes of public-domain songs, made on the
/// device (no recordings are shipped). A four-on-the-floor beat, an
/// offbeat bass, warm chords and a synth lead on the tune, arranged like a
/// DJ set: a drum intro with a riser, the song, then a "drop" with busier
/// hats and the tune an octave up with an echo. Each track is cut into
/// four-bar phrases (one WAV each), so the music can stop dead for a
/// freeze and come back in on the next phrase, the way a DJ cuts a record.

const djBpm = 124.0;
const djRate = 22050;

/// Seconds in one beat and one four-bar phrase.
const djBeat = 60 / djBpm;
const djPhraseSeconds = djBeat * 16;

/// The songs: a name and the tune as notes (`C4`, `F#4`, `R` for a rest),
/// each with its length in beats after a colon (one beat when missing).
/// All are traditional or long out of copyright.
const djSongs = <(String, String)>[
  ('Twinkle Twinkle', 'C4 C4 G4 G4 A4 A4 G4:2 F4 F4 E4 E4 D4 D4 C4:2 G4 G4 F4 F4 E4 E4 D4:2 G4 G4 F4 F4 E4 E4 D4:2 '
      'C4 C4 G4 G4 A4 A4 G4:2 F4 F4 E4 E4 D4 D4 C4:2'),
  ('Old MacDonald', 'C4 C4 C4 G3 A3 A3 G3:2 E4 E4 D4 D4 C4:3 G3 C4 C4 C4 G3 A3 A3 G3:2 E4 E4 D4 D4 C4:4'),
  ('Mary Had a Little Lamb', 'E4 D4 C4 D4 E4 E4 E4:2 D4 D4 D4:2 E4 G4 G4:2 E4 D4 C4 D4 E4 E4 E4 E4 D4 D4 E4 D4 C4:4'),
  ('London Bridge', 'G4:1.5 A4:0.5 G4 F4 E4 F4 G4:2 D4 E4 F4:2 E4 F4 G4:2 G4:1.5 A4:0.5 G4 F4 E4 F4 G4:2 D4:2 G4:2 E4 C4:3'),
  ('Jingle Bells', 'E4 E4 E4:2 E4 E4 E4:2 E4 G4 C4 D4 E4:4 F4 F4 F4 F4 F4 E4 E4 E4 E4 D4 D4 E4 D4:2 G4:2 '
      'E4 E4 E4:2 E4 E4 E4:2 E4 G4 C4 D4 E4:4 F4 F4 F4 F4 F4 E4 E4 E4 G4 G4 F4 D4 C4:4'),
  ('Ode to Joy', 'E4 E4 F4 G4 G4 F4 E4 D4 C4 C4 D4 E4 E4:1.5 D4:0.5 D4:2 E4 E4 F4 G4 G4 F4 E4 D4 C4 C4 D4 E4 D4:1.5 C4:0.5 C4:2'),
];

/// A note: MIDI number (0 a rest), where it starts and how long, in beats.
typedef DjNote = ({int midi, double at, double beats});

const _names = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};

/// The tune as notes, padded with rest to whole four-bar phrases.
List<DjNote> djParse(String tune) {
  final out = <DjNote>[];
  var at = 0.0;
  for (final token in tune.split(RegExp(r'\s+')).where((t) => t.isNotEmpty)) {
    final [note, ...rest] = token.split(':');
    final beats = rest.isEmpty ? 1.0 : double.parse(rest.first);
    var midi = 0;
    if (note != 'R') {
      final m = RegExp(r'^([A-G])([#b]?)(\d)$').firstMatch(note)!;
      midi = 12 * (int.parse(m.group(3)!) + 1) + _names[m.group(1)!]! + (m.group(2) == '#' ? 1 : (m.group(2) == 'b' ? -1 : 0));
    }
    out.add((midi: midi, at: at, beats: beats));
    at += beats;
  }
  final total = (at / 16).ceil() * 16.0;
  if (total > at) out.add((midi: 0, at: at, beats: total - at));
  return out;
}

/// The bar's chord in C (root pitch class and its three notes): whichever
/// of C, F, G or A minor holds most of the bar's tune.
(int, List<int>) djChord(List<DjNote> notes, int bar) {
  const chords = [(0, [0, 4, 7]), (5, [5, 9, 0]), (7, [7, 11, 2]), (9, [9, 0, 4])];
  var best = chords.first;
  var bestScore = -1.0;
  for (final c in chords) {
    var score = 0.0;
    for (final n in notes) {
      if (n.midi == 0) continue;
      final start = math.max(n.at, bar * 4.0), end = math.min(n.at + n.beats, bar * 4.0 + 4);
      if (end <= start) continue;
      if (c.$2.contains(n.midi % 12)) score += end - start;
    }
    if (score > bestScore + 1e-9) {
      bestScore = score;
      best = c;
    }
  }
  return best;
}

double _hz(double midi) => 440.0 * math.pow(2, (midi - 69) / 12);

/// What one phrase plays: the tune's bars from [fromBar] (or none, for
/// the intro), and whether it is the drop.
typedef DjPhrase = ({int? fromBar, bool drop, bool intro});

/// The set: intro, the song, then the drop.
List<DjPhrase> djArrangement(List<DjNote> notes) {
  final bars = ((notes.last.at + notes.last.beats) / 4).round();
  return [
    (fromBar: null, drop: false, intro: true),
    for (var b = 0; b < bars; b += 4) (fromBar: b, drop: false, intro: false),
    for (var b = 0; b < bars; b += 4) (fromBar: b, drop: true, intro: false),
  ];
}

/// Renders one four-bar phrase, mono at [djRate].
Float64List djRender(List<DjNote> notes, DjPhrase phrase, {int seed = 1}) {
  final spb = djBeat * djRate; // samples a beat
  final n = (spb * 16).round();
  final out = Float64List(n);
  var noise = seed * 2654435761 & 0x7fffffff;
  double rnd() {
    noise = (noise * 1103515245 + 12345) & 0x7fffffff;
    return noise / 0x7fffffff * 2 - 1;
  }

  void add(int i, double v) {
    if (i >= 0 && i < n) out[i] += v;
  }

  final drop = phrase.drop, intro = phrase.intro;
  final from = phrase.fromBar ?? 0;
  // Drums: a kick every beat, claps on 2 and 4, offbeat hats (16ths in the drop).
  for (var beat = 0; beat < 16; beat++) {
    final b0 = (beat * spb).round();
    var phase = 0.0;
    for (var i = 0; i < (0.32 * djRate); i++) {
      final t = i / djRate;
      phase += 2 * math.pi * (45 + 80 * math.exp(-t * 28)) / djRate;
      add(b0 + i, math.sin(phase) * math.exp(-t * 8) * 0.95);
    }
    if (beat % 2 == 1) {
      for (final delay in const [0.0, 0.011, 0.022]) {
        final c0 = b0 + (delay * djRate).round();
        var prev = 0.0;
        for (var i = 0; i < (0.14 * djRate); i++) {
          final r = rnd();
          add(c0 + i, (r - prev) * math.exp(-i / djRate * 28) * 0.22);
          prev = r;
        }
      }
    }
    final hats = drop ? const [0.25, 0.5, 0.75] : const [0.5];
    for (final off in hats) {
      final h0 = b0 + (off * spb).round();
      var prev = 0.0;
      for (var i = 0; i < (0.04 * djRate); i++) {
        final r = rnd();
        add(h0 + i, (r - prev) * math.exp(-i / djRate * 90) * (off == 0.5 ? 0.16 : 0.08));
        prev = r;
      }
    }
  }
  // The pump: everything but the drums ducks under each kick.
  double pump(int i) {
    final since = (i % spb) / djRate;
    return 1 - 0.65 * math.exp(-since * 9);
  }

  // Chords: an offbeat bass on the root and a soft pad.
  for (var bar = 0; bar < 4; bar++) {
    final (root, tones) = djChord(notes, from + bar);
    final bar0 = (bar * 4 * spb).round();
    for (var eighth = 1; eighth < 8; eighth += 2) {
      final s0 = bar0 + (eighth * spb / 2).round();
      final f = _hz(36.0 + root);
      for (var i = 0; i < (0.2 * djRate); i++) {
        final t = i / djRate;
        var v = 0.0;
        for (var k = 1; k <= 4; k++) {
          v += math.sin(2 * math.pi * f * k * t) / k;
        }
        add(s0 + i, v * math.exp(-t * 9) * 0.32);
      }
    }
    for (var i = 0; i < (4 * spb).round(); i++) {
      final t = i / djRate;
      var v = 0.0;
      for (final pc in tones) {
        v += math.sin(2 * math.pi * _hz(60.0 + pc) * t);
      }
      final swell = math.min(1.0, t * 3);
      add(bar0 + i, v * 0.035 * swell * pump(bar0 + i));
    }
  }
  if (intro) {
    // A riser into the song: noise swelling up through the last bar.
    final r0 = (12 * spb).round();
    for (var i = 0; i < (4 * spb).round(); i++) {
      add(r0 + i, rnd() * 0.16 * math.pow(i / (4 * spb), 2));
    }
  } else {
    // The tune, as a bright pluck (an octave up with an echo in the drop).
    final lift = drop ? 12 : 0;
    for (final note in notes) {
      if (note.midi == 0) continue;
      final start = note.at - from * 4;
      if (start < 0 || start >= 16) continue;
      final s0 = (start * spb).round();
      final len = (note.beats * spb * 0.92).round();
      final f = _hz(note.midi + 12.0 + lift);
      for (final (delay, gain) in drop ? const [(0.0, 1.0), (0.375, 0.35), (0.75, 0.15)] : const [(0.0, 1.0)]) {
        final d0 = s0 + (delay * spb).round();
        for (var i = 0; i < len; i++) {
          final t = i / djRate;
          var v = 0.0;
          for (var k = 1; k <= 5; k++) {
            v += (math.sin(2 * math.pi * f * k * t) + math.sin(2 * math.pi * f * 1.004 * k * t)) / k;
          }
          final env = math.min(1.0, t * 200) * (0.45 + 0.55 * math.exp(-t * 6)) * math.min(1.0, (len - i) / (0.02 * djRate));
          add(d0 + i, v * env * 0.085 * gain);
        }
      }
    }
  }
  // Soft clip, so loud moments round off rather than crackle.
  for (var i = 0; i < n; i++) {
    out[i] = _tanh(out[i] * 1.1) * 0.9;
  }
  return out;
}

double _tanh(double x) {
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

/// The record scratch a freeze cuts in with.
Float64List djScratch() {
  final n = (0.38 * djRate).round();
  final out = Float64List(n);
  var phase = 0.0;
  var noise = 7;
  for (var i = 0; i < n; i++) {
    final t = i / djRate;
    // The pitch sweeps down and back, like a hand on the vinyl.
    final f = 180 + 520 * (0.5 + 0.5 * math.cos(t * 30)) * math.exp(-t * 3);
    phase += 2 * math.pi * f / djRate;
    noise = (noise * 1103515245 + 12345) & 0x7fffffff;
    final grit = noise / 0x7fffffff * 2 - 1;
    out[i] = (math.sin(phase) * 0.5 + grit * 0.25) * math.exp(-t * 6) * math.min(1.0, t * 300);
  }
  return out;
}

List<Uint8List> _renderSong(int song) {
  final notes = djParse(djSongs[song].$2);
  return [for (final p in djArrangement(notes)) wavBytes(djRender(notes, p, seed: song + 1), rate: djRate)];
}

/// Plays Freeze Dance's music: a song's phrases one after another (after
/// the intro the set goes round its song and drop), stopping dead for a
/// freeze. Silent where nothing can play (tests).
class KidsDj {
  KidsDj(this._play, this._stop);

  final Future<bool> Function(String id, String path) _play;
  final Future<void> Function(String id) _stop;

  List<String> _phrases = const [];
  String? _scratch;
  int _next = 0, _n = 0;
  String? _playing;

  /// Gets [song]'s phrases ready (made once, then kept in the cache).
  Future<void> load(int song) async {
    try {
      final dir = await getTemporaryDirectory();
      final arrangement = djArrangement(djParse(djSongs[song].$2));
      final files = [for (var i = 0; i < arrangement.length; i++) File('${dir.path}/phx_dj_v1_${song}_$i.wav')];
      if (!files.every((f) => f.existsSync())) {
        final wavs = await compute(_renderSong, song);
        for (var i = 0; i < files.length; i++) {
          await files[i].writeAsBytes(wavs[i], flush: true);
        }
      }
      final scratch = File('${dir.path}/phx_dj_scratch_v1.wav');
      if (!scratch.existsSync()) await scratch.writeAsBytes(wavBytes(djScratch(), rate: djRate), flush: true);
      _phrases = [for (final f in files) f.path];
      _scratch = scratch.path;
      _next = 0;
    } on MissingPluginException {
      _phrases = const [];
    } catch (e) {
      debugPrint('dj: $e');
      _phrases = const [];
    }
  }

  /// Plays the next phrase (the intro only once).
  Future<void> nextPhrase() async {
    if (_phrases.isEmpty) return;
    final i = _next;
    _next = _next + 1 >= _phrases.length ? 1 : _next + 1;
    final id = 'kidsdj${_n++ % 4}';
    final last = _playing;
    _playing = id;
    try {
      await _play(id, _phrases[i]);
      if (last != null) unawaited(_stop(last).catchError((_) {}));
    } on MissingPluginException {
      // No player (tests).
    } on PlatformException {
      // A busy output: the game goes on.
    }
  }

  /// Stops the music for a freeze, with a scratch.
  Future<void> freeze() async {
    final id = _playing;
    _playing = null;
    try {
      if (id != null) await _stop(id);
      final s = _scratch;
      if (s != null) await _play('kidsdjscratch', s);
    } on MissingPluginException {
      // No player (tests).
    } on PlatformException {
      // Same.
    }
  }

  Future<void> stop() async {
    final id = _playing;
    _playing = null;
    if (id == null) return;
    try {
      await _stop(id);
    } on MissingPluginException {
      // No player (tests).
    } on PlatformException {
      // Same.
    }
  }
}
