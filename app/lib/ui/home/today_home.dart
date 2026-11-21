import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../app_container.dart';
import '../../core/command_registry.dart';
import '../../managers/home/panchang.dart';
import '../../managers/home/school_service.dart';
import '../../managers/home/telugu_words.dart';
import '../theme.dart';
import '../toast.dart';
import 'home_apps.dart';
import 'home_themes.dart';
import 'phoenix_home.dart' show weatherIcon, weatherWords;
import 'photo_frame.dart';
import 'school_page.dart';
import 'weather_backdrop.dart';

/// The Today screen: a calm, glanceable home over today's landscape photo.
/// A greeting and today's date up top with the next festival and the moon,
/// six glass cards (clock and weather, photos, up next, the front door or
/// favourite apps, school, a Telugu word), and one row of big buttons along
/// the bottom. Everything else is one tap away, not crowded onto the screen.
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

  Future<void> _command(String name, String what) async {
    final overlay = Overlay.maybeOf(context);
    final CommandResult result = await c.commands.execute(name, const {});
    if (!result.ok && overlay != null && overlay.mounted) {
      showToastIn(overlay, title: "Couldn't open $what", message: result.error, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = c.phoenixHome;
    return ListenableBuilder(
      listenable: Listenable.merge([home.theme, home.weather, home.weatherEffects, home.backdrop]),
      builder: (context, _) {
        final theme = homeTheme(home.theme.value);
        final photo = home.backdrop.value;
        final w = home.weather.value;
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: const Alignment(-0.6, -1.1), radius: 1.5, colors: theme.background, stops: const [0, 0.45, 1]),
              ),
            ),
            if (photo != null) Image.memory(photo, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.shrink()),
            // Darken the photo so white text always reads.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Color(0x33000000), Color(0xAA000000)],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
            if (home.weatherEffects.value && w != null) WeatherBackdrop(code: w.code, isDay: w.isDay),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, box) {
                  final wide = box.maxWidth >= 860 && box.maxWidth > box.maxHeight;
                  final pad = box.maxWidth < 700 ? 14.0 : 24.0;
                  return Padding(
                    padding: EdgeInsets.fromLTRB(pad, 14, pad, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          container: c,
                          now: _now,
                          compact: !wide,
                          onNight: () => unawaited(_command('startScreensaver', 'the screensaver')),
                          onOpenMenu: widget.onOpenMenu,
                          onCustomize: () => unawaited(showTodaySetup(context, c)),
                        ),
                        const SizedBox(height: 14),
                        Expanded(child: wide ? _wideCards() : _narrowCards()),
                        const SizedBox(height: 12),
                        _NavBar(
                          container: c,
                          onKids: () => unawaited(_command('openKids', 'the Kids Portal')),
                          onPhotos: () => unawaited(_openPhotos()),
                          onOpenSettings: widget.onOpenSettings,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
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

  // Three columns, two cards each: room to breathe on a 10" landscape screen.
  Widget _wideCards() {
    const gap = SizedBox(width: 14, height: 14);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 10,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 6,
                child: _ClockWeatherCard(container: c, now: _now),
              ),
              gap,
              Expanded(
                flex: 5,
                child: _UpNextCard(container: c, now: _now),
              ),
            ],
          ),
        ),
        gap,
        Expanded(
          flex: 10,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 6,
                child: _PhotoCard(container: c, onOpen: () => unawaited(_openPhotos())),
              ),
              gap,
              Expanded(flex: 5, child: _DoorOrAppsCard(container: c)),
            ],
          ),
        ),
        gap,
        Expanded(
          flex: 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 6,
                child: _SchoolCard(container: c, now: _now),
              ),
              gap,
              Expanded(
                flex: 5,
                child: _WordCard(container: c, now: _now),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Portrait or a small screen: the same cards, one under another.
  Widget _narrowCards() => ListView(
    padding: EdgeInsets.zero,
    children: [
      SizedBox(
        height: 280,
        child: _ClockWeatherCard(container: c, now: _now),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 280,
        child: _SchoolCard(container: c, now: _now),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 220,
        child: _UpNextCard(container: c, now: _now),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 260,
        child: _PhotoCard(container: c, onOpen: () => unawaited(_openPhotos())),
      ),
      const SizedBox(height: 12),
      SizedBox(height: 200, child: _DoorOrAppsCard(container: c)),
      const SizedBox(height: 12),
      SizedBox(
        height: 170,
        child: _WordCard(container: c, now: _now),
      ),
    ],
  );
}

