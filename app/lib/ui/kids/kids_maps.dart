import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kids_activities.dart';
import 'kids_games.dart';
import 'kids_learn.dart' show quizStars;
import 'kids_logic.dart' show KidsScores;
import 'kids_more_logic.dart' show flagEmoji, kidsCountries;

/// The Maps shelf: the USA's states, India's states and union territories,
/// and the countries of the world. Find a place, name it, its capital, its
/// continent or flag, fill in the whole map, or match shapes from memory.
///
/// The maps are packed from public map data (see assets/maps/SOURCES.md):
/// each region's outline in a box 1000 units wide.

class MapRegion {
  MapRegion._(this.name, this.group, this.asked, this.label, this.area, this.path, this.bounds, this.mainPath, {this.id, this.capital, this.iso});

  factory MapRegion.fromJson(Map<String, dynamic> j) {
    final path = Path()..fillType = PathFillType.evenOdd;
    var main = Path();
    var mainArea = -1.0;
    for (final ring in j['p'] as List) {
      final r = (ring as List).cast<num>();
      final pts = [for (var i = 0; i + 1 < r.length; i += 2) Offset(r[i].toDouble(), r[i + 1].toDouble())];
      path.addPolygon(pts, true);
      final b = Rect.fromPoints(pts.first, pts.first).expandToInclude(Rect.fromPoints(pts.reduce((a, b) => Offset(math.min(a.dx, b.dx), math.min(a.dy, b.dy))), pts.reduce((a, b) => Offset(math.max(a.dx, b.dx), math.max(a.dy, b.dy)))));
      if (b.width * b.height > mainArea) {
        mainArea = b.width * b.height;
        main = Path()..addPolygon(pts, true);
      }
    }
    final c = (j['c'] as List).cast<num>();
    return MapRegion._(
      j['n'] as String,
      j['g'] as String? ?? '',
      j['q'] as bool? ?? true,
      Offset(c[0].toDouble(), c[1].toDouble()),
      (j['a'] as num).toDouble(),
      path,
      path.getBounds(),
      main,
      id: j['id'] as String?,
      capital: j['cap'] as String?,
      iso: j['iso'] as String?,
    );
  }

  final String name;

  /// Region (USA), state or union territory (India), continent (world).
  final String group;

  /// Whether quizzes ask about it (not territories, tiny or disputed places).
  final bool asked;
  final Offset label;
  final double area;
  final Path path;
  final Rect bounds;

  /// The biggest piece alone (for drawing its shape on a card).
  final Path mainPath;
  final String? id, capital, iso;

  /// The country's capital from the flag quiz's list (world map).
  String? get worldCapital {
    final code = iso;
    if (code == null) return null;
    for (final (c, _, cap) in kidsCountries) {
      if (c == code) return cap;
    }
    return null;
  }

  /// Small enough to need a ring around it to be seen.
  bool get tiny => area < 120;
}

class KidsMapData {
  KidsMapData._(this.key, this.title, this.credit, this.size, this.regions);

  factory KidsMapData.parse(String key, String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    return KidsMapData._(
      key,
      j['title'] as String,
      j['credit'] as String,
      Size((j['w'] as num).toDouble(), (j['h'] as num).toDouble()),
      [for (final r in j['regions'] as List) MapRegion.fromJson(r as Map<String, dynamic>)],
    );
  }

  static final _cache = <String, Future<KidsMapData>>{};
  static final _loaded = <String, KidsMapData>{};

  /// 'usa', 'india' or 'world', from the app's assets (loaded once).
  static Future<KidsMapData> load(String key, {AssetBundle? bundle}) => _cache[key] ??= (bundle ?? rootBundle)
      .loadString('assets/maps/$key.json')
      .then((s) => _loaded[key] = KidsMapData.parse(key, s));

  /// The map, if it has been loaded already.
  static KidsMapData? loaded(String key) => _loaded[key];

  final String key, title, credit;
  final Size size;
  final List<MapRegion> regions;

  List<MapRegion> get asked => [for (final r in regions) if (r.asked) r];

