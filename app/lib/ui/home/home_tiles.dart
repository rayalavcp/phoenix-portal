import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_container.dart';
import '../../core/command_registry.dart';
import '../../managers/alarms/alarm_model.dart';
import '../../managers/home/panchang.dart';
import '../../managers/home/phoenix_home_manager.dart';
import '../../managers/home/school_service.dart';
import '../../managers/settings/definitions.dart' as defs;
import '../kids/kids_logic.dart';
import '../kids/kids_more_logic.dart';
import '../toast.dart';
import 'home_apps.dart';
import 'home_glass.dart';
import 'home_themes.dart';
import 'photo_frame.dart';
import 'school_page.dart';
import 'telugu_calendar_page.dart';

/// Phoenix Home's tiles: live, resizable, reorderable, themed.
///
/// Each tile shows current data and more of it as it grows: a 1×1 tile its
/// headline, a wide one a line more, a 2×2 one the details. In edit mode
/// (hold any tile) they work like widgets on an Android home screen: drag a
/// tile to move it, drag its corner handle to resize it, tap × to hide it.
class HomeTileGrid extends StatefulWidget {
  const HomeTileGrid({super.key, required this.container, required this.onOpenSettings});

  final AppContainer container;
  final VoidCallback onOpenSettings;

  @override
  State<HomeTileGrid> createState() => _HomeTileGridState();
}

class _HomeTileGridState extends State<HomeTileGrid> {
  AppContainer get c => widget.container;
  late final Timer _tick;

  /// The tile being resized and the size it shows while the corner is
  /// dragged (the grid reflows live; saved when the finger lifts).
  ({String id, int w, int h})? _resizing;

  /// The tile being moved and how far the finger has dragged it.
  ({String id, Offset by})? _moving;

  Future<void> _commitResize() async {
    final r = _resizing;
    if (r == null) return;
    final home = c.phoenixHome;
    await home.setTiles([for (final t in home.tiles.value) t.id == r.id ? t.sized(r.w, r.h) : t]);
    if (mounted) setState(() => _resizing = null);
  }

  /// Drops the moved tile where the finger is: it takes the place of the
  /// tile under it (the others shift along).
  Future<void> _commitMove(List<HomeTileSpec> specs, List<Rect> rects) async {
    final m = _moving;
    if (m == null) return;
    final from = specs.indexWhere((t) => t.id == m.id);
    final at = rects[from].center + m.by;
    var to = -1;
    for (var i = 0; i < rects.length; i++) {
      if (i != from && rects[i].inflate(7).contains(at)) to = i;
    }
    setState(() => _moving = null);
    if (from < 0 || to < 0) return;
    final home = c.phoenixHome;
    final list = [...home.tiles.value];
    final moved = list.removeAt(list.indexWhere((t) => t.id == m.id));
    list.insert(list.indexWhere((t) => t.id == specs[to].id) + (to > from ? 1 : 0), moved);
    await home.setTiles(list);
  }