// ── Building blocks ───────────────────────────────────────────────────────

/// Frosted glass over the photo.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap, this.radius = 26});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Material(
        color: Colors.white.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    ),
  );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.icon, this.text, {this.trailing});

  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: Phx.gold, size: 18),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.2),
        ),
      ),
      ?trailing,
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Glass(
    radius: 40,
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

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Glass(
      radius: 40,
      onTap: onTap,
      padding: const EdgeInsets.all(11),
      child: Icon(icon, color: Colors.white, size: 24),
    ),
  );
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _whenDays(int days) => days == 0
    ? 'today'
    : days == 1
    ? 'tomorrow'
    : 'in $days days';

// ── Header ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.container,
    required this.now,
    required this.compact,
    required this.onNight,
    required this.onOpenMenu,
    required this.onCustomize,
  });

  final AppContainer container;
  final DateTime now;
  final bool compact;
  final VoidCallback onNight;
  final VoidCallback onOpenMenu;
  final VoidCallback onCustomize;

  String get _greeting => switch (now.hour) {
    < 5 => 'Good night',
    < 12 => 'Good morning',
    < 17 => 'Good afternoon',
    < 21 => 'Good evening',
    _ => 'Good night',
  };

  @override
  Widget build(BuildContext context) {
    final calc = container.phoenixHome.panchang;
    final today = calc.day(now);
    final midnight = DateTime(now.year, now.month, now.day);
    final festival = today.festivals.isNotEmpty ? (midnight, today.festivals.first) : calc.upcoming(midnight.add(const Duration(days: 1)), 60).firstOrNull;
    final (phase, lit) = moonPhase(now);
    final paksha = today.amavasya ? '' : (today.shukla ? 'Shukla ' : 'Krishna ');
    final chips = [
      if (festival != null)
        _Chip(
          icon: Icons.celebration_rounded,
          text: '${festival.$2.split(' (').first} ${_whenDays(festival.$1.difference(midnight).inDays)}',
          onTap: container.phoenixHome.openTelugu,
        ),
      _Chip(icon: Icons.brightness_2_rounded, text: '$phase $lit% lit · $paksha${today.tithiNameEn}', onTap: container.phoenixHome.openTelugu),
    ];
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _greeting,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 32 : 42,
              fontWeight: FontWeight.w700,
              height: 1.1,
              shadows: const [Shadow(color: Colors.black45, blurRadius: 12)],
            ),
          ),
        ),
        Text(
          DateFormat('EEEE, MMMM d').format(now),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 18,
            fontWeight: FontWeight.w500,
            shadows: [Shadow(color: Colors.black45, blurRadius: 8)],
          ),
        ),
      ],
    );
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassButton(icon: Icons.bedtime_rounded, tooltip: 'Night mode', onTap: onNight),
        const SizedBox(width: 8),
        _GlassButton(icon: Icons.tune_rounded, tooltip: 'Customize home', onTap: onCustomize),
        const SizedBox(width: 8),
        _GlassButton(icon: Icons.menu_rounded, tooltip: 'Menu', onTap: onOpenMenu),
      ],
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: title),
              buttons,
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: 4, child: title),
        Expanded(
          flex: 6,
          child: Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 8, children: chips),
        ),
        const SizedBox(width: 14),
        buttons,
      ],
    );
  }
}

// ── Clock and weather ─────────────────────────────────────────────────────

class _ClockWeatherCard extends StatelessWidget {
  const _ClockWeatherCard({required this.container, required this.now});

