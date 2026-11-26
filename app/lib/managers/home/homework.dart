import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One day's homework practice: spelling and times tables, each as
/// (answered, right).
@immutable
class HomeworkDay {
  const HomeworkDay({this.spelling = (0, 0), this.times = (0, 0)});
  final (int, int) spelling;
  final (int, int) times;

  HomeworkDay add(String kind, bool right) {
    (int, int) bump((int, int) v) => (v.$1 + 1, v.$2 + (right ? 1 : 0));
    return kind == 'spelling' ? HomeworkDay(spelling: bump(spelling), times: times) : HomeworkDay(spelling: spelling, times: bump(times));
  }

  Map<String, Object?> toJson() => {'s': [spelling.$1, spelling.$2], 't': [times.$1, times.$2]};

  static HomeworkDay fromJson(Object? raw) {
    (int, int) pair(Object? v) => v is List && v.length == 2 && v[0] is int && v[1] is int ? (v[0] as int, v[1] as int) : (0, 0);
    return raw is Map ? HomeworkDay(spelling: pair(raw['s']), times: pair(raw['t'])) : const HomeworkDay();
  }
}

/// The homework a grown-up sets (a spelling list and the times tables to
/// practise) and how each day's practice went. Set on the Portal (behind
/// the parent PIN) or in the remote admin; practised in the Kids Portal's
/// Homework game. Kept on the Portal only.
class HomeworkStore {
  HomeworkStore(this._prefs);
  final Future<SharedPreferences> Function() _prefs;

  static const _wordsKey = 'phx.kids.homework.words';
  static const _tablesKey = 'phx.kids.homework.tables';
  static const _logKey = 'phx.kids.homework.log';

  /// Days of practice kept.
  static const keepDays = 30;

  final words = ValueNotifier<List<String>>(const []);
  final tables = ValueNotifier<List<int>>(const []);
  final log = ValueNotifier<Map<String, HomeworkDay>>(const {});

  bool get isSet => words.value.isNotEmpty || tables.value.isNotEmpty;

  /// Words from a list typed any way: commas, new lines or spaces between,
  /// tidied, without repeats, at most 40.
  static List<String> parseWords(String text) {
    final out = <String>[];
    for (final w in text.split(RegExp(r'[\s,;]+'))) {
      final word = w.trim().replaceAll(RegExp(r"[^A-Za-z'\-]"), '');
      if (word.isEmpty || out.any((o) => o.toLowerCase() == word.toLowerCase())) continue;
      out.add(word);
      if (out.length == 40) break;
    }
    return out;
  }

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> load() async {
    final prefs = await _prefs();
    words.value = prefs.getStringList(_wordsKey) ?? const [];
    tables.value = [for (final t in prefs.getStringList(_tablesKey) ?? const <String>[]) ?int.tryParse(t)];
    try {
      final raw = jsonDecode(prefs.getString(_logKey) ?? '{}');
      if (raw is Map) log.value = {for (final e in raw.entries) '${e.key}': HomeworkDay.fromJson(e.value)};
    } catch (_) {}
  }

  Future<void> setWords(List<String> next) async {
    words.value = List.unmodifiable(next.take(40));
    await (await _prefs()).setStringList(_wordsKey, words.value);
  }

  Future<void> setTables(List<int> next) async {
    tables.value = List.unmodifiable({for (final t in next) if (t >= 1 && t <= 12) t}.toList()..sort());
    await (await _prefs()).setStringList(_tablesKey, [for (final t in tables.value) '$t']);
  }

  /// One answer: [kind] 'spelling' or 'times'.
  Future<void> record(String kind, bool right, {DateTime? now}) async {
    final today = dayKey(now ?? DateTime.now());
    final next = {...log.value, today: (log.value[today] ?? const HomeworkDay()).add(kind, right)};
    final keys = next.keys.toList()..sort();
    for (final old in keys.take(keys.length > keepDays ? keys.length - keepDays : 0)) {
      next.remove(old);
    }
    log.value = next;
    await (await _prefs()).setString(_logKey, jsonEncode({for (final e in next.entries) e.key: e.value.toJson()}));
  }

  /// The last [days] days, newest first, for the report.
  List<(String, HomeworkDay)> report({int days = 7, DateTime? now}) {
    final today = now ?? DateTime.now();
    return [
      for (var i = 0; i < days; i++)
        if (dayKey(DateTime(today.year, today.month, today.day - i)) case final k) (k, log.value[k] ?? const HomeworkDay()),
    ];
  }

  Map<String, Object?> toJson() => {
    'words': words.value,
    'tables': tables.value,
    'report': [
      for (final (day, d) in report())
        {'day': day, 'spelling': [d.spelling.$1, d.spelling.$2], 'times': [d.times.$1, d.times.$2]},
    ],
  };

  void dispose() {
    words.dispose();
    tables.dispose();
    log.dispose();
  }
}
