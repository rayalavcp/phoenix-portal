import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_container.dart';
import '../../core/command_registry.dart';
import '../../managers/home/panchang.dart';
import '../../managers/home/phoenix_home_manager.dart';
import '../../managers/home/school_service.dart';
import '../../managers/home/telugu_words.dart';
import '../theme.dart';
import '../toast.dart';
import '../settings_screen.dart' show pickDrawerMenuItems;
import 'home_glass.dart';
import 'live_cameras.dart';
import 'home_themes.dart';
import 'phoenix_home.dart' show weatherIcon, weatherWords;
import 'photo_frame.dart';
import 'school_page.dart';
import 'weather_backdrop.dart';

/// The Today screen. The wallpaper (Bing's 4K photos, your own photos, or a
/// link) fills the screen under live weather; the time and the weather sit
/// right on it; a short column of glance cards (camera, up next, school, a
/// Telugu word) on the right; a floating dock of big buttons at the bottom.
class TodayHome extends StatefulWidget {
  const TodayHome({super.key, required this.container, required this.onOpenMenu, required this.onOpenSettings});

  final AppContainer container;
  final VoidCallback onOpenMenu;
  final VoidCallback onOpenSettings;

  @override
  State<TodayHome> createState() => _TodayHomeState();
}

class _TodayHomeState extends State<TodayHome> {
  AppContainer get c => widget.container;
  late DateTime _now = DateTime.now();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  // Repaint on the minute: the clock, the greeting, the school status.
  void _schedule() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    _tick = Timer(next.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// The Portal's own calling (WhatsApp, Messenger, contacts) lives in
  /// Meta's stock home, which only lets itself open it: this deep link
  /// brings its Home tab (the calling screen) forward, the way Immortal's
  /// Calls tile did.
  Future<void> _openCalls() async {
    final overlay = Overlay.maybeOf(context);
    final result = await c.commands.execute('openUri', const {'uri': 'portal://launcher/home'});
    if ((!result.ok || result.data == false) && overlay != null && overlay.mounted) {
      showToastIn(overlay, title: 'Calls are not available', message: "This device has no Portal calling app.", kind: ToastKind.error);
    }
  }

  Future<void> _command(String name, String what) async {
    final overlay = Overlay.maybeOf(context);
    final CommandResult result = await c.commands.execute(name, const {});
    if (!result.ok && overlay != null && overlay.mounted) {
      showToastIn(overlay, title: "Couldn't open $what", message: result.error, kind: ToastKind.error);
    }
  }

  Future<void> _openPhotos() async {
    if (!c.phoenixHome.photos.configured) return showPhotoSetup(context, c);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (route) => GestureDetector(
          onTap: () => Navigator.pop(route),
          child: PhoenixPhotoFrame(container: c),
        ),
      ),
    );
  }

  double? _swipeFrom;

  @override
  Widget build(BuildContext context) {
    final home = c.phoenixHome;
    return ListenableBuilder(
      listenable: Listenable.merge([home.weather, home.weatherEffects, home.weatherDemo, home.cameraEntities, home.glassOpacity, home.telugu]),
      builder: (context, _) {
        final w = home.weather.value;
        final demo = home.weatherDemo.value;
        // A swipe to the right opens Smart Home (the Home Assistant
        // dashboard, or whatever the Smart Home button opens). Not from
        // the very left edge, which pulls out the menu; the camera card's
        // own swipes win over this one.
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (d) => _swipeFrom = d.globalPosition.dx,
          onHorizontalDragEnd: (d) {
            final from = _swipeFrom;
            _swipeFrom = null;
            if (isSmartHomeSwipe(from, d.primaryVelocity)) home.openSmartHomeButton();
          },
          child: GlassScope(
            opacity: home.glassOpacity.value,
            child: Stack(
              fit: StackFit.expand,
              children: [
                HomeWallpaper(container: c),
                if (home.weatherEffects.value && (w != null || demo.isNotEmpty))
                  WeatherBackdrop(code: w?.code, isDay: w?.isDay ?? (_now.hour >= 7 && _now.hour < 18), demo: demo, sunrise: w?.sunrise, sunset: w?.sunset),
                // Shade behind the text, so it reads over any photo.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0x8C000000), Color(0x26000000), Color(0x00000000), Color(0x40000000)],
                      stops: [0, 0.4, 0.6, 1],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x33000000), Color(0x00000000), Color(0x00000000), Color(0x8C000000)],
                      stops: [0, 0.25, 0.7, 1],
                    ),
                  ),
                ),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final wide = box.maxWidth >= 860 && box.maxWidth > box.maxHeight;
                      final pad = box.maxWidth < 700 ? 16.0 : 28.0;
                      final dock = _Dock(
                        container: c,
                        onKids: () => unawaited(_command('openKids', 'the Kids Portal')),
                        onCalls: () => unawaited(_openCalls()),
                        onPhotos: () => unawaited(_openPhotos()),
                        onOpenSettings: widget.onOpenSettings,
                      );
                      final buttons = _TopButtons(
                        onNight: () => unawaited(_command('startScreensaver', 'the screensaver')),
                        onCustomize: () => unawaited(showTodaySetup(context, c)),
                        onOpenMenu: widget.onOpenMenu,
                      );
                      if (wide) {
                        return Padding(
                          padding: EdgeInsets.fromLTRB(pad, 18, pad, 14),
                          child: Column(
                            children: [
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: _Hero(container: c, now: _now, big: box.maxHeight >= 640),
                                    ),
                                    const SizedBox(width: 24),
                                    SizedBox(
                                      width: (box.maxWidth * 0.32).clamp(320.0, 440.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Align(alignment: Alignment.centerRight, child: buttons),
                                          const SizedBox(height: 12),
                                          Expanded(
                                            child: _GlanceColumn(container: c, now: _now),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              dock,
                            ],
                          ),
                        );
                      }
                      return Padding(
                        padding: EdgeInsets.fromLTRB(pad, 12, pad, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(alignment: Alignment.centerRight, child: buttons),
                            Expanded(
                              child: ListView(
                                padding: EdgeInsets.zero,
                                children: [
                                  _Hero(container: c, now: _now, big: false),
                                  const SizedBox(height: 18),
                                  if (home.cameraEntities.value.isNotEmpty && home.homeAssistantConfigured) ...[
                                    SizedBox(
                                      height: 220,
                                      child: LiveCamerasCard(
                                        key: ValueKey(home.cameraEntities.value.join(',')),
                                        container: c,
                                        entities: home.cameraEntities.value,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  SizedBox(
                                    height: 230,
                                    child: _UpNextCard(container: c, now: _now),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    height: 280,
                                    child: _SchoolCard(container: c, now: _now),
                                  ),
                                  const SizedBox(height: 12),
                                  if (home.telugu.value) ...[
                                    SizedBox(
                                      height: 120,
                                      child: _WordCard(now: _now, onTap: home.openTelugu),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            dock,
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
      },
    );
  }
}

// ── Building blocks ───────────────────────────────────────────────────────

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.icon, this.text);

  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: Phx.gold, size: 17),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.3),
        ),
      ),
    ],
  );
}

const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 18), Shadow(color: Color(0x66000000), blurRadius: 4)];

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _whenDays(int days) => days == 0
    ? 'today'
    : days == 1
    ? 'tomorrow'
    : 'in $days days';