  final AppContainer container;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final home = container.phoenixHome;
    final h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final time = DateFormat(h24 ? 'HH:mm' : 'h:mm').format(now);
    final period = h24 ? '' : DateFormat('a').format(now);
    final w = home.weather.value;
    return Glass(
      onTap: () => unawaited(home.refreshWeather()),
      child: LayoutBuilder(
        builder: (context, box) {
          final tight = box.maxHeight < 230;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              time,
                              style: const TextStyle(color: Colors.white, fontSize: 84, fontWeight: FontWeight.w300, letterSpacing: -3, height: 1),
                            ),
                            if (period.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                period,
                                style: const TextStyle(color: Colors.white70, fontSize: 24, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (w != null)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(weatherIcon(w.code, day: w.isDay), color: Phx.gold, size: 38),
                              const SizedBox(width: 6),
                              Text(
                                '${w.temperature.round()}°',
                                style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          Text(weatherWords(w.code), style: const TextStyle(color: Colors.white70, fontSize: 14)),
                          if (w.days.isNotEmpty)
                            Text(
                              'H ${w.days.first.high.round()}°  L ${w.days.first.low.round()}°',
                              style: const TextStyle(color: Colors.white60, fontSize: 13),
                            ),
                        ],
                      )
                    else
                      ValueListenableBuilder(
                        valueListenable: home.weatherProblem,
                        builder: (context, problem, _) =>
                            problem == null ? const SizedBox.shrink() : const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 32),
                      ),
                  ],
                ),
              ),
              if (w != null && w.days.length > 1 && !tight) ...[
                Divider(color: Colors.white.withValues(alpha: 0.12), height: 18),
                Row(
                  children: [
                    for (final d in w.days.skip(1).take(5))
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              DateFormat('EEE').format(d.date),
                              style: const TextStyle(color: Colors.white60, fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Icon(weatherIcon(d.code), color: Colors.white, size: 22),
                            const SizedBox(height: 4),
                            Text(
                              '${d.high.round()}°',
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            Text('${d.low.round()}°', style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              if (w != null && w.place.isNotEmpty && !tight)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    w.place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Photos ────────────────────────────────────────────────────────────────

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.container, required this.onOpen});

  final AppContainer container;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final photos = container.phoenixHome.photos;
    return ValueListenableBuilder(
      valueListenable: photos.settings,
      builder: (context, settings, _) {
        if (!photos.configured) {
          return Glass(
            onTap: () => unawaited(showPhotoSetup(context, container)),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.photo_library_rounded, color: Phx.gold, size: 44),
                SizedBox(height: 10),
                Text(
                  'Your photos',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  'Tap to connect Immich or a network folder',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60),
                ),
              ],
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: GestureDetector(
            onTap: onOpen,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black26,
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                borderRadius: BorderRadius.circular(26),
              ),
              child: PhoenixPhotoFrame(key: ValueKey(settings), container: container, showClock: false, seconds: 20),
            ),
          ),
        );
      },
    );
  }
}