  /// The region at [p] (map units); else the nearest small one within
  /// [slop], so tiny places can still be tapped.
  MapRegion? hit(Offset p, {double slop = 18}) {
    // The smallest place under the tap (an enclave beats what surrounds it).
    MapRegion? inside;
    for (final r in regions) {
      if (r.bounds.contains(p) && r.path.contains(p) && (inside == null || r.area < inside.area)) inside = r;
    }
    // A tiny place right by the tap wins: it is too small to hit exactly.
    MapRegion? near;
    // ...but only when the tap is closer to it than to the middle of the
    // place it landed in.
    var nearD = inside == null ? slop : math.min(slop * 0.35, (inside.label - p).distance);
    for (final r in regions) {
      if (!r.tiny || r == inside || (inside != null && inside.area < r.area * 6)) continue;
      final d = (r.label - p).distance;
      if (d < nearD) {
        near = r;
        nearD = d;
      }
    }
    return near ?? inside;
  }

  /// The biggest half of [list]: the easy ones.
  static List<MapRegion> bigOnes(List<MapRegion> list) {
    final sorted = [...list]..sort((a, b) => b.area.compareTo(a.area));
    return sorted.take(math.max(10, sorted.length ~/ 2)).toList();
  }
}

/// What a map game asks.
enum MapMode { find, name, capital, continent, flag, fill, memory }

extension MapModeText on MapMode {
  String get label => switch (this) {
    MapMode.find => 'Find it',
    MapMode.name => 'Name it',
    MapMode.capital => 'Capitals',
    MapMode.continent => 'Continents',
    MapMode.flag => 'Flags',
    MapMode.fill => 'Fill the map',
    MapMode.memory => 'Shape memory',
  };
}

/// The modes each map offers.
List<MapMode> mapModes(String key) => switch (key) {
  'world' => const [MapMode.find, MapMode.name, MapMode.continent, MapMode.flag, MapMode.capital, MapMode.fill, MapMode.memory],
  _ => const [MapMode.find, MapMode.name, MapMode.capital, MapMode.fill, MapMode.memory],
};

const worldContinents = ['Africa', 'Asia', 'Europe', 'North America', 'South America', 'Oceania'];

/// The regions a round asks about, for a mode and level.
List<MapRegion> mapPool(KidsMapData map, MapMode mode, int level) {
  var pool = map.asked;
  if (mode == MapMode.capital) {
    pool = [for (final r in pool) if ((map.key == 'world' ? r.worldCapital : r.capital) != null) r];
  }
  if (mode == MapMode.flag) pool = [for (final r in pool) if (r.iso != null && RegExp(r'^[A-Z]{2}$').hasMatch(r.iso!)) r];
  if (mode == MapMode.fill && map.key == 'world') {
    final continent = worldContinents[level.clamp(0, worldContinents.length - 1)];
    return [for (final r in pool) if (r.group == continent) r];
  }
  if (mode == MapMode.fill) return pool;
  return level == 0 ? KidsMapData.bigOnes(pool) : pool;
}

/// Four different answers for [target] (names or capitals), the right one
/// among them.
List<String> mapChoices(MapRegion target, List<MapRegion> pool, String Function(MapRegion) text, math.Random rng) {
  final answer = text(target);
  final out = <String>{answer};
  final others = [...pool]..shuffle(rng);
  for (final r in others) {
    if (out.length >= 4) break;
    final t = text(r);
    if (t.isNotEmpty) out.add(t);
  }
  return out.toList()..shuffle(rng);
}

// ── The game ──────────────────────────────────────────────────────────────

/// A map game: [mapKey] is 'usa', 'india' or 'world'.
class MapQuest extends StatefulWidget {
  const MapQuest({super.key, required this.mapKey, required this.onBack});
  final String mapKey;
  final VoidCallback onBack;

  @override
  State<MapQuest> createState() => _MapQuestState();
}

class _MapQuestState extends State<MapQuest> with SingleTickerProviderStateMixin {
  final _rng = math.Random();
  late final AnimationController _pulse;
  KidsMapData? _map;
  int _mode = 0, _level = 0;
  bool _playing = false, _over = false, _newBest = false, _busy = false;

  List<MapRegion> _queue = [];
  int _total = 0, _asked = 0, _score = 0, _misses = 0, _tries = 0;
  MapRegion? _target, _wrong, _reveal;
  String _continent = '';
  List<String> _choices = [];
  String? _picked;
  final _found = <MapRegion>{};
  String _note = '';
  final _view = TransformationController();

  MapMode get _m => mapModes(widget.mapKey)[_mode];
  bool get _world => widget.mapKey == 'world';
  String get _key => 'map_${widget.mapKey}_${_m.name}${_m == MapMode.fill && _world ? _level : ''}';

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _map = KidsMapData.loaded(widget.mapKey);
    if (_map == null) {
      unawaited(KidsMapData.load(widget.mapKey).then((m) {
        if (mounted) setState(() => _map = m);
      }));
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _view.dispose();
    super.dispose();
  }