class _TopButtons extends StatelessWidget {
  const _TopButtons({required this.onNight, required this.onCustomize, required this.onOpenMenu});

  final VoidCallback onNight;
  final VoidCallback onCustomize;
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (icon, tip, onTap) in [
        (Icons.bedtime_rounded, 'Night mode', onNight),
        (Icons.tune_rounded, 'Customize home', onCustomize),
        (Icons.menu_rounded, 'Menu', onOpenMenu),
      ])
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Tooltip(
            message: tip,
            child: Glass(
              blur: false,
              radius: 40,
              onTap: onTap,
              padding: const EdgeInsets.all(11),
              child: Icon(icon, color: Colors.white, size: 23),
            ),
          ),
        ),
    ],
  );
}

// ── Hero: time, date, weather, festival and moon, right on the photo ──────

class _Hero extends StatelessWidget {
  const _Hero({required this.container, required this.now, required this.big});

  final AppContainer container;
  final DateTime now;
  final bool big;

  String get _greeting => switch (now.hour) {
    < 5 => 'Good night',
    < 12 => 'Good morning',
    < 17 => 'Good afternoon',
    < 21 => 'Good evening',
    _ => 'Good night',
  };

  @override
  Widget build(BuildContext context) {
    final home = container.phoenixHome;
    final h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final time = DateFormat(h24 ? 'HH:mm' : 'h:mm').format(now);
    final period = h24 ? '' : DateFormat('a').format(now);
    final w = home.weather.value;
    final calc = home.panchang;
    final today = calc.day(now);
    final midnight = DateTime(now.year, now.month, now.day);
    final festival = today.festivals.isNotEmpty ? (midnight, today.festivals.first) : calc.upcoming(midnight.add(const Duration(days: 1)), 60).firstOrNull;
    final (phase, lit) = moonPhase(now);
    final paksha = today.amavasya ? '' : (today.shukla ? 'Shukla ' : 'Krishna ');

    final clockSize = big ? 150.0 : 108.0;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _greeting,
          style: const TextStyle(color: Phx.gold, fontSize: 22, fontWeight: FontWeight.w600, shadows: _shadow),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                time,
                style: TextStyle(color: Colors.white, fontSize: clockSize, fontWeight: FontWeight.w200, letterSpacing: -4, height: 1.02, shadows: _shadow),
              ),
              if (period.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(
                  period,
                  style: TextStyle(color: Colors.white70, fontSize: clockSize * 0.24, fontWeight: FontWeight.w500, shadows: _shadow),
                ),
              ],
            ],
          ),
        ),
        Text(
          DateFormat('EEEE, MMMM d').format(now),
          style: TextStyle(color: Colors.white, fontSize: big ? 26 : 21, fontWeight: FontWeight.w500, shadows: _shadow),
        ),
        SizedBox(height: big ? 22 : 14),
        if (w != null) ...[
          GestureDetector(
            onTap: () => unawaited(home.refreshWeather()),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  weatherIcon(w.code, day: w.isDay),
                  color: Phx.gold,
                  size: big ? 54 : 44,
                  shadows: _shadow,
                ),
                const SizedBox(width: 12),
                Text(
                  '${w.temperature.round()}°',
                  style: TextStyle(color: Colors.white, fontSize: big ? 58 : 46, fontWeight: FontWeight.w300, height: 1, shadows: _shadow),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      weatherWords(w.code),
                      style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600, shadows: _shadow),
                    ),
                    Text(
                      [if (w.days.isNotEmpty) 'H ${w.days.first.high.round()}°  L ${w.days.first.low.round()}°', if (w.place.isNotEmpty) w.place].join('  ·  '),
                      style: const TextStyle(color: Colors.white70, fontSize: 14.5, shadows: _shadow),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (w.days.length > 1) ...[
            const SizedBox(height: 14),
            Glass(
              blur: false,
              radius: 20,
              lighter: true,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final d in w.days.skip(1).take(5))
                    SizedBox(
                      width: big ? 82 : 66,
                      child: Column(
                        children: [
                          Text(
                            DateFormat('EEE').format(d.date),
                            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Icon(weatherIcon(d.code), color: Colors.white, size: 24),
                          const SizedBox(height: 4),
                          Text(
                            '${d.high.round()}°  ${d.low.round()}°',
                            style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ] else
          ValueListenableBuilder(
            valueListenable: home.weatherProblem,
            builder: (context, problem, _) => problem == null
                ? const SizedBox.shrink()
                : TextButton.icon(
                    onPressed: () => unawaited(home.refreshWeather()),
                    icon: const Icon(Icons.cloud_off_rounded, color: Colors.white54),
                    label: Text(problem, style: const TextStyle(color: Colors.white54)),
                  ),
          ),
        SizedBox(height: big ? 22 : 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            if (festival != null && home.telugu.value)
              _Pill(
                icon: Icons.celebration_rounded,
                text: '${festival.$2.split(' (').first} ${_whenDays(festival.$1.difference(midnight).inDays)}',
                onTap: home.openTelugu,
              ),
            home.telugu.value
                ? _Pill(icon: Icons.brightness_2_rounded, text: '$phase · $lit% · $paksha${today.tithiNameEn}', onTap: home.openTelugu)
                : _Pill(icon: Icons.brightness_2_rounded, text: '$phase · $lit%'),
          ],
        ),
      ],
    );
    return big
        ? Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(child: content),
          )
        : content;
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Glass(
    blur: false,
    radius: 40,
    lighter: true,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Phx.gold),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

// ── Glance cards ──────────────────────────────────────────────────────────

class _GlanceColumn extends StatelessWidget {
  const _GlanceColumn({required this.container, required this.now});

  final AppContainer container;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final home = container.phoenixHome;
    final camera = home.cameraEntities.value.isNotEmpty && home.homeAssistantConfigured;
    const gap = SizedBox(height: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (camera) ...[
          Expanded(
            flex: 4,
            child: LiveCamerasCard(key: ValueKey(home.cameraEntities.value.join(',')), container: container, entities: home.cameraEntities.value),
          ),
          gap,
        ],
        Expanded(
          flex: camera ? 3 : 4,
          child: _UpNextCard(container: container, now: now),
        ),
        gap,
        Expanded(
          flex: 5,
          child: _SchoolCard(container: container, now: now),
        ),
        if (!camera && home.telugu.value) ...[
          gap,
          SizedBox(
            height: 96,
            child: _WordCard(now: now, onTap: home.openTelugu),
          ),
        ],
      ],
    );
  }
}

// Up next ----------------------------------------------------------------

class _UpNextItem {
  const _UpNextItem(this.start, this.title, this.allDay, this.icon);
  final DateTime start;
  final String title;
  final bool allDay;
  final IconData icon;
}

class _UpNextCard extends StatefulWidget {
  const _UpNextCard({required this.container, required this.now});

  final AppContainer container;
  final DateTime now;

  @override
  State<_UpNextCard> createState() => _UpNextCardState();
}

class _UpNextCardState extends State<_UpNextCard> {
  List<_UpNextItem> _family = const [];
  DateTime? _loaded;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_UpNextCard old) {
    super.didUpdateWidget(old);
    // The family calendar, every 15 minutes.
    if (_loaded == null || widget.now.difference(_loaded!).inMinutes >= 15) unawaited(_load());
  }

  Future<void> _load() async {
    final c = widget.container;
    _loaded = DateTime.now();
    if (!c.phoenixHome.homeAssistantConfigured || c.calendar.enabled.isEmpty) return;
    try {
      final from = DateTime.now();
      final all = await c.calendar.readEvents(from, from.add(const Duration(days: 7)));
      final items = [
        for (final list in all.values)
          for (final e in list)
            if (e.end.isAfter(from)) _UpNextItem(e.start, e.summary, e.allDay, Icons.event_rounded),
      ];
      if (mounted) setState(() => _family = items);
    } catch (_) {
      // Home Assistant unreachable: school and festivals still show.
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.container.phoenixHome;
    final now = widget.now;
    final midnight = DateTime(now.year, now.month, now.day);
    return ValueListenableBuilder(
      valueListenable: home.school.events,
      builder: (context, schoolEvents, _) {
        final items = <_UpNextItem>[
          ..._family,
          for (final e in schoolEvents)
            if (!e.end.isBefore(midnight) && e.start.isBefore(midnight.add(const Duration(days: 14))))
              _UpNextItem(e.start.isBefore(midnight) ? midnight : e.start, e.title, e.allDay, Icons.school_rounded),
          if (home.telugu.value)
            for (final (d, f) in home.panchang.upcoming(midnight, 21)) _UpNextItem(d, f.split(' (').first, true, Icons.celebration_rounded),
        ]..sort((a, b) => a.start.compareTo(b.start));
        return Glass(
          onTap: () => unawaited(widget.container.commands.execute('openCalendar', const {})),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _CardTitle(Icons.event_note_rounded, 'Up next'),
              const SizedBox(height: 4),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text('Nothing coming up', style: TextStyle(color: Colors.white54)),
                      )
                    : LayoutBuilder(
                        builder: (context, box) {
                          final fit = (box.maxHeight / 40).floor().clamp(1, 6);
                          return Column(children: [for (final e in items.take(fit)) _row(e, midnight)]);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(_UpNextItem e, DateTime midnight) {
    final day = DateTime(e.start.year, e.start.month, e.start.day);
    final days = day.difference(midnight).inDays;
    final when = days == 0
        ? (e.allDay ? 'Today' : DateFormat.jm().format(e.start))
        : days == 1
        ? (e.allDay ? 'Tomorrow' : 'Tmrw ${DateFormat.jm().format(e.start)}')
        : DateFormat(days < 7 ? 'EEE' : 'MMM d').format(e.start);
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Icon(e.icon, size: 19, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              e.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            when,
            style: TextStyle(color: days == 0 ? Phx.gold : Colors.white60, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// Camera -----------------------------------------------------------------

// School -----------------------------------------------------------------

/// The next day there is school on or after [from].
DateTime? nextSchoolDay(SchoolService school, DateTime from) {
  final start = DateTime(from.year, from.month, from.day);
  for (var i = 0; i < 40; i++) {
    final d = start.add(Duration(days: i));
    if (d.weekday > DateTime.friday) continue;
    if (school.eventsOn(d).any((e) => e.noSchool)) continue;
    return d;
  }
  return null;
}

class _SchoolCard extends StatelessWidget {
  const _SchoolCard({required this.container, required this.now});

  final AppContainer container;
  final DateTime now;

  MenuDay? _lunch(SchoolService school, DateTime day) {
    final types = school.config.value.menuTypes;
    for (final (slug, _) in types) {
      if (slug.toLowerCase().contains('lunch')) return school.menuOn(slug, day);
    }
    return types.isEmpty ? null : school.menuOn(types.last.$1, day);
  }

  @override
  Widget build(BuildContext context) {
    final home = container.phoenixHome;
    final school = home.school;
    return ListenableBuilder(
      listenable: Listenable.merge([school.config, school.menus, school.events]),
      builder: (context, _) {
        final cfg = school.config.value;
        final midnight = DateTime(now.year, now.month, now.day);
        final schoolToday = now.weekday <= DateTime.friday && !school.eventsOn(now).any((e) => e.noSchool);
        final status = school.status(now);
        final next = nextSchoolDay(school, midnight.add(const Duration(days: 1)));
        // After school, show the next school day's menu; before and during, today's.
        final out = status == 'School is out for today';
        final menuDay = schoolToday && !out ? midnight : (next ?? midnight);
        final lunch = _lunch(school, menuDay);
        final dayName = _sameDay(menuDay, midnight)
            ? "Today's"
            : _sameDay(menuDay, midnight.add(const Duration(days: 1)))
            ? "Tomorrow's"
            : "${DateFormat('EEE').format(menuDay)}'s";
        final monday = midnight.subtract(Duration(days: midnight.weekday - 1)).add(Duration(days: now.weekday > DateTime.friday ? 7 : 0));
        return Glass(
          onTap: home.openSchool,
          child: LayoutBuilder(
            builder: (context, box) {
              final roomy = box.maxHeight >= 220;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CardTitle(Icons.school_rounded, cfg.schoolName.isEmpty ? 'School' : cfg.schoolName),
                  const SizedBox(height: 8),
                  Text(
                    schoolToday ? status : (now.weekday > DateTime.friday ? 'No school · Weekend' : status),
                    maxLines: roomy ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, height: 1.2),
                  ),
                  if (!schoolToday && next != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'Back ${DateFormat('EEE M/d').format(next)} · ${_whenDays(next.difference(midnight).inDays)}',
                        style: const TextStyle(color: Phx.gold, fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => unawaited(showTodayAtSchool(context, container)),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                        child: lunch == null || lunch.isEmpty
                            ? Row(
                                children: [
                                  const Icon(Icons.restaurant_rounded, color: Colors.white54, size: 19),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      school.problem.value != null && school.menus.value.isEmpty
                                          ? 'Menu: ${school.problem.value}'
                                          : '$dayName menu not posted yet',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white70, fontSize: 13.5),
                                    ),
                                  ),
                                ],
                              )
                            : LayoutBuilder(
                                builder: (context, box) {
                                  final lines = ((box.maxHeight - 20) / 19).floor().clamp(1, 6);
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$dayName lunch',
                                        style: const TextStyle(color: Phx.gold, fontSize: 12.5, fontWeight: FontWeight.w700),
                                      ),
                                      for (final item in lunch.items.take(lines))
                                        Text(
                                          '• $item',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35),
                                        ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                  if (roomy) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [for (var i = 0; i < 5; i++) Expanded(child: _weekDay(school, monday.add(Duration(days: i)), midnight))],
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _weekDay(SchoolService school, DateTime d, DateTime today) {
    final off = school.eventsOn(d).any((e) => e.noSchool);
    final isToday = _sameDay(d, today);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: isToday ? Phx.ember.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        children: [
          Text(
            DateFormat('EEE').format(d),
            style: TextStyle(color: isToday ? const Color(0xFF2A0A00) : Colors.white60, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          Text(
            '${d.day}',
            style: TextStyle(color: isToday ? const Color(0xFF2A0A00) : Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(color: off ? Colors.white24 : const Color(0xFF7BD88F), shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

// Telugu word ------------------------------------------------------------

class _WordCard extends StatelessWidget {
  const _WordCard({required this.now, required this.onTap});

  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = teluguWordOfTheDay(now);
    return Glass(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'TELUGU WORD OF THE DAY',
                  style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    w.telugu,
                    style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w700, height: 1.15),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                w.say,
                style: const TextStyle(color: Phx.gold, fontSize: 17, fontWeight: FontWeight.w700),
              ),
              Text(w.meaning, style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Dock ──────────────────────────────────────────────────────────────────

class _Dock extends StatelessWidget {
  const _Dock({required this.container, required this.onKids, required this.onCalls, required this.onPhotos, required this.onOpenSettings});

  final AppContainer container;
  final VoidCallback onKids;
  final VoidCallback onCalls;
  final VoidCallback onPhotos;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final home = container.phoenixHome;
    final items = <(IconData, String, VoidCallback, bool)>[
      (Icons.child_care_rounded, 'Kids Portal', onKids, true),
      (Icons.home_work_rounded, 'Smart Home', home.openSmartHomeButton, true),
      (Icons.call_rounded, 'Calls', onCalls, false),
      (Icons.apps_rounded, 'Apps', () => home.appsOpen.value = true, false),
      (Icons.school_rounded, 'School', home.openSchool, false),
      home.telugu.value
          ? (Icons.brightness_5_rounded, 'Calendar', home.openTelugu, false)
          : (Icons.calendar_month_rounded, 'Calendar', () => unawaited(container.commands.execute('openCalendar', const {})), false),
      (Icons.photo_library_rounded, 'Photos', onPhotos, false),
      (Icons.settings_rounded, 'Settings', onOpenSettings, false),
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Glass(
          radius: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: LayoutBuilder(
            builder: (context, box) {
              final labels = box.maxWidth >= 600;
              return Row(
                children: [
                  for (final (icon, label, onTap, primary) in items)
                    Expanded(
                      flex: primary ? 4 : 3,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Tooltip(
                          message: label,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(22),
                            onTap: onTap,
                            child: Ink(
                              height: 60,
                              // The two main doors stand out by a soft tint
                              // of glass, not a loud fill.
                              decoration: primary
                                  ? BoxDecoration(
                                      color: label == 'Kids Portal' ? const Color(0x339A8CE8) : const Color(0x33DB7B4E),
                                      border: Border.all(
                                        color: label == 'Kids Portal' ? const Color(0x66B3A8F0) : const Color(0x66E9A27E),
                                      ),
                                      borderRadius: BorderRadius.circular(22),
                                    )
                                  : null,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    icon,
                                    color: !primary ? Colors.white : (label == 'Kids Portal' ? const Color(0xFFCFC7FA) : const Color(0xFFF2C3A8)),
                                    size: primary ? 26 : 24,
                                  ),
                                  if (labels)
                                    Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: primary ? Colors.white : Colors.white70,
                                        fontSize: 12,
                                        fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Customize ─────────────────────────────────────────────────────────────

/// The Today screen's own settings: wallpaper, weather, Smart Home, layout,
/// colours and the camera.
Future<void> showTodaySetup(BuildContext context, AppContainer c) {
  final home = c.phoenixHome;
  final camera = TextEditingController(text: home.cameraEntities.value.join(', '));
  final trigger = TextEditingController(text: home.doorbellTrigger.value);
  final link = TextEditingController(text: home.wallpaperUrl.value);
  final haPage = TextEditingController(text: home.smartHomePage);
  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
  );
  return showDialog<void>(
    context: context,
    builder: (dialog) => ListenableBuilder(
      listenable: Listenable.merge([
        home.layout,
        home.theme,
        home.weatherEffects,
        home.weatherDemo,
        home.wallpaper,
        home.wallpaperUrl,
        home.smartHomeTarget,
        home.glassOpacity,
        home.telugu,
      ]),
      builder: (dialog, _) => AlertDialog(
        title: const Text('Customize home'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading('Wallpaper'),
                WallpaperPicker(container: c),
                if (home.wallpaper.value == 'photos' && !home.photos.configured)
                  TextButton(onPressed: () => unawaited(showPhotoSetup(dialog, c)), child: const Text('Set up Immich or a network folder')),
                if (home.wallpaper.value == 'url' && !home.wallpaperUrl.value.startsWith('/th?'))
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: link,
                          decoration: const InputDecoration(labelText: 'Image link (JPG or PNG)', hintText: 'http://tower/wallpapers/lake.jpg'),
                        ),
                      ),
                      TextButton(
                        onPressed: () => unawaited(home.setWallpaper('url', url: link.text)),
                        child: const Text('Use'),
                      ),
                    ],
                  ),
                heading('Glass'),
                Row(
                  children: [
                    const Text('Clear'),
                    Expanded(
                      child: Slider(
                        value: home.glassOpacity.value,
                        divisions: 20,
                        label: '${(home.glassOpacity.value * 100).round()}%',
                        onChanged: (v) => home.glassOpacity.value = v,
                        onChangeEnd: (v) => unawaited(home.setGlassOpacity(v)),
                      ),
                    ),
                    const Text('Frosted'),
                  ],
                ),
                heading('Weather'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Live weather over the wallpaper'),
                  subtitle: const Text('Rain, snow, storms, fog, sun rays, clouds and stars'),
                  value: home.weatherEffects.value,
                  onChanged: (v) => unawaited(home.setWeatherEffects(v)),
                ),
                const Text('Try an effect now (until you leave this screen):', style: TextStyle(fontSize: 12.5)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (id, label) in const [
                      ('', 'Real weather'),
                      ('clear', 'Sun'),
                      ('clouds', 'Clouds'),
                      ('rain', 'Rain'),
                      ('storm', 'Storm'),
                      ('snow', 'Snow'),
                      ('fog', 'Fog'),
                    ])
                      ChoiceChip(label: Text(label), selected: home.weatherDemo.value == id, onSelected: (_) => home.weatherDemo.value = id),
                  ],
                ),
                heading('Telugu calendar'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show the Telugu calendar'),
                  subtitle: const Text('Word of the day, festivals, tithi, and the Calendar button opens it'),
                  value: home.telugu.value,
                  onChanged: (v) => unawaited(home.setTelugu(v)),
                ),
                heading('Smart Home button'),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ha', icon: Icon(Icons.web_rounded), label: Text('Home Assistant')),
                    ButtonSegment(value: 'phoenix', icon: Icon(Icons.toggle_on_rounded), label: Text('Phoenix controls')),
                  ],
                  selected: {home.smartHomeTarget.value},
                  onSelectionChanged: (s) => unawaited(home.setSmartHomeTarget(s.first)),
                ),
                if (home.smartHomeTarget.value == 'ha')
                  TextField(
                    controller: haPage,
                    decoration: const InputDecoration(
                      labelText: 'Home Assistant page it opens',
                      hintText: 'http://homeassistant.local:8123/lovelace/home',
                      helperText: 'Your dashboard or your own HTML page in Home Assistant.',
                    ),
                  ),
                heading('Cameras (live, from Home Assistant)'),
                TextField(
                  controller: camera,
                  decoration: const InputDecoration(
                    hintText: 'camera.front_door, camera.driveway',
                    helperText: 'In order, doorbell first. Swipe across the camera card to go between them.',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 6),
                _FindCameras(container: c, onPicked: (list) => camera.text = list.join(', ')),
                heading('Doorbell'),
                TextField(
                  controller: trigger,
                  decoration: const InputDecoration(
                    labelText: 'When this Home Assistant entity rings',
                    hintText: 'binary_sensor.front_door_ding or event.front_door_ding',
                    helperText: 'The screen wakes and shows the first camera live, full screen.',
                    helperMaxLines: 2,
                  ),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: home.doorbellSeconds,
                  builder: (context, secs, _) => Row(
                    children: [
                      Text('Show for $secs s'),
                      Expanded(
                        child: Slider(
                          value: secs.toDouble(),
                          min: 10,
                          max: 120,
                          divisions: 11,
                          label: '$secs s',
                          onChanged: (v) => home.doorbellSeconds.value = v.round(),
                          onChangeEnd: (v) => unawaited(home.setDoorbell(seconds: v.round())),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await home.setCameraEntity(camera.text);
                          await home.setDoorbell(trigger: trigger.text);
                          if (dialog.mounted) Navigator.pop(dialog);
                          await home.ringDoorbell();
                        },
                        icon: const Icon(Icons.doorbell_rounded),
                        label: const Text('Test'),
                      ),
                    ],
                  ),
                ),
                heading('Menu'),
                OutlinedButton.icon(
                  onPressed: () => unawaited(pickDrawerMenuItems(dialog, c)),
                  icon: const Icon(Icons.checklist_rounded),
                  label: const Text('Choose the menu items (swipe in from the left)'),
                ),
                heading('Layout'),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'today', icon: Icon(Icons.wb_sunny_rounded), label: Text('Today')),
                    ButtonSegment(value: 'tiles', icon: Icon(Icons.grid_view_rounded), label: Text('Tiles')),
                  ],
                  selected: {home.layout.value},
                  onSelectionChanged: (s) => unawaited(home.setLayout(s.first)),
                ),
                heading('Colours'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in homeThemes)
                      ChoiceChip(label: Text(t.name), selected: home.theme.value == t.id, onSelected: (_) => unawaited(home.setTheme(t.id))),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              unawaited(home.setCameraEntity(camera.text));
              unawaited(home.setDoorbell(trigger: trigger.text));
              if (home.smartHomeTarget.value == 'ha') unawaited(home.setSmartHomeTarget('ha', page: haPage.text));
              Navigator.pop(dialog);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  ).whenComplete(() {
    camera.dispose();
    trigger.dispose();
    link.dispose();
    haPage.dispose();
  });
}

/// The wallpaper choices: every built-in 4K picture as a thumbnail, a
/// rotation of them, Bing's 4K photos, your photos, a link, plain colours.
class WallpaperPicker extends StatefulWidget {
  const WallpaperPicker({super.key, required this.container});

  final AppContainer container;

  @override
  State<WallpaperPicker> createState() => _WallpaperPickerState();
}

class _WallpaperPickerState extends State<WallpaperPicker> {
  List<(String, String)>? _bing;
  String? _bingProblem;
  bool _loadingBing = false;

  Future<void> _loadBing() async {
    setState(() => _loadingBing = true);
    try {
      final list = await widget.container.phoenixHome.bingGallery();
      if (mounted) setState(() => _bing = list);
    } catch (e) {
      if (mounted) setState(() => _bingProblem = "Couldn't reach Bing: $e");
    } finally {
      if (mounted) setState(() => _loadingBing = false);
    }
  }

  Widget _thumb({required Widget image, required String label, required bool selected, required VoidCallback onTap}) => SizedBox(
    width: 150,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 84,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? Phx.ember : Colors.white24, width: selected ? 3 : 1),
            ),
            child: image,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
          ),
        ],
      ),
    ),
  );

  Widget _icon(IconData icon) => ColoredBox(
    color: Colors.white10,
    child: Center(child: Icon(icon, size: 30)),
  );

  @override
  Widget build(BuildContext context) {
    final home = widget.container.phoenixHome;
    return ListenableBuilder(
      listenable: Listenable.merge([home.wallpaper, home.wallpaperUrl]),
      builder: (context, _) {
        final current = home.wallpaper.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (id, name, _) in builtinWallpapers)
                  _thumb(
                    image: Image.asset(builtinWallpaperThumb(id), fit: BoxFit.cover, width: double.infinity),
                    label: name,
                    selected: current == 'builtin:$id',
                    onTap: () => unawaited(home.setWallpaper('builtin:$id')),
                  ),
                _thumb(
                  image: _icon(Icons.autorenew_rounded),
                  label: 'All photos, rotating',
                  selected: current == 'builtin',
                  onTap: () => unawaited(home.setWallpaper('builtin')),
                ),
                _thumb(
                  image: _icon(Icons.public_rounded),
                  label: 'Bing 4K, rotating',
                  selected: current == 'bing',
                  onTap: () => unawaited(home.setWallpaper('bing')),
                ),
                _thumb(
                  image: _icon(Icons.photo_library_rounded),
                  label: 'My photos',
                  selected: current == 'photos',
                  onTap: () => unawaited(home.setWallpaper('photos')),
                ),
                _thumb(
                  image: _icon(Icons.link_rounded),
                  label: 'Image link',
                  selected: current == 'url' && !home.wallpaperUrl.value.startsWith('/th?'),
                  onTap: () => unawaited(home.setWallpaper('url', url: '')),
                ),
                _thumb(
                  image: _icon(Icons.palette_rounded),
                  label: 'Colours only',
                  selected: current == 'theme',
                  onTap: () => unawaited(home.setWallpaper('theme')),
                ),
              ],
            ),
            for (final (id, name, credit) in builtinWallpapers)
              if (current == 'builtin:$id' && credit.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('$name photo: $credit', style: const TextStyle(fontSize: 11.5)),
                ),
            const SizedBox(height: 12),
            if (_bing == null)
              OutlinedButton.icon(
                onPressed: _loadingBing ? null : () => unawaited(_loadBing()),
                icon: const Icon(Icons.image_search_rounded),
                label: Text(_loadingBing ? 'Loading…' : (_bingProblem ?? 'More: pick one of Bing\'s 4K photos')),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (base, thumb) in _bing!)
                    _thumb(
                      image: Image.network(thumb, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, _, _) => _icon(Icons.broken_image_rounded)),
                      label: 'Bing 4K',
                      selected: current == 'url' && home.wallpaperUrl.value == base,
                      onTap: () => unawaited(home.setWallpaper('url', url: base)),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// "Find my cameras": imports the Home Assistant cameras into the app's
/// camera setup and lets the parent tick which go on the card.
class _FindCameras extends StatefulWidget {
  const _FindCameras({required this.container, required this.onPicked});
  final AppContainer container;
  final ValueChanged<List<String>> onPicked;

  @override
  State<_FindCameras> createState() => _FindCamerasState();
}

class _FindCamerasState extends State<_FindCameras> {
  List<(String, String)>? _found;
  final _picked = <String>[];
  bool _busy = false;
  String? _problem;

  Future<void> _find() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final found = await homeAssistantCameras(widget.container);
      _picked
        ..clear()
        ..addAll(widget.container.phoenixHome.cameraEntities.value.where((e) => found.any((f) => f.$1 == e)));
      setState(() => _found = found);
      if (found.isEmpty) setState(() => _problem = 'No cameras found in Home Assistant');
    } catch (e) {
      setState(() => _problem = "Couldn't read Home Assistant: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : () => unawaited(_find()),
          icon: const Icon(Icons.videocam_rounded),
          label: Text(_busy ? 'Looking…' : 'Find my Home Assistant cameras'),
        ),
        if (_problem != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_problem!)),
        if (found != null)
          for (final (entity, name) in found)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _picked.contains(entity),
              title: Text(name.isEmpty ? cameraLabel(entity) : name),
              subtitle: Text(_picked.contains(entity) ? '$entity · #${_picked.indexOf(entity) + 1}' : entity),
              onChanged: (on) {
                setState(() => on == true ? _picked.add(entity) : _picked.remove(entity));
                widget.onPicked(List.of(_picked));
              },
            ),
      ],
    );
  }
}

/// Whether a horizontal drag that started at [fromX] and ended moving at
/// [velocity] (pixels a second, + to the right) is the swipe that opens
/// Smart Home: quick, to the right, not from the menu's left edge.
bool isSmartHomeSwipe(double? fromX, double? velocity) => fromX != null && fromX > 40 && velocity != null && velocity > 500;