  @override
  void initState() {
    super.initState();
    // Clocks in tiles (timers, alarms, school countdown) move on.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    if (c.phoenixHome.homeAssistantConfigured) unawaited(c.phoenixHome.loadEntities());
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  /// Whether a tile has anything to show on this device.
  bool _available(String id) => switch (id) {
    'kids' => c.settings.get(defs.kidsEnabled),
    'calendar' => c.phoenixHome.homeAssistantConfigured,
    'cameras' => c.camera.config.defaultView != null,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final home = c.phoenixHome;
    return ListenableBuilder(
      listenable: Listenable.merge([
        home.tiles,
        home.hiddenTiles,
        home.theme,
        home.editing,
        home.school.menus,
        home.school.config,
        home.school.events,
        home.entities,
        home.photos.settings,
        c.voiceTimers.timers,
        c.alarms.alarms,
        c.launcher.installedRevision,
        home.usage,
        KidsScores.changes,
      ]),
      builder: (context, _) {
        final theme = homeTheme(home.theme.value);
        final editing = home.editing.value;
        final r = editing ? _resizing : null;
        final specs = [
          for (final t in home.tiles.value)
            if (_available(t.id) && !home.hiddenTiles.value.contains(t.id))
              r != null && r.id == t.id ? t.sized(r.w, r.h) : t,
        ];
        return LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth > box.maxHeight ? 6 : 4;
            const gap = 14.0;
            final cell = (box.maxWidth - gap * (columns - 1)) / columns;
            final spots = packTiles([for (final t in specs) (t.w, t.h)], columns);
            final rows = spots.isEmpty
                ? 1
                : [for (var i = 0; i < specs.length; i++) spots[i].$2 + specs[i].h].reduce(math.max);
            // Rows share the height when they fit; tall layouts scroll.
            final rowH = math.max(104.0, math.min(cell, (box.maxHeight - gap * (rows - 1)) / rows));
            final height = rows * rowH + (rows - 1) * gap;
            final rects = [
              for (var i = 0; i < specs.length; i++)
                Rect.fromLTWH(
                  spots[i].$1 * (cell + gap),
                  spots[i].$2 * (rowH + gap),
                  math.min(specs[i].w, columns) * cell + (math.min(specs[i].w, columns) - 1) * gap,
                  specs[i].h * rowH + (specs[i].h - 1) * gap,
                ),
            ];
            Widget tile(int i) {
              final spec = specs[i];
              final child = _Tile(
                container: c,
                spec: spec,
                colors: theme.tile(i),
                editing: editing,
                onOpenSettings: widget.onOpenSettings,
              );
              if (!editing) return child;
              return _EditFrame(
                spec: spec,
                resizing: _resizing?.id == spec.id,
                onHide: () => unawaited(c.phoenixHome.setTileHidden(spec.id, true)),
                onMove: (by) => setState(() => _moving = (id: spec.id, by: by)),
                onMoveEnd: () => unawaited(_commitMove(specs, rects)),
                onResize: (target) {
                  // Snap to whole cells, as an Android widget does.
                  final w = ((target.width + gap) / (cell + gap)).round().clamp(1, columns);
                  final h = ((target.height + gap) / (rowH + gap)).round().clamp(1, 4);
                  final now = _resizing;
                  if (now == null || now.w != w || now.h != h) setState(() => _resizing = (id: spec.id, w: w, h: h));
                },
                onResizeStart: () => setState(() => _resizing = (id: spec.id, w: spec.w, h: spec.h)),
                onResizeEnd: () => unawaited(_commitResize()),
                child: child,
              );
            }

            final movingAt = specs.indexWhere((t) => t.id == _moving?.id);
            return SingleChildScrollView(
              physics: _moving != null || _resizing != null ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
              child: SizedBox(
                height: height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < specs.length; i++)
                      if (i != movingAt)
                        AnimatedPositioned(
                          key: ValueKey(specs[i].id),
                          duration: Duration(milliseconds: _resizing?.id == specs[i].id ? 90 : 260),
                          curve: Curves.easeOutCubic,
                          left: rects[i].left,
                          top: rects[i].top,
                          width: rects[i].width,
                          height: rects[i].height,
                          child: tile(i),
                        ),
                    // The tile being moved floats over the others.
                    if (movingAt >= 0)
                      AnimatedPositioned(
                        key: ValueKey(specs[movingAt].id),
                        duration: Duration.zero,
                        left: rects[movingAt].left + _moving!.by.dx,
                        top: rects[movingAt].top + _moving!.by.dy,
                        width: rects[movingAt].width,
                        height: rects[movingAt].height,
                        child: tile(movingAt),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.container,
    required this.spec,
    required this.colors,
    required this.editing,
    required this.onOpenSettings,
  });

  final AppContainer container;
  final HomeTileSpec spec;
  final List<Color> colors;
  final bool editing;
  final VoidCallback onOpenSettings;

  AppContainer get c => container;

  Future<void> _command(BuildContext context, String name, String what) async {
    final overlay = Overlay.maybeOf(context);
    final CommandResult result = await c.commands.execute(name, const {});
    if (!result.ok && overlay != null && overlay.mounted) {
      showToastIn(overlay, title: "Couldn't open $what", message: result.error, kind: ToastKind.error);
    }
  }

  Future<void> _open(BuildContext context) async {
    final home = c.phoenixHome;
    switch (spec.id) {
      case 'kids':
        await _command(context, 'openKids', 'the Kids Portal');
      case 'apps':
        home.appsOpen.value = true;
      case 'smart':
        home.openSmartHomeButton();
      case 'school':
        await showTodayAtSchool(context, c);
      case 'telugu':
        home.openTelugu();
      case 'photos':
        if (!home.photos.configured) {
          await showPhotoSetup(context, c);
        } else {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (route) => GestureDetector(
                onTap: () => Navigator.pop(route),
                child: PhoenixPhotoFrame(container: c),
              ),
            ),
          );
        }
      case 'timers':
        await _command(context, 'openTimers', 'timers');
      case 'alarms':
        await _command(context, 'openAlarms', 'alarms');
      case 'store':
        await _command(context, 'openStore', 'the store');
      case 'calendar':
        await _command(context, 'openCalendar', 'the calendar');
      case 'cameras':
        if (c.camera.config.defaultView case final view?) c.camera.showView(view.id);
      case 'settings':
        onOpenSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = spec.w >= 2 && spec.h >= 2
        ? _Size.large
        : spec.w >= 2
        ? _Size.wide
        : spec.h >= 2
        ? _Size.tall
        : _Size.small;
    final content = _content(context, size);
    // Glass, with a thin line of the tile's colour along the top.
    final tile = Glass(
      blur: false,
      padding: EdgeInsets.zero,
      onTap: editing ? null : () => unawaited(_open(context)),
      onLongPress: () => c.phoenixHome.editing.value = true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          Positioned(
            left: 18,
            right: 18,
            top: 0,
            height: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
              ),
            ),
          ),
        ],
      ),
    );
    if (!editing) return tile;
    return AnimatedScale(scale: 0.96, duration: const Duration(milliseconds: 200), child: tile);
  }

  Widget _content(BuildContext context, _Size size) {
    final home = c.phoenixHome;
    final now = DateTime.now();
    switch (spec.id) {
      case 'kids':
        final left = c.kids.minutesLeft;
        final challenge = dailyChallenge(now);
        return _Body(
          icon: Icons.child_care_rounded,
          title: 'Kids Portal',
          line: left == null ? 'Games & learning' : '$left min of play left today',
          size: size,
          extra: FutureBuilder<(int, bool)>(
            future: _kidsStatus(),
            builder: (context, snap) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Chip(Icons.star_rounded, '${snap.data?.$1 ?? 0} stars today'),
                const SizedBox(height: 6),
                Text(
                  snap.data?.$2 == true ? "Today's challenge done!" : "Today's challenge: ${challenge.text}",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      case 'apps':
        final recent = home.recent(size == _Size.large ? 8 : 4);
        return _Body(
          icon: Icons.apps_rounded,
          title: 'All apps',
          line: home.apps.length == 1 ? '1 app' : '${home.apps.length} apps',
          size: size,
          extra: recent.isEmpty
              ? null
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final a in recent) HomeAppIcon(container: c, app: a, size: 40)],
                ),
        );
      case 'smart':
        if (!home.homeAssistantConfigured) {
          return _Body(icon: Icons.home_work_rounded, title: 'Smart Home', line: 'Optional add-on', size: size);
        }
        final all = home.entities.value ?? const <HomeEntity>[];
        final lights = all.where((e) => e.domain == 'light' && e.active).length;
        final pinned = [
          for (final id in home.pinnedEntities.value)
            for (final e in all)
              if (e.id == id) e,
        ];
        return _Body(
          icon: Icons.home_work_rounded,
          title: 'Smart Home',
          line: all.isEmpty ? 'Lights, scenes, climate' : (lights == 0 ? 'All lights off' : '$lights light${lights == 1 ? '' : 's'} on'),
          size: size,
          extra: pinned.isEmpty
              ? null
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in pinned.take(4))
                      ActionChip(
                        avatar: Icon(e.active ? Icons.toggle_on_rounded : Icons.toggle_off_outlined, size: 18),
                        label: Text(e.name, overflow: TextOverflow.ellipsis),
                        onPressed: () => unawaited(home.activate(e)),
                      ),
                  ],
                ),
        );
      case 'school':
        final school = home.school;
        // Today's lunch, or the next school day's on a weekend or holiday.
        final day = nextMenuDay(school);
        final lunch = _menuOn(school, 'lunch', day);
        final when = day.year == now.year && day.month == now.month && day.day == now.day
            ? 'Lunch'
            : '${DateFormat('EEEE').format(day)} lunch';
        return _Body(
          icon: Icons.school_rounded,
          title: school.config.value.schoolName.isEmpty ? 'School' : school.config.value.schoolName,
          line: lunch == null || lunch.isEmpty ? school.status(now) : '$when: ${lunch.items.first}',
          size: size,
          extra: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (lunch != null && !lunch.isEmpty) Text(school.status(now), style: const TextStyle(color: Colors.white70, fontSize: 13)),
              if (lunch != null)
                for (final item in lunch.items.skip(1).take(size == _Size.large ? 5 : 2))
                  Text('• $item', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
            ],
          ),
        );
      case 'telugu':
        final calc = home.panchang;
        final today = calc.day(now);
        final (title, line) = teluguTileLines(calc);
        final (rs, re) = today.rahuKalam;
        return _Body(
          icon: Icons.brightness_5_rounded,
          title: title,
          line: line,
          size: size,
          extra: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${today.varaNameTe} · ${nakshatraTe[today.nakshatra]} · ${today.samvatsaraName}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
              Text('Sunrise ${DateFormat.jm().format(today.sunrise)} · Rahu ${DateFormat.jm().format(rs)}–${DateFormat.jm().format(re)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            ],
          ),
        );
      case 'photos':
        if (!home.photos.configured) {
          return _Body(icon: Icons.photo_library_rounded, title: 'Photos', line: 'Immich or a network folder: tap to set up', size: size);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            PhoenixPhotoFrame(key: ValueKey(home.photos.settings.value), container: c, showClock: false, seconds: 15),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black54], stops: [0.6, 1]),
              ),
            ),
            Positioned(
              left: 14,
              bottom: 10,
              child: Row(
                children: [
                  const Icon(Icons.photo_library_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 6),
                  Text(home.photos.settings.value.source == 'immich' ? 'Immich' : 'Photos',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton(
                color: Colors.white70,
                tooltip: 'Photo settings',
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => unawaited(showPhotoSetup(context, c)),
              ),
            ),
          ],
        );
      case 'timers':
        final running = [...c.voiceTimers.timers.value]..sort((a, b) => a.endsAt(now).compareTo(b.endsAt(now)));
        final first = running.firstOrNull;
        String fmt(int s) => s >= 3600 ? '${s ~/ 3600}h ${(s % 3600) ~/ 60}m' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
        return _Body(
          icon: Icons.timer_rounded,
          title: 'Timers',
          line: first == null ? 'None running' : '${first.name.isEmpty ? 'Timer' : first.name} ${fmt(first.remaining(now))}',
          size: size,
          extra: running.length < 2
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final t in running.skip(1).take(3))
                      Text('${t.name.isEmpty ? 'Timer' : t.name} ${fmt(t.remaining(now))}', style: const TextStyle(color: Colors.white, fontSize: 13.5)),
                  ],
                ),
        );
      case 'alarms':
        final upcoming = [
          for (final a in c.alarms.alarms.value)
            if (nextRing(a, now) case final at?) (at, a),
        ]..sort((x, y) => x.$1.compareTo(y.$1));
        final next = upcoming.firstOrNull;
        String when(DateTime at) =>
            '${at.day == now.day ? '' : '${DateFormat('EEE').format(at)} '}${DateFormat.jm().format(at)}';
        return _Body(
          icon: Icons.alarm_rounded,
          title: 'Alarms',
          line: next == null ? 'No alarms set' : 'Next ${when(next.$1)}',
          size: size,
          extra: upcoming.length < 2
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (at, a) in upcoming.skip(1).take(3))
                      Text('${when(at)} ${a.label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
                  ],
                ),
        );
      case 'store':
        return _Body(icon: Icons.storefront_rounded, title: 'App Store', line: 'Free apps for Portal', size: size);
      case 'calendar':
        return _Body(icon: Icons.calendar_month_rounded, title: 'Calendar', line: 'Family calendars', size: size);
      case 'cameras':
        return _Body(icon: Icons.videocam_rounded, title: 'Cameras', line: c.camera.config.defaultView?.name ?? '', size: size);
      default:
        return _Body(icon: Icons.settings_rounded, title: 'Settings', line: 'Home screen, Wi-Fi, more', size: size);
    }
  }
}

