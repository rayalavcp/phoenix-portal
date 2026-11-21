import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_container.dart';
import '../../managers/launcher/app_launcher_manager.dart';
import '../theme.dart';
import '../toast.dart';

/// Phoenix Home's app pieces: the icon, the tile, the long-press sheet and
/// the full app drawer with search.

/// Decoded icons by package, kept for the session so scrolling the grid or
/// reopening the drawer never decodes an icon twice.
final _iconImages = <String, ImageProvider?>{};

Future<ImageProvider?> _iconFor(AppContainer c, String package) async {
  if (_iconImages.containsKey(package)) return _iconImages[package];
  final Uint8List? bytes = await c.launcher.icon(package);
  final image = bytes == null ? null : MemoryImage(bytes);
  _iconImages[package] = image;
  return image;
}

/// Warm the icons of [apps] so the next screen paints them on its first
/// frame.
void warmHomeIcons(AppContainer c, Iterable<LauncherApp> apps) {
  for (final app in apps) {
    if (!_iconImages.containsKey(app.package)) {
      unawaited(_iconFor(c, app.package));
    }
  }
}

/// An app's launcher icon at [size], a lettered disc while it loads or
/// when the app has none.
class HomeAppIcon extends StatefulWidget {
  const HomeAppIcon({
    super.key,
    required this.container,
    required this.app,
    this.size = 64,
  });

  final AppContainer container;
  final LauncherApp app;
  final double size;

  @override
  State<HomeAppIcon> createState() => _HomeAppIconState();
}

class _HomeAppIconState extends State<HomeAppIcon> {
  ImageProvider? _image;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(HomeAppIcon old) {
    super.didUpdateWidget(old);
    if (old.app.package != widget.app.package) _resolve();
  }

