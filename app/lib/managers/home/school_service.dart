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
    this.district = 'friscoisd',
    this.schoolSlug = '',
    this.schoolName = '',
    this.menuTypes = const [],
    this.calendarUrl = '',
    this.startTime = '',
    this.endTime = '',
  });

  /// The district's Nutrislice name: friscoisd.nutrislice.com → friscoisd.
  final String district;
  final String schoolSlug;
  final String schoolName;

  /// The menus to show, as (slug, name): lunch, breakfast.
  final List<(String, String)> menuTypes;

  /// An iCal (.ics) link to the school or district calendar.
  final String calendarUrl;

  /// Bell times as H:MM in 24 hours ("7:50", "15:05"), empty when unset.
  final String startTime;
  final String endTime;

  bool get hasMenu => district.isNotEmpty && schoolSlug.isNotEmpty && menuTypes.isNotEmpty;

  SchoolConfig copyWith({
    String? district,
    String? schoolSlug,
    String? schoolName,
    List<(String, String)>? menuTypes,
    String? calendarUrl,
    String? startTime,
    String? endTime,
  }) => SchoolConfig(
    district: district ?? this.district,
    schoolSlug: schoolSlug ?? this.schoolSlug,
    schoolName: schoolName ?? this.schoolName,
    menuTypes: menuTypes ?? this.menuTypes,
    calendarUrl: calendarUrl ?? this.calendarUrl,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
  );

  Map<String, Object?> toJson() => {
    'district': district,
    'school': schoolSlug,
    'schoolName': schoolName,
    'menus': [for (final (slug, name) in menuTypes) {'slug': slug, 'name': name}],
    'calendar': calendarUrl,
    'start': startTime,
    'end': endTime,
  };

  static SchoolConfig fromJson(Object? raw) {
    if (raw is! Map) return const SchoolConfig();
    return SchoolConfig(
      district: '${raw['district'] ?? 'friscoisd'}',
      schoolSlug: '${raw['school'] ?? ''}',
      schoolName: '${raw['schoolName'] ?? ''}',
      menuTypes: [
        if (raw['menus'] is List)
          for (final m in raw['menus'] as List)
            if (m is Map && '${m['slug'] ?? ''}'.isNotEmpty) ('${m['slug']}', '${m['name'] ?? m['slug']}'),
      ],
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
    return !d.isBefore(DateTime(start.year, start.month, start.day)) && d.isBefore(end);
  }

  /// Days off read as holidays: no school, breaks, holidays, closures.
  bool get noSchool {
    final t = title.toLowerCase();
    return const ['no school', 'holiday', 'break', 'closed', 'student holiday', 'staff development', 'teacher work']
        .any(t.contains);
  }

  bool get earlyRelease => title.toLowerCase().contains('early release');
}

class SchoolService {
  SchoolService(this._client, this._prefs, this._log);

  final http.Client _client;
  final Future<SharedPreferences> Function() _prefs;
  final Logger _log;

  static const _configKey = 'phx.home.school';

  final config = ValueNotifier<SchoolConfig>(const SchoolConfig());