  List<String> get _levels => _m == MapMode.fill && _world
      ? worldContinents
      : (_m == MapMode.fill ? const ['Whole map'] : (_m == MapMode.memory ? const ['6 pairs', '8 pairs'] : const ['Big ones', 'All of them']));

  String get _things => switch (widget.mapKey) { 'usa' => 'states', 'india' => 'states and territories', _ => 'countries' };

  void _start() {
    final map = _map!;
    _view.value = Matrix4.identity();
    setState(() {
      _playing = true;
      _over = false;
      _score = 0;
      _misses = 0;
      _asked = 0;
      _found.clear();
      final pool = mapPool(map, _m, _level)..shuffle(_rng);
      _queue = _m == MapMode.fill ? pool : pool.take(10).toList();
      _total = _m == MapMode.continent ? 10 : _queue.length;
      _next();
    });
  }

  void _next() {
    final map = _map!;
    _tries = 0;
    _wrong = null;
    _reveal = null;
    _picked = null;
    _note = '';
    if (_asked >= _total) {
      unawaited(_finish());
      return;
    }
    _asked++;
    if (_m == MapMode.continent) {
      _continent = worldContinents[_rng.nextInt(worldContinents.length)];
      _target = null;
      return;
    }
    _target = _queue.removeLast();
    final pool = mapPool(map, _m, 1);
    if (_m == MapMode.name) _choices = mapChoices(_target!, pool, (r) => r.name, _rng);
    if (_m == MapMode.capital) _choices = mapChoices(_target!, pool, (r) => (_world ? r.worldCapital : r.capital) ?? '', _rng);
  }

  int get _stars => switch (_m) {
    MapMode.fill => _misses <= _total * 0.1 ? 3 : (_misses <= _total * 0.3 ? 2 : 1),
    // Shape memory: _score holds the moves taken.
    MapMode.memory => _score <= _total * 1.5 ? 3 : (_score <= _total * 2.25 ? 2 : 1),
    _ => quizStars(_score, math.max(1, _total)),
  };

  Future<void> _finish() async {
    final best = await KidsScores.offer(_key, _score, lowerIsBetter: _m == MapMode.memory);
    await KidsScores.addStars(_stars);
    if (mounted) {
      setState(() {
        _playing = false;
        _over = true;
        _newBest = best;
      });
    }
  }

  void _after(Duration d) {
    _busy = true;
    Timer(d, () {
      if (!mounted || !_playing) return;
      setState(() {
        _busy = false;
        _next();
      });
    });
  }

  bool _matches(MapRegion r) => switch (_m) {
    MapMode.continent => r.group == _continent,
    MapMode.flag => r.iso == _target?.iso,
    _ => r == _target,
  };

  void _tap(Offset local, Size box) {
    final map = _map;
    if (map == null || _busy || !_playing) return;
    if (!const [MapMode.find, MapMode.continent, MapMode.flag, MapMode.fill].contains(_m)) return;
    final p = Offset(local.dx / box.width * map.size.width, local.dy / box.height * map.size.height);
    final scale = _view.value.getMaxScaleOnAxis();
    final r = map.hit(p, slop: 22 / scale);
    if (r == null) return;
    setState(() {
      if (_matches(r)) {
        if (_tries == 0) _score++;
        if (_target != null) _found.add(_target!);
        if (_m == MapMode.continent) _found.addAll(map.regions.where((x) => x.group == _continent));
        _note = _m == MapMode.continent ? 'Yes! ${r.name} is in $_continent' : 'Yes! ${r.name}';
        _wrong = null;
        _after(Duration(milliseconds: _m == MapMode.fill ? 700 : 1100));
        return;
      }
      _tries++;
      _misses++;
      _wrong = r;
      _note = _m == MapMode.continent ? '${r.name} is in ${r.group.isEmpty ? 'no continent' : r.group}' : 'That is ${r.name}';
      if (_tries >= 3) {
        _reveal = _target;
        _note = _target == null ? 'Look for the glowing countries' : 'Here it is: ${_target!.name}';
        if (_m == MapMode.continent) _found.addAll(map.regions.where((x) => x.group == _continent));
        _after(const Duration(milliseconds: 2200));
      }
    });
  }

