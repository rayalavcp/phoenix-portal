import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/command_registry.dart';
import '../../core/events.dart';
import '../../core/manager.dart';
import '../home_assistant/home_assistant_manager.dart';
import '../launcher/app_launcher_manager.dart';
import '../location/location_manager.dart';
import '../settings/definitions.dart' as defs;
import '../settings/settings_manager.dart';
import 'school_service.dart';

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
  });

  final String place;
  final double temperature;

  /// WMO weather code (Open-Meteo's `weather_code`).
  final int code;
  final bool isDay;
  final List<HomeWeatherDay> days;
  final bool fahrenheit;
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
    this._homeAssistant, {
    http.Client? client,
    Future<SharedPreferences> Function()? prefs,
  }) : _client = client ?? http.Client(),
       _prefs = prefs ?? SharedPreferences.getInstance;

  final SettingsManager _settings;
  final AppLauncherManager _launcher;
  final LocationManager _location;
  final HomeAssistantManager _homeAssistant;
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
      schoolOpen.value;

  /// The Home Assistant dashboard is on screen over Phoenix Home. The
  /// dashboard page is only loaded while this holds (dashboard_page.dart).
  final dashboardOpen = ValueNotifier<bool>(false);

  /// The Smart Home page is on screen.
  final smartHomeOpen = ValueNotifier<bool>(false);

  /// The full app drawer (every app, with search) is on screen.
  final appsOpen = ValueNotifier<bool>(false);

  /// The School page (menus, calendar, bell times) is on screen.
  final schoolOpen = ValueNotifier<bool>(false);

  /// School menus and calendar (Frisco ISD's Nutrislice by default).
  late final school = SchoolService(_client, _prefs, log);

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
    _weatherTimer = Timer.periodic(_weatherRefresh, (_) {
      unawaited(refreshWeather());
      unawaited(school.refresh());
    });
    unawaited(_launcher.refreshInstalled());
    commands
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
          name: 'openAllApps',
          description: 'Open the full app drawer of Phoenix Home.',
          handler: (_) async {
            appsOpen.value = true;
            return const CommandResult.ok();
          },
        ),
      );
  }

  void goHome() {
    dashboardOpen.value = false;
    smartHomeOpen.value = false;
    appsOpen.value = false;
    schoolOpen.value = false;
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
        'daily': 'weather_code,temperature_2m_max,temperature_2m_min',
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
    usage.value = decodeUsage(prefs.getString(_usageKey));
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
    school.dispose();
    weather.dispose();
    weatherProblem.dispose();
    favorites.dispose();
    hidden.dispose();
    usage.dispose();
    pinnedEntities.dispose();
    kidsApps.dispose();
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
  if (data['daily'] case final Map daily) {
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
  );
}
