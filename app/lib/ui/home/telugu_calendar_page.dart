import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_container.dart';
import '../../managers/home/panchang.dart';
import '../theme.dart';
import 'home_glass.dart';

/// Phoenix Home's Telugu calendar (తెలుగు క్యాలెండర్): today's full
/// panchangam, the month with each day's tithi and festivals, and what is
/// coming up. Computed on the Portal for its place; no network.
class TeluguCalendarPage extends StatefulWidget {
  const TeluguCalendarPage({super.key, required this.container});

  final AppContainer container;

  @override
  State<TeluguCalendarPage> createState() => _TeluguCalendarPageState();
}

class _TeluguCalendarPageState extends State<TeluguCalendarPage> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = _today;

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  PanchangCalculator get calc => widget.container.phoenixHome.panchang;

  @override
  // On the wallpaper in glass, like the Today screen.
  Widget build(BuildContext context) => PhoenixPageBackdrop(
    container: widget.container,
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 24, 4),
            child: Row(
              children: [
                IconButton(
                  iconSize: 30,
                  color: Colors.white,
                  tooltip: 'Back',
                  onPressed: () => widget.container.phoenixHome.teluguOpen.value = false,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.brightness_5_rounded, color: Phx.gold, size: 30),
                const SizedBox(width: 12),
                const Text(
                  'తెలుగు క్యాలెండర్',
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 12),
                Text(
                  '${calc.day(_today).samvatsaraName} nama samvatsaram',
                  style: const TextStyle(color: Colors.white54, fontSize: 16),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _selected = _today;
                    _month = DateTime(_today.year, _today.month);
                  }),
                  icon: const Icon(Icons.today_rounded),
                  label: const Text('Today'),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth > 900;
                final detail = _DayDetail(day: calc.day(_selected), upcoming: calc.upcoming(_today, 75));
                final grid = _Month(
                  calc: calc,
                  month: _month,
                  selected: _selected,
                  onMonth: (m) => setState(() => _month = m),
                  onPick: (d) => setState(() => _selected = d),
                );
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 380, child: detail),
                            const SizedBox(width: 20),
                            Expanded(child: grid),
                          ],
                        )
                      : Column(
                          children: [
                            SizedBox(height: box.maxHeight * 0.45, child: detail),
                            const SizedBox(height: 12),
                            Expanded(child: grid),
                          ],
                        ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

String _hm(DateTime t) => DateFormat.jm().format(t);

class _DayDetail extends StatelessWidget {
  const _DayDetail({required this.day, required this.upcoming});
  final PanchangDay day;
  final List<(DateTime, String)> upcoming;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value, {String? sub}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                if (sub != null) Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
    final (rahuS, rahuE) = day.rahuKalam;
    final (yamaS, yamaE) = day.yamagandam;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: glassFill,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Phx.gold.withValues(alpha: 0.35)),
      ),
      child: ListView(
        children: [
          Text(DateFormat('EEEE, MMMM d, yyyy').format(day.date), style: const TextStyle(color: Phx.gold, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(day.titleTe, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          Text(day.titleEn, style: const TextStyle(color: Colors.white70, fontSize: 15)),
          for (final f in day.festivals)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFD42A1A), Color(0xFFF5A623)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(f, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          const SizedBox(height: 12),
          row('వారం', '${day.varaNameTe} · ${day.varaNameEn}'),
          row('తిథి', '${day.tithiNameTe} (${day.tithiNameEn})', sub: 'until ${DateFormat('EEE').format(day.tithiEnds)} ${_hm(day.tithiEnds)}'),
          row('నక్షత్రం', '${nakshatraTe[day.nakshatra]} (${nakshatraEn[day.nakshatra]})',
              sub: 'until ${DateFormat('EEE').format(day.nakshatraEnds)} ${_hm(day.nakshatraEnds)}'),
          row('యోగం', yogaEn[day.yoga]),
          row('కరణం', day.karana),
          row('మాసం', '${day.masaNameTe} · ${day.pakshaTe} పక్షం', sub: '${day.masaNameEn} masam, ${day.pakshaEn} paksha'),
          row('ఋతువు', '${day.rituTeName} ఋతువు', sub: '${day.rituEnName} ritu'),
          row('సూర్యోదయం', _hm(day.sunrise), sub: 'Sunset ${_hm(day.sunset)}'),
          row('రాహు కాలం', '${_hm(rahuS)} – ${_hm(rahuE)}'),
          row('యమగండం', '${_hm(yamaS)} – ${_hm(yamaE)}'),
          const SizedBox(height: 14),
          const Text('COMING UP', style: TextStyle(color: Phx.gold, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
          const SizedBox(height: 6),
          for (final (date, name) in upcoming.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(DateFormat('EEE MMM d').format(date), style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  ),
                  Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Month extends StatelessWidget {
  const _Month({
    required this.calc,
    required this.month,
    required this.selected,
    required this.onMonth,
    required this.onPick,
  });

  final PanchangCalculator calc;
  final DateTime month;
  final DateTime selected;
  final ValueChanged<DateTime> onMonth;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final lead = first.weekday % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final rows = ((lead + days) / 7).ceil();
    final mid = calc.day(DateTime(month.year, month.month, 15));
    final now = DateTime.now();
    return Column(
      children: [
        Row(
          children: [
            IconButton(color: Colors.white, onPressed: () => onMonth(DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left_rounded, size: 32)),
            Expanded(
              child: Column(
                children: [
                  Text(DateFormat('MMMM yyyy').format(month), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  Text('${mid.masaNameTe} · ${mid.samvatsaraName}', style: const TextStyle(color: Colors.white54)),
                ],
              ),
            ),
            IconButton(color: Colors.white, onPressed: () => onMonth(DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right_rounded, size: 32)),
          ],
        ),
        Row(
          children: [
            for (final d in const ['ఆది', 'సోమ', 'మంగళ', 'బుధ', 'గురు', 'శుక్ర', 'శని'])
              Expanded(child: Text(d, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w700))),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Column(
            children: [
              for (var r = 0; r < rows; r++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: r == 0 ? 0 : 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var c = 0; c < 7; c++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(left: c == 0 ? 0 : 5),
                              child: _cell(r * 7 + c - lead + 1, days, now),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cell(int n, int days, DateTime now) {
    if (n < 1 || n > days) return const SizedBox.shrink();
    final date = DateTime(month.year, month.month, n);
    final p = calc.day(date);
    final today = date.year == now.year && date.month == now.month && date.day == now.day;
    final picked = date == selected;
    final festival = p.festivals.firstOrNull;
    final special = p.pournami || p.amavasya;
    return Material(
      color: picked ? glassPicked : glassFill,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onPick(date),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: today ? Phx.ember : (picked ? Phx.gold : Colors.transparent), width: 2),
          ),
          child: ClipRect(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('$n', style: TextStyle(color: today ? Phx.gold : Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                    const Spacer(),
                    if (special)
                      Icon(p.pournami ? Icons.circle : Icons.circle_outlined, size: 12, color: const Color(0xFFFFE08A)),
                  ],
                ),
                Text(p.tithiNameTe, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                if (festival != null)
                  Text(
                    festival.split(' (').first,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Phx.gold, fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Telugu calendar tile's lines: today's tithi in Telugu, then the day's
/// festival, or the next one and how far off it is.
(String, String) teluguTileLines(PanchangCalculator calc) {
  final now = DateTime.now();
  final today = calc.day(now);
  if (today.festivals.isNotEmpty) return (today.titleTe, today.festivals.first);
  final next = calc.upcoming(DateTime(now.year, now.month, now.day + 1), 45).firstOrNull;
  if (next == null) return (today.titleTe, nakshatraEn[today.nakshatra]);
  final days = next.$1.difference(DateTime(now.year, now.month, now.day)).inDays;
  return (today.titleTe, '${next.$2.split(' (').first} ${days == 1 ? 'tomorrow' : 'in $days days'}');
}
