import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/command_registry.dart';
import '../../core/events.dart';
import '../../core/manager.dart';
import '../home_assistant/home_assistant_manager.dart';
import '../launcher/app_launcher_manager.dart';
import '../location/location_manager.dart';
import '../settings/definitions.dart' as defs;
import '../settings/settings_manager.dart';
import '../screensaver/immich_manager.dart';
import 'panchang.dart';
import 'photo_service.dart';
import 'homework.dart';
import 'school_service.dart';
import 'todo_service.dart';

/// The 4K wallpapers built into the app (assets/wallpapers): id, name and,
/// for photos, the credit their licence asks for (see CREDITS.md there).
const builtinWallpapers = <(String, String, String)>[
  ('lake_louise', 'Lake Louise', 'Chensiyuan · CC BY-SA 4.0 · Wikimedia Commons'),
  ('kathleen_lake', 'Kathleen Lake', 'Jakub Fryš · CC BY-SA 4.0 · Wikimedia Commons'),
  ('flatirons_sunrise', 'Flatirons sunrise', 'Tyler Cipriani · CC BY-SA 4.0 · Wikimedia Commons'),
  ('loch_tummel', 'Loch Tummel autumn', 'Eric Kilby · CC BY-SA 4.0 · Wikimedia Commons'),
  ('dzukou_valley', 'Dzukou Valley', 'Samudra Bikash Hazarika, edited by UnpetitproleX · CC BY-SA 4.0 · Wikimedia Commons'),
  ('above_the_clouds', 'Above the clouds', 'Dmytro Balkhovitin · CC BY-SA 4.0 · Wikimedia Commons'),
  ('rundle_pond', 'Mount Rundle', 'The Cosmonaut · CC BY-SA 2.5 ca · Wikimedia Commons'),
  ('alpine_valley', 'Alpine valley', 'Böhringer · CC BY-SA 3.0 at · Wikimedia Commons'),
  ('titicaca_dawn', 'Lake Titicaca dawn', 'Diego Delso · CC BY-SA 4.0 · Wikimedia Commons'),
  ('gokyo_lakes', 'Gokyo lakes', 'Megaurab09, edited by UnpetitproleX · CC BY-SA 4.0 · Wikimedia Commons'),
  ('highland_loch', 'Highland loch', 'Michal Klajban · CC BY-SA 4.0 · Wikimedia Commons'),
  ('zhangjiajie', 'Zhangjiajie', 'chensiyuan · CC BY-SA 4.0 · Wikimedia Commons'),
  ('gavarnie_valley', 'Gavarnie valley', 'Moahim · CC BY-SA 4.0 · Wikimedia Commons'),
  ('valle_de_la_luna', 'Valle de la Luna', 'Diego Delso · CC BY-SA 4.0 · Wikimedia Commons'),
  ('mountains_dawn', 'Mountain dawn (minimal)', ''),
  ('alpine_lake', 'Alpine lake (minimal)', ''),
  ('misty_forest', 'Misty forest (minimal)', ''),
  ('desert_dunes', 'Desert dunes (minimal)', ''),
  ('autumn_valley', 'Autumn valley (minimal)', ''),
  ('rolling_hills', 'Rolling hills (minimal)', ''),
  ('ocean_sunset', 'Ocean sunset (minimal)', ''),
  ('moonlit_bay', 'Moonlit bay (minimal)', ''),
  ('aurora_night', 'Aurora (minimal)', ''),
  ('deep_ocean', 'Deep ocean (minimal)', ''),
  ('ember_flow', 'Ember (minimal)', ''),
];

/// The minimal wallpapers ship inside the app; the 4K photos are fetched
/// from the project's repository the first time they show, then kept.
String builtinWallpaperAsset(String id) => 'assets/wallpapers/$id.jpg';

/// A small picture of a wallpaper, for the picker.
String builtinWallpaperThumb(String id) => 'assets/wallpapers/thumbs/$id.jpg';

/// Where a built-in 4K photo is downloaded from: the wallpapers folder of
/// the repository's main branch.
List<Uri> builtinWallpaperUrls(String id) => [
  Uri.parse('https://raw.githubusercontent.com/rayalavcp/phoenix-portal/main/wallpapers/$id.jpg'),
];

/// The built-in 4K landscapes (id, name, credit), for the Scenic photo frame
/// shown when no photos are set up.
List<(String, String, String)> get scenicWallpapers => _photoWallpapers;

final _photoWallpapers = [for (final w in builtinWallpapers) if (w.$3.isNotEmpty) w];

/// Today's weather and the next days, from Open-Meteo (no account, no key,
/// no Home Assistant).
@immutable
class HomeWeather {
  const HomeWeather({
    required this.place,
    required this.temperature,
    required this.code,
    required this.isDay,
    required this.days,
    required this.fahrenheit,
    this.sunrise,
    this.sunset,
  });

  final String place;
  final double temperature;

  /// WMO weather code (Open-Meteo's `weather_code`).
  final int code;
  final bool isDay;
  final List<HomeWeatherDay> days;
  final bool fahrenheit;

  /// Today's sunrise and sunset (local time), for the sun's path across
  /// the weather effect; null when the forecast did not carry them.
  final DateTime? sunrise, sunset;
}

@immutable
class HomeWeatherDay {
  const HomeWeatherDay({
    required this.date,
    required this.code,
    required this.high,
    required this.low,
  });

  final DateTime date;
  final int code;
  final double high;
  final double low;
}

/// One Home Assistant entity on the Smart Home page.
@immutable
class HomeEntity {
  const HomeEntity({
    required this.id,
    required this.name,
    required this.state,
    required this.domain,
    this.area,
  });

  final String id;
  final String name;
  final String state;
  final String domain;
  final String? area;

  /// Lights, switches and friends that are on, covers that are open, locks
  /// that are unlocked, players that play, climate that runs.
  bool get active {
    final s = state.toLowerCase();
    if (domain == 'lock') return s == 'unlocked' || s == 'open';
    if (domain == 'climate') return s != 'off' && s != 'unavailable';
    return const {'on', 'open', 'opening', 'playing', 'home'}.contains(s);
  }

  /// Scenes and scripts run; the rest toggle.
  bool get runs => domain == 'scene' || domain == 'script';
}

/// One tile on Phoenix Home: which, and how many grid cells it spans.
@immutable
class HomeTileSpec {
  const HomeTileSpec(this.id, this.w, this.h, {this.page = 0});
  final String id;
  final int w;
  final int h;

  /// Which home screen the tile is on: 0 is the first (Home), 1 Home 2, ...
  final int page;

  HomeTileSpec sized(int w, int h) => HomeTileSpec(id, w.clamp(1, 6), h.clamp(1, 4), page: page);

  HomeTileSpec onPage(int page) => HomeTileSpec(id, w, h, page: page.clamp(0, maxHomePages - 1));

  Map<String, Object?> toJson() => {'id': id, 'w': w, 'h': h, if (page > 0) 'p': page};
}

/// The most home screens there can be.
const maxHomePages = 5;

/// The home screens [tiles] are on, in order, without gaps: a page whose
/// tiles all moved away is gone. Answers each tile's page in that run
/// (0, 1, ...) and how many pages there are.
({List<int> pages, int count}) homePages(List<HomeTileSpec> tiles) {
  final used = {for (final t in tiles) t.page}.toList()..sort();
  final index = {for (var i = 0; i < used.length; i++) used[i]: i};
  return (pages: [for (final t in tiles) index[t.page]!], count: used.isEmpty ? 1 : used.length);
}

/// Every tile Phoenix Home knows, in the default order and size (a six
/// column grid). Tiles a device has no use for (cameras without a view,
/// the calendar without Home Assistant) are skipped when drawn.
const defaultHomeTiles = [
  HomeTileSpec('telugu', 2, 1),
  HomeTileSpec('kids', 2, 2),
  HomeTileSpec('photos', 2, 2),
  HomeTileSpec('school', 2, 1),
  HomeTileSpec('apps', 1, 1),
  HomeTileSpec('smart', 1, 1),
  HomeTileSpec('timers', 1, 1),
  HomeTileSpec('alarms', 1, 1),
  HomeTileSpec('store', 1, 1),
  HomeTileSpec('settings', 1, 1),
  HomeTileSpec('calendar', 1, 1),
  HomeTileSpec('cameras', 1, 1),
  HomeTileSpec('shopping', 1, 1),
];

/// A tile the family made: a Home Assistant entity, a web page, a Home
/// Assistant camera or an app. Its layout id starts with `c_`.
@immutable
class CustomTile {
  const CustomTile({required this.id, required this.kind, required this.title, required this.target});

  final String id;

  /// 'entity', 'web', 'camera' or 'app'.
  final String kind;
  final String title;

  /// The entity id, the address, the camera entity id or the app package.
  final String target;

  static const kinds = ['entity', 'web', 'camera', 'app'];

  /// The size a new tile of this kind starts at.
  HomeTileSpec get spec => switch (kind) {
    'camera' => HomeTileSpec(id, 2, 2),
    'web' => HomeTileSpec(id, 2, 1),
    _ => HomeTileSpec(id, 1, 1),
  };