  /// Menus by type slug: this week's and next week's days.
  final menus = ValueNotifier<Map<String, List<MenuDay>>>(const {});
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
    if (!force && at != null && DateTime.now().difference(at) < const Duration(hours: 3)) return;
    final c = config.value;
    loading.value = true;
    final problems = <String>[];
    try {
      if (c.hasMenu) {
        final next = <String, List<MenuDay>>{};
        final monday = _monday(DateTime.now());
        for (final (slug, name) in c.menuTypes) {
          try {
            next[slug] = [
              ...await _week(c, slug, monday),
              ...await _week(c, slug, monday.add(const Duration(days: 7))),
            ];
          } catch (e) {
            _log.warn('phoenix_home', 'school menu $slug: $e');
            problems.add('the $name menu');
          }
        }
        menus.value = next;
      } else {
        menus.value = const {};
      }
      if (c.calendarUrl.isNotEmpty) {
        try {
          final res = await _client.get(Uri.parse(_webcal(c.calendarUrl))).timeout(const Duration(seconds: 20));
          if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
          final now = DateTime.now();
          final from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
          events.value = [
            for (final e in parseIcs(utf8.decode(res.bodyBytes, allowMalformed: true)))
              if (e.end.isAfter(from)) e,
          ]..sort((a, b) => a.start.compareTo(b.start));
        } catch (e) {
          _log.warn('phoenix_home', 'school calendar: $e');
          problems.add('the calendar');
        }
      } else {
        events.value = const [];
      }
      problem.value = problems.isEmpty ? null : "Couldn't load ${problems.join(' and ')}. Showing what we have.";
      _loadedAt = DateTime.now();
    } finally {
      loading.value = false;
    }
  }

  /// The district's schools and their menus, for the school picker.
  Future<List<SchoolChoice>> schools(String district) async {
    final res = await _client
        .get(Uri.https('$district.api.nutrislice.com', '/menu/api/schools/'))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
    return parseNutrisliceSchools(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  Future<List<MenuDay>> _week(SchoolConfig c, String type, DateTime monday) async {
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
  List<SchoolEvent> eventsOn(DateTime day) => [for (final e in events.value) if (e.covers(day)) e];

  /// The status line for [now]: no school, before, during or after school.
  String status(DateTime now) {
    final today = eventsOn(now);
    if (now.weekday >= DateTime.saturday) return 'No school today, it is the weekend';
    if (today.any((e) => e.noSchool)) return 'No school today: ${today.firstWhere((e) => e.noSchool).title}';
    final c = config.value;
    final start = _at(now, c.startTime), end = _at(now, c.endTime);
    final early = today.any((e) => e.earlyRelease) ? ' (early release today)' : '';
    if (start == null || end == null) return today.isEmpty ? 'School day' : 'School day: ${today.first.title}';
    if (now.isBefore(start)) {
      final m = start.difference(now).inMinutes;
      return m <= 90 ? 'School starts in $m min$early' : 'School starts at ${_hm(start)}$early';
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

DateTime _monday(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  // On the weekend, show the coming week.
  if (day.weekday >= DateTime.saturday) return day.add(Duration(days: 8 - day.weekday));
  return day.subtract(Duration(days: day.weekday - 1));
}

String _webcal(String url) => url.startsWith('webcal://') ? 'https://${url.substring(9)}' : url;

DateTime? _at(DateTime day, String hm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hm.trim());
  if (m == null) return null;
  return DateTime(day.year, day.month, day.day, int.parse(m[1]!), int.parse(m[2]!));
}

String _hm(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// Nutrislice's school list: [{name, slug, active_menu_types: [{name, slug}]}].
List<SchoolChoice> parseNutrisliceSchools(Object? data) {
  if (data is! List) return const [];
  return [
    for (final s in data)
      if (s is Map && '${s['slug'] ?? ''}'.isNotEmpty)
        SchoolChoice(
          '${s['slug']}',
          '${s['name'] ?? s['slug']}',
          [
            for (final t in (s['active_menu_types'] is List ? s['active_menu_types'] as List : const []))
              if (t is Map && '${t['slug'] ?? ''}'.isNotEmpty) ('${t['slug']}', '${t['name'] ?? t['slug']}'),
          ],
        ),
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
    for (final item in (d['menu_items'] is List ? d['menu_items'] as List : const [])) {
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
        final end = _icsDate(cur['DTEND']) ?? start.add(allDay ? const Duration(days: 1) : const Duration(hours: 1));
        final title = (cur['SUMMARY'] ?? '')
            .replaceAll(r'\,', ',')
            .replaceAll(r'\;', ';')
            .replaceAll(r'\n', ' ')
            .trim();
        events.add(SchoolEvent(start, end, title.isEmpty ? 'Event' : title, allDay: allDay));
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
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?').firstMatch(v.trim());
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  if (m[4] == null) return DateTime(y, mo, d);
  final t = DateTime.utc(y, mo, d, int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
  return m[7] == 'Z' ? t.toLocal() : DateTime(y, mo, d, int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
}
