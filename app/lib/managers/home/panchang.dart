import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A Telugu calendar (పంచాంగం) computed on the device, no network: the Sun
/// and the Moon from Meeus' series, tithi, nakshatra, yoga and karana at
/// local sunrise, the amanta lunar month (adhika masa included), the
/// samvatsara, sunrise and sunset, Rahu Kalam and Yamagandam, and the Telugu
/// festivals that follow from them. Sidereal positions use the Lahiri
/// ayanamsa.
///
/// Days follow the place's sunrise, as Telugu calendars printed for a city
/// do, so a festival can land a day apart from India's.

// ── Astronomy ───────────────────────────────────────────────────────────────

double _rad(double d) => d * math.pi / 180;
double _norm(double d) => ((d % 360) + 360) % 360;

/// Julian day of a UTC instant.
double julianDay(DateTime t) => t.toUtc().millisecondsSinceEpoch / 86400000.0 + 2440587.5;

DateTime _fromJd(double jd) =>
    DateTime.fromMillisecondsSinceEpoch(((jd - 2440587.5) * 86400000).round(), isUtc: true);

/// Julian centuries of Terrestrial Time from J2000 (TT ≈ UT + 69 s).
double _t(double jd) => (jd + 69 / 86400 - 2451545.0) / 36525;

/// The Sun's apparent tropical longitude in degrees (±0.01°).
double sunLongitude(double jd) {
  final t = _t(jd);
  final l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;
  final m = _rad(357.52911 + 35999.05029 * t - 0.0001537 * t * t);
  final c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * math.sin(m) +
      (0.019993 - 0.000101 * t) * math.sin(2 * m) +
      0.000289 * math.sin(3 * m);
  final omega = _rad(125.04 - 1934.136 * t);
  return _norm(l0 + c - 0.00569 - 0.00478 * math.sin(omega));
}

// Meeus chapter 47, the largest terms of the Moon's longitude:
// D, M, M', F and the coefficient in millionths of a degree.
const _moonTerms = <List<int>>[
  [0, 0, 1, 0, 6288774], [2, 0, -1, 0, 1274027], [2, 0, 0, 0, 658314],
  [0, 0, 2, 0, 213618], [0, 1, 0, 0, -185116], [0, 0, 0, 2, -114332],
  [2, 0, -2, 0, 58793], [2, -1, -1, 0, 57066], [2, 0, 1, 0, 53322],
  [2, -1, 0, 0, 45758], [0, 1, -1, 0, -40923], [1, 0, 0, 0, -34720],
  [0, 1, 1, 0, -30383], [2, 0, 0, -2, 15327], [0, 0, 1, 2, -12528],
  [0, 0, 1, -2, 10980], [4, 0, -1, 0, 10675], [0, 0, 3, 0, 10034],
  [4, 0, -2, 0, 8548], [2, 1, -1, 0, -7888], [2, 1, 0, 0, -6766],
  [1, 0, -1, 0, -5163], [1, 1, 0, 0, 4987], [2, -1, 1, 0, 4036],
  [2, 0, 2, 0, 3994], [4, 0, 0, 0, 3861], [2, 0, -3, 0, 3665],
  [0, 1, -2, 0, -2689], [2, 0, -1, 2, -2602], [2, -1, -2, 0, 2390],
  [1, 0, 1, 0, -2348], [2, -2, 0, 0, 2236], [0, 1, 2, 0, -2120],
  [0, 2, 0, 0, -2069], [2, -2, -1, 0, 2048], [2, 0, 1, -2, -1773],
  [2, 0, 0, 2, -1595], [4, -1, -1, 0, 1215], [0, 0, 2, 2, -1110],
  [3, 0, -1, 0, -892], [2, 1, 1, 0, -810], [4, -1, -2, 0, 759],
  [0, 2, -1, 0, -713], [2, 2, -1, 0, -700], [2, 1, -2, 0, 691],
  [2, -1, 0, -2, 596], [4, 0, 1, 0, 549], [0, 0, 4, 0, 537],
  [4, -1, 0, 0, 520], [1, 0, -2, 0, -487],
];