  Map<String, Object?> toJson() => {'id': id, 'kind': kind, 'title': title, 'target': target};

  static CustomTile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}', kind = '${raw['kind'] ?? ''}';
    final title = '${raw['title'] ?? ''}'.trim(), target = '${raw['target'] ?? ''}'.trim();
    if (!id.startsWith('c_') || !kinds.contains(kind) || target.isEmpty) return null;
    if (kind == 'web' && !(Uri.tryParse(target)?.hasScheme ?? false)) return null;
    return CustomTile(id: id, kind: kind, title: title.isEmpty ? target : title, target: target);
  }
}

/// Custom tiles from their stored JSON; malformed ones are skipped.
List<CustomTile> decodeCustomTiles(String? raw) {
  try {
    final data = raw == null ? null : jsonDecode(raw);
    if (data is! List) return const [];
    final out = <CustomTile>[];
    for (final t in data) {
      final c = CustomTile.fromJson(t);
      if (c != null && !out.any((o) => o.id == c.id)) out.add(c);
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// The stored layout: known tiles in the stored order and size, then any
/// tile added since, so an update's new tiles appear. [custom] are the
/// family's own tiles, known too.
List<HomeTileSpec> decodeTileLayout(String? raw, {List<CustomTile> custom = const []}) {
  final known = {for (final t in defaultHomeTiles) t.id: t, for (final c in custom) c.id: c.spec};
  final out = <HomeTileSpec>[];
  try {
    final data = raw == null ? null : jsonDecode(raw);
    if (data is List) {
      for (final t in data) {
        if (t is! Map || !known.containsKey(t['id']) || out.any((o) => o.id == t['id'])) continue;
        out.add(
          known[t['id']]!
              .sized(t['w'] is int ? t['w'] as int : 1, t['h'] is int ? t['h'] as int : 1)
              .onPage(t['p'] is int ? t['p'] as int : 0),
        );
      }
    }
  } catch (_) {}
  for (final t in [...defaultHomeTiles, for (final c in custom) c.spec]) {
    if (!out.any((o) => o.id == t.id)) out.add(t);
  }
  return out;
}

/// Where each tile lands in a [columns]-wide grid: the first free spot,
/// row by row, so small tiles fill the gaps big ones leave. Answers
/// (column, row) per tile, in order.
List<(int, int)> packTiles(List<(int, int)> sizes, int columns) {
  final taken = <(int, int)>{};
  bool free(int c, int r, int w, int h) {
    if (c + w > columns) return false;
    for (var y = r; y < r + h; y++) {
      for (var x = c; x < c + w; x++) {
        if (taken.contains((x, y))) return false;
      }
    }
    return true;
  }

  final out = <(int, int)>[];
  for (final (w0, h) in sizes) {
    final w = w0.clamp(1, columns);
    var placed = false;
    for (var r = 0; !placed; r++) {
      for (var c = 0; c < columns && !placed; c++) {
        if (free(c, r, w, h)) {
          for (var y = r; y < r + h; y++) {
            for (var x = c; x < c + w; x++) {
              taken.add((x, y));
            }
          }
          out.add((c, r));
          placed = true;
        }
      }
    }
  }
  return out;
}

/// The domains the Smart Home page offers, in the order it groups them.
const homeEntityDomains = [
  'light',
  'switch',
  'fan',
  'cover',
  'climate',
  'lock',
  'media_player',
  'input_boolean',
  'scene',
  'script',
];

/// Phoenix Home: the launcher home screen. It runs without Home Assistant:
/// the clock, the weather (Open-Meteo), the apps and the Kids Portal never
/// need it. Home Assistant is an add-on: the Smart Home page controls its
/// entities, and its dashboard only loads while [dashboardOpen] holds.
class PhoenixHomeManager extends Manager {
  PhoenixHomeManager(
    super.bus,
    super.commands,
    super.log,
    this._settings,
    this._launcher,
    this._location,
    this._homeAssistant,
    this._immich, {
    http.Client? client,
    Future<SharedPreferences> Function()? prefs,
  }) : _client = client ?? http.Client(),
       _prefs = prefs ?? SharedPreferences.getInstance;

  final SettingsManager _settings;
  final AppLauncherManager _launcher;
  final LocationManager _location;
  final HomeAssistantManager _homeAssistant;
  final ImmichManager _immich;

  /// The Photos tile and the Phoenix Photo Frame screensaver.
  late final photos = PhotoService(_client, _prefs, log, _immich);
  final http.Client _client;
  final Future<SharedPreferences> Function() _prefs;

  @override
  String get name => 'phoenix_home';

  /// Whether Phoenix Home is the home screen (the default), rather than
  /// the Home Assistant dashboard.
  bool get enabled =>
      _settings.get(defs.homeScreen) == 'phoenix' &&
      _settings.get(defs.navStyle) != 'compass';

  /// [enabled], live: the kiosk screen shows Phoenix Home while it holds.
  late final active = ValueNotifier<bool>(enabled);

  /// Something of Phoenix Home's own is open over it (the app drawer, the
  /// Smart Home page or the dashboard): back closes it first.
  bool get layerOpen =>
      dashboardOpen.value ||
      smartHomeOpen.value ||
      appsOpen.value ||
      schoolOpen.value ||
      teluguOpen.value ||
      shoppingOpen.value;

  /// The Home Assistant dashboard is on screen over Phoenix Home. The
  /// dashboard page is only loaded while this holds (dashboard_page.dart).
  final dashboardOpen = ValueNotifier<bool>(false);

  /// The Smart Home page is on screen.
  final smartHomeOpen = ValueNotifier<bool>(false);

  /// The full app drawer (every app, with search) is on screen.
  final appsOpen = ValueNotifier<bool>(false);

  /// The Telugu calendar page is on screen.
  final teluguOpen = ValueNotifier<bool>(false);

  /// The Shopping list page is on screen.
  final shoppingOpen = ValueNotifier<bool>(false);

  /// The Home Assistant to-do list the Shopping tile and page show.
  late final todo = TodoService(commands, configured: () => homeAssistantConfigured);

  /// The Telugu calendar for the weather's place (Hyderabad until a city
  /// is set): computed here, no network.
  PanchangCalculator get panchang {
    final g = _geo;
    final lat = g?.lat ?? 17.385, lon = g?.lon ?? 78.4867;
    final calc = _panchang;
    if (calc != null && calc.lat == lat && calc.lon == lon) return calc;
    return _panchang = PanchangCalculator(lat, lon);
  }

  PanchangCalculator? _panchang;

  /// The School page (menus, calendar, bell times) is on screen.
  final schoolOpen = ValueNotifier<bool>(false);

  /// School menus and calendar (none until the School page's Set up).
  late final school = SchoolService(
    _client,
    _prefs,
    log,
    homeAssistant: () => (
      base: _homeAssistant.baseUrl,
      token: _settings.get(defs.haToken),
    ),
  );

  final weather = ValueNotifier<HomeWeather?>(null);

  /// Why there is no weather, for the header's hint: null while loading or
  /// when there is weather.
  final weatherProblem = ValueNotifier<String?>(null);

  /// Pinned app packages, in dock order.
  final favorites = ValueNotifier<List<String>>(const []);

  /// Packages the user hid from Phoenix Home.
  final hidden = ValueNotifier<Set<String>>(const {});

  /// Launch counts and last launch per package, for the "most used" and
  /// "recent" rows.
  final usage = ValueNotifier<Map<String, ({int count, int last})>>(const {});

  /// Apps a parent put in the Kids Portal's "My apps" row, by package.
  final kidsApps = ValueNotifier<List<String>>(const []);

  /// Kids Portal activities a parent has hidden (their ids, e.g. 'snake').
  final kidsHiddenGames = ValueNotifier<List<String>>(const []);

  /// How camera games follow the child: 'body' (the whole body, works
  /// across the room) or 'hands' (the hand alone, close up).
  final kidsTracking = ValueNotifier<String>('body');
  static const _kidsTrackingKey = 'phx.kids.tracking';

  Future<void> setKidsTracking(String mode) async {
    if (mode != 'body' && mode != 'hands') return;
    kidsTracking.value = mode;
    await (await _prefs()).setString(_kidsTrackingKey, mode);
  }

  /// Homework a grown-up sets for the Kids Portal's Homework game.
  late final homework = HomeworkStore(_prefs);

  Future<void> setKidsHiddenGames(List<String> ids) async {
    kidsHiddenGames.value = List.unmodifiable(ids.toSet());
    await (await _prefs()).setStringList(_kidsHiddenKey, kidsHiddenGames.value);
  }

  /// Clears every Kids Portal best score, today's stars and the challenge.
  final kidsScoresReset = ValueNotifier<int>(0);

  Future<void> resetKidsScores() async {
    final prefs = await _prefs();
    for (final k in prefs.getKeys().toList()) {
      if (k.startsWith('phx.kids.best.') || k.startsWith('phx.kids.board.') || k == 'phx.kids.names' || k == 'phx.kids.stars' || k == 'phx.kids.challenge_done') {
        await prefs.remove(k);
      }
    }
    kidsScoresReset.value++;
  }

  /// Phoenix Home's tiles in order and size, and the ones taken off.
  final tiles = ValueNotifier<List<HomeTileSpec>>(defaultHomeTiles);
  final hiddenTiles = ValueNotifier<Set<String>>(const {});

  /// The colour theme (home_themes.dart).
  final theme = ValueNotifier<String>('ember');

  /// 'today': the glass-card Today screen (the default). 'tiles': the
  /// resizable tile grid.
  final layout = ValueNotifier<String>('today');

  /// The home camera (a Home Assistant camera entity) for the Today screen:
  /// the first of [cameraEntities].
  final cameraEntity = ValueNotifier<String>('');

  /// The Home Assistant cameras on the Today screen's camera card, in order
  /// (the doorbell first); swipe across the card to go between them.
  final cameraEntities = ValueNotifier<List<String>>(const []);

  Future<void> setCameraEntities(List<String> entities) async {
    final clean = <String>[
      for (final e in entities)
        if (e.trim().startsWith('camera.')) e.trim(),
    ];
    final seen = <String>{};
    clean.retainWhere(seen.add);
    cameraEntities.value = List.unmodifiable(clean);
    cameraEntity.value = clean.firstOrNull ?? '';
    final prefs = await _prefs();
    await prefs.setStringList(_camerasKey, clean);
    await prefs.setString(_cameraKey, cameraEntity.value);
  }

  /// The wallpaper behind the Today screen, already downloaded.
  final backdrop = ValueNotifier<Uint8List?>(null);

  /// Where the wallpaper comes from: 'builtin:ID' (one of the built-in 4K
  /// wallpapers), 'builtin' (all of them, a new one every three hours),
  /// 'bing' (Bing's 4K photos, a new one every three hours), 'photos' (your
  /// Immich or folder photos), 'url' (one image link) or 'theme' (colours).
  final wallpaper = ValueNotifier<String>('builtin');

  /// How see-through the glass cards and tiles are: 0 clear, 1 solid.
  final glassOpacity = ValueNotifier<double>(0.35);

  Future<void> setGlassOpacity(double value) async {
    glassOpacity.value = value.clamp(0.0, 1.0);
    await (await _prefs()).setDouble(_glassKey, glassOpacity.value);
  }
  final wallpaperUrl = ValueNotifier<String>('');

  /// Show a weather effect whatever the weather ('' = the real weather), to
  /// see what each one looks like. Not saved.
  final weatherDemo = ValueNotifier<String>('');

  String _backdropKey = '';
  List<String> _bingList = const [];
  String _bingListDay = '';

  Future<void> setWallpaper(String source, {String? url}) async {
    wallpaper.value = _validWallpaper(source) ? source : 'builtin';
    if (url != null) wallpaperUrl.value = url.trim();
    final prefs = await _prefs();
    await prefs.setString(_wallpaperKey, wallpaper.value);
    await prefs.setString(_wallpaperUrlKey, wallpaperUrl.value);
    _backdropKey = '';
    if (wallpaper.value == 'theme') backdrop.value = null;
    await refreshBackdrop();
  }

  static bool _validWallpaper(String source) =>
      const {'builtin', 'bing', 'photos', 'url', 'theme'}.contains(source) ||
      builtinWallpapers.any((w) => 'builtin:${w.$1}' == source);

  Future<void> setLayout(String value) async {
    layout.value = value == 'tiles' ? 'tiles' : 'today';
    await (await _prefs()).setString(_layoutKey, layout.value);
  }

  /// The Home Assistant entity that changes when someone rings the doorbell
  /// (a ding binary sensor, an event entity or a button); empty for none.
  final doorbellTrigger = ValueNotifier<String>('');

  /// The camera shown when it rings; empty means the first of
  /// [cameraEntities].
  final doorbellCamera = ValueNotifier<String>('');

  /// How long the live doorbell feed stays on screen.
  final doorbellSeconds = ValueNotifier<int>(30);

  GlanceSubscription? _doorbellSub;
  Timer? _doorbellRetry;
  Timer? _doorbellHide;
  String? _doorbellLast;

  Future<void> setDoorbell({String? trigger, String? camera, int? seconds}) async {
    final prefs = await _prefs();
    if (trigger != null) {
      doorbellTrigger.value = trigger.trim();
      await prefs.setString(_doorbellTriggerKey, doorbellTrigger.value);
    }
    if (camera != null) {
      doorbellCamera.value = camera.trim();
      await prefs.setString(_doorbellCameraKey, doorbellCamera.value);
    }
    if (seconds != null) {
      doorbellSeconds.value = seconds.clamp(10, 300);
      await prefs.setInt(_doorbellSecondsKey, doorbellSeconds.value);
    }
    unawaited(_watchDoorbell());
  }

  /// Follows the doorbell entity over Home Assistant's websocket, and
  /// reconnects a minute after the connection drops.
  Future<void> _watchDoorbell() async {
    _doorbellRetry?.cancel();
    final old = _doorbellSub;
    _doorbellSub = null;
    await old?.close();
    _doorbellLast = null;
    final trigger = doorbellTrigger.value;
    if (trigger.isEmpty || !_homeAssistant.configured) return;
    final sub = await _homeAssistant.subscribeEntities([trigger], (id, state) {
      final value = '${state['state'] ?? ''}';
      final seen = _doorbellLast;
      _doorbellLast = value;
      // The first report is how things stand, not a ring.
      if (seen == null || value == seen) return;
      if (isDoorbellRing(trigger, value)) unawaited(ringDoorbell());
    });
    if (sub == null) {
      _doorbellRetry = Timer(const Duration(minutes: 1), () => unawaited(_watchDoorbell()));
      return;
    }
    _doorbellSub = sub;
    sub.onClosed = () {
      if (identical(_doorbellSub, sub)) {
        _doorbellRetry = Timer(const Duration(seconds: 30), () => unawaited(_watchDoorbell()));
      }
    };
  }

  /// Someone rang: wake the screen and show the doorbell camera live, full
  /// screen, then close it after [doorbellSeconds].
  Future<CommandResult> ringDoorbell() async {
    final entity = doorbellCamera.value.isNotEmpty ? doorbellCamera.value : cameraEntities.value.firstOrNull;
    if (entity == null || entity.isEmpty) return const CommandResult.fail('no doorbell camera chosen');
    final viewId = await _liveViewFor(entity);
    if (viewId == null) return const CommandResult.fail('could not set up the camera');
    await commands.execute('screenOn', const {});
    await commands.execute('bringToFront', const {});
    final shown = await commands.execute('showCameraView', {'viewId': viewId});
    if (!shown.ok) return shown;
    _doorbellHide?.cancel();
    _doorbellHide = Timer(Duration(seconds: doorbellSeconds.value), () {
      unawaited(commands.execute('hideCameraView', const {}));
    });
    return const CommandResult.ok();
  }

  /// A one-camera view of [entity] in the app's camera setup (importing the
  /// Home Assistant cameras first when needed): its id.
  Future<String?> _liveViewFor(String entity) async {
    Future<Map?> config() async {
      final r = await commands.execute('cameraGetConfig', const {});
      return r.ok && r.data is Map ? r.data as Map : null;
    }

    String? sourceId(Map? cfg) {
      for (final cam in (cfg?['cameras'] as List?) ?? const []) {
        if (cam is Map && cam['kind'] == 'ha' && cam['entityId'] == entity) return '${cam['id']}';
      }
      return null;
    }

    var cfg = await config();
    var source = sourceId(cfg);
    if (source == null) {
      await commands.execute('cameraImportHomeAssistant', const {});
      cfg = await config();
      source = sourceId(cfg);
    }
    if (source == null) return null;
    for (final v in (cfg?['views'] as List?) ?? const []) {
      if (v is Map && v['cameraIds'] is List && (v['cameraIds'] as List).length == 1 && (v['cameraIds'] as List).first == source) {
        return '${v['id']}';
      }
    }
    final made = await commands.execute('cameraPutView', {
      'id': '',
      'name': '${entity.split('.').last.replaceAll('_', ' ')} (live)',
      'cameraIds': [source],
      'showCameraNames': false,
    });
    return made.ok && made.data is Map ? '${(made.data as Map)['id']}' : null;
  }

  Future<void> setCameraEntity(String entity) =>
      setCameraEntities(entity.split(RegExp(r'[,\s]+')));

  /// Home Assistant's address and token, for camera snapshots.
  ({String base, String token}) get homeAssistantAuth =>
      (base: _homeAssistant.baseUrl, token: _settings.get(defs.haToken));

  /// Loads the wallpaper when it is due for a change (every three hours, or
  /// when the source changes). A failed download keeps the current one.
  Future<void> refreshBackdrop({bool force = false}) async {
    final now = DateTime.now();
    final slot = '${wallpaper.value}|${wallpaperUrl.value}|${now.year}-${now.month}-${now.day}-${now.hour ~/ 3}';
    if (!force && slot == _backdropKey && backdrop.value != null) return;
    try {
      final bytes = switch (wallpaper.value) {
        'theme' => null,
        'builtin' => await _builtin(_photoWallpapers[(now.day * 8 + now.hour ~/ 3) % _photoWallpapers.length].$1),
        final w when w.startsWith('builtin:') => await _builtin(w.substring(8)),
        'url' when wallpaperUrl.value.startsWith('/th?') => await _bingOne(wallpaperUrl.value),
        'url' => await _download(Uri.parse(wallpaperUrl.value)),
        'photos' => await _fromPhotos(now),
        _ => await _fromBing(now),
      };
      if (bytes != null) {
        backdrop.value = bytes;
        _backdropKey = slot;
      }
    } catch (e) {
      log.warn(name, 'wallpaper: $e');
      if (backdrop.value == null) {
        // Offline at boot: the last wallpaper that loaded, else a built-in.
        final file = await _cacheFile('last');
        if (file != null && file.existsSync()) {
          backdrop.value = await file.readAsBytes();
        } else {
          try {
            backdrop.value = await _builtin(builtinWallpapers.firstWhere((w) => w.$3.isEmpty).$1);
          } catch (_) {}
        }
      }
    }
  }

  /// A built-in 4K landscape for the Scenic photo frame: downloaded once,
  /// then from the cache; null when it cannot be had (offline, first time).
  Future<Uint8List?> scenicPhoto(String id) async {
    try {
      return await _builtin(id);
    } catch (e) {
      log.warn(name, 'scenic photo $id: $e');
      return null;
    }
  }

  Future<Uint8List> _builtin(String id) async {
    final photo = builtinWallpapers.any((w) => w.$1 == id && w.$3.isNotEmpty);
    if (!photo) {
      final data = await rootBundle.load(builtinWallpaperAsset(id));
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    final file = await _cacheFile('photo_$id');
    if (file != null && file.existsSync()) return file.readAsBytes();
    Object? failure;
    for (final url in builtinWallpaperUrls(id)) {
      try {
        final bytes = await _download(url);
        await file?.writeAsBytes(bytes, flush: true);
        return bytes;
      } catch (e) {
        failure = e;
      }
    }
    throw failure ?? 'could not download $id';
  }

  /// Bing's recent 4K photos, for the wallpaper picker: (id, thumbnail URL).
  Future<List<(String, String)>> bingGallery() async {
    final res = await _client
        .get(Uri.https('www.bing.com', '/HPImageArchive.aspx', {'format': 'js', 'idx': '0', 'n': '8', 'mkt': 'en-US'}))
        .timeout(const Duration(seconds: 15));
    final res2 = await _client
        .get(Uri.https('www.bing.com', '/HPImageArchive.aspx', {'format': 'js', 'idx': '7', 'n': '8', 'mkt': 'en-US'}))
        .timeout(const Duration(seconds: 15));
    final out = <(String, String)>[];
    for (final r in [res, res2]) {
      if (r.statusCode != 200) continue;
      final images = (jsonDecode(r.body) as Map)['images'];
      if (images is! List) continue;
      for (final i in images) {
        final base = i is Map ? '${i['urlbase'] ?? ''}' : '';
        if (base.isEmpty || out.any((o) => o.$1 == base)) continue;
        out.add((base, 'https://www.bing.com${base}_480x270.jpg'));
      }
    }
    if (out.isEmpty) throw 'Bing sent no photos';
    return out;
  }

  Future<Uint8List> _download(Uri url) async {
    final res = await _client.get(url).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200 || res.bodyBytes.length < 10000) throw 'HTTP ${res.statusCode} from ${url.host}';
    unawaited(_cacheFile('last').then((f) => f?.writeAsBytes(res.bodyBytes, flush: true)));
    return res.bodyBytes;
  }

  /// Bing's last eight photos of the day in 4K (3840×2160), one every three
  /// hours. Each is downloaded once and kept on disk.
  Future<Uint8List> _fromBing(DateTime now) async {
    final day = '${now.year}-${now.month}-${now.day}';
    if (_bingListDay != day || _bingList.isEmpty) {
      final res = await _client
          .get(Uri.https('www.bing.com', '/HPImageArchive.aspx', {'format': 'js', 'idx': '0', 'n': '8', 'mkt': 'en-US'}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw 'Bing HTTP ${res.statusCode}';
      final images = (jsonDecode(res.body) as Map)['images'];
      if (images is! List || images.isEmpty) throw 'Bing sent no photos';
      _bingList = [
        for (final i in images)
          if (i is Map && '${i['urlbase'] ?? ''}'.isNotEmpty) '${i['urlbase']}',
      ];
      _bingListDay = day;
    }
    final base = _bingList[(now.hour ~/ 3) % _bingList.length];
    final id = RegExp(r'id=([^&]+)').firstMatch(base)?.group(1) ?? base.hashCode.toString();
    final file = await _cacheFile('bing_${id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')}');
    if (file != null && file.existsSync()) return file.readAsBytes();
    Uint8List bytes;
    try {
      bytes = await _download(Uri.parse('https://www.bing.com${base}_UHD.jpg'));
    } catch (_) {
      bytes = await _download(Uri.parse('https://www.bing.com${base}_1920x1080.jpg'));
    }
    await file?.writeAsBytes(bytes, flush: true);
    await _pruneCache();
    return bytes;
  }

  Future<Uint8List> _bingOne(String base) async {
    final id = RegExp(r'id=([^&]+)').firstMatch(base)?.group(1) ?? base.hashCode.toString();
    final file = await _cacheFile('bing_${id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')}');
    if (file != null && file.existsSync()) return file.readAsBytes();
    final bytes = await _download(Uri.parse('https://www.bing.com${base}_UHD.jpg'));
    await file?.writeAsBytes(bytes, flush: true);
    return bytes;
  }

  Future<Uint8List?> _fromPhotos(DateTime now) async {
    if (!photos.configured) throw 'photos are not set up';
    final list = await photos.photos();
    if (list.isEmpty) throw 'no photos found';
    return photos.bytes(list[(now.day * 8 + now.hour ~/ 3) % list.length]);
  }

  Future<File?> _cacheFile(String name) async {
    try {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/wallpapers');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File('${dir.path}/$name.jpg');
    } catch (_) {
      return null;
    }
  }

  /// Keeps the ten newest Bing photos (about 30 MB).
  Future<void> _pruneCache() async {
    try {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/wallpapers');
      final files = dir.listSync().whereType<File>().where((f) => f.path.contains('/bing_')).toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final f in files.skip(10)) {
        f.deleteSync();
      }
    } catch (_) {}
  }

  /// The animated weather in the background (weather_backdrop.dart).
  final weatherEffects = ValueNotifier<bool>(true);

  Future<void> setWeatherEffects(bool on) async {
    weatherEffects.value = on;
    await (await _prefs()).setBool(_weatherFxKey, on);
  }

  /// Rearranging tiles: sizes, order, hiding.
  final editing = ValueNotifier<bool>(false);

  Future<void> setTiles(List<HomeTileSpec> next) async {
    tiles.value = next;
    await (await _prefs()).setString(_tilesKey, jsonEncode([for (final t in next) t.toJson()]));
  }

  /// The family's own tiles.
  final customTiles = ValueNotifier<List<CustomTile>>(const []);

  static const _customTilesKey = 'phx.home.custom_tiles';

  Future<void> _saveCustom(List<CustomTile> next) async {
    customTiles.value = next;
    await (await _prefs()).setString(_customTilesKey, jsonEncode([for (final c in next) c.toJson()]));
  }

  /// Adds a tile (at the end of the first home screen it fits) and
  /// answers it; [kind], [title] and [target] as in [CustomTile].
  Future<CustomTile?> addCustomTile(String kind, String title, String target) async {
    var n = 1;
    while (customTiles.value.any((c) => c.id == 'c_$n')) {
      n++;
    }
    final tile = CustomTile.fromJson({'id': 'c_$n', 'kind': kind, 'title': title, 'target': target});
    if (tile == null) return null;
    await _saveCustom([...customTiles.value, tile]);
    await setTiles([...tiles.value, tile.spec]);
    return tile;
  }

  /// Changes a tile's title or target.
  Future<void> updateCustomTile(String id, {String? title, String? target}) async {
    final next = [
      for (final c in customTiles.value)
        if (c.id == id)
          CustomTile.fromJson({...c.toJson(), 'title': ?title, 'target': ?target}) ?? c
        else
          c,
    ];
    await _saveCustom(next);
  }

  /// Deletes a tile for good (hiding keeps it for later).
  Future<void> removeCustomTile(String id) async {
    await _saveCustom([for (final c in customTiles.value) if (c.id != id) c]);
    await setTiles([for (final t in tiles.value) if (t.id != id) t]);
    if (hiddenTiles.value.contains(id)) await setTileHidden(id, false);
  }

  CustomTile? customTile(String id) {
    for (final c in customTiles.value) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> setTileHidden(String id, bool hide) async {
    final next = {...hiddenTiles.value};
    hide ? next.add(id) : next.remove(id);
    hiddenTiles.value = next;
    await (await _prefs()).setStringList(_hiddenTilesKey, next.toList());
  }

  Future<void> setTheme(String id) async {
    theme.value = id;
    await (await _prefs()).setString(_themeKey, id);
  }

  Future<void> resetTiles() async {
    // The family's own tiles stay, at the end.
    await setTiles([...defaultHomeTiles, for (final c in customTiles.value) c.spec]);
    hiddenTiles.value = const {};
    await (await _prefs()).remove(_hiddenTilesKey);
  }

  /// Smart Home entities pinned to the page's top, by entity id.
  final pinnedEntities = ValueNotifier<List<String>>(const []);

  /// The last entity list, null before the first load or without HA.
  final entities = ValueNotifier<List<HomeEntity>?>(null);
  final entitiesLoading = ValueNotifier<bool>(false);
  final entitiesError = ValueNotifier<String?>(null);

  bool get homeAssistantConfigured => _homeAssistant.configured;

  static const _favoritesKey = 'phx.home.favorites';
  static const _hiddenKey = 'phx.home.hidden';
  static const _usageKey = 'phx.home.usage';
  static const _pinnedKey = 'phx.home.pinned_entities';
  static const _kidsAppsKey = 'phx.home.kids_apps';
  static const _kidsHiddenKey = 'phx.kids.hidden_games';
  static const _tilesKey = 'phx.home.tiles';
  static const _hiddenTilesKey = 'phx.home.hidden_tiles';
  static const _themeKey = 'phx.home.theme';
  static const _weatherFxKey = 'phx.home.weather_fx';
  static const _layoutKey = 'phx.home.layout';
  static const _cameraKey = 'phx.home.camera';
  static const _camerasKey = 'phx.home.cameras';
  static const _doorbellTriggerKey = 'phx.home.doorbell_trigger';
  static const _doorbellCameraKey = 'phx.home.doorbell_camera';
  static const _doorbellSecondsKey = 'phx.home.doorbell_seconds';
  static const _wallpaperKey = 'phx.home.wallpaper';
  static const _smartTargetKey = 'phx.home.smart_target';
  static const _glassKey = 'phx.home.glass';
  /// The clock's look on the Today screen and the photo frame (see
  /// clock_faces.dart): classic, bold, flip, analog or words.
  final clockFace = ValueNotifier<String>('classic');
  static const _clockFaceKey = 'phx.home.clock_face';
  static const clockFaceIds = ['classic', 'bold', 'flip', 'analog', 'words'];

  Future<void> setClockFace(String id) async {
    if (!clockFaceIds.contains(id)) return;
    clockFace.value = id;
    await (await _prefs()).setString(_clockFaceKey, id);
  }

  static const _teluguKey = 'phx.home.telugu';

  /// The Telugu calendar on Phoenix Home: the word of the day, festivals in
  /// Up next, the tithi line, the Telugu tile and the dock's Calendar
  /// button. Off on a new install; Portals that ran an earlier build (which
  /// always showed it) keep it on.
  final telugu = ValueNotifier<bool>(false);

  Future<void> setTelugu(bool on) async {
    telugu.value = on;
    await (await _prefs()).setBool(_teluguKey, on);
  }
  static const _wallpaperUrlKey = 'phx.home.wallpaper_url';
  static const _weatherRefresh = Duration(minutes: 30);

  StreamSubscription<SettingChanged>? _settingSub;
  StreamSubscription<AppLaunched>? _launchSub;
  Timer? _weatherTimer;

  /// The geocoded place for the configured city, cached for the session.
  ({String query, double lat, double lon, String place})? _geo;

  @override
  Future<void> init() async {
    await _load();
    await school.init();
    await photos.init();
    unawaited(_watchDoorbell());
    unawaited(school.refresh());
    _settingSub = bus.on<SettingChanged>().listen((e) {
      if (e.key == defs.homeWeatherCity.key ||
          e.key == defs.homeTemperatureUnit.key) {
        unawaited(refreshWeather());
      }
      if (e.key == defs.homeScreen.key || e.key == defs.navStyle.key) {
        active.value = enabled;
        if (!enabled) goHome();
      }
    });
    // Phoenix Home leaves the screen to the app the user opened.
    _launchSub = bus.on<AppLaunched>().listen((e) {
      appsOpen.value = false;
      unawaited(_recordLaunch(e.package));
    });
    unawaited(refreshWeather());
    unawaited(refreshBackdrop());
    _weatherTimer = Timer.periodic(_weatherRefresh, (_) {
      unawaited(refreshWeather());
      unawaited(refreshBackdrop());
      unawaited(school.refresh());
    });
    unawaited(_launcher.refreshInstalled());
    commands
      ..register(
        Command(
          name: 'phoenixDoorbell',
          description:
              'Someone rang: wake the screen and show the doorbell camera live '
              'for a while (Phoenix Home > Doorbell). For a Home Assistant '
              'automation when the doorbell has no entity to watch.',
          handler: (_) => ringDoorbell(),
        ),
      )
      ..register(
        Command(
          name: 'openHome',
          description:
              'Show Phoenix Home: closes the dashboard, the Smart Home page '
              'and the app drawer.',
          handler: (_) async {
            goHome();
            return const CommandResult.ok();
          },
        ),
      )
      ..register(
        Command(
          name: 'openDashboard',
          description:
              'Open the Home Assistant dashboard over Phoenix Home. Fails '
              'without a configured dashboard.',
          handler: (_) async {
            if (_settings.get(defs.startUrl).isEmpty) {
              return const CommandResult.fail('no dashboard configured');
            }
            openDashboard();
            return const CommandResult.ok();
          },
        ),
      )
      ..register(
        Command(
          name: 'openSmartHome',
          description: 'Open the Smart Home page of Phoenix Home.',
          handler: (_) async {
            openSmartHome();
            return const CommandResult.ok();
          },
        ),
      )
      ..register(
        Command(
          name: 'openSchool',
          description:
              'Open the School page of Phoenix Home: menus, calendar, bell '
              'times.',
          handler: (_) async {
            openSchool();
            return const CommandResult.ok();
          },
        ),
      )
      ..register(
        Command(
          name: 'phoenixHomeGet',
          description:
              'Phoenix Home as the remote admin edits it: tiles, theme, '
              'weather effects, dock, hidden and Kids Portal apps, every '
              'installed app, the school and the photos.',
          handler: (_) async => CommandResult.ok(remoteState()),
        ),
      )
      ..register(
        Command(
          name: 'phoenixHomeSet',
          description:
              'Change Phoenix Home: any of tiles [{id, w, h}], hiddenTiles, '
              'theme, weatherEffects, favorites, hiddenApps, kidsApps, '
              'school {district, school, schoolName, menus, calendar, start, '
              'end} and photos {source, folder, seconds}.',
          handler: (p) async {
            await applyRemote(p);
            return CommandResult.ok(remoteState());
          },
        ),
      )
      ..register(
        Command(
          name: 'phoenixSchoolList',
          description: "A district's schools and their menus, from SchoolCafe or Nutrislice.",
          params: const {'district': 'the district, e.g. exampleisd', 'provider': 'schoolcafe or nutrislice'},
          handler: (p) async {
            final district = '${p['district'] ?? school.config.value.district}'.trim().toLowerCase();
            try {
              final provider = p['provider'] is String ? p['provider'] as String : null;
              final list = await school.schools(district, provider: provider);
              return CommandResult.ok([
                for (final s in list)
                  {
                    'slug': s.slug,
                    'name': s.name,
                    'menus': [for (final (slug, name) in s.menuTypes) {'slug': slug, 'name': name}],
                  },
              ]);
            } catch (e) {
              return CommandResult.fail("couldn't load $district's schools: $e");
            }
          },
        ),
      )
      ..register(
        Command(
          name: 'openAllApps',
          description: 'Open the full app drawer of Phoenix Home.',
          handler: (_) async {
            appsOpen.value = true;
            return const CommandResult.ok();
          },
        ),
      );
  }

  // ── Remote admin ────────────────────────────────────────────────────────

  static const themeIds = ['auto', 'ember', 'ocean', 'forest', 'midnight', 'sunset', 'graphite'];

  /// Everything the remote admin's Phoenix Home page shows.
  Map<String, Object?> remoteState() => {
    'tiles': [
      for (final t in tiles.value) {'id': t.id, 'w': t.w, 'h': t.h, 'p': t.page, 'hidden': hiddenTiles.value.contains(t.id)},
    ],
    'customTiles': [for (final c in customTiles.value) c.toJson()],
    'theme': theme.value,
    'themes': themeIds,
    'weatherEffects': weatherEffects.value,
    'layout': layout.value,
    'camera': cameraEntity.value,
    'cameras': cameraEntities.value,
    'doorbell': {'trigger': doorbellTrigger.value, 'camera': doorbellCamera.value, 'seconds': doorbellSeconds.value},
    'menuItems': _settings.get(defs.uiDrawerItems),
    'wallpaper': wallpaper.value,
    'smartHome': smartHomeTarget.value,
    'glass': glassOpacity.value,
    'telugu': telugu.value,
    'clockFace': clockFace.value,
    'wallpapers': [for (final (id, name, credit) in builtinWallpapers) {'id': 'builtin:$id', 'name': name, 'credit': credit}],
    'smartHomePage': smartHomePage,
    'wallpaperUrl': wallpaperUrl.value,
    'favorites': favorites.value,
    'hiddenApps': hidden.value.toList(),
    'kidsApps': kidsApps.value,
    'kids': {
      'enabled': _settings.get(defs.kidsEnabled),
      'name': _settings.get(defs.kidsName),
      'minutes': _settings.get(defs.kidsDailyMinutes),
      'bedtime': _settings.get(defs.kidsBedtime),
      'wake': _settings.get(defs.kidsWakeTime),
      'hasPin': _settings.get(defs.kidsPin).isNotEmpty,
      'profile': _settings.get(defs.phoenixProfile),
      'hiddenGames': kidsHiddenGames.value,
      'homework': homework.toJson(),
      'tracking': kidsTracking.value,
    },
    'apps': [for (final a in _launcher.installed) {'package': a.package, 'label': a.label}],
    'school': school.config.value.toJson(),
    'photos': {...photos.settings.value.toJson(), 'immichConfigured': _immich.configured},
  };

  List<String> _strings(Object? v) => [
    if (v is List)
      for (final s in v)
        if ('$s'.trim().isNotEmpty) '$s'.trim(),
  ];

  /// Apply what the remote admin sent; unknown or malformed parts are
  /// skipped.
  Future<void> applyRemote(Map<String, Object?> p) async {
    final prefs = await _prefs();
    // The family's own tiles: added (no id), changed or deleted (left out).
    if (p['customTiles'] is List) {
      final sent = p['customTiles'] as List;
      final keep = <String>{};
      for (final raw in sent) {
        if (raw is! Map) continue;
        final id = '${raw['id'] ?? ''}';
        if (customTile(id) != null) {
          keep.add(id);
          await updateCustomTile(id, title: '${raw['title'] ?? ''}', target: '${raw['target'] ?? ''}');
        } else {
          final made = await addCustomTile('${raw['kind'] ?? ''}', '${raw['title'] ?? ''}', '${raw['target'] ?? ''}');
          if (made != null) keep.add(made.id);
        }
      }
      for (final c in [...customTiles.value]) {
        if (!keep.contains(c.id)) await removeCustomTile(c.id);
      }
    }
    if (p['tiles'] is List) {
      final known = {for (final t in defaultHomeTiles) t.id, for (final c in customTiles.value) c.id};
      final next = <HomeTileSpec>[
        for (final t in p['tiles'] as List)
          if (t is Map && known.contains(t['id']))
            HomeTileSpec('${t['id']}', 1, 1)
                .sized(
                  t['w'] is num ? (t['w'] as num).toInt() : 1,
                  t['h'] is num ? (t['h'] as num).toInt() : 1,
                )
                .onPage(t['p'] is num ? (t['p'] as num).toInt() : 0),
      ];
      // Tiles the admin left out keep their place at the end.
      for (final t in tiles.value) {
        if (!next.any((n) => n.id == t.id)) next.add(t);
      }
      await setTiles(next);
    }
    if (p['hiddenTiles'] is List) {
      hiddenTiles.value = _strings(p['hiddenTiles']).toSet();
      await prefs.setStringList(_hiddenTilesKey, hiddenTiles.value.toList());
    }
    if (p['theme'] is String && themeIds.contains(p['theme'])) await setTheme(p['theme'] as String);
    if (p['weatherEffects'] is bool) await setWeatherEffects(p['weatherEffects'] as bool);
    if (p['layout'] is String) await setLayout(p['layout'] as String);
    if (p['doorbell'] is Map) {
      final d = (p['doorbell'] as Map).cast<String, Object?>();
      await setDoorbell(
        trigger: d['trigger'] is String ? d['trigger'] as String : null,
        camera: d['camera'] is String ? d['camera'] as String : null,
        seconds: d['seconds'] is num ? (d['seconds'] as num).toInt() : null,
      );
    }
    if (p['cameras'] is List) {
      await setCameraEntities([for (final e in p['cameras'] as List) '$e']);
    } else if (p['camera'] is String) {
      await setCameraEntity(p['camera'] as String);
    }
    if (p['glass'] is num) await setGlassOpacity((p['glass'] as num).toDouble());
    if (p['telugu'] is bool) await setTelugu(p['telugu'] as bool);
    if (p['clockFace'] is String) await setClockFace(p['clockFace'] as String);
    if (p['smartHome'] is String || p['smartHomePage'] is String) {
      await setSmartHomeTarget(
        p['smartHome'] is String ? p['smartHome'] as String : smartHomeTarget.value,
        page: p['smartHomePage'] is String ? p['smartHomePage'] as String : null,
      );
    }
    if (p['wallpaper'] is String || p['wallpaperUrl'] is String) {
      await setWallpaper(
        p['wallpaper'] is String ? p['wallpaper'] as String : wallpaper.value,
        url: p['wallpaperUrl'] is String ? p['wallpaperUrl'] as String : null,
      );
    }
    if (p['favorites'] is List) {
      favorites.value = _strings(p['favorites']);
      await prefs.setStringList(_favoritesKey, favorites.value);
    }
    if (p['hiddenApps'] is List) {
      hidden.value = _strings(p['hiddenApps']).toSet();
      await prefs.setStringList(_hiddenKey, hidden.value.toList());
    }
    if (p['kids'] is Map) {
      final k = (p['kids'] as Map).cast<String, Object?>();
      if (k['enabled'] is bool) await _settings.set(defs.kidsEnabled, k['enabled'] as bool);
      if (k['name'] is String) await _settings.set(defs.kidsName, (k['name'] as String).trim());
      if (k['minutes'] is String) await _settings.set(defs.kidsDailyMinutes, k['minutes'] as String);
      if (k['bedtime'] is String) await _settings.set(defs.kidsBedtime, k['bedtime'] as String);
      if (k['wake'] is String) await _settings.set(defs.kidsWakeTime, k['wake'] as String);
      if (k['pin'] is String) await _settings.set(defs.kidsPin, (k['pin'] as String).trim());
      if (k['hiddenGames'] is List) await setKidsHiddenGames([for (final g in k['hiddenGames'] as List) '$g']);
      if (k['resetScores'] == true) await resetKidsScores();
      if (k['tracking'] is String) await setKidsTracking(k['tracking'] as String);
      if (k['homework'] is Map) {
        final h = (k['homework'] as Map).cast<String, Object?>();
        if (h['words'] is String) await homework.setWords(HomeworkStore.parseWords(h['words'] as String));
        if (h['words'] is List) await homework.setWords(HomeworkStore.parseWords((h['words'] as List).join(' ')));
        if (h['tables'] is List) {
          await homework.setTables([for (final t in h['tables'] as List) if (t is num) t.toInt() else ?int.tryParse('$t')]);
        }
      }
    }
    if (p['kidsApps'] is List) {
      kidsApps.value = _strings(p['kidsApps']);
    kidsHiddenGames.value = prefs.getStringList(_kidsHiddenKey) ?? const [];
    await homework.load();
    kidsTracking.value = prefs.getString(_kidsTrackingKey) == 'hands' ? 'hands' : 'body';
      await prefs.setStringList(_kidsAppsKey, kidsApps.value);
    }
    if (p['school'] is Map) {
      final merged = {...school.config.value.toJson(), ...(p['school'] as Map).cast<String, Object?>()};
      await school.save(SchoolConfig.fromJson(merged));
    }
    if (p['photos'] is Map) {
      final merged = {...photos.settings.value.toJson(), ...(p['photos'] as Map).cast<String, Object?>()};
      await photos.save(PhotoSettings.fromJson(merged));
    }
  }

  void goHome() {
    dashboardOpen.value = false;
    smartHomeOpen.value = false;
    appsOpen.value = false;
    schoolOpen.value = false;
    teluguOpen.value = false;
    shoppingOpen.value = false;
  }

  void openShopping() {
    goHome();
    shoppingOpen.value = true;
    unawaited(todo.refresh());
  }

  void openTelugu() {
    goHome();
    teluguOpen.value = true;
  }

  void openSchool() {
    appsOpen.value = false;
    smartHomeOpen.value = false;
    schoolOpen.value = true;
    unawaited(school.refresh());
  }

  void openDashboard() {
    schoolOpen.value = false;
    smartHomeOpen.value = false;
    appsOpen.value = false;
    dashboardOpen.value = true;
  }

  /// What the Smart Home button opens: 'ha' (your Home Assistant
  /// dashboard, the default) or 'phoenix' (Phoenix's own lights and scenes).
  final smartHomeTarget = ValueNotifier<String>('ha');

  /// The Home Assistant page the Smart Home button opens (the browser's
  /// start page: a dashboard such as /lovelace/home, or your own HTML page).
  String get smartHomePage => _settings.get(defs.startUrl);

  Future<void> setSmartHomeTarget(String target, {String? page}) async {
    smartHomeTarget.value = target == 'phoenix' ? 'phoenix' : 'ha';
    await (await _prefs()).setString(_smartTargetKey, smartHomeTarget.value);
    if (page != null && page.trim().isNotEmpty && page.trim() != smartHomePage) {
      await _settings.set(defs.startUrl, page.trim());
    }
  }

  /// The Smart Home button: Home Assistant's dashboard, or Phoenix's own
  /// page when that is chosen or Home Assistant is not set up yet.
  void openSmartHomeButton() {
    if (smartHomeTarget.value == 'ha' && smartHomePage.trim().isNotEmpty) {
      openDashboard();
    } else {
      openSmartHome();
    }
  }

  void openSmartHome() {
    appsOpen.value = false;
    schoolOpen.value = false;
    smartHomeOpen.value = true;
    if (_homeAssistant.configured) unawaited(loadEntities());
  }

  // ── Apps ────────────────────────────────────────────────────────────────

  /// Every launchable app but Phoenix itself and the hidden ones,
  /// alphabetical.
  List<LauncherApp> get apps => [
    for (final app in _launcher.installed)
      if (!hidden.value.contains(app.package)) app,
  ];

  /// The dock: the pinned apps that are still installed, in order. With
  /// nothing pinned yet, the most used apps stand in.
  List<LauncherApp> get dock {
    final byPackage = {for (final a in _launcher.installed) a.package: a};
    final pinned = [
      for (final p in favorites.value) ?byPackage[p],
    ];
    if (pinned.isNotEmpty) return pinned;
    return mostUsed(6);
  }

  /// The most launched apps, most first.
  List<LauncherApp> mostUsed(int count) {
    final list = [
      for (final a in apps)
        if ((usage.value[a.package]?.count ?? 0) > 0) a,
    ]..sort((a, b) => usage.value[b.package]!.count.compareTo(
        usage.value[a.package]!.count,
      ));
    return list.take(count).toList();
  }

  /// The most recently launched apps, latest first.
  List<LauncherApp> recent(int count) {
    final list = [
      for (final a in apps)
        if (usage.value.containsKey(a.package)) a,
    ]..sort((a, b) => usage.value[b.package]!.last.compareTo(
        usage.value[a.package]!.last,
      ));
    return list.take(count).toList();
  }

  bool isFavorite(String package) => favorites.value.contains(package);

  bool isKidsApp(String package) => kidsApps.value.contains(package);

  Future<void> toggleKidsApp(String package) async {
    final next = [...kidsApps.value];
    if (!next.remove(package)) next.add(package);
    kidsApps.value = next;
    await (await _prefs()).setStringList(_kidsAppsKey, next);
  }

  /// The Kids Portal's apps that are still installed, in the order added.
  List<LauncherApp> get kidsAppList {
    final byPackage = {for (final a in _launcher.installed) a.package: a};
    return [for (final p in kidsApps.value) ?byPackage[p]];
  }

  Future<void> toggleFavorite(String package) async {
    final next = [...favorites.value];
    if (!next.remove(package)) next.add(package);
    favorites.value = next;
    await (await _prefs()).setStringList(_favoritesKey, next);
  }

  Future<void> moveFavorite(String package, int delta) async {
    final next = [...favorites.value];
    final i = next.indexOf(package);
    if (i < 0) return;
    final j = (i + delta).clamp(0, next.length - 1);
    next
      ..removeAt(i)
      ..insert(j, package);
    favorites.value = next;
    await (await _prefs()).setStringList(_favoritesKey, next);
  }

  Future<void> setHidden(String package, bool hide) async {
    final next = {...hidden.value};
    hide ? next.add(package) : next.remove(package);
    hidden.value = next;
    if (hide && isFavorite(package)) await toggleFavorite(package);
    await (await _prefs()).setStringList(_hiddenKey, next.toList());
  }

  Future<void> unhideAll() async {
    hidden.value = const {};
    await (await _prefs()).remove(_hiddenKey);
  }

  /// Open [package]. False when Android could not open it. The launch is
  /// counted for the most used and recent rows through [AppLaunched].
  Future<bool> launch(String package) async {
    final result = await commands.execute('launchApp', {'package': package});
    return result.ok;
  }

  /// Count a launch, whoever made it (this home, the drawer, a gesture).
  Future<void> _recordLaunch(String package) async {
    if (!package.contains('.')) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = {...usage.value};
    next[package] = (count: (next[package]?.count ?? 0) + 1, last: now);
    usage.value = next;
    await (await _prefs()).setString(
      _usageKey,
      jsonEncode({
        for (final e in next.entries)
          e.key: {'c': e.value.count, 'l': e.value.last},
      }),
    );
  }

  /// Open Android's own page for [package] (uninstall, permissions,
  /// storage).
  Future<void> openAppInfo(String package) async {
    try {
      await _channel.invokeMethod<bool>('openAppInfo', {'package': package});
    } on MissingPluginException {
      // Not Android.
    } on PlatformException catch (e) {
      log.warn(name, 'app info for $package failed: $e');
    }
  }

  static const _channel = MethodChannel('kiosk_satellite/background');

  // ── Weather ─────────────────────────────────────────────────────────────

  bool get fahrenheit =>
      _settings.get(defs.homeTemperatureUnit) != 'celsius';

  Future<void> refreshWeather() async {
    try {
      final where = await _where();
      if (where == null) {
        weather.value = null;
        weatherProblem.value = 'Set your city in Settings > Home Screen';
        return;
      }
      final unit = fahrenheit ? 'fahrenheit' : 'celsius';
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': '${where.lat}',
        'longitude': '${where.lon}',
        'current': 'temperature_2m,weather_code,is_day',
        'daily': 'weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset',
        'temperature_unit': unit,
        'timezone': 'auto',
        'forecast_days': '5',
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
      weather.value = parseOpenMeteo(
        jsonDecode(res.body),
        place: where.place,
        fahrenheit: fahrenheit,
      );
      weatherProblem.value = weather.value == null ? 'No weather data' : null;
    } catch (e) {
      log.warn(name, 'weather unavailable: $e');
      // Keep the last good reading on a passing network error.
      if (weather.value == null) weatherProblem.value = 'Weather unavailable';
    }
  }

  /// The configured city, geocoded, or the tablet's own location.
  Future<({double lat, double lon, String place})?> _where() async {
    final city = _settings.get(defs.homeWeatherCity).trim();
    if (city.isNotEmpty) {
      if (_geo case final g? when g.query == city) {
        return (lat: g.lat, lon: g.lon, place: g.place);
      }
      // "Austin, US" searches for Austin; the part after the comma picks
      // between the matches by country code or region name.
      final parts = city.split(',').map((p) => p.trim()).toList();
      final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': parts.first,
        'count': '10',
        'language': 'en',
        'format': 'json',
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw 'geocoding HTTP ${res.statusCode}';
      final hit = pickGeocodeResult(
        jsonDecode(res.body),
        parts.length > 1 ? parts.sublist(1).join(',') : null,
      );
      if (hit == null) {
        weatherProblem.value = 'City "$city" not found';
        return null;
      }
      _geo = (query: city, lat: hit.lat, lon: hit.lon, place: hit.place);
      return (lat: hit.lat, lon: hit.lon, place: hit.place);
    }
    final fix = (await _location.currentFix(
      timeout: const Duration(seconds: 10),
    )).fix;
    if (fix == null) return null;
    return (lat: fix.latitude, lon: fix.longitude, place: '');
  }

  // ── Smart Home (Home Assistant add-on) ───────────────────────────────────

  Future<void> loadEntities() async {
    if (!_homeAssistant.configured) {
      entities.value = null;
      return;
    }
    entitiesLoading.value = true;
    try {
      final result = await commands.execute('haListEntities', {
        'domains': homeEntityDomains,
      });
      if (!result.ok || result.data is! List) {
        entitiesError.value = 'Home Assistant is not reachable right now.';
        return;
      }
      entities.value = [
        for (final e in result.data as List)
          if (e is Map && '${e['entity_id'] ?? ''}'.isNotEmpty)
            HomeEntity(
              id: '${e['entity_id']}',
              name: '${e['name'] ?? e['entity_id']}',
              state: '${e['state'] ?? ''}',
              domain: '${e['domain'] ?? '${e['entity_id']}'.split('.').first}',
              area: e['area'] as String?,
            ),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      entitiesError.value = null;
    } finally {
      entitiesLoading.value = false;
    }
  }

  /// Toggle [entity], or run it when it is a scene or script. The list
  /// refreshes shortly after so the tile shows the new state.
  Future<bool> activate(HomeEntity entity) async {
    final (domain, service) = switch (entity.domain) {
      'scene' => ('scene', 'turn_on'),
      'script' => ('script', 'turn_on'),
      'lock' => ('lock', entity.active ? 'lock' : 'unlock'),
      'cover' => ('cover', 'toggle'),
      'media_player' => ('media_player', 'media_play_pause'),
      'climate' => ('climate', entity.active ? 'turn_off' : 'turn_on'),
      _ => ('homeassistant', 'toggle'),
    };
    final result = await commands.execute('haCallService', {
      'domain': domain,
      'service': service,
      'entity_id': entity.id,
    });
    if (result.ok && !entity.runs) {
      // Show the change at once, then confirm it from Home Assistant.
      entities.value = [
        for (final e in entities.value ?? const <HomeEntity>[])
          e.id == entity.id
              ? HomeEntity(
                  id: e.id,
                  name: e.name,
                  state: e.active ? 'off' : 'on',
                  domain: e.domain,
                  area: e.area,
                )
              : e,
      ];
      Future<void>.delayed(
        const Duration(milliseconds: 1500),
        () => unawaited(loadEntities()),
      );
    }
    return result.ok;
  }

  bool isPinnedEntity(String id) => pinnedEntities.value.contains(id);

  Future<void> togglePinnedEntity(String id) async {
    final next = [...pinnedEntities.value];
    if (!next.remove(id)) next.add(id);
    pinnedEntities.value = next;
    await (await _prefs()).setStringList(_pinnedKey, next);
  }

  // ── Storage ─────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final prefs = await _prefs();
    favorites.value = prefs.getStringList(_favoritesKey) ?? const [];
    hidden.value = {...?prefs.getStringList(_hiddenKey)};
    pinnedEntities.value = prefs.getStringList(_pinnedKey) ?? const [];
    kidsApps.value = prefs.getStringList(_kidsAppsKey) ?? const [];
    customTiles.value = decodeCustomTiles(prefs.getString(_customTilesKey));
    tiles.value = decodeTileLayout(prefs.getString(_tilesKey), custom: customTiles.value);
    hiddenTiles.value = {...?prefs.getStringList(_hiddenTilesKey)};
    theme.value = prefs.getString(_themeKey) ?? 'ember';
    weatherEffects.value = prefs.getBool(_weatherFxKey) ?? true;
    layout.value = prefs.getString(_layoutKey) == 'tiles' ? 'tiles' : 'today';
    cameraEntity.value = prefs.getString(_cameraKey) ?? '';
    doorbellTrigger.value = prefs.getString(_doorbellTriggerKey) ?? '';
    doorbellCamera.value = prefs.getString(_doorbellCameraKey) ?? '';
    doorbellSeconds.value = (prefs.getInt(_doorbellSecondsKey) ?? 30).clamp(10, 300);
    cameraEntities.value = List.unmodifiable(
      prefs.getStringList(_camerasKey) ?? [if (cameraEntity.value.isNotEmpty) cameraEntity.value],
    );
    final savedWall = prefs.getString(_wallpaperKey) ?? '';
    wallpaper.value = _validWallpaper(savedWall) ? savedWall : 'builtin';
    glassOpacity.value = (prefs.getDouble(_glassKey) ?? 0.35).clamp(0.0, 1.0);
    smartHomeTarget.value = prefs.getString(_smartTargetKey) == 'phoenix' ? 'phoenix' : 'ha';
    wallpaperUrl.value = prefs.getString(_wallpaperUrlKey) ?? '';
    usage.value = decodeUsage(prefs.getString(_usageKey));
    final face = prefs.getString(_clockFaceKey);
    if (face != null && clockFaceIds.contains(face)) clockFace.value = face;
    final savedTelugu = prefs.getBool(_teluguKey);
    if (savedTelugu != null) {
      telugu.value = savedTelugu;
    } else {
      // Anything Phoenix saved before means an earlier build, which always
      // showed the Telugu calendar: keep it. A new install starts without.
      telugu.value = prefs.getKeys().any((k) => k.startsWith('phx.') && k != _teluguKey);
      await prefs.setBool(_teluguKey, telugu.value);
    }
  }

  @override
  Future<void> dispose() async {
    await _settingSub?.cancel();
    await _launchSub?.cancel();
    _weatherTimer?.cancel();
    _client.close();
    active.dispose();
    dashboardOpen.dispose();
    smartHomeOpen.dispose();
    appsOpen.dispose();
    schoolOpen.dispose();
    teluguOpen.dispose();
    telugu.dispose();
    clockFace.dispose();
    shoppingOpen.dispose();
    todo.dispose();
    school.dispose();
    photos.dispose();
    weather.dispose();
    weatherProblem.dispose();
    favorites.dispose();
    hidden.dispose();
    usage.dispose();
    pinnedEntities.dispose();
    kidsApps.dispose();
    tiles.dispose();
    customTiles.dispose();
    hiddenTiles.dispose();
    theme.dispose();
    weatherEffects.dispose();
    layout.dispose();
    cameraEntity.dispose();
    cameraEntities.dispose();
    _doorbellRetry?.cancel();
    _doorbellHide?.cancel();
    unawaited(_doorbellSub?.close());
    doorbellTrigger.dispose();
    doorbellCamera.dispose();
    doorbellSeconds.dispose();
    backdrop.dispose();
    wallpaper.dispose();
    smartHomeTarget.dispose();
    kidsHiddenGames.dispose();
    homework.dispose();
    kidsTracking.dispose();
    kidsScoresReset.dispose();
    glassOpacity.dispose();
    wallpaperUrl.dispose();
    weatherDemo.dispose();
    editing.dispose();
    entities.dispose();
    entitiesLoading.dispose();
    entitiesError.dispose();
  }
}

/// The stored usage map, dropping anything malformed.
Map<String, ({int count, int last})> decodeUsage(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    final data = jsonDecode(raw);
    if (data is! Map) return const {};
    return {
      for (final e in data.entries)
        if (e.value is Map &&
            (e.value as Map)['c'] is int &&
            (e.value as Map)['l'] is int)
          '${e.key}': (
            count: (e.value as Map)['c'] as int,
            last: (e.value as Map)['l'] as int,
          ),
    };
  } catch (_) {
    return const {};
  }
}

/// The best geocoding match: the first result, or the first whose country
/// code, country or region matches [hint] ("US", "Texas", "India").
({double lat, double lon, String place})? pickGeocodeResult(
  Object? data,
  String? hint,
) {
  if (data is! Map || data['results'] is! List) return null;
  final results = [
    for (final r in data['results'] as List)
      if (r is Map && r['latitude'] is num && r['longitude'] is num) r,
  ];
  if (results.isEmpty) return null;
  final h = hint?.trim().toLowerCase() ?? '';
  final match = h.isEmpty
      ? results.first
      : results.firstWhere(
          (r) => [
            r['country_code'],
            r['country'],
            r['admin1'],
          ].any((v) => '${v ?? ''}'.toLowerCase() == h),
          orElse: () => results.first,
        );
  return (
    lat: (match['latitude'] as num).toDouble(),
    lon: (match['longitude'] as num).toDouble(),
    place: '${match['name'] ?? ''}',
  );
}

/// Open-Meteo's forecast answer as [HomeWeather], null when it lacks the
/// current conditions.
HomeWeather? parseOpenMeteo(
  Object? data, {
  required String place,
  required bool fahrenheit,
}) {
  if (data is! Map || data['current'] is! Map) return null;
  final current = data['current'] as Map;
  final temp = current['temperature_2m'];
  if (temp is! num) return null;
  final days = <HomeWeatherDay>[];
  DateTime? sunrise, sunset;
  if (data['daily'] case final Map daily) {
    DateTime? first(Object? list) => list is List && list.isNotEmpty ? DateTime.tryParse('${list.first}') : null;
    sunrise = first(daily['sunrise']);
    sunset = first(daily['sunset']);
    final times = daily['time'];
    final codes = daily['weather_code'];
    final highs = daily['temperature_2m_max'];
    final lows = daily['temperature_2m_min'];
    if (times is List && codes is List && highs is List && lows is List) {
      for (var i = 0; i < times.length; i++) {
        final date = DateTime.tryParse('${times[i]}');
        if (date == null ||
            i >= codes.length ||
            i >= highs.length ||
            i >= lows.length ||
            highs[i] is! num ||
            lows[i] is! num) {
          continue;
        }
        days.add(
          HomeWeatherDay(
            date: date,
            code: codes[i] is num ? (codes[i] as num).toInt() : 0,
            high: (highs[i] as num).toDouble(),
            low: (lows[i] as num).toDouble(),
          ),
        );
      }
    }
  }
  return HomeWeather(
    place: place,
    temperature: temp.toDouble(),
    code: current['weather_code'] is num
        ? (current['weather_code'] as num).toInt()
        : 0,
    isDay: current['is_day'] != 0,
    days: days,
    fahrenheit: fahrenheit,
    sunrise: sunrise,
    sunset: sunset,
  );
}

/// Whether [state] of the doorbell entity [trigger] means a ring: a binary
/// sensor or input boolean turning on, an event or button entity firing (its
/// state is the time it fired), anything else changing to something real.
bool isDoorbellRing(String trigger, String state) {
  final domain = trigger.split('.').first;
  if (state == 'unavailable' || state == 'unknown' || state.isEmpty) return false;
  return switch (domain) {
    'binary_sensor' || 'input_boolean' || 'switch' => state == 'on',
    _ => true,
  };
}