  String get _answer => _m == MapMode.name ? _target!.name : ((_world ? _target!.worldCapital : _target!.capital) ?? '');

  void _pick(String choice) {
    if (_picked != null || _busy) return;
    final right = choice == _answer;
    setState(() {
      _picked = choice;
      if (right) {
        _score++;
        _found.add(_target!);
      } else {
        _misses++;
      }
      _note = _m == MapMode.capital
          ? 'The capital of ${_target!.name} is ${(_world ? _target!.worldCapital : _target!.capital)}'
          : 'This is ${_target!.name}';
    });
    _after(Duration(milliseconds: right ? 1000 : 2200));
  }

  String get _prompt => switch (_m) {
    MapMode.find || MapMode.fill => 'Find ${_target?.name ?? ''}',
    MapMode.name => 'What is the glowing ${widget.mapKey == 'world' ? 'country' : 'state'}?',
    MapMode.capital => 'What is the capital of ${_target?.name ?? ''}?',
    MapMode.continent => 'Tap a country in $_continent',
    MapMode.flag => 'Whose flag is this?',
    MapMode.memory => '',
  };

  @override
  Widget build(BuildContext context) {
    final map = _map;
    final title = switch (widget.mapKey) { 'usa' => 'USA Map', 'india' => 'India Map', _ => 'World Map' };
    return KidsActivityFrame(
      title: title,
      colors: const [Color(0xFF14365A), Color(0xFF2F7B4A)],
      onBack: widget.onBack,
      trailing: _playing && _m != MapMode.memory
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_m == MapMode.fill ? '${_found.length} / $_total' : '$_asked / $_total', style: kidsText(26)),
                if (_m != MapMode.fill) ...[
                  const SizedBox(width: 14),
                  const Icon(Icons.star_rounded, color: Color(0xFFFFD27A), size: 30),
                  Text('$_score', style: kidsText(26)),
                ],
              ],
            )
          : null,
      child: map == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _over
          ? KidsResult(
              title: _m == MapMode.fill ? 'Map complete!' : (_stars == 3 ? 'Map master!' : 'Nice exploring!'),
              detail: switch (_m) {
                MapMode.fill => 'All $_total $_things · $_misses wrong taps',
                MapMode.memory => 'All $_total pairs in $_score moves',
                _ => '$_score of $_total right first time',
              },
              stars: _stars,
              newBest: _newBest,
              onAgain: _start,
            )
          : !_playing
          ? KidsStartPanel(
              icon: Icons.public_rounded,
              pitch: _pitch(map),
              best: KidsScores.best(_key).then((b) => b == null ? null : (_m == MapMode.memory ? 'Best: $b moves' : 'Best: $b')),
              options: Column(
                children: [
                  kidsLevelChips([for (final m in mapModes(widget.mapKey)) m.label], _mode, (i) => setState(() {
                    _mode = i;
                    _level = 0;
                  })),
                  if (_levels.length > 1) ...[
                    const SizedBox(height: 14),
                    kidsLevelChips(_levels, _level, (i) => setState(() => _level = i)),
                  ],
                ],
              ),
              onStart: _start,
            )
          : _m == MapMode.memory
          ? MapShapeMemory(
              map: map,
              pairs: _level == 0 ? 6 : 8,
              onDone: (moves) {
                _score = moves;
                _total = _level == 0 ? 6 : 8;
                unawaited(_finish());
              },
            )
          : _board(map),
    );
  }

  String _pitch(KidsMapData map) => switch (_m) {
    MapMode.find => 'A name pops up: tap that place on the map. Pinch to zoom in on the small ones!',
    MapMode.name => 'One place glows: which one is it?',
    MapMode.capital => 'One place glows: pick its capital city.',
    MapMode.continent => 'Tap any country in the continent named.',
    MapMode.flag => 'A flag pops up: tap its country on the map.',
    MapMode.fill => 'Find all ${mapPool(map, _m, _level).length} $_things until the whole map is coloured in!',
    MapMode.memory => 'Turn cards to match each shape with its name.',
  };

  Widget _board(KidsMapData map) {
    final choicesMode = _m == MapMode.name || _m == MapMode.capital;
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth > box.maxHeight;
        final header = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_m == MapMode.flag && _target != null) Text(flagEmoji(_target!.iso!), style: const TextStyle(fontSize: 64)),
            Text(_prompt, textAlign: TextAlign.center, style: kidsText(30)),
            SizedBox(
              height: 34,
              child: Text(_note, textAlign: TextAlign.center, style: kidsText(22, color: _wrong != null && _reveal == null ? const Color(0xFFFFB4B4) : const Color(0xFFB8FFB8), weight: FontWeight.w700)),
            ),
          ],
        );
        final mapView = ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            color: const Color(0xFF0E2A44).withValues(alpha: 0.55),
            child: InteractiveViewer(
              transformationController: _view,
              maxScale: 8,
              child: Center(
                child: AspectRatio(
                  aspectRatio: map.size.width / map.size.height,
                  child: LayoutBuilder(
                    builder: (context, inner) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => _tap(d.localPosition, Size(inner.maxWidth, inner.maxHeight)),
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) => CustomPaint(
                          size: Size(inner.maxWidth, inner.maxHeight),
                          painter: _MapPainter(
                            map: map,
                            found: _found,
                            wrong: _wrong,
                            glow: _m == MapMode.name || _m == MapMode.capital ? _target : _reveal,
                            pulse: _pulse.value,
                            colorBy: _world ? 'group' : 'index',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final credit = Text('Map: ${map.credit}', style: kidsText(11, color: Colors.white54, weight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis);
        Widget choiceGrid() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in _choices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(width: double.infinity, child: _ChoiceButton(text: c, state: _choiceState(c), onTap: () => _pick(c))),
              ),
          ],
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: wide
              ? Row(
                  children: [
                    Expanded(flex: 7, child: Column(children: [Expanded(child: mapView), credit])),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: math.min(340, box.maxWidth * 0.3),
                      child: SingleChildScrollView(child: Column(children: [header, if (choicesMode) choiceGrid()])),
                    ),
                  ],
                )
              : Column(
                  children: [
                    header,
                    Expanded(child: mapView),
                    credit,
                    if (choicesMode) Padding(padding: const EdgeInsets.only(top: 6), child: choiceGrid()),
                  ],
                ),
        );
      },
    );
  }

  int _choiceState(String c) {
    if (_picked == null) return 0;
    if (c == _answer) return 1;
    return c == _picked ? 2 : 3;
  }

  @visibleForTesting
  MapRegion? get debugTarget => _target;
  @visibleForTesting
  String get debugContinent => _continent;
  @visibleForTesting
  List<String> get debugChoices => _choices;
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({required this.text, required this.state, required this.onTap});
  final String text;

  /// 0 waiting, 1 the right one, 2 picked and wrong, 3 the others.
  final int state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KidsBounce(
    onTap: state == 0 ? onTap : null,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: switch (state) { 1 => const Color(0xFF2FB872), 2 => const Color(0xFFE0525A), 3 => Colors.white.withValues(alpha: 0.35), _ => Colors.white.withValues(alpha: 0.94) },
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        style: kidsText(24, color: state == 1 || state == 2 ? Colors.white : const Color(0xFF1E2A44)),
      ),
    ),
  );
}