  void _resolve() {
    final package = widget.app.package;
    if (_iconImages.containsKey(package)) {
      _image = _iconImages[package];
      return;
    }
    _image = null;
    unawaited(
      _iconFor(widget.container, package).then((image) {
        if (mounted && widget.app.package == package) {
          setState(() => _image = image);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    if (_image case final image?) {
      return Image(
        image: image,
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      );
    }
    final letter = widget.app.label.trim().isEmpty
        ? '?'
        : widget.app.label.trim()[0].toUpperCase();
    final hue = (widget.app.package.hashCode % 360).abs().toDouble();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: HSLColor.fromAHSL(1, hue, 0.45, 0.38).toColor(),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One app: icon over its label. Tap opens it, long press offers pin,
/// hide and app info.
class HomeAppTile extends StatelessWidget {
  const HomeAppTile({
    super.key,
    required this.container,
    required this.app,
    this.iconSize = 64,
    this.labelColor = Colors.white,
  });

  final AppContainer container;
  final LauncherApp app;
  final double iconSize;
  final Color labelColor;

  @override
  Widget build(BuildContext context) => _Pressable(
    onTap: () => launchHomeApp(context, container, app),
    onLongPress: () => showHomeAppSheet(context, container, app),
    child: SizedBox(
      width: iconSize + 32,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HomeAppIcon(container: container, app: app, size: iconSize),
          const SizedBox(height: 8),
          Text(
            app.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: labelColor,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Open [app] with a short scale-in so the tap reads as a launch, and say
/// so when Android cannot open it.
Future<void> launchHomeApp(
  BuildContext context,
  AppContainer c,
  LauncherApp app,
) async {
  final overlay = Overlay.maybeOf(context);
  // A splash at once: an old Portal can take a second or two to bring the
  // app up, and a tap with no answer reads as a missed tap.
  OverlayEntry? splash;
  if (overlay != null) {
    splash = OverlayEntry(
      builder: (_) => _LaunchSplash(container: c, app: app),
    );
    overlay.insert(splash);
  }
  final ok = await c.phoenixHome.launch(app.package);
  Future<void>.delayed(
    Duration(milliseconds: ok ? 900 : 0),
    () => splash?.remove(),
  );
  if (!ok && overlay != null && overlay.mounted) {
    showToastIn(
      overlay,
      title: "Couldn't open ${app.label}",
      message: 'It may have been uninstalled.',
      kind: ToastKind.error,
    );
    unawaited(c.launcher.refreshInstalled());
  }
}

/// The long-press sheet: pin to the dock, hide, app info.
Future<void> showHomeAppSheet(
  BuildContext context,
  AppContainer c,
  LauncherApp app,
) {
  final home = c.phoenixHome;
  final pinned = home.isFavorite(app.package);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF181B21),
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: HomeAppIcon(container: c, app: app, size: 40),
              title: Text(
                app.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              subtitle: Text(
                app.package,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            const Divider(color: Colors.white12),
            _SheetAction(
              icon: Icons.open_in_new_rounded,
              label: 'Open',
              onTap: () {
                Navigator.pop(sheet);
                unawaited(launchHomeApp(context, c, app));
              },
            ),
            _SheetAction(
              icon: pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
              label: pinned ? 'Remove from dock' : 'Add to dock',
              onTap: () {
                Navigator.pop(sheet);
                unawaited(home.toggleFavorite(app.package));
              },
            ),
            if (pinned) ...[
              _SheetAction(
                icon: Icons.arrow_back_rounded,
                label: 'Move left in dock',
                onTap: () {
                  Navigator.pop(sheet);
                  unawaited(home.moveFavorite(app.package, -1));
                },
              ),
              _SheetAction(
                icon: Icons.arrow_forward_rounded,
                label: 'Move right in dock',
                onTap: () {
                  Navigator.pop(sheet);
                  unawaited(home.moveFavorite(app.package, 1));
                },
              ),
            ],
            _SheetAction(
              icon: Icons.child_care_rounded,
              label: home.isKidsApp(app.package)
                  ? 'Remove from the Kids Portal'
                  : 'Add to the Kids Portal',
              onTap: () {
                Navigator.pop(sheet);
                unawaited(home.toggleKidsApp(app.package));
              },
            ),
            _SheetAction(
              icon: Icons.visibility_off_outlined,
              label: 'Hide from Phoenix Home',
              onTap: () {
                Navigator.pop(sheet);
                unawaited(home.setHidden(app.package, true));
              },
            ),
            _SheetAction(
              icon: Icons.info_outline_rounded,
              label: 'App info (uninstall, permissions)',
              onTap: () {
                Navigator.pop(sheet);
                unawaited(home.openAppInfo(app.package));
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: Phx.ember),
    title: Text(label, style: const TextStyle(color: Colors.white)),
    onTap: onTap,
  );
}

/// A press-down squish for tiles: feedback that costs nothing on an old
/// Portal's GPU.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, this.onTap, this.onLongPress});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) => setState(() => _down = true),
    onTapCancel: () => setState(() => _down = false),
    onTapUp: (_) => setState(() => _down = false),
    onTap: widget.onTap,
    onLongPress: widget.onLongPress,
    child: AnimatedScale(
      scale: _down ? 0.9 : 1,
      duration: const Duration(milliseconds: 110),
      child: widget.child,
    ),
  );
}

/// A big rounded tile with an icon and a label, for the home screen's
/// shortcuts row.
class HomeShortcutTile extends StatelessWidget {
  const HomeShortcutTile({
    super.key,
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Pressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: Colors.white, size: 34),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Every app, alphabetical, with search, a recent row and the hidden
/// apps one tap away.
class HomeAppDrawer extends StatefulWidget {
  const HomeAppDrawer({super.key, required this.container});

  final AppContainer container;

  @override
  State<HomeAppDrawer> createState() => _HomeAppDrawerState();
}

class _HomeAppDrawerState extends State<HomeAppDrawer> {
  final _query = TextEditingController();
  bool _showHidden = false;

  /// A to Z, or most used first.
  bool _byUse = false;

  AppContainer get c => widget.container;

  @override
  void initState() {
    super.initState();
    unawaited(c.launcher.refreshInstalled());
    warmHomeIcons(c, c.phoenixHome.apps);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = c.phoenixHome;
    return ListenableBuilder(
      listenable: Listenable.merge([
        c.launcher.installedRevision,
        home.hidden,
        home.favorites,
        home.usage,
        _query,
      ]),
      builder: (context, _) {
        final q = _query.text.trim().toLowerCase();
        final hiddenApps = [
          for (final a in c.launcher.installed)
            if (home.hidden.value.contains(a.package)) a,
        ];
        final list = _showHidden
            ? hiddenApps
            : [
                for (final a in home.apps)
                  if (q.isEmpty ||
                      a.label.toLowerCase().contains(q) ||
                      a.package.toLowerCase().contains(q))
                    a,
              ];
        if (_byUse && !_showHidden) {
          int uses(LauncherApp a) => home.usage.value[a.package]?.count ?? 0;
          list.sort((a, b) => uses(b).compareTo(uses(a)));
        }
        final recent = q.isEmpty && !_showHidden ? home.recent(8) : const [];
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF15181F), Color(0xFF0B0D10)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 24, 8),
                  child: Row(
                    children: [
                      IconButton(
                        iconSize: 30,
                        color: Colors.white,
                        tooltip: 'Back',
                        onPressed: () => _showHidden
                            ? setState(() => _showHidden = false)
                            : home.appsOpen.value = false,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _showHidden ? 'Hidden apps' : 'All apps',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 24),
                      if (!_showHidden)
                        Expanded(
                          child: TextField(
                            controller: _query,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search apps',
                              hintStyle: const TextStyle(color: Colors.white54),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                color: Colors.white70,
                              ),
                              suffixIcon: q.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        color: Colors.white70,
                                      ),
                                      onPressed: _query.clear,
                                    ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.08),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(99),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      if (!_showHidden) ...[
                        const SizedBox(width: 12),
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            selectedForegroundColor: const Color(0xFF2A0A00),
                            selectedBackgroundColor: Phx.ember,
                            side: const BorderSide(color: Colors.white24),
                          ),
                          segments: const [
                            ButtonSegment(value: false, label: Text('A–Z')),
                            ButtonSegment(value: true, label: Text('Most used')),
                          ],
                          selected: {_byUse},
                          onSelectionChanged: (v) =>
                              setState(() => _byUse = v.first),
                        ),
                      ],
                      if (!_showHidden && hiddenApps.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        TextButton.icon(
                          onPressed: () => setState(() => _showHidden = true),
                          icon: const Icon(Icons.visibility_off_outlined),
                          label: Text('Hidden (${hiddenApps.length})'),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? Center(
                          child: Text(
                            c.launcher.installed.isEmpty
                                ? 'Loading apps…'
                                : 'No apps match "${_query.text}"',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                            ),
                          ),
                        )
                      : CustomScrollView(
                          slivers: [
                            if (recent.isNotEmpty) ...[
                              const _SectionLabel('Recent'),
                              _grid([for (final a in recent) a]),
                              _SectionLabel(_byUse ? 'Most used' : 'A to Z'),
                            ],
                            _grid(list),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 32),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _grid(List<LauncherApp> apps) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    sliver: SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 128,
        mainAxisExtent: 120,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) => _showHidden
            ? _HiddenTile(container: c, app: apps[i])
            : Center(
                child: HomeAppTile(container: c, app: apps[i]),
              ),
        childCount: apps.length,
      ),
    ),
  );
}

class _HiddenTile extends StatelessWidget {
  const _HiddenTile({required this.container, required this.app});

  final AppContainer container;
  final LauncherApp app;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: () => unawaited(container.phoenixHome.setHidden(app.package, false)),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Opacity(
          opacity: 0.5,
          child: HomeAppIcon(container: container, app: app, size: 56),
        ),
        const SizedBox(height: 6),
        Text(
          app.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70),
        ),
        const Text(
          'Tap to show',
          style: TextStyle(color: Phx.gold, fontSize: 12),
        ),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Phx.gold,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    ),
  );
}

/// "Opening YouTube": the app's icon growing out of the dark, shown from
/// the tap until the app is up.
class _LaunchSplash extends StatelessWidget {
  const _LaunchSplash({required this.container, required this.app});

  final AppContainer container;
  final LauncherApp app;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => ColoredBox(
        color: Color.fromRGBO(11, 13, 16, 0.92 * t),
        child: Center(
          child: Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HomeAppIcon(container: container, app: app, size: 112),
          const SizedBox(height: 20),
          Text(
            'Opening ${app.label}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    ),
  );
}