/// The Moon's apparent tropical longitude in degrees (about ±0.005°).
double moonLongitude(double jd) {
  final t = _t(jd);
  final lp = 218.3164477 + 481267.88123421 * t - 0.0015786 * t * t;
  final d = 297.8501921 + 445267.1114034 * t - 0.0018819 * t * t;
  final m = 357.5291092 + 35999.0502909 * t - 0.0001536 * t * t;
  final mp = 134.9633964 + 477198.8675055 * t + 0.0087414 * t * t;
  final f = 93.2720950 + 483202.0175233 * t - 0.0036539 * t * t;
  final e = 1 - 0.002516 * t - 0.0000074 * t * t;
  var sum = 0.0;
  for (final term in _moonTerms) {
    final arg = _rad(term[0] * d + term[1] * m + term[2] * mp + term[3] * f);
    final ecc = term[1].abs() == 2 ? e * e : (term[1].abs() == 1 ? e : 1.0);
    sum += term[4] * ecc * math.sin(arg);
  }
  final a1 = _rad(119.75 + 131.849 * t);
  final a2 = _rad(53.09 + 479264.290 * t);
  sum += 3958 * math.sin(a1) + 1962 * math.sin(_rad(lp - f)) + 318 * math.sin(a2);
  final omega = _rad(125.04452 - 1934.136261 * t);
  final nutation = -0.00478 * math.sin(omega);
  return _norm(lp + sum / 1e6 + nutation);
}

/// Lahiri ayanamsa in degrees.
double ayanamsa(double jd) => 23.85309 + (jd - 2451545.0) / 365.25 * 0.0139687;

double siderealSun(double jd) => _norm(sunLongitude(jd) - ayanamsa(jd));
double siderealMoon(double jd) => _norm(moonLongitude(jd) - ayanamsa(jd));

/// Moon minus Sun, 0..360: twelve degrees a tithi.
double elongation(double jd) => _norm(moonLongitude(jd) - sunLongitude(jd));

/// When [f] (an angle growing about [rate] degrees a day) next reaches
/// [target] after [jd].
double _nextCrossing(double Function(double) f, double target, double jd, double rate) {
  var t = jd + _norm(target - f(jd)) / rate;
  for (var i = 0; i < 8; i++) {
    final diff = ((target - f(t) + 540) % 360) - 180;
    t += diff / rate;
    if (diff.abs() < 1e-5) break;
  }
  return t;
}

/// The last new moon at or before [jd], and the next one after it.
(double, double) newMoonsAround(double jd) {
  final next = _nextCrossing(elongation, 0, jd, 12.19);
  final prev = _nextCrossing(elongation, 0, next - 31, 12.19);
  return prev > jd ? (_nextCrossing(elongation, 0, prev - 31, 12.19), prev) : (prev, next);
}

/// Sunrise and sunset (UTC) on the local date [day] at [lat], [lon]; null
/// for polar day or night.
(DateTime, DateTime)? sunTimes(DateTime day, double lat, double lon) {
  // Noon at the place, first guess, then refine the event times twice.
  final base = julianDay(DateTime.utc(day.year, day.month, day.day, 12)) - lon / 360;
  double? event(bool rise) {
    var jd = base + (rise ? -0.25 : 0.25);
    for (var i = 0; i < 3; i++) {
      final t = _t(jd);
      final lambda = _rad(sunLongitude(jd));
      final eps = _rad(23.439291 - 0.0130042 * t);
      final dec = math.asin(math.sin(eps) * math.sin(lambda));
      final ra = math.atan2(math.cos(eps) * math.sin(lambda), math.cos(lambda));
      final cosH = (math.sin(_rad(-0.833)) - math.sin(_rad(lat)) * math.sin(dec)) /
          (math.cos(_rad(lat)) * math.cos(dec));
      if (cosH.abs() > 1) return null;
      final h = math.acos(cosH) * 180 / math.pi;
      // Local sidereal time of the event must equal RA ∓ H.
      final gmst = _norm(280.46061837 + 360.98564736629 * (jd - 2451545.0));
      final lst = _norm(gmst + lon);
      final want = _norm(ra * 180 / math.pi + (rise ? -h : h));
      jd += (((want - lst + 540) % 360) - 180) / 360.98564736629;
    }
    return jd;
  }

  final r = event(true), s = event(false);
  if (r == null || s == null) return null;
  return (_fromJd(r), _fromJd(s));
}

// ── Names ───────────────────────────────────────────────────────────────────

