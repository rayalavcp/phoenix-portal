import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_container.dart';
import '../../core/command_registry.dart';
import '../../managers/home/school_service.dart';
import '../../managers/launcher/app_launcher_manager.dart';
import '../../managers/settings/definitions.dart' as defs;
import '../kit.dart' show PhoenixMark;
import '../theme.dart';
import '../toast.dart';
import 'home_apps.dart';
import 'school_page.dart';
import 'smart_home_page.dart';

/// Phoenix Home: the launcher home screen. The clock, the weather, big
/// shortcuts (Kids Portal, Smart Home, apps, timers, alarms, the store,
/// the photo frame), and a dock of favourite apps. Nothing here needs Home
/// Assistant; the Smart Home page is where it plugs in, and the dashboard
/// opens over this screen only when asked for.
///
/// It sits at the bottom of the kiosk's stack, over the dashboard page's
/// slot: every overlay (the Kids Portal, timers, alarms, the store) draws
/// over it as before.
class PhoenixHome extends StatefulWidget {
  const PhoenixHome({
    super.key,
    required this.container,
    required this.onOpenMenu,
    required this.onOpenSettings,
  });

  final AppContainer container;
  final VoidCallback onOpenMenu;
  final VoidCallback onOpenSettings;

  @override
  State<PhoenixHome> createState() => _PhoenixHomeState();
}

class _PhoenixHomeState extends State<PhoenixHome> {
  AppContainer get c => widget.container;

  /// Back from another app: anything installed or removed meanwhile shows
  /// (the Play-less Portal installs through the store or adb).
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: () => unawaited(c.launcher.refreshInstalled()),
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) warmHomeIcons(c, c.phoenixHome.dock);
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = c.phoenixHome;
    return ListenableBuilder(
      listenable: Listenable.merge([
        home.dashboardOpen,
        home.smartHomeOpen,
        home.appsOpen,
        home.schoolOpen,
      ]),
      builder: (context, _) {
        // The dashboard is on screen: only a way back home floats over it.
        if (home.dashboardOpen.value) {
          return Align(
            alignment: Alignment.bottomRight,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: FloatingActionButton.extended(
                  heroTag: null,
                  backgroundColor: Phx.ember,
                  foregroundColor: const Color(0xFF2A0A00),
                  onPressed: home.goHome,
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('Home'),
                ),
              ),
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            _HomeScreen(
              container: c,
              onOpenMenu: widget.onOpenMenu,
              onOpenSettings: widget.onOpenSettings,
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: home.smartHomeOpen.value
                  ? SmartHomePage(
                      key: const ValueKey('smart'),
                      container: c,
                      onOpenSettings: widget.onOpenSettings,
                    )
                  : home.appsOpen.value
                  ? HomeAppDrawer(key: const ValueKey('apps'), container: c)
                  : home.schoolOpen.value
                  ? SchoolPage(key: const ValueKey('school'), container: c)
                  : const SizedBox.shrink(key: ValueKey('none')),
            ),
          ],
        );
      },
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({
    required this.container,
    required this.onOpenMenu,
    required this.onOpenSettings,
  });

  final AppContainer container;
  final VoidCallback onOpenMenu;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(-0.6, -1.1),
        radius: 1.5,
        colors: [Color(0xFF3A1A0E), Color(0xFF14161C), Color(0xFF0B0D10)],
        stops: [0, 0.45, 1],
      ),
    ),
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxHeight < 560;
          final pad = box.maxWidth < 700 ? 18.0 : 32.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(pad, compact ? 12 : 24, pad, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  container: container,
                  compact: compact,
                  onOpenMenu: onOpenMenu,
                  onOpenSettings: onOpenSettings,
                ),
                SizedBox(height: compact ? 12 : 24),
                Expanded(
                  child: ListenableBuilder(
                    listenable: Listenable.merge([
                      container.phoenixHome.school.menus,
                      container.phoenixHome.school.config,
                      container.phoenixHome.school.events,
                    ]),
                    builder: (context, _) => _Shortcuts(
                      container: container,
                      onOpenSettings: onOpenSettings,
                    ),
                  ),
                ),
                SizedBox(height: compact ? 10 : 18),
                _Dock(container: container),
              ],
            ),
          );
        },
      ),
    ),
  );
}