Future<(int, bool)> _kidsStatus() async => (await KidsScores.starsToday(), await KidsScores.challengeDone());

MenuDay? _menuOn(SchoolService school, String kind, DateTime day) {
  for (final (slug, _) in school.config.value.menuTypes) {
    if (slug.contains(kind)) return school.menuOn(slug, day);
  }
  return null;
}

enum _Size { small, wide, tall, large }

/// A tile's face: icon, title, a live line, and [extra] when there is room.
class _Body extends StatelessWidget {
  const _Body({required this.icon, required this.title, required this.line, required this.size, this.extra});

  final IconData icon;
  final String title;
  final String line;
  final _Size size;
  final Widget? extra;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: LayoutBuilder(
      builder: (context, box) {
        final roomy = box.maxHeight >= 84;
        final showExtra = extra != null && size != _Size.small && box.maxHeight >= 120;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white, size: roomy ? 30 : 24),
                if (size != _Size.small) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ],
              ],
            ),
            if (showExtra) ...[
              const SizedBox(height: 10),
              Expanded(child: ClipRect(child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: extra))),
            ] else
              const Spacer(),
            if (size == _Size.small)
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            if (roomy || size != _Size.small)
              Text(line, maxLines: size == _Size.small ? 1 : 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13.5, fontWeight: FontWeight.w500)),
          ],
        );
      },
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(14)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFFFFD27A)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