const tithiTe = [
  'పాడ్యమి', 'విదియ', 'తదియ', 'చవితి', 'పంచమి', 'షష్ఠి', 'సప్తమి', 'అష్టమి',
  'నవమి', 'దశమి', 'ఏకాదశి', 'ద్వాదశి', 'త్రయోదశి', 'చతుర్దశి', 'పౌర్ణమి',
];
const tithiEn = [
  'Padyami', 'Vidiya', 'Tadiya', 'Chavithi', 'Panchami', 'Shashthi', 'Saptami', 'Ashtami',
  'Navami', 'Dashami', 'Ekadashi', 'Dwadashi', 'Trayodashi', 'Chaturdashi', 'Pournami',
];
const masaTe = [
  'చైత్రం', 'వైశాఖం', 'జ్యేష్ఠం', 'ఆషాఢం', 'శ్రావణం', 'భాద్రపదం',
  'ఆశ్వయుజం', 'కార్తీకం', 'మార్గశిరం', 'పుష్యం', 'మాఘం', 'ఫాల్గుణం',
];
const masaEn = [
  'Chaitra', 'Vaishakha', 'Jyeshtha', 'Ashadha', 'Shravana', 'Bhadrapada',
  'Ashvayuja', 'Kartika', 'Margashira', 'Pushya', 'Magha', 'Phalguna',
];
const nakshatraTe = [
  'అశ్విని', 'భరణి', 'కృత్తిక', 'రోహిణి', 'మృగశిర', 'ఆర్ద్ర', 'పునర్వసు', 'పుష్యమి', 'ఆశ్లేష',
  'మఖ', 'పుబ్బ', 'ఉత్తర', 'హస్త', 'చిత్త', 'స్వాతి', 'విశాఖ', 'అనూరాధ', 'జ్యేష్ఠ',
  'మూల', 'పూర్వాషాఢ', 'ఉత్తరాషాఢ', 'శ్రవణం', 'ధనిష్ఠ', 'శతభిషం', 'పూర్వాభాద్ర', 'ఉత్తరాభాద్ర', 'రేవతి',
];
const nakshatraEn = [
  'Ashwini', 'Bharani', 'Krittika', 'Rohini', 'Mrigashira', 'Ardra', 'Punarvasu', 'Pushyami', 'Ashlesha',
  'Makha', 'Pubba', 'Uttara', 'Hasta', 'Chitta', 'Swati', 'Vishakha', 'Anuradha', 'Jyeshtha',
  'Moola', 'Purvashadha', 'Uttarashadha', 'Shravanam', 'Dhanishtha', 'Shatabhisham', 'Purvabhadra',
  'Uttarabhadra', 'Revati',
];
const yogaEn = [
  'Vishkambha', 'Priti', 'Ayushman', 'Saubhagya', 'Shobhana', 'Atiganda', 'Sukarma', 'Dhriti', 'Shoola',
  'Ganda', 'Vriddhi', 'Dhruva', 'Vyaghata', 'Harshana', 'Vajra', 'Siddhi', 'Vyatipata', 'Variyan',
  'Parigha', 'Shiva', 'Siddha', 'Sadhya', 'Shubha', 'Shukla', 'Brahma', 'Indra', 'Vaidhriti',
];
const varaTe = ['సోమవారం', 'మంగళవారం', 'బుధవారం', 'గురువారం', 'శుక్రవారం', 'శనివారం', 'ఆదివారం'];
const varaEn = ['Somavaram', 'Mangalavaram', 'Budhavaram', 'Guruvaram', 'Shukravaram', 'Shanivaram', 'Adivaram'];
const samvatsaraEn = [
  'Prabhava', 'Vibhava', 'Shukla', 'Pramoda', 'Prajapati', 'Angirasa', 'Shrimukha', 'Bhava', 'Yuva', 'Dhatu',
  'Ishvara', 'Bahudhanya', 'Pramathi', 'Vikrama', 'Vrisha', 'Chitrabhanu', 'Svabhanu', 'Tarana', 'Parthiva', 'Vyaya',
  'Sarvajit', 'Sarvadhari', 'Virodhi', 'Vikriti', 'Khara', 'Nandana', 'Vijaya', 'Jaya', 'Manmatha', 'Durmukhi',
  'Hevilambi', 'Vilambi', 'Vikari', 'Sharvari', 'Plava', 'Shubhakritu', 'Shobhakritu', 'Krodhi', 'Vishvavasu', 'Parabhava',
  'Plavanga', 'Kilaka', 'Saumya', 'Sadharana', 'Virodhikritu', 'Paridhavi', 'Pramadicha', 'Ananda', 'Rakshasa', 'Nala',
  'Pingala', 'Kalayukti', 'Siddharthi', 'Raudri', 'Durmati', 'Dundubhi', 'Rudhirodgari', 'Raktakshi', 'Krodhana', 'Akshaya',
];
const rituEn = ['Vasanta', 'Grishma', 'Varsha', 'Sharad', 'Hemanta', 'Shishira'];
const rituTe = ['వసంత', 'గ్రీష్మ', 'వర్ష', 'శరద్', 'హేమంత', 'శిశిర'];
const _karanaMovable = ['Bava', 'Balava', 'Kaulava', 'Taitila', 'Garaja', 'Vanija', 'Vishti'];