/// Calm colours for the map: by continent (world) or a soft patchwork.
const _patch = [Color(0xFF8FD3B5), Color(0xFFF7D488), Color(0xFFF2A7A0), Color(0xFFA9C4F5), Color(0xFFC9B3F0), Color(0xFFB5E08C)];
const _continentColors = {
  'Africa': Color(0xFFF7D488),
  'Asia': Color(0xFFF2A7A0),
  'Europe': Color(0xFFA9C4F5),
  'North America': Color(0xFF8FD3B5),
  'South America': Color(0xFFB5E08C),
  'Oceania': Color(0xFFC9B3F0),
  'Antarctica': Color(0xFFE6EEF5),
};

class _MapPainter extends CustomPainter {
  _MapPainter({required this.map, required this.found, required this.wrong, required this.glow, required this.pulse, required this.colorBy});
  final KidsMapData map;
  final Set<MapRegion> found;
  final MapRegion? wrong, glow;
  final double pulse;
  final String colorBy;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / map.size.width;
    canvas.save();
    canvas.scale(k);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 / k
      ..color = const Color(0xFF34506B);
    for (var i = 0; i < map.regions.length; i++) {
      final r = map.regions[i];
      var c = colorBy == 'group' ? (_continentColors[r.group] ?? const Color(0xFFD8D8D8)) : _patch[i % _patch.length];
      if (!r.asked && colorBy != 'group') c = const Color(0xFFD8D8D8);
      if (found.contains(r)) c = const Color(0xFF2FB872);
      if (r == wrong) c = const Color(0xFFE0525A);
      if (r == glow) c = Color.lerp(const Color(0xFFFF3D8B), Colors.white, pulse * 0.5)!;
      canvas.drawPath(r.path, Paint()..color = c);
      canvas.drawPath(r.path, edge);
    }
    // The glowing place on top, with a bright outline.
    final gl = glow;
    if (gl != null) {
      canvas.drawPath(gl.path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 / k
        ..color = Colors.white);
    }
    // A ring around a glowing place too small to see.
    final g = glow;
    if (g != null && g.tiny) {
      canvas.drawCircle(g.label, (16 + pulse * 6) / k, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 / k
        ..color = const Color(0xFFFF3D8B));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MapPainter old) => true;
}

