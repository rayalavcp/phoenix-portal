import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging.dart';

/// Phoenix Home's School page: the school's breakfast and lunch menus and
/// its calendar. No Home Assistant: menus come straight from the district's
/// Nutrislice site (Frisco ISD by default), the calendar from any iCal feed
/// the district publishes, and the bell times are typed in once.

@immutable
class SchoolConfig {
  const SchoolConfig({
    this.provider = 'schoolcafe',
    this.servingLine = 'Main Line',
    this.grade = '02',
    this.district = 'friscoisd',
    this.schoolSlug = '',
    this.schoolName = 'Miller Elementary',
    this.menuTypes = const [('Breakfast', 'Breakfast'), ('Lunch', 'Lunch')],
    this.calendarUrl = '',
    this.startTime = '',
    this.endTime = '',
  });

  /// Where the menus come from: 'schoolcafe' (Frisco ISD and many Texas
  /// districts, schoolcafe.com) or 'nutrislice'.
  final String provider;

  /// SchoolCafe's serving line ("Main Line") and grade ("02"), which pick
  /// the menu a student sees.
  final String servingLine;
  final String grade;

  /// The district: SchoolCafe's short name (friscoisd) or the Nutrislice
  /// site (friscoisd.nutrislice.com → friscoisd).
  final String district;

  /// The school: SchoolCafe's school id (a GUID) or the Nutrislice slug.
  final String schoolSlug;
  final String schoolName;

  /// The menus to show, as (slug, name): lunch, breakfast.
  final List<(String, String)> menuTypes;

  /// The school calendar: an iCal (.ics) link, or a Home Assistant calendar
  /// entity (calendar.frisco_isd).
  final String calendarUrl;

  /// Bell times as H:MM in 24 hours ("7:50", "15:05"), empty when unset.
  final String startTime;
  final String endTime;

  bool get hasMenu =>
      district.isNotEmpty && schoolSlug.isNotEmpty && menuTypes.isNotEmpty;

  SchoolConfig copyWith({
    String? provider,
    String? servingLine,
    String? grade,
    String? district,
    String? schoolSlug,
    String? schoolName,
    List<(String, String)>? menuTypes,
    String? calendarUrl,
    String? startTime,
    String? endTime,
  }) => SchoolConfig(
    provider: provider ?? this.provider,
    servingLine: servingLine ?? this.servingLine,
    grade: grade ?? this.grade,
    district: district ?? this.district,
    schoolSlug: schoolSlug ?? this.schoolSlug,
    schoolName: schoolName ?? this.schoolName,
    menuTypes: menuTypes ?? this.menuTypes,
    calendarUrl: calendarUrl ?? this.calendarUrl,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
  );

  Map<String, Object?> toJson() => {
    'provider': provider,
    'servingLine': servingLine,
    'grade': grade,
    'district': district,
    'school': schoolSlug,
    'schoolName': schoolName,
    'menus': [
      for (final (slug, name) in menuTypes) {'slug': slug, 'name': name},
    ],
    'calendar': calendarUrl,
    'start': startTime,
    'end': endTime,
  };

  static SchoolConfig fromJson(Object? raw) {
    if (raw is! Map) return const SchoolConfig();
    final menus = <(String, String)>[
      if (raw['menus'] is List)
        for (final m in raw['menus'] as List)
          if (m is Map && '${m['slug'] ?? ''}'.isNotEmpty)
            ('${m['slug']}', '${m['name'] ?? m['slug']}'),
    ];
    return SchoolConfig(
      provider: raw['provider'] == 'nutrislice' ? 'nutrislice' : 'schoolcafe',
      servingLine: '${raw['servingLine'] ?? 'Main Line'}',
      grade: '${raw['grade'] ?? '02'}',
      district: '${raw['district'] ?? 'friscoisd'}',
      schoolSlug: '${raw['school'] ?? ''}',
      schoolName: '${raw['schoolName'] ?? 'Miller Elementary'}',
      menuTypes: raw['menus'] is List ? menus : const [('Breakfast', 'Breakfast'), ('Lunch', 'Lunch')],
      calendarUrl: '${raw['calendar'] ?? ''}',
      startTime: '${raw['start'] ?? ''}',
      endTime: '${raw['end'] ?? ''}',
    );
  }
}