String karanaName(int halfTithi) {
  // 60 half-tithis a month: Kimstughna first, then the seven movable ones
  // eight times over, then Shakuni, Chatushpada and Naga.
  if (halfTithi == 0) return 'Kimstughna';
  if (halfTithi >= 57) return const ['Shakuni', 'Chatushpada', 'Naga'][halfTithi - 57];
  return _karanaMovable[(halfTithi - 1) % 7];
}

// ── The day ─────────────────────────────────────────────────────────────────

@immutable
class PanchangDay {
  const PanchangDay({
    required this.date,
    required this.sunrise,
    required this.sunset,
    required this.tithi,
    required this.tithiEnds,
    required this.nakshatra,
    required this.nakshatraEnds,
    required this.yoga,
    required this.karana,
    required this.masa,
    required this.adhika,
    required this.samvatsara,
    required this.festivals,
  });

  final DateTime date;
  final DateTime sunrise;
  final DateTime sunset;

  /// 0..29 at sunrise: 0..14 shukla (శుద్ధ), 15..29 krishna (బహుళ); 29 is
  /// amavasya.
  final int tithi;
  final DateTime tithiEnds;
  final int nakshatra;
  final DateTime nakshatraEnds;
  final int yoga;
  final String karana;

  /// 0 Chaitra .. 11 Phalguna.
  final int masa;
  final bool adhika;
  final int samvatsara;
  final List<String> festivals;

  bool get shukla => tithi < 15;
  int get tithiInPaksha => tithi % 15;
  bool get amavasya => tithi == 29;
  bool get pournami => tithi == 14;

  String get pakshaTe => shukla ? 'శుద్ధ' : 'బహుళ';
  String get pakshaEn => shukla ? 'Shukla' : 'Krishna';
  String get tithiNameTe => amavasya ? 'అమావాస్య' : tithiTe[tithiInPaksha];
  String get tithiNameEn => amavasya ? 'Amavasya' : tithiEn[tithiInPaksha];
  String get masaNameTe => '${adhika ? 'అధిక ' : ''}${masaTe[masa]}';
  String get masaNameEn => '${adhika ? 'Adhika ' : ''}${masaEn[masa]}';
  String get varaNameTe => varaTe[date.weekday - 1];
  String get varaNameEn => varaEn[date.weekday - 1];
  String get rituTeName => rituTe[masa ~/ 2];
  String get rituEnName => rituEn[masa ~/ 2];
  String get samvatsaraName => samvatsaraEn[samvatsara];

  /// "కార్తీక శుద్ధ ఏకాదశి", the way a Telugu calendar names a day.
  String get titleTe {
    final masa = masaNameTe.endsWith('ం') ? masaNameTe.substring(0, masaNameTe.length - 1) : masaNameTe;
    return '$masa $pakshaTe $tithiNameTe';
  }

  String get titleEn => '$masaNameEn $pakshaEn $tithiNameEn';

  /// Rahu Kalam and Yamagandam: an eighth of the daylight each, by weekday.
  (DateTime, DateTime) _eighth(int part) {
    final span = sunset.difference(sunrise) ~/ 8;
    final start = sunrise.add(span * (part - 1));
    return (start, start.add(span));
  }

  (DateTime, DateTime) get rahuKalam => _eighth(const [2, 7, 5, 6, 4, 3, 8][date.weekday - 1]);
  (DateTime, DateTime) get yamagandam => _eighth(const [4, 3, 2, 1, 7, 6, 5][date.weekday - 1]);
}

/// Computes days for one place, keeping what it has worked out.
class PanchangCalculator {
  PanchangCalculator(this.lat, this.lon);

  final double lat;
  final double lon;
  final _cache = <String, PanchangDay>{};