// ── Shape memory ──────────────────────────────────────────────────────────

/// Match each place's shape with its name: cards face down, two at a time.
class MapShapeMemory extends StatefulWidget {
  const MapShapeMemory({super.key, required this.map, required this.pairs, required this.onDone});
  final KidsMapData map;
  final int pairs;
  final ValueChanged<int> onDone;

  @override
  State<MapShapeMemory> createState() => _MapShapeMemoryState();
}

class _MapShapeMemoryState extends State<MapShapeMemory> {
  final _rng = math.Random();
  late final List<(MapRegion, bool)> _cards; // (place, shows the shape)
  final _open = <int>{}, _matched = <int>{};
  int _moves = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Shapes worth recognising: not the tiny ones.
    final pool = KidsMapData.bigOnes(widget.map.asked)..shuffle(_rng);
    final picks = pool.take(widget.pairs).toList();
    _cards = [for (final p in picks) ...[(p, true), (p, false)]]..shuffle(_rng);
  }

  Future<void> _flip(int i) async {
    if (_busy || _open.contains(i) || _matched.contains(i)) return;
    setState(() => _open.add(i));
    if (_open.length < 2) return;
    _moves++;
    final [a, b] = _open.toList();
    if (_cards[a].$1 == _cards[b].$1) {
      setState(() {
        _matched.addAll(_open);
        _open.clear();
      });
      if (_matched.length == _cards.length) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        widget.onDone(_moves);
      }
      return;
    }
    _busy = true;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    setState(() {
      _open.clear();
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: LayoutBuilder(
      builder: (context, box) {
        final n = _cards.length;
        final wide = box.maxWidth > box.maxHeight;
        final cols = wide ? (n == 12 ? 4 : 4) : 3;
        final rows = (n / cols).ceil();
        const gap = 10.0;
        final w = (box.maxWidth - gap * (cols - 1)) / cols, h = (box.maxHeight - 40 - gap * (rows - 1)) / rows;
        return Column(
          children: [
            SizedBox(height: 40, child: Text('$_moves ${_moves == 1 ? 'move' : 'moves'}  ·  ${_matched.length ~/ 2} of ${widget.pairs} matched', style: kidsText(24))),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < n; i++)
                  SizedBox(
                    width: w,
                    height: h,
                    child: KidsBounce(
                      onTap: () => _flip(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        decoration: BoxDecoration(
                          color: _matched.contains(i)
                              ? const Color(0xFF2FB872)
                              : (_open.contains(i) ? Colors.white : const Color(0xFF2B4C7E)),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: !(_open.contains(i) || _matched.contains(i))
                            ? const Icon(Icons.public_rounded, color: Colors.white54, size: 40)
                            : _cards[i].$2
                            ? CustomPaint(painter: _ShapePainter(_cards[i].$1, _matched.contains(i) ? Colors.white : const Color(0xFF2F7BD6)))
                            : Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _cards[i].$1.name,
                                    textAlign: TextAlign.center,
                                    style: kidsText(26, color: _matched.contains(i) ? Colors.white : const Color(0xFF1E2A44)),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

/// One place's outline, fitted into its card.
class _ShapePainter extends CustomPainter {
  _ShapePainter(this.region, this.color);
  final MapRegion region;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // The largest piece decides the fit (so far-off islands don't shrink it).
    final b = region.mainPath.getBounds();
    final k = math.min(size.width / b.width, size.height / b.height);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(k);
    canvas.translate(-b.center.dx, -b.center.dy);
    canvas.drawPath(region.mainPath, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShapePainter old) => old.region != region || old.color != color;
}