/// A school from the district's Nutrislice list, with its menus.
@immutable
class SchoolChoice {
  const SchoolChoice(this.slug, this.name, this.menuTypes);
  final String slug;
  final String name;
  final List<(String, String)> menuTypes;
}

/// One day of one menu: the items under their section headings.
@immutable
class MenuDay {
  const MenuDay(this.date, this.sections);
  final DateTime date;

  /// (heading, items) in order; the heading is empty for items before any.
  final List<(String, List<String>)> sections;

  List<String> get items => [for (final (_, list) in sections) ...list];
  bool get isEmpty => items.isEmpty;
}

@immutable
class SchoolEvent {
  const SchoolEvent(this.start, this.end, this.title, {this.allDay = true});
  final DateTime start;

  /// Exclusive end (iCal's DTEND).
  final DateTime end;
  final String title;
  final bool allDay;

  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(DateTime(start.year, start.month, start.day)) &&
        d.isBefore(end);
  }

  /// Days off read as holidays: no school, breaks, holidays, closures.
  bool get noSchool {
    final t = title.toLowerCase();
    return const [
      'no school',
      'holiday',
      'break',
      'closed',
      'student holiday',
      'staff development',
      'teacher work',
    ].any(t.contains);
  }

  bool get earlyRelease => title.toLowerCase().contains('early release');
}

class SchoolService {
  SchoolService(this._client, this._prefs, this._log, {this.homeAssistant});

  /// Home Assistant's address and token, for a calendar entity as the
  /// school calendar.
  final ({String base, String token}) Function()? homeAssistant;

  final http.Client _client;
  final Future<SharedPreferences> Function() _prefs;
  final Logger _log;

  static const _configKey = 'phx.home.school';

  final config = ValueNotifier<SchoolConfig>(const SchoolConfig());

  /// Menus by type slug, every day loaded so far (this week and next at
  /// once, more as the calendar pages through months), by date.
  final menus = ValueNotifier<Map<String, List<MenuDay>>>(const {});

  /// Mondays already fetched, so paging the calendar loads each week once.
  final _weeks = <String>{};
  final events = ValueNotifier<List<SchoolEvent>>(const []);
  final loading = ValueNotifier<bool>(false);
  final problem = ValueNotifier<String?>(null);
  DateTime? _loadedAt;

  Future<void> init() async {
    final raw = (await _prefs()).getString(_configKey);
    if (raw != null) {
      try {
        config.value = SchoolConfig.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
  }

  Future<void> save(SchoolConfig next) async {
    config.value = next;
    await (await _prefs()).setString(_configKey, jsonEncode(next.toJson()));
    _loadedAt = null;
    await refresh();
  }

  /// Load the menus and the calendar, at most every 3 hours unless [force].
  Future<void> refresh({bool force = false}) async {
    final at = _loadedAt;
    if (!force &&
        at != null &&
        DateTime.now().difference(at) < const Duration(hours: 3)) {
      return;
    }
    final c = config.value;
    loading.value = true;
    final problems = <String>[];
    try {
      if (!c.hasMenu && c.schoolName.isNotEmpty && c.district.isNotEmpty) {
        // A name but no school picked yet (Miller Elementary out of the
        // box): find it in the district's list.
        await _resolveSchool(c);
      }
      final cfg = config.value;
      if (cfg.hasMenu) {
        _weeks.clear();
        menus.value = const {};
        final monday = _monday(DateTime.now());
        final failed = await loadWeeks([
          monday,
          monday.add(const Duration(days: 7)),
        ]);
        problems.addAll(failed);
      } else {
        menus.value = const {};
      }
      if (c.calendarUrl.isNotEmpty) {
        try {
          final now = DateTime.now();
          final from = DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 1));
          final List<SchoolEvent> all;
          if (c.calendarUrl.startsWith('calendar.')) {
            all = await _haCalendar(c.calendarUrl, from);
          } else {
            final res = await _client
                .get(Uri.parse(_webcal(c.calendarUrl)))
                .timeout(const Duration(seconds: 20));
            if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
            all = parseIcs(utf8.decode(res.bodyBytes, allowMalformed: true));
          }
          events.value = [
            for (final e in all)
              if (e.end.isAfter(from)) e,
          ]..sort((a, b) => a.start.compareTo(b.start));
        } catch (e) {
          _log.warn('phoenix_home', 'school calendar: $e');
          problems.add('the calendar');
        }
      } else {
        events.value = const [];
      }
      problem.value = !cfg.hasMenu && cfg.schoolName.isNotEmpty
          ? "Couldn't find ${cfg.schoolName}'s menus yet. Pick the school under Set up."
          : problems.isEmpty
          ? null
          : "Couldn't load ${problems.join(' and ')}. Showing what we have.";
      _loadedAt = DateTime.now();
    } finally {
      loading.value = false;
    }
  }

