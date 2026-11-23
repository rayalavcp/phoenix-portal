import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_container.dart';
import '../../managers/launcher/app_launcher_manager.dart';
import '../kit.dart' show PhoenixMark;
import '../theme.dart';
import 'home_apps.dart';
import 'home_glass.dart';
import 'home_tiles.dart';
import 'school_page.dart';
import 'telugu_calendar_page.dart';
import 'today_home.dart';
import 'weather_backdrop.dart';
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
        home.teluguOpen,
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
            ValueListenableBuilder(
              valueListenable: home.layout,
              builder: (context, layout, _) => layout == 'tiles'
                  ? _HomeScreen(
                      container: c,
                      onOpenMenu: widget.onOpenMenu,
                      onOpenSettings: widget.onOpenSettings,
                    )
                  : TodayHome(
                      container: c,
                      onOpenMenu: widget.onOpenMenu,
                      onOpenSettings: widget.onOpenSettings,
                    ),
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
                  : home.teluguOpen.value
                  ? TeluguCalendarPage(
                      key: const ValueKey('telugu'),
                      container: c,
                    )
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      container.phoenixHome.theme,
      container.phoenixHome.editing,
      container.phoenixHome.weather,
      container.phoenixHome.weatherEffects,
      container.phoenixHome.weatherDemo,
      container.phoenixHome.glassOpacity,
    ]),
    builder: (context, _) {
      final editing = container.phoenixHome.editing.value;
      return GlassScope(
        opacity: container.phoenixHome.glassOpacity.value,
        child: Stack(
          fit: StackFit.expand,
          children: [
            HomeWallpaper(container: container),
            if (container.phoenixHome.weatherEffects.value &&
                (container.phoenixHome.weather.value != null || container.phoenixHome.weatherDemo.value.isNotEmpty))
              WeatherBackdrop(
                code: container.phoenixHome.weather.value?.code,
                isDay: container.phoenixHome.weather.value?.isDay ?? true,
                demo: container.phoenixHome.weatherDemo.value,
                sunrise: container.phoenixHome.weather.value?.sunrise,
                sunset: container.phoenixHome.weather.value?.sunset,
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x66000000), Color(0x1A000000), Color(0x73000000)],
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, box) {
                  final compact = box.maxHeight < 560;
                  final pad = box.maxWidth < 700 ? 18.0 : 32.0;
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      pad,
                      compact ? 12 : 24,
                      pad,
                      12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          container: container,
                          compact: compact,
                          onOpenMenu: onOpenMenu,
                          onOpenSettings: onOpenSettings,
                        ),
                        SizedBox(height: compact ? 12 : 22),
                        Expanded(
                          child: HomeTileGrid(
                            container: container,
                            onOpenSettings: onOpenSettings,
                          ),
                        ),
                        SizedBox(height: compact ? 10 : 16),
                        if (editing)
                          HomeEditBar(container: container)
                        else
                          _Dock(container: container),
                      ],
                    ),
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
          const SizedBox(height: 8),
          _RoundButton(
            icon: Icons.dashboard_customize_rounded,
            tooltip: 'Edit tiles and theme',
            onTap: () => container.phoenixHome.editing.value =
                !container.phoenixHome.editing.value,
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
    final next = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
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
                    fontFamily: Ks.displayFont,
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