// ── Edit mode ─────────────────────────────────────────────────────────────

/// A tile in edit mode, like a widget on an Android home screen: a white
/// frame; drag the tile to move it, drag the round handle at its corner to
/// resize it (it snaps to whole cells), tap × to hide it.
class _EditFrame extends StatefulWidget {
  const _EditFrame({
    required this.spec,
    required this.resizing,
    required this.onHide,
    required this.onMove,
    required this.onMoveEnd,
    required this.onResizeStart,
    required this.onResize,
    required this.onResizeEnd,
    required this.child,
  });

  final HomeTileSpec spec;
  final bool resizing;
  final VoidCallback onHide;
  final ValueChanged<Offset> onMove;
  final VoidCallback onMoveEnd;
  final VoidCallback onResizeStart;

  /// The size the finger asks for (the tile's size when the drag began
  /// plus how far the handle moved).
  final ValueChanged<Size> onResize;
  final VoidCallback onResizeEnd;
  final Widget child;

  @override
  State<_EditFrame> createState() => _EditFrameState();
}

class _EditFrameState extends State<_EditFrame> {
  Offset _moved = Offset.zero, _pulled = Offset.zero;
  Size _start = Size.zero;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _moved = Offset.zero,
          onPanUpdate: (d) => w.onMove(_moved += d.delta),
          onPanEnd: (_) => w.onMoveEnd(),
          onPanCancel: w.onMoveEnd,
          child: w.child,
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: w.resizing ? 1 : 0.8), width: w.resizing ? 3 : 2),
            ),
          ),
        ),
        if (w.resizing)
          Center(
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)),
                child: Text('${w.spec.w} × ${w.spec.h}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        // Hide (top left).
        Positioned(
          left: -10,
          top: -10,
          child: _Handle(icon: Icons.close_rounded, tooltip: 'Hide tile', onTap: w.onHide),
        ),
        // Resize (bottom right): hold and drag.
        Positioned(
          right: -12,
          bottom: -12,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              _pulled = Offset.zero;
              _start = context.size ?? Size.zero;
              w.onResizeStart();
            },
            onPanUpdate: (d) {
              _pulled += d.delta;
              w.onResize(Size(_start.width + _pulled.dx, _start.height + _pulled.dy));
            },
            onPanEnd: (_) => w.onResizeEnd(),
            onPanCancel: w.onResizeEnd,
            child: const _Handle(icon: Icons.open_in_full_rounded, tooltip: 'Drag to resize', big: true),
          ),
        ),
      ],
    );
  }
}