// ── Up next ───────────────────────────────────────────────────────────────

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
          for (final (d, f) in home.panchang.upcoming(midnight, 21)) _UpNextItem(d, f.split(' (').first, true, Icons.celebration_rounded),
        ]..sort((a, b) => a.start.compareTo(b.start));
        return Glass(
          onTap: () => unawaited(widget.container.commands.execute('openCalendar', const {})),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _CardTitle(Icons.event_note_rounded, 'Up next'),
              const SizedBox(height: 8),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text('Nothing coming up', style: TextStyle(color: Colors.white54)),
                      )
                    : LayoutBuilder(
                        builder: (context, box) {
                          final fit = (box.maxHeight / 44).floor().clamp(1, 6);
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
      height: 44,
      child: Row(
        children: [
          Icon(e.icon, size: 20, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              e.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            when,
            style: TextStyle(color: days == 0 ? Phx.gold : Colors.white60, fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ── Front door camera, or favourite apps ──────────────────────────────────

class _DoorOrAppsCard extends StatelessWidget {
  const _DoorOrAppsCard({required this.container});

  final AppContainer container;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: container.phoenixHome.cameraEntity,
    builder: (context, entity, _) => entity.isNotEmpty && container.phoenixHome.homeAssistantConfigured
        ? _CameraCard(key: ValueKey(entity), container: container, entity: entity)
        : _AppsCard(container: container),
  );
}

class _CameraCard extends StatefulWidget {
  const _CameraCard({super.key, required this.container, required this.entity});

  final AppContainer container;
  final String entity;

  @override
  State<_CameraCard> createState() => _CameraCardState();
}

class _CameraCardState extends State<_CameraCard> {
  Uint8List? _frame;
  DateTime? _at;
  bool _failed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_grab());
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_grab()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _grab() async {
    final auth = widget.container.phoenixHome.homeAssistantAuth;
    final base = auth.base.trim().replaceFirst(RegExp(r'/+$'), '');
    if (base.isEmpty || auth.token.isEmpty) return;
    try {
      final res = await http
          .get(Uri.parse('$base/api/camera_proxy/${widget.entity}'), headers: {'Authorization': 'Bearer ${auth.token}'})
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        setState(() {
          _frame = res.bodyBytes;
          _at = DateTime.now();
          _failed = false;
        });
      } else {
        setState(() => _failed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.entity.split('.').last.replaceAll('_', ' ');
    final label = name.isEmpty ? 'Camera' : name[0].toUpperCase() + name.substring(1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: GestureDetector(
        onTap: () {
          final cam = widget.container.camera;
          if (cam.config.defaultView case final view?) {
            cam.showView(view.id);
          } else {
            unawaited(_grab());
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black38),
            if (_frame != null) Image.memory(_frame!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.shrink()),
            if (_frame == null) Center(child: Icon(_failed ? Icons.videocam_off_rounded : Icons.videocam_rounded, color: Colors.white38, size: 44)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x88000000), Colors.transparent],
                  stops: [0, 0.4],
                ),
              ),
            ),
            Positioned(
              left: 16,
              top: 12,
              right: 16,
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(color: _failed ? Colors.white38 : Colors.redAccent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                  if (_at != null) Text(DateFormat.jms().format(_at!), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppsCard extends StatelessWidget {
  const _AppsCard({required this.container});

  final AppContainer container;

  @override
  Widget build(BuildContext context) {
    final home = container.phoenixHome;
    return ListenableBuilder(
      listenable: Listenable.merge([container.launcher.installedRevision, home.favorites, home.usage, home.hidden]),
      builder: (context, _) {
        final apps = home.dock;
        return Glass(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CardTitle(
                Icons.star_rounded,
                home.favorites.value.isEmpty ? 'Most used apps' : 'Favourite apps',
                trailing: TextButton(
                  style: TextButton.styleFrom(foregroundColor: Phx.gold, visualDensity: VisualDensity.compact),
                  onPressed: () => home.appsOpen.value = true,
                  child: const Text('All apps'),
                ),
              ),
              Expanded(
                child: apps.isEmpty
                    ? const Center(
                        child: Text(
                          'Open All apps and press and hold an app to add it here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white60),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, box) {
                          final perRow = (box.maxWidth / 92).floor().clamp(2, 6);
                          final rows = box.maxHeight >= 220 ? 2 : 1;
                          return Wrap(
                            alignment: WrapAlignment.spaceEvenly,
                            runAlignment: WrapAlignment.center,
                            children: [
                              for (final app in apps.take(perRow * rows))
                                SizedBox(
                                  width: box.maxWidth / perRow,
                                  child: HomeAppTile(container: container, app: app, iconSize: 52),
                                ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── School ────────────────────────────────────────────────────────────────

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
        // After school, show tomorrow's menu; before and during, today's.
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
              final roomy = box.maxHeight >= 230;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CardTitle(Icons.school_rounded, cfg.schoolName.isEmpty ? 'School' : cfg.schoolName),
                  const SizedBox(height: 10),
                  Text(
                    schoolToday ? status : (now.weekday > DateTime.friday ? 'No school today · Weekend' : status),
                    maxLines: roomy ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, height: 1.2),
                  ),
                  if (!schoolToday && next != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Back to school ${DateFormat('EEE M/d').format(next)} · ${_whenDays(next.difference(midnight).inDays)}',
                      style: const TextStyle(color: Phx.gold, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => unawaited(showTodayAtSchool(context, container)),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                        child: lunch == null || lunch.isEmpty
                            ? Row(
                                children: [
                                  const Icon(Icons.restaurant_rounded, color: Colors.white54, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      school.problem.value != null && school.menus.value.isEmpty
                                          ? 'Menu: ${school.problem.value}'
                                          : "$dayName menu not posted yet",
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                                    ),
                                  ),
                                ],
                              )
                            : LayoutBuilder(
                                builder: (context, box) {
                                  final lines = ((box.maxHeight - 22) / 20).floor().clamp(1, 6);
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$dayName lunch',
                                        style: const TextStyle(color: Phx.gold, fontSize: 13, fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 2),
                                      for (final item in lunch.items.take(lines))
                                        Text(
                                          '• $item',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.35),
                                        ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                  if (roomy) ...[
                    const SizedBox(height: 10),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isToday ? Phx.ember.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            DateFormat('EEE').format(d),
            style: TextStyle(color: isToday ? const Color(0xFF2A0A00) : Colors.white60, fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
          Text(
            '${d.day}',
            style: TextStyle(color: isToday ? const Color(0xFF2A0A00) : Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
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

// ── Telugu word of the day ────────────────────────────────────────────────

class _WordCard extends StatelessWidget {
  const _WordCard({required this.container, required this.now});

  final AppContainer container;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final w = teluguWordOfTheDay(now);
    return Glass(
      onTap: container.phoenixHome.openTelugu,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(Icons.translate_rounded, 'Telugu word of the day'),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      w.telugu,
                      style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      w.say,
                      style: const TextStyle(color: Phx.gold, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    Text(w.meaning, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom navigation ─────────────────────────────────────────────────────

class _NavBar extends StatelessWidget {
  const _NavBar({required this.container, required this.onKids, required this.onPhotos, required this.onOpenSettings});

  final AppContainer container;
  final VoidCallback onKids;
  final VoidCallback onPhotos;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final home = container.phoenixHome;
    final items = <(IconData, String, VoidCallback)>[
      (Icons.wb_sunny_rounded, 'Today', home.goHome),
      (Icons.apps_rounded, 'Apps', () => home.appsOpen.value = true),
      (Icons.child_care_rounded, 'Kids', onKids),
      (Icons.school_rounded, 'School', home.openSchool),
      (Icons.brightness_5_rounded, 'Calendar', home.openTelugu),
      (Icons.photo_library_rounded, 'Photos', onPhotos),
      (Icons.home_work_rounded, 'Smart Home', home.openSmartHome),
      (Icons.settings_rounded, 'Settings', onOpenSettings),
    ];
    return Glass(
      radius: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: LayoutBuilder(
        builder: (context, box) {
          final labels = box.maxWidth >= 640;
          return Row(
            children: [
              for (final (i, (icon, label, onTap)) in items.indexed)
                Expanded(
                  child: Tooltip(
                    message: label,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: onTap,
                      child: Container(
                        height: 56,
                        decoration: i == 0 ? BoxDecoration(color: Phx.ember.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(22)) : null,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, color: i == 0 ? const Color(0xFF2A0A00) : Colors.white, size: 24),
                            if (labels)
                              Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: i == 0 ? const Color(0xFF2A0A00) : Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Customize ─────────────────────────────────────────────────────────────

/// The Today screen's own settings: layout, theme, weather, the camera.
Future<void> showTodaySetup(BuildContext context, AppContainer c) {
  final home = c.phoenixHome;
  final camera = TextEditingController(text: home.cameraEntity.value);
  return showDialog<void>(
    context: context,
    builder: (dialog) => ListenableBuilder(
      listenable: Listenable.merge([home.layout, home.theme, home.weatherEffects]),
      builder: (dialog, _) => AlertDialog(
        title: const Text('Customize home'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Layout', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'today', icon: Icon(Icons.wb_sunny_rounded), label: Text('Today')),
                    ButtonSegment(value: 'tiles', icon: Icon(Icons.grid_view_rounded), label: Text('Tiles')),
                  ],
                  selected: {home.layout.value},
                  onSelectionChanged: (s) => unawaited(home.setLayout(s.first)),
                ),
                const SizedBox(height: 16),
                const Text('Colours (shown when the daily photo is not loaded)', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in homeThemes)
                      ChoiceChip(label: Text(t.name), selected: home.theme.value == t.id, onSelected: (_) => unawaited(home.setTheme(t.id))),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Weather effects'),
                  subtitle: const Text('Rain, snow, sun and clouds over the background'),
                  value: home.weatherEffects.value,
                  onChanged: (v) => unawaited(home.setWeatherEffects(v)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: camera,
                  decoration: const InputDecoration(
                    labelText: 'Front door camera (optional)',
                    hintText: 'camera.front_door',
                    helperText: 'A Home Assistant camera. Leave empty to show your favourite apps instead.',
                    helperMaxLines: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              unawaited(home.setCameraEntity(camera.text));
              Navigator.pop(dialog);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  ).whenComplete(camera.dispose);
}