  /// The local date's panchangam, festivals included.
  PanchangDay day(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final key = '${d.year}-${d.month}-${d.day}';
    final hit = _cache[key];
    if (hit != null) return hit;
    final base = _basic(d);
    final full = PanchangDay(
      date: base.date,
      sunrise: base.sunrise,
      sunset: base.sunset,
      tithi: base.tithi,
      tithiEnds: base.tithiEnds,
      nakshatra: base.nakshatra,
      nakshatraEnds: base.nakshatraEnds,
      yoga: base.yoga,
      karana: base.karana,
      masa: base.masa,
      adhika: base.adhika,
      samvatsara: base.samvatsara,
      festivals: _festivals(d, base),
    );
    _cache[key] = full;
    return full;
  }

  final _basicCache = <String, PanchangDay>{};

  PanchangDay _basic(DateTime d) {
    final key = '${d.year}-${d.month}-${d.day}';
    final hit = _basicCache[key];
    if (hit != null) return hit;
    final times = sunTimes(d, lat, lon) ??
        (DateTime(d.year, d.month, d.day, 6).toUtc(), DateTime(d.year, d.month, d.day, 18).toUtc());
    final jd = julianDay(times.$1);
    final e = elongation(jd);
    final tithi = (e / 12).floor() % 30;
    final tithiEnds = _fromJd(_nextCrossing(elongation, ((tithi + 1) * 12) % 360, jd, 12.19)).toLocal();
    final moon = siderealMoon(jd);
    const nak = 360 / 27;
    final nakshatra = (moon / nak).floor() % 27;
    final nakEnds = _fromJd(_nextCrossing(siderealMoon, ((nakshatra + 1) * nak) % 360, jd, 13.18)).toLocal();
    final yoga = (_norm(moon + siderealSun(jd)) / nak).floor() % 27;
    final karana = karanaName((e / 6).floor() % 60);
    final (prevNm, nextNm) = newMoonsAround(jd);
    final rasiStart = (siderealSun(prevNm) / 30).floor() % 12;
    final rasiEnd = (siderealSun(nextNm) / 30).floor() % 12;
    final masa = (rasiStart + 1) % 12;
    // Ugadi (Chaitra shukla padyami) starts the year: before it, still
    // last year's samvatsara.
    final year = d.month <= 4 && masa >= 9 ? d.year - 1 : d.year;
    final day = PanchangDay(
      date: d,
      sunrise: times.$1.toLocal(),
      sunset: times.$2.toLocal(),
      tithi: tithi,
      tithiEnds: tithiEnds,
      nakshatra: nakshatra,
      nakshatraEnds: nakEnds,
      yoga: yoga,
      karana: karana,
      masa: masa,
      adhika: rasiStart == rasiEnd,
      samvatsara: ((year - 1987) % 60 + 60) % 60,
      festivals: const [],
    );
    _basicCache[key] = day;
    return day;
  }

  /// Whether [target] (0..29) is this day's tithi: at sunrise (the first
  /// of two sunrises when it spans both), or skipped over between this
  /// sunrise and the next (a kshaya tithi falls here).
  bool _isTithi(PanchangDay prev, PanchangDay day, PanchangDay next, int target) =>
      (day.tithi == target && prev.tithi != target) ||
      (day.tithi == (target + 29) % 30 && next.tithi == (target + 1) % 30);