/// A round white handle on a tile's frame.
class _Handle extends StatelessWidget {
  const _Handle({required this.icon, required this.tooltip, this.onTap, this.big = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final size = big ? 40.0 : 32.0;
    final dot = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Icon(icon, size: size * 0.55, color: const Color(0xFF1F2937)),
    );
    return Tooltip(
      message: tooltip,
      // A finger-sized touch area round the dot.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(6), child: dot),
      ),
    );
  }
}

/// The edit bar under the grid: hidden tiles back, themes, reset, done.
class HomeEditBar extends StatelessWidget {
  const HomeEditBar({super.key, required this.container});
  final AppContainer container;

  static const _names = {
    'telugu': 'Telugu calendar',
    'kids': 'Kids Portal',
    'photos': 'Photos',
    'school': 'School',
    'apps': 'All apps',
    'smart': 'Smart Home',
    'timers': 'Timers',
    'alarms': 'Alarms',
    'store': 'App Store',
    'settings': 'Settings',
    'calendar': 'Calendar',
    'cameras': 'Cameras',
  };

  @override
  Widget build(BuildContext context) {
    final home = container.phoenixHome;
    return ListenableBuilder(
      listenable: Listenable.merge([home.hiddenTiles, home.theme, home.weatherEffects]),
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFF181B21), borderRadius: BorderRadius.circular(24)),
        child: Row(
          children: [
            const Icon(Icons.dashboard_customize_rounded, color: Colors.white),
            const SizedBox(width: 10),
            const Text('Edit home', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(width: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final t in homeThemes)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Tooltip(
                          message: t.name,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => unawaited(home.setTheme(t.id)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: t.tiles.first),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: home.theme.value == t.id ? Colors.white : Colors.transparent, width: 2),
                              ),
                              child: Text(t.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (home.hiddenTiles.value.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Add a tile',
                onSelected: (id) => unawaited(home.setTileHidden(id, false)),
                itemBuilder: (_) => [
                  for (final id in home.hiddenTiles.value) PopupMenuItem(value: id, child: Text(_names[id] ?? id)),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [Icon(Icons.add_circle_outline, color: Colors.white), SizedBox(width: 6), Text('Add tile', style: TextStyle(color: Colors.white))]),
                ),
              ),
            Tooltip(
              message: 'Weather in the background',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.thunderstorm_rounded, color: Colors.white70, size: 20),
                  Switch(
                    value: home.weatherEffects.value,
                    onChanged: (v) => unawaited(home.setWeatherEffects(v)),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () {
                home.editing.value = false;
                unawaited(home.setLayout('today'));
              },
              icon: const Icon(Icons.wb_sunny_rounded),
              label: const Text('Today layout'),
            ),
            TextButton(onPressed: () => unawaited(home.resetTiles()), child: const Text('Reset')),
            const SizedBox(width: 6),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: homeTheme(home.theme.value).accent, foregroundColor: Colors.black),
              onPressed: () => home.editing.value = false,
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