  /// Load the menus of the weeks starting on [mondays] not loaded yet, and
  /// merge them in. Answers the menus that failed, by name.
  Future<List<String>> loadWeeks(List<DateTime> mondays) async {
    final c = config.value;
    if (!c.hasMenu) return const [];
    final todo = [
      for (final m in mondays)
        if (_weeks.add('${c.schoolSlug}/${m.year}-${m.month}-${m.day}')) m,
    ];
    if (todo.isEmpty) return const [];
    final failed = <String>{};
    final next = {
      for (final e in menus.value.entries) e.key: [...e.value],
    };
    for (final (slug, name) in c.menuTypes) {
      final days = {
        for (final d in next[slug] ?? const <MenuDay>[]) _key(d.date): d,
      };
      for (final monday in todo) {
        try {
          for (final d in await _week(c, slug, monday)) {
            days[_key(d.date)] = d;
          }
        } catch (e) {
          _log.warn('phoenix_home', 'school menu $slug: $e');
          failed.add('the $name menu');
        }
      }
      next[slug] = days.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));
    }
    menus.value = next;
    return failed.toList();
  }

  /// The weeks a month view shows, loaded.
  Future<void> loadMonth(DateTime month) async {
    final first = DateTime(month.year, month.month);
    var monday = first.subtract(Duration(days: first.weekday - 1));
    final mondays = <DateTime>[];
    while (monday.isBefore(DateTime(month.year, month.month + 1))) {
      mondays.add(monday);
      monday = monday.add(const Duration(days: 7));
    }
    loading.value = true;
    try {
      await loadWeeks(mondays);
    } finally {
      loading.value = false;
    }
  }

  /// One menu's day, null when nothing is published for it.
  MenuDay? menuOn(String slug, DateTime day) {
    for (final d in menus.value[slug] ?? const <MenuDay>[]) {
      if (_key(d.date) == _key(day)) return d;
    }
    return null;
  }

  Future<void> _resolveSchool(SchoolConfig c) async {
    try {
      final match = bestSchoolMatch(await schools(c.district), c.schoolName);
      if (match == null) return;
      final picked = [
        for (final m in match.menuTypes)
          if (m.$1.contains('breakfast') || m.$1.contains('lunch')) m,
      ];
      final next = c.copyWith(
        schoolSlug: match.slug,
        menuTypes: picked.isEmpty ? match.menuTypes : picked,
      );
      config.value = next;
      await (await _prefs()).setString(_configKey, jsonEncode(next.toJson()));
    } catch (e) {
      _log.warn('phoenix_home', 'school lookup: $e');
    }
  }

  /// A Home Assistant calendar's events for the next year.
  Future<List<SchoolEvent>> _haCalendar(String entity, DateTime from) async {
    final ha = homeAssistant?.call();
    if (ha == null || ha.base.isEmpty || ha.token.isEmpty) {
      throw 'Home Assistant is not connected';
    }
    final uri = Uri.parse('${ha.base}/api/calendars/$entity').replace(
      queryParameters: {
        'start': from.toUtc().toIso8601String(),
        'end': from.add(const Duration(days: 366)).toUtc().toIso8601String(),
      },
    );
    final res = await _client
        .get(uri, headers: {'Authorization': 'Bearer ${ha.token}'})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
    return parseHaCalendar(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  static const _schoolCafe = 'webapis.schoolcafe.com';

  /// The district's schools and their menus, for the school picker.
  Future<List<SchoolChoice>> schools(String district, {String? provider}) async {
    if ((provider ?? config.value.provider) == 'schoolcafe') return _schoolCafeSchools(district);
    final res = await _client
        .get(Uri.https('$district.api.nutrislice.com', '/menu/api/schools/'))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
    return parseNutrisliceSchools(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  /// SchoolCafe's district and school lists. Not published as an API, so
  /// read tolerantly: any list of objects with a school id and a name.
  Future<List<SchoolChoice>> _schoolCafeSchools(String district) async {
    final isd = await _client
        .get(Uri.https(_schoolCafe, '/api/GetISDByShortName', {'shortname': district}))
        .timeout(const Duration(seconds: 20));
    if (isd.statusCode != 200) throw 'district HTTP ${isd.statusCode}';
    final isdId = findSchoolCafeId(jsonDecode(utf8.decode(isd.bodyBytes)), 'ISD');
    if (isdId == null) throw 'district $district not found on SchoolCafe';
    final res = await _client
        .get(Uri.https(_schoolCafe, '/api/GetSchoolsList', {'districtId': isdId}))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw 'schools HTTP ${res.statusCode}';
    return parseSchoolCafeSchools(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  Future<List<MenuDay>> _week(
    SchoolConfig c,
    String type,
    DateTime monday,
  ) async {
    if (c.provider == 'schoolcafe') {
      final days = <MenuDay>[];
      for (var i = 0; i < 5; i++) {
        final day = monday.add(Duration(days: i));
        final date = '${day.month.toString().padLeft(2, '0')}/${day.day.toString().padLeft(2, '0')}/${day.year}';
        final res = await _client
            .get(Uri.https(_schoolCafe, '/api/CalendarView/GetDailyMenuitemsByGrade', {
              'SchoolId': c.schoolSlug,
              'ServingDate': date,
              'ServingLine': c.servingLine,
              'MealType': type,
              'Grade': c.grade,
              'PersonId': 'null',
            }))
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
        days.add(parseSchoolCafeDay(jsonDecode(utf8.decode(res.bodyBytes)), day));
      }
      return days;
    }
    final uri = Uri.https(
      '${c.district}.api.nutrislice.com',
      '/menu/api/weeks/school/${c.schoolSlug}/menu-type/$type/'
          '${monday.year}/${monday.month.toString().padLeft(2, '0')}/${monday.day.toString().padLeft(2, '0')}/',
    );
    final res = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
    return parseNutrisliceWeek(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  /// Today's events: holidays, early release, anything else on the day.
  List<SchoolEvent> eventsOn(DateTime day) => [
    for (final e in events.value)
      if (e.covers(day)) e,
  ];

  /// The status line for [now]: no school, before, during or after school.
  String status(DateTime now) {
    final today = eventsOn(now);
    if (now.weekday >= DateTime.saturday) {
      return 'No school today, it is the weekend';
    }
    if (today.any((e) => e.noSchool)) {
      return 'No school today: ${today.firstWhere((e) => e.noSchool).title}';
    }
    final c = config.value;
    final start = _at(now, c.startTime), end = _at(now, c.endTime);
    final early = today.any((e) => e.earlyRelease)
        ? ' (early release today)'
        : '';
    if (start == null || end == null) {
      return today.isEmpty ? 'School day' : 'School day: ${today.first.title}';
    }
    if (now.isBefore(start)) {
      final m = start.difference(now).inMinutes;
      return m <= 90
          ? 'School starts in $m min$early'
          : 'School starts at ${_hm(start)}$early';
    }
    if (now.isBefore(end)) return 'At school until ${_hm(end)}$early';
    return 'School is out for today';
  }

  void dispose() {
    config.dispose();
    menus.dispose();
    events.dispose();
    loading.dispose();
    problem.dispose();
  }
}

String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// The district school that best matches a typed [name]: every word of the
/// name in the school's name, the shortest such name first ("Miller" finds
/// "Miller Elementary", not "Miller Middle Annex" before it).
SchoolChoice? bestSchoolMatch(List<SchoolChoice> schools, String name) {
  final words = name
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return null;
  final hits = [
    for (final s in schools)
      if (words.every(s.name.toLowerCase().contains)) s,
  ]..sort((a, b) => a.name.length.compareTo(b.name.length));
  return hits.firstOrNull;
}

DateTime _monday(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  // On the weekend, show the coming week.
  if (day.weekday >= DateTime.saturday) {
    return day.add(Duration(days: 8 - day.weekday));
  }
  return day.subtract(Duration(days: day.weekday - 1));
}

String _webcal(String url) =>
    url.startsWith('webcal://') ? 'https://${url.substring(9)}' : url;

DateTime? _at(DateTime day, String hm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hm.trim());
  if (m == null) return null;
  return DateTime(
    day.year,
    day.month,
    day.day,
    int.parse(m[1]!),
    int.parse(m[2]!),
  );
}

String _hm(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// SchoolCafe's day: {CATEGORY: [{MenuItemId, MenuItemDescription}]}, the
/// categories ("ENTREES", "LUNCH- HOT", "FRUIT") as section headings.
MenuDay parseSchoolCafeDay(Object? data, DateTime day) {
  final sections = <(String, List<String>)>[];
  if (data is Map) {
    for (final e in data.entries) {
      if (e.value is! List) continue;
      final items = <String>[];
      for (final item in e.value as List) {
        if (item is! Map) continue;
        final name = '${item['MenuItemDescription'] ?? ''}'.trim();
        if (name.isNotEmpty && !items.contains(name)) items.add(name);
      }
      if (items.isNotEmpty) sections.add((_title('${e.key}'), items));
    }
  }
  return MenuDay(DateTime(day.year, day.month, day.day), sections);
}

/// "LUNCH- HOT" → "Lunch Hot", "ENTREES" → "Entrees".
String _title(String raw) => raw
    .replaceAll(RegExp(r'[-_]+'), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

/// The first GUID-looking id in SchoolCafe's answer, preferring a key that
/// mentions [kind] ("ISD", "School").
String? findSchoolCafeId(Object? data, String kind) {
  final guid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  String? any;
  void walk(Object? v) {
    if (v is Map) {
      for (final e in v.entries) {
        final value = e.value;
        if (value is String && guid.hasMatch(value)) {
          if ('${e.key}'.toLowerCase().contains(kind.toLowerCase())) {
            any = value;
            return;
          }
          any ??= value;
        } else {
          walk(value);
        }
      }
    } else if (v is List && v.isNotEmpty) {
      walk(v.first);
    }
  }

  walk(data);
  return any;
}

/// SchoolCafe's school list: objects with an id (SchoolId, SchoolGuid, Id)
/// and a name (SchoolName, Name), sorted by name.
List<SchoolChoice> parseSchoolCafeSchools(Object? data) {
  final list = data is Map ? (data.values.firstWhere((v) => v is List, orElse: () => const [])) : data;
  if (list is! List) return const [];
  String? pick(Map m, List<String> keys) {
    for (final k in m.keys) {
      if (keys.contains('$k'.toLowerCase()) && '${m[k] ?? ''}'.trim().isNotEmpty) return '${m[k]}'.trim();
    }
    return null;
  }

  return [
    for (final s in list)
      if (s is Map)
        if ((pick(s, ['schoolid', 'schoolguid', 'id', 'guid']), pick(s, ['schoolname', 'name'])) case (final String id, final String name))
          SchoolChoice(id, name, const [('Breakfast', 'Breakfast'), ('Lunch', 'Lunch')]),
  ]..sort((a, b) => a.name.compareTo(b.name));
}

/// Home Assistant's calendar events: [{summary, start: {date|dateTime},
/// end: {date|dateTime}}].
List<SchoolEvent> parseHaCalendar(Object? data) {
  if (data is! List) return const [];
  DateTime? when(Object? v) {
    if (v is Map) {
      final d = v['date'] ?? v['dateTime'];
      return d == null ? null : DateTime.tryParse('$d')?.toLocal();
    }
    return v == null ? null : DateTime.tryParse('$v')?.toLocal();
  }

  return [
    for (final e in data)
      if (e is Map && when(e['start']) != null)
        SchoolEvent(
          when(e['start'])!,
          when(e['end']) ?? when(e['start'])!.add(const Duration(days: 1)),
          '${e['summary'] ?? 'Event'}',
          allDay: e['start'] is Map && (e['start'] as Map).containsKey('date'),
        ),
  ];
}

/// Nutrislice's school list: [{name, slug, active_menu_types: [{name, slug}]}].
List<SchoolChoice> parseNutrisliceSchools(Object? data) {
  if (data is! List) return const [];
  return [
    for (final s in data)
      if (s is Map && '${s['slug'] ?? ''}'.isNotEmpty)
        SchoolChoice('${s['slug']}', '${s['name'] ?? s['slug']}', [
          for (final t
              in (s['active_menu_types'] is List
                  ? s['active_menu_types'] as List
                  : const []))
            if (t is Map && '${t['slug'] ?? ''}'.isNotEmpty)
              ('${t['slug']}', '${t['name'] ?? t['slug']}'),
        ]),
  ]..sort((a, b) => a.name.compareTo(b.name));
}

/// Nutrislice's week: {days: [{date, menu_items: [{is_section_title, text,
/// food: {name}}]}]}. Section titles group the items below them.
List<MenuDay> parseNutrisliceWeek(Object? data) {
  if (data is! Map || data['days'] is! List) return const [];
  final days = <MenuDay>[];
  for (final d in data['days'] as List) {
    if (d is! Map) continue;
    final date = DateTime.tryParse('${d['date']}');
    if (date == null) continue;
    final sections = <(String, List<String>)>[];
    var heading = '';
    var items = <String>[];
    for (final item
        in (d['menu_items'] is List ? d['menu_items'] as List : const [])) {
      if (item is! Map) continue;
      if (item['is_section_title'] == true) {
        if (items.isNotEmpty) sections.add((heading, items));
        heading = '${item['text'] ?? ''}'.trim();
        items = <String>[];
        continue;
      }
      final food = item['food'];
      final name = (food is Map ? '${food['name'] ?? ''}' : '').trim();
      final text = name.isNotEmpty ? name : '${item['text'] ?? ''}'.trim();
      if (text.isNotEmpty && !items.contains(text)) items.add(text);
    }
    if (items.isNotEmpty) sections.add((heading, items));
    days.add(MenuDay(date, sections));
  }
  return days;
}

/// The VEVENTs of an iCal file: DTSTART, DTEND and SUMMARY, folded lines
/// joined. Timed events keep their times; all-day ones last whole days.
List<SchoolEvent> parseIcs(String text) {
  final lines = <String>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    if ((raw.startsWith(' ') || raw.startsWith('\t')) && lines.isNotEmpty) {
      lines[lines.length - 1] += raw.substring(1);
    } else {
      lines.add(raw);
    }
  }
  final events = <SchoolEvent>[];
  Map<String, String>? cur;
  for (final line in lines) {
    if (line == 'BEGIN:VEVENT') {
      cur = {};
    } else if (line == 'END:VEVENT' && cur != null) {
      final start = _icsDate(cur['DTSTART']);
      if (start != null) {
        final allDay = !(cur['DTSTART'] ?? '').contains('T');
        final end =
            _icsDate(cur['DTEND']) ??
            start.add(
              allDay ? const Duration(days: 1) : const Duration(hours: 1),
            );
        final title = (cur['SUMMARY'] ?? '')
            .replaceAll(r'\,', ',')
            .replaceAll(r'\;', ';')
            .replaceAll(r'\n', ' ')
            .trim();
        events.add(
          SchoolEvent(
            start,
            end,
            title.isEmpty ? 'Event' : title,
            allDay: allDay,
          ),
        );
      }
      cur = null;
    } else if (cur != null) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final name = line.substring(0, colon).split(';').first.toUpperCase();
      cur[name] = line.substring(colon + 1);
    }
  }
  return events;
}

DateTime? _icsDate(String? v) {
  if (v == null) return null;
  final m = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?',
  ).firstMatch(v.trim());
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  if (m[4] == null) return DateTime(y, mo, d);
  final t = DateTime.utc(
    y,
    mo,
    d,
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6]!),
  );
  return m[7] == 'Z'
      ? t.toLocal()
      : DateTime(
          y,
          mo,
          d,
          int.parse(m[4]!),
          int.parse(m[5]!),
          int.parse(m[6]!),
        );
}