// ── Header: clock, date, weather ──────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.container,
    required this.compact,
    required this.onOpenMenu,
    required this.onOpenSettings,
  });

  final AppContainer container;
  final bool compact;
  final VoidCallback onOpenMenu;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: _Clock(compact: compact)),
      const SizedBox(width: 16),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: _WeatherCard(container: container, compact: compact),
      ),
      const SizedBox(width: 8),
      Column(
        children: [
          _RoundButton(
            icon: Icons.menu_rounded,
            tooltip: 'Menu',
            onTap: onOpenMenu,
          ),
          const SizedBox(height: 8),
          _RoundButton(
            icon: Icons.settings_rounded,
            tooltip: 'Settings',
            onTap: onOpenSettings,
          ),
        ],
      ),
    ],
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.08),
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: tooltip,
      iconSize: 26,
      color: Colors.white,
      onPressed: onTap,
      icon: Icon(icon),
    ),
  );
}

class _Clock extends StatefulWidget {
  const _Clock({required this.compact});

  final bool compact;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  // Tick on the minute, not every second: a launcher that sits on screen
  // all day should not repaint for nothing.
  void _schedule() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    _timer = Timer(next.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _greeting() => switch (_now.hour) {
    < 5 => 'Good night',
    < 12 => 'Good morning',
    < 17 => 'Good afternoon',
    < 21 => 'Good evening',
    _ => 'Good night',
  };

  @override
  Widget build(BuildContext context) {
    final h24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final time = DateFormat(h24 ? 'HH:mm' : 'h:mm').format(_now);
    final period = h24 ? '' : DateFormat('a').format(_now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _greeting(),
          style: const TextStyle(
            color: Phx.gold,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
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
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.compact ? 72 : 104,
                  fontWeight: FontWeight.w300,
                  height: 1.05,
                  letterSpacing: -3,
                ),
              ),
              if (period.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  period,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          DateFormat('EEEE, MMMM d').format(_now),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// WMO weather code to an icon.
IconData weatherIcon(int code, {bool day = true}) => switch (code) {
  0 => day ? Icons.wb_sunny_rounded : Icons.nightlight_round,
  1 || 2 => day ? Icons.wb_cloudy_outlined : Icons.nights_stay_outlined,
  3 => Icons.cloud_rounded,
  45 || 48 => Icons.foggy,
  51 || 53 || 55 || 56 || 57 => Icons.grain_rounded,
  61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => Icons.water_drop_rounded,
  71 || 73 || 75 || 77 || 85 || 86 => Icons.ac_unit_rounded,
  95 || 96 || 99 => Icons.thunderstorm_rounded,
  _ => Icons.wb_cloudy_outlined,
};

/// WMO weather code in words.
String weatherWords(int code) => switch (code) {
  0 => 'Clear',
  1 => 'Mostly clear',
  2 => 'Partly cloudy',
  3 => 'Cloudy',
  45 || 48 => 'Fog',
  51 || 53 || 55 => 'Drizzle',
  56 || 57 => 'Freezing drizzle',
  61 || 63 || 80 || 81 => 'Rain',
  65 || 82 => 'Heavy rain',
  66 || 67 => 'Freezing rain',
  71 || 73 || 75 || 77 || 85 || 86 => 'Snow',
  95 || 96 || 99 => 'Thunderstorms',
  _ => '',
};

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.container, required this.compact});

  final AppContainer container;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final home = container.phoenixHome;
    return ListenableBuilder(
      listenable: Listenable.merge([home.weather, home.weatherProblem]),
      builder: (context, _) {
        final w = home.weather.value;
        final problem = home.weatherProblem.value;
        if (w == null) {
          if (problem == null) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.topRight,
            child: TextButton.icon(
              onPressed: () => unawaited(home.refreshWeather()),
              icon: const Icon(Icons.cloud_off_rounded, color: Colors.white54),
              label: Text(
                problem,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          );
        }
        final unit = w.fahrenheit ? '°F' : '°C';
        return Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    weatherIcon(w.code, day: w.isDay),
                    color: Phx.gold,
                    size: compact ? 36 : 44,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${w.temperature.round()}$unit',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 34 : 44,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                [
                  weatherWords(w.code),
                  if (w.place.isNotEmpty) w.place,
                ].where((s) => s.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              if (!compact && w.days.length > 1) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final d in w.days.skip(1).take(4))
                      Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Column(
                          children: [
                            Text(
                              DateFormat('EEE').format(d.date),
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                              ),
                            ),
                            Icon(
                              weatherIcon(d.code),
                              color: Colors.white70,
                              size: 22,
                            ),
                            Text(
                              '${d.high.round()}° ${d.low.round()}°',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Shortcuts ─────────────────────────────────────────────────────────────

class _Shortcut {
  const _Shortcut(this.icon, this.label, this.subtitle, this.colors, this.run);

  final IconData icon;
  final String label;
  final String? subtitle;
  final List<Color> colors;
  final Future<void> Function(BuildContext context) run;
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.container, required this.onOpenSettings});

  final AppContainer container;
  final VoidCallback onOpenSettings;

  Future<void> _command(BuildContext context, String name, String what) async {
    final overlay = Overlay.maybeOf(context);
    final CommandResult result = await container.commands.execute(
      name,
      const {},
    );
    if (!result.ok && overlay != null && overlay.mounted) {
      showToastIn(
        overlay,
        title: "Couldn't open $what",
        message: result.error,
        kind: ToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = container;
    final home = c.phoenixHome;
    final ha = home.homeAssistantConfigured;
    final shortcuts = <_Shortcut>[
      if (c.settings.get(defs.kidsEnabled))
        _Shortcut(
          Icons.child_care_rounded,
          'Kids Portal',
          'Games & learning',
          const [Color(0xFF7B5CFF), Color(0xFFB06BFF)],
          (ctx) => _command(ctx, 'openKids', 'the Kids Portal'),
        ),
      _Shortcut(
        Icons.apps_rounded,
        'All apps',
        '${home.apps.length} apps',
        const [Color(0xFFD42A1A), Color(0xFFF07A1A)],
        (_) async => home.appsOpen.value = true,
      ),
      _Shortcut(
        Icons.home_work_rounded,
        'Smart Home',
        ha ? 'Lights, scenes, climate' : 'Optional add-on',
        const [Color(0xFF14A06B), Color(0xFF52D69F)],
        (_) async => home.openSmartHome(),
      ),
      _Shortcut(
        Icons.school_rounded,
        'School',
        _schoolLine(home.school),
        const [Color(0xFF283066), Color(0xFF5B6CFF)],
        (_) async => home.openSchool(),
      ),
      _Shortcut(
        Icons.timer_rounded,
        'Timers',
        null,
        const [Color(0xFFE08A00), Color(0xFFF7B733)],
        (ctx) => _command(ctx, 'openTimers', 'timers'),
      ),
      _Shortcut(
        Icons.alarm_rounded,
        'Alarms',
        null,
        const [Color(0xFF1C8ED6), Color(0xFF63C3FF)],
        (ctx) => _command(ctx, 'openAlarms', 'alarms'),
      ),
      _Shortcut(
        Icons.storefront_rounded,
        'App Store',
        'Free apps for Portal',
        const [Color(0xFF5B6CFF), Color(0xFF9AA6FF)],
        (ctx) => _command(ctx, 'openStore', 'the store'),
      ),
      _Shortcut(
        Icons.photo_library_rounded,
        'Photo frame',
        null,
        const [Color(0xFFE0446A), Color(0xFFFF8FA3)],
        (ctx) => _command(ctx, 'startScreensaver', 'the photo frame'),
      ),
      if (c.camera.config.defaultView != null)
        _Shortcut(
          Icons.videocam_rounded,
          'Cameras',
          null,
          const [Color(0xFF3E4552), Color(0xFF6B7385)],
          (_) async {
            if (c.camera.config.defaultView case final view?) {
              c.camera.showView(view.id);
            }
          },
        ),
      if (ha)
        _Shortcut(
          Icons.calendar_month_rounded,
          'Calendar',
          null,
          const [Color(0xFF128A5A), Color(0xFF3CCB8C)],
          (ctx) => _command(ctx, 'openCalendar', 'the calendar'),
        ),
      _Shortcut(
        Icons.settings_rounded,
        'Settings',
        null,
        const [Color(0xFF282D37), Color(0xFF3E4552)],
        (_) async => onOpenSettings(),
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        // Two rows filling the space on a landscape Portal, more rows when
        // the screen is narrow (portrait).
        final fit = (box.maxWidth / 180).floor().clamp(2, 6);
        final targetRows = box.maxHeight > box.maxWidth ? 4 : 2;
        final columns = (shortcuts.length / targetRows).ceil().clamp(2, fit);
        final rows = (shortcuts.length / columns).ceil();
        final tileHeight = ((box.maxHeight - (rows - 1) * 14) / rows).clamp(
          96.0,
          220.0,
        );
        return GridView.builder(
          padding: EdgeInsets.zero,
          physics: const BouncingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            mainAxisExtent: tileHeight,
          ),
          itemCount: shortcuts.length,
          itemBuilder: (context, i) {
            final s = shortcuts[i];
            return HomeShortcutTile(
              icon: s.icon,
              label: s.label,
              subtitle: s.subtitle,
              colors: s.colors,
              onTap: () => unawaited(s.run(context)),
            );
          },
        );
      },
    );
  }
}

/// The School tile's line: today's lunch, else the day's status.
String _schoolLine(SchoolService school) {
  final now = DateTime.now();
  final cfg = school.config.value;
  if (!cfg.hasMenu && cfg.calendarUrl.isEmpty) return 'Lunch menu, calendar';
  for (final (slug, _) in cfg.menuTypes) {
    if (!slug.contains('lunch')) continue;
    for (final day in school.menus.value[slug] ?? const <MenuDay>[]) {
      if (day.date.year == now.year && day.date.month == now.month && day.date.day == now.day && !day.isEmpty) {
        return 'Lunch: ${day.items.first}';
      }
    }
  }
  return school.status(now);
}

// ── Dock ──────────────────────────────────────────────────────────────────

class _Dock extends StatelessWidget {
  const _Dock({required this.container});

  final AppContainer container;

  @override
  Widget build(BuildContext context) {
    final home = container.phoenixHome;
    return ListenableBuilder(
      listenable: Listenable.merge([
        container.launcher.installedRevision,
        home.favorites,
        home.usage,
        home.hidden,
      ]),
      builder: (context, _) {
        final List<LauncherApp> dock = home.dock;
        final pinned = home.favorites.value.isNotEmpty;
        return Container(
          height: 118,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Row(
            children: [
              const PhoenixMark(size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: dock.isEmpty
                    ? Text(
                        container.launcher.installed.isEmpty
                            ? 'Loading your apps…'
                            : 'Your favourite apps live here. Open All apps, '
                                  'then press and hold an app to add it.',
                        style: const TextStyle(color: Colors.white60),
                      )
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          if (!pinned)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: Text(
                                    'MOST USED',
                                    style: TextStyle(
                                      color: Phx.gold,
                                      fontSize: 10,
                                      letterSpacing: 1.2,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          for (final app in dock)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: HomeAppTile(
                                container: container,
                                app: app,
                                iconSize: 56,
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Phx.ember,
                  foregroundColor: const Color(0xFF2A0A00),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 18,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: () => home.appsOpen.value = true,
                icon: const Icon(Icons.apps_rounded),
                label: const Text('All apps'),
              ),
            ],
          ),
        );
      },
    );
  }
}

