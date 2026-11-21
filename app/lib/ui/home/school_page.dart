import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_container.dart';
import '../../managers/home/school_service.dart';
import '../theme.dart';

/// Phoenix Home's School page: today's status and bell times, this week's
/// breakfast and lunch menus, and what is coming up on the school calendar.
class SchoolPage extends StatefulWidget {
  const SchoolPage({super.key, required this.container});

  final AppContainer container;

  @override
  State<SchoolPage> createState() => _SchoolPageState();
}

class _SchoolPageState extends State<SchoolPage> {
  SchoolService get school => widget.container.phoenixHome.school;

  /// This week, or the month calendar.
  bool _calendar = false;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _showMonth(DateTime month) {
    setState(() => _month = month);
    unawaited(school.loadMonth(month));
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF15181F), Color(0xFF0B0D10)],
      ),
    ),
    child: SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          school.config,
          school.menus,
          school.events,
          school.loading,
          school.problem,
        ]),
        builder: (context, _) {
          final cfg = school.config.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 24, 8),
                child: Row(
                  children: [
                    IconButton(
                      iconSize: 30,
                      color: Colors.white,
                      tooltip: 'Back',
                      onPressed: () =>
                          widget.container.phoenixHome.schoolOpen.value = false,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.school_rounded,
                      color: Phx.ember,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        cfg.schoolName.isEmpty ? 'School' : cfg.schoolName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        selectedForegroundColor: const Color(0xFF2A0A00),
                        selectedBackgroundColor: Phx.ember,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('This week'),
                          icon: Icon(Icons.view_week_rounded),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Calendar'),
                          icon: Icon(Icons.calendar_month_rounded),
                        ),
                      ],
                      selected: {_calendar},
                      onSelectionChanged: (v) {
                        setState(() => _calendar = v.first);
                        if (_calendar) _showMonth(_month);
                      },
                    ),
                    const SizedBox(width: 8),
                    if (school.loading.value)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    else
                      IconButton(
                        color: Colors.white70,
                        tooltip: 'Refresh',
                        onPressed: () => unawaited(school.refresh(force: true)),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                      ),
                      onPressed: () =>
                          unawaited(showSchoolSetup(context, school)),
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('Set up'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: !cfg.hasMenu && cfg.calendarUrl.isEmpty
                    ? _Welcome(
                        onSetUp: () =>
                            unawaited(showSchoolSetup(context, school)),
                      )
                    : _calendar
                    ? _MonthCalendar(
                        school: school,
                        month: _month,
                        onMonth: _showMonth,
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(28, 4, 28, 32),
                        children: [
                          _StatusCard(school: school),
                          if (cfg.hasMenu) _TodayMenu(school: school),
                          if (school.problem.value case final p?)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                p,
                                style: const TextStyle(color: Phx.gold),
                              ),
                            ),
                          for (final (slug, name) in cfg.menuTypes) ...[
                            _Heading('$name this week'),
                            _MenuWeek(
                              school: school,
                              days: school.menus.value[slug] ?? const [],
                            ),
                          ],
                          if (cfg.calendarUrl.isNotEmpty) ...[
                            const _Heading('Coming up'),
                            _Upcoming(events: school.events.value),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Phx.gold,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.school});
  final SchoolService school;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = school.eventsOn(now);
    final cfg = school.config.value;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF3A1C0E), Color(0xFF1C2028)],
        ),
        border: Border.all(color: Phx.ember.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: Phx.gold, size: 44),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  school.status(now),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (cfg.startTime.isNotEmpty && cfg.endTime.isNotEmpty)
                  Text(
                    'Bell times ${_pretty(cfg.startTime)} to ${_pretty(cfg.endTime)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                for (final e in today)
                  Text(
                    e.title,
                    style: const TextStyle(color: Phx.gold, fontSize: 15),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _pretty(String hm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hm.trim());
  if (m == null) return hm;
  final h = int.parse(m[1]!);
  return '${h % 12 == 0 ? 12 : h % 12}:${m[2]} ${h < 12 ? 'AM' : 'PM'}';
}

class _MenuWeek extends StatelessWidget {
  const _MenuWeek({required this.school, required this.days});
  final SchoolService school;
  final List<MenuDay> days;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final shown = [
      for (final d in days)
        if (!d.date.isBefore(start) && d.date.weekday <= DateTime.friday) d,
    ].take(5).toList();
    if (shown.isEmpty) {
      return const Text(
        'No menu published for the coming days.',
        style: TextStyle(color: Colors.white54),
      );
    }
    return SizedBox(
      height: 250,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final d = shown[i];
          final isToday =
              d.date.year == today.year &&
              d.date.month == today.month &&
              d.date.day == today.day;
          return GestureDetector(
            onTap: () => unawaited(showSchoolDay(context, school, d.date)),
            child: Container(
              width: 230,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isToday
                    ? const Color(0xFF3A1C0E)
                    : const Color(0xFF1C2028),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isToday
                      ? Phx.ember
                      : Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isToday ? 'Today' : DateFormat('EEEE').format(d.date),
                    style: TextStyle(
                      color: isToday ? Phx.gold : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    DateFormat('MMM d').format(d.date),
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: d.isEmpty
                        ? const Text(
                            'No menu',
                            style: TextStyle(color: Colors.white54),
                          )
                        : ListView(
                            children: [
                              for (final (heading, items) in d.sections) ...[
                                if (heading.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      heading,
                                      style: const TextStyle(
                                        color: Phx.gold,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                for (final item in items)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      '• $item',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Upcoming extends StatelessWidget {
  const _Upcoming({required this.events});
  final List<SchoolEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Text(
        'Nothing on the calendar.',
        style: TextStyle(color: Colors.white54),
      );
    }
    return Column(
      children: [
        for (final e in events.take(12))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              e.noSchool
                  ? Icons.beach_access_rounded
                  : (e.earlyRelease
                        ? Icons.directions_run_rounded
                        : Icons.event_rounded),
              color: e.noSchool ? Phx.gold : Colors.white70,
            ),
            title: Text(
              e.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              _when(e),
              style: const TextStyle(color: Colors.white54),
            ),
          ),
      ],
    );
  }

  String _when(SchoolEvent e) {
    final f = DateFormat('EEE, MMM d');
    if (!e.allDay) {
      return '${f.format(e.start)} · ${DateFormat.jm().format(e.start)}';
    }
    final last = e.end.subtract(const Duration(days: 1));
    return last.isAfter(e.start)
        ? '${f.format(e.start)} to ${f.format(last)}'
        : f.format(e.start);
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onSetUp});
  final VoidCallback onSetUp;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.school_rounded, color: Phx.ember, size: 72),
          const SizedBox(height: 16),
          const Text(
            'Lunch menus and the school calendar',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Pick your school to see this week's breakfast and lunch, add the district calendar for holidays "
            'and early release days, and set the bell times.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Phx.ember,
              foregroundColor: const Color(0xFF2A0A00),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            ),
            onPressed: onSetUp,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Set up school'),
          ),
        ],
      ),
    ),
  );
}