  List<String> _festivals(DateTime d, PanchangDay day) {
    final next = _basic(d.add(const Duration(days: 1)));
    final prev = _basic(d.subtract(const Duration(days: 1)));
    final out = <String>[];
    bool on(int masa, int tithi) => !day.adhika && day.masa == masa && _isTithi(prev, day, next, tithi);
    // Shukla tithis are 0..14 (padyami..pournami), krishna 15..29 (29 amavasya).
    const s = 0, k = 15;
    final named = <(int, int, String)>[
      (0, s + 0, 'Ugadi (ఉగాది)'),
      (0, s + 8, 'Sri Rama Navami (శ్రీరామ నవమి)'),
      (0, s + 14, 'Chaitra Pournami / Hanuman Jayanti'),
      (1, s + 2, 'Akshaya Tritiya (అక్షయ తృతీయ)'),
      (1, s + 13, 'Narasimha Jayanti'),
      (2, s + 14, 'Jyeshtha Pournami'),
      (3, s + 10, 'Tholi Ekadashi (తొలి ఏకాదశి)'),
      (3, s + 14, 'Guru Pournami (గురు పౌర్ణమి)'),
      (4, s + 4, 'Naga Panchami (నాగ పంచమి)'),
      (4, s + 14, 'Raksha Bandhan / Shravana Pournami'),
      (4, k + 7, 'Sri Krishna Janmashtami'),
      (5, s + 3, 'Vinayaka Chavithi (వినాయక చవితి)'),
      (5, k + 14, 'Mahalaya Amavasya'),
      (6, s + 0, 'Dasara Navaratri begins'),
      (6, s + 7, 'Durgashtami (దుర్గాష్టమి)'),
      (6, s + 8, 'Mahanavami (మహానవమి)'),
      (6, s + 9, 'Vijaya Dashami / Dasara (దసరా)'),
      (6, k + 2, 'Atla Taddi (అట్ల తద్ది)'),
      (6, k + 13, 'Naraka Chaturdashi (నరక చతుర్దశి)'),
      (6, k + 14, 'Deepavali (దీపావళి)'),
      (7, s + 0, 'Kartika Masam begins'),
      (7, s + 3, 'Nagula Chavithi (నాగుల చవితి)'),
      (7, s + 10, 'Kartika Ekadashi'),
      (7, s + 14, 'Kartika Pournami (కార్తీక పౌర్ణమి)'),
      (8, s + 5, 'Subrahmanya Shashthi'),
      (8, s + 14, 'Datta Jayanti'),
      (10, s + 4, 'Vasant Panchami / Sri Panchami'),
      (10, s + 6, 'Ratha Saptami (రథసప్తమి)'),
      (10, s + 14, 'Magha Pournami'),
      (10, k + 13, 'Maha Shivaratri (మహా శివరాత్రి)'),
      (11, s + 14, 'Holi / Phalguna Pournami'),
    ];
    for (final (masa, tithi, name) in named) {
      if (on(masa, tithi)) out.add(name);
    }
    int rasiAt(PanchangDay p) => (siderealSun(julianDay(p.sunrise)) / 30).floor() % 12;
    // Mukkoti (Vaikuntha) Ekadashi: the shukla ekadashi while the Sun is in
    // Dhanu (Dhanurmasam).
    if (rasiAt(day) == 8 && _isTithi(prev, day, next, s + 10)) out.add('Vaikuntha (Mukkoti) Ekadashi');
    // Varalakshmi Vratam: the Friday before Shravana pournami.
    if (d.weekday == DateTime.friday && !day.adhika && day.masa == 4 && day.shukla && day.tithi >= 7 && day.tithi <= 13) {
      out.add('Varalakshmi Vratam (వరలక్ష్మీ వ్రతం)');
    }
    // Kartika Somavaram: every Monday of Kartika.
    if (d.weekday == DateTime.monday && day.masa == 7 && !day.adhika) out.add('Kartika Somavaram');
    // Sankranti: the day the Sun enters Makara (sidereal 270°), with Bhogi
    // the day before and Kanuma the day after.
    final r = rasiAt(day), rn = rasiAt(next), rp = rasiAt(prev);
    final prev2 = _basic(d.subtract(const Duration(days: 2)));
    if (r == 8 && rn == 9) out.add('Bhogi (భోగి)');
    if (r == 9 && rp == 8) out.add('Makara Sankranti (సంక్రాంతి)');
    if (rp == 9 && rasiAt(prev2) == 8) out.add('Kanuma (కనుమ)');
    // The recurring days, when nothing bigger is on.
    if (out.isEmpty) {
      if (_isTithi(prev, day, next, s + 10) || _isTithi(prev, day, next, k + 10)) out.add('Ekadashi (ఏకాదశి)');
      if (_isTithi(prev, day, next, s + 14)) out.add('Pournami (పౌర్ణమి)');
      if (_isTithi(prev, day, next, k + 14)) out.add('Amavasya (అమావాస్య)');
      if (_isTithi(prev, day, next, k + 3)) out.add('Sankashti Chaturthi');
    }
    return out;
  }

  /// The festivals in the [days] from [from], for the "coming up" list.
  List<(DateTime, String)> upcoming(DateTime from, int days, {bool majorOnly = true}) => [
    for (var i = 0; i < days; i++)
      for (final f in day(from.add(Duration(days: i))).festivals)
        if (!majorOnly || !_minor.contains(f)) (DateTime(from.year, from.month, from.day + i), f),
  ];

  static const _minor = {'Ekadashi (ఏకాదశి)', 'Pournami (పౌర్ణమి)', 'Amavasya (అమావాస్య)', 'Sankashti Chaturthi', 'Kartika Somavaram'};
}