/// The setup sheet: district, school (picked from the district's list),
/// menus, calendar link and bell times.
Future<void> showSchoolSetup(BuildContext context, SchoolService school) =>
    showDialog<void>(
      context: context,
      builder: (_) => _SchoolSetup(school: school),
    );

class _SchoolSetup extends StatefulWidget {
  const _SchoolSetup({required this.school});
  final SchoolService school;

  @override
  State<_SchoolSetup> createState() => _SchoolSetupState();
}

class _SchoolSetupState extends State<_SchoolSetup> {
  late SchoolConfig _cfg = widget.school.config.value;
  late final _district = TextEditingController(text: _cfg.district);
  late final _schoolId = TextEditingController(text: _cfg.schoolSlug);
  late final _line = TextEditingController(text: _cfg.servingLine);
  late final _grade = TextEditingController(text: _cfg.grade);
  late final _name = TextEditingController(text: _cfg.schoolName);
  late final _calendar = TextEditingController(text: _cfg.calendarUrl);
  late final _start = TextEditingController(text: _cfg.startTime);
  late final _end = TextEditingController(text: _cfg.endTime);
  late final _filter = TextEditingController(
    text: _cfg.schoolSlug.isEmpty ? _cfg.schoolName.split(' ').first : '',
  );
  List<SchoolChoice>? _schools;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSchools());
  }

  @override
  void dispose() {
    for (final c in [_district, _schoolId, _line, _grade, _name, _calendar, _start, _end, _filter]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSchools() async {
    final district = _district.text.trim();
    if (district.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.school.schools(district, provider: _cfg.provider);
      if (mounted) setState(() => _schools = list);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              "Couldn't load $district's schools. Check the name (it is the first part of "
              'the menu site, like friscoisd in friscoisd.nutrislice.com).',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _time(String text) {
    final t = text.trim();
    if (t.isEmpty) return '';
    final m = RegExp(r'^(\d{1,2}):(\d{2})\s*([aApP][mM])?$').firstMatch(t);
    if (m == null) return null;
    var h = int.parse(m[1]!);
    final min = int.parse(m[2]!);
    final ap = m[3]?.toLowerCase();
    if (ap == 'pm' && h < 12) h += 12;
    if (ap == 'am' && h == 12) h = 0;
    if (h > 23 || min > 59) return null;
    return '$h:${min.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    final start = _time(_start.text), end = _time(_end.text);
    if (start == null || end == null) {
      setState(() => _error = 'Bell times look like 7:50 AM and 3:05 PM.');
      return;
    }
    Navigator.pop(context);
    await widget.school.save(
      _cfg.copyWith(
        schoolName: _name.text.trim(),
        schoolSlug: _schoolId.text.trim(),
        servingLine: _line.text.trim().isEmpty ? 'Main Line' : _line.text.trim(),
        grade: _grade.text.trim().isEmpty ? '02' : _grade.text.trim(),
        menuTypes: _cfg.provider == 'schoolcafe' && _cfg.menuTypes.isEmpty
            ? const [('Breakfast', 'Breakfast'), ('Lunch', 'Lunch')]
            : _cfg.menuTypes,
        district: _district.text.trim().toLowerCase(),
        calendarUrl: _calendar.text.trim(),
        startTime: start,
        endTime: end,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _filter.text.trim().toLowerCase();
    final schools = [
      for (final s in _schools ?? const <SchoolChoice>[])
        if (q.isEmpty || s.name.toLowerCase().contains(q)) s,
    ];
    return AlertDialog(
      title: const Text('Set up school'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'schoolcafe', label: Text('SchoolCafe (Frisco ISD)')),
                  ButtonSegment(value: 'nutrislice', label: Text('Nutrislice')),
                ],
                selected: {_cfg.provider},
                onSelectionChanged: (v) => setState(() {
                  _cfg = _cfg.copyWith(provider: v.first, menuTypes: const []);
                  _schools = null;
                }),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _district,
                      decoration: InputDecoration(
                        labelText: 'School district',
                        helperText: _cfg.provider == 'schoolcafe'
                            ? 'friscoisd for Frisco ISD on schoolcafe.com'
                            : 'friscoisd for friscoisd.nutrislice.com',
                      ),
                      onSubmitted: (_) => unawaited(_loadSchools()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => unawaited(_loadSchools()),
                    child: const Text('Load schools'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'School name',
                  helperText:
                      'Shown on Phoenix Home. Pick the school below for its menus.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _filter,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search schools',
                ),
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(
                height: 200,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        children: [
                          for (final s in schools)
                            ListTile(
                              dense: true,
                              selected: s.slug == _cfg.schoolSlug,
                              title: Text(s.name),
                              subtitle: Text(
                                s.menuTypes.map((m) => m.$2).join(', '),
                              ),
                              onTap: () => setState(() {
                                // Breakfast and lunch when the school has
                                // them, else every menu it offers.
                                final picked = [
                                  for (final m in s.menuTypes)
                                    if (m.$1.contains('breakfast') ||
                                        m.$1.contains('lunch'))
                                      m,
                                ];
                                _name.text = s.name;
                                _schoolId.text = s.slug;
                                _cfg = _cfg.copyWith(
                                  schoolSlug: s.slug,
                                  schoolName: s.name,
                                  menuTypes: picked.isEmpty
                                      ? s.menuTypes
                                      : picked,
                                );
                              }),
                            ),
                        ],
                      ),
              ),
              if (_cfg.provider == 'schoolcafe') ...[
                TextField(
                  controller: _schoolId,
                  decoration: const InputDecoration(
                    labelText: 'SchoolCafe school ID',
                    helperText:
                        'Filled in when you pick the school above. If the list does not load, paste the '
                        'SchoolId from your Home Assistant SchoolCafe setup (it looks like 1a2b3c4d-...).',
                    helperMaxLines: 3,
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _line,
                        decoration: const InputDecoration(labelText: 'Serving line', hintText: 'Main Line'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _grade,
                        decoration: const InputDecoration(labelText: 'Grade', hintText: '02'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (_cfg.schoolSlug.isNotEmpty) ...[
                Text(
                  'Menus to show',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in (_schools ?? const <SchoolChoice>[]).where(
                      (s) => s.slug == _cfg.schoolSlug,
                    ))
                      for (final m in s.menuTypes)
                        FilterChip(
                          label: Text(m.$2),
                          selected: _cfg.menuTypes.any((t) => t.$1 == m.$1),
                          onSelected: (on) => setState(() {
                            final next = [..._cfg.menuTypes]
                              ..removeWhere((t) => t.$1 == m.$1);
                            if (on) next.add(m);
                            _cfg = _cfg.copyWith(menuTypes: next);
                          }),
                        ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _calendar,
                decoration: const InputDecoration(
                  labelText: 'School calendar',
                  helperText:
                      "The district calendar's iCal (.ics) or Subscribe link, or a Home Assistant "
                      'calendar such as calendar.frisco_isd.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _start,
                      decoration: const InputDecoration(
                        labelText: 'School starts',
                        hintText: '7:50 AM',
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _end,
                      decoration: const InputDecoration(
                        labelText: 'School ends',
                        hintText: '3:05 PM',
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => unawaited(_save()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The next day with a menu: today, or the next school day (on a weekend
/// or after a holiday).
DateTime nextMenuDay(SchoolService school) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  for (var i = 0; i < 10; i++) {
    final d = today.add(Duration(days: i));
    if (d.weekday > DateTime.friday) continue;
    for (final (slug, _) in school.config.value.menuTypes) {
      if (!(school.menuOn(slug, d)?.isEmpty ?? true)) return d;
    }
  }
  return today;
}

/// Today's (or the next school day's) menus in full, every section open.
class _TodayMenu extends StatelessWidget {
  const _TodayMenu({required this.school});
  final SchoolService school;

  @override
  Widget build(BuildContext context) {
    final day = nextMenuDay(school);
    final isToday = _sameDay(day, DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1C2028),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.restaurant_rounded, color: Phx.ember),
                const SizedBox(width: 10),
                Text(
                  isToday
                      ? "Today's menu"
                      : 'Menu for ${DateFormat('EEEE, MMM d').format(day)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () =>
                      unawaited(showSchoolDay(context, school, day)),
                  icon: const Icon(Icons.open_in_full_rounded),
                  label: const Text('Full day'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 32,
              runSpacing: 16,
              children: [
                for (final (slug, name) in school.config.value.menuTypes)
                  SizedBox(
                    width: 340,
                    child: _MenuList(
                      title: name,
                      day: school.menuOn(slug, day),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One menu of one day, every section and item.
class _MenuList extends StatelessWidget {
  const _MenuList({required this.title, required this.day});
  final String title;
  final MenuDay? day;

  @override
  Widget build(BuildContext context) {
    final d = day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: Phx.gold,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        if (d == null || d.isEmpty)
          const Text(
            'No menu published',
            style: TextStyle(color: Colors.white54),
          )
        else
          for (final (heading, items) in d.sections) ...[
            if (heading.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Text(
                  heading,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• $item',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
          ],
      ],
    );
  }
}

/// A day in full: its events (no school, early release, anything else) and
/// every menu.
Future<void> showSchoolDay(
  BuildContext context,
  SchoolService school,
  DateTime day,
) => showDialog<void>(
  context: context,
  builder: (dialog) {
    final events = school.eventsOn(day);
    return AlertDialog(
      backgroundColor: const Color(0xFF181B21),
      title: Text(
        DateFormat('EEEE, MMMM d').format(day),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (day.weekday > DateTime.friday)
                const Text(
                  'Weekend: no school',
                  style: TextStyle(color: Phx.gold, fontSize: 16),
                ),
              for (final e in events)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    e.noSchool
                        ? Icons.beach_access_rounded
                        : (e.earlyRelease
                              ? Icons.directions_run_rounded
                              : Icons.event_rounded),
                    color: e.noSchool ? Phx.gold : Colors.white70,
                  ),
                  title: Text(
                    e.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: e.allDay
                      ? null
                      : Text(
                          DateFormat.jm().format(e.start),
                          style: const TextStyle(color: Colors.white54),
                        ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 32,
                runSpacing: 16,
                children: [
                  for (final (slug, name) in school.config.value.menuTypes)
                    SizedBox(
                      width: 280,
                      child: _MenuList(
                        title: name,
                        day: school.menuOn(slug, day),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Close'),
        ),
      ],
    );
  },
);

/// The month: each school day with its lunch and its events (the student
/// calendar), weekends dimmed, days off marked. Tap a day for all of it.
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.school,
    required this.month,
    required this.onMonth,
  });
  final SchoolService school;
  final DateTime month;
  final ValueChanged<DateTime> onMonth;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final lead = first.weekday % 7; // Sunday first
    final days = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((lead + days) / 7).ceil() * 7;
    final lunch =
        [
          for (final t in school.config.value.menuTypes)
            if (t.$1.contains('lunch')) t.$1,
        ].firstOrNull ??
        school.config.value.menuTypes.firstOrNull?.$1;
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                color: Colors.white,
                onPressed: () => onMonth(DateTime(month.year, month.month - 1)),
                icon: const Icon(Icons.chevron_left_rounded, size: 32),
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(month),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                color: Colors.white,
                onPressed: () => onMonth(DateTime(month.year, month.month + 1)),
                icon: const Icon(Icons.chevron_right_rounded, size: 32),
              ),
            ],
          ),
          Row(
            children: [
              for (final d in const [
                'Sun',
                'Mon',
                'Tue',
                'Wed',
                'Thu',
                'Fri',
                'Sat',
              ])
                Expanded(
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final rows = cells ~/ 7;
                final h = (box.maxHeight - (rows - 1) * 6) / rows;
                return Column(
                  children: [
                    for (var r = 0; r < rows; r++)
                      Padding(
                        padding: EdgeInsets.only(top: r == 0 ? 0 : 6),
                        child: SizedBox(
                          height: h,
                          child: Row(
                            children: [
                              for (var c = 0; c < 7; c++)
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: c == 0 ? 0 : 6,
                                    ),
                                    child: _dayCell(
                                      context,
                                      r * 7 + c - lead + 1,
                                      days,
                                      lunch,
                                      now,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayCell(
    BuildContext context,
    int n,
    int days,
    String? lunch,
    DateTime now,
  ) {
    if (n < 1 || n > days) return const SizedBox.shrink();
    final day = DateTime(month.year, month.month, n);
    final weekend = day.weekday > DateTime.friday;
    final events = school.eventsOn(day);
    final off = events.any((e) => e.noSchool);
    final menu = lunch == null ? null : school.menuOn(lunch, day);
    final today = _sameDay(day, now);
    return Material(
      color: off
          ? const Color(0xFF3A2A0E)
          : weekend
          ? const Color(0xFF14161B)
          : const Color(0xFF1C2028),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => unawaited(showSchoolDay(context, school, day)),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: today ? Phx.ember : Colors.transparent,
              width: 2,
            ),
          ),
          child: ClipRect(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$n',
                  style: TextStyle(
                    color: today
                        ? Phx.gold
                        : (weekend ? Colors.white38 : Colors.white),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                for (final e in events.take(2))
                  Text(
                    e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: e.noSchool ? Phx.gold : const Color(0xFF8FB8FF),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (!off && menu != null && !menu.isEmpty)
                  Text(
                    menu.items.first,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Phoenix Home's School tile: a pop-up with today at school (status, bell
/// times, events, every menu in full) and the way to the calendar.
Future<void> showTodayAtSchool(BuildContext context, AppContainer c) {
  final home = c.phoenixHome;
  final school = home.school;
  final cfg = school.config.value;
  if (!cfg.hasMenu && cfg.calendarUrl.isEmpty) {
    home.openSchool();
    return Future.value();
  }
  return showDialog<void>(
    context: context,
    builder: (dialog) => ListenableBuilder(
      listenable: Listenable.merge([school.menus, school.events]),
      builder: (context, _) {
        final day = nextMenuDay(school);
        return AlertDialog(
          backgroundColor: const Color(0xFF181B21),
          title: Row(
            children: [
              const Icon(Icons.school_rounded, color: Phx.ember),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  cfg.schoolName.isEmpty ? 'School' : cfg.schoolName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusCard(school: school),
                  const SizedBox(height: 14),
                  Text(
                    _sameDay(day, DateTime.now())
                        ? "Today's menu"
                        : 'Next school day: ${DateFormat('EEEE, MMM d').format(day)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 32,
                    runSpacing: 16,
                    children: [
                      for (final (slug, name) in cfg.menuTypes)
                        SizedBox(
                          width: 300,
                          child: _MenuList(
                            title: name,
                            day: school.menuOn(slug, day),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Phx.ember,
                foregroundColor: const Color(0xFF2A0A00),
              ),
              onPressed: () {
                Navigator.pop(dialog);
                home.openSchool();
              },
              icon: const Icon(Icons.calendar_month_rounded),
              label: const Text('Week & calendar'),
            ),
          ],
        );
      },
    ),
  );
}
