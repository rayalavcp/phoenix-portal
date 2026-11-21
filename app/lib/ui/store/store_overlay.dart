import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_container.dart';
import '../../managers/store/store_manager.dart';
import '../kit.dart' show PhoenixMark;
import '../theme.dart';

/// Phoenix Portal's app store: a curated, free catalog for Portals,
/// installed from F-Droid's current builds. Full screen over the dashboard,
/// opened from the menu (openStore).
class StoreOverlay extends StatelessWidget {
  const StoreOverlay({super.key, required this.container});
  final AppContainer container;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: container.store.visible,
    builder: (context, visible, _) => AnimatedSwitcher(
      duration: Ks.motion,
      switchInCurve: Ks.motionIn,
      switchOutCurve: Ks.motionOut,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a),
          child: child,
        ),
      ),
      child: visible ? _StorePage(key: const ValueKey('store'), container: container) : const SizedBox.shrink(),
    ),
  );
}

const _icons = <String, IconData>{
  'videogame': Icons.sports_esports_rounded,
  'kart': Icons.directions_car_filled_rounded,
  'chess': Icons.castle_rounded,
  'grid': Icons.grid_on_rounded,
  'factory': Icons.factory_rounded,
  'school': Icons.school_rounded,
  'palette': Icons.palette_rounded,
  'memory': Icons.style_rounded,
  'cards': Icons.quiz_rounded,
  'play': Icons.play_circle_fill_rounded,
  'movie': Icons.movie_rounded,
  'smart_display': Icons.smart_display_rounded,
  'podcast': Icons.podcasts_rounded,
  'home': Icons.home_rounded,
  'store': Icons.storefront_rounded,
  'store_alt': Icons.shop_rounded,
  'folder': Icons.folder_rounded,
};

class _StorePage extends StatefulWidget {
  const _StorePage({super.key, required this.container});
  final AppContainer container;

  @override
  State<_StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<_StorePage> {
  String? _category;

  StoreManager get store => widget.container.store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 16, 4),
              child: Row(
                children: [
                  const PhoenixMark(size: 40),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('App Store', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4)),
                        Text(
                          'Free apps picked for Portal. Installed from F-Droid, always the current version.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => unawaited(widget.container.commands.execute('hideStore', const {})),
                    icon: const Icon(Icons.close_rounded),
                    iconSize: 28,
                  ),
                ],
              ),
            ),
            ValueListenableBuilder<List<String>>(
              valueListenable: store.categories,
              builder: (context, categories, _) => SizedBox(
                height: 60,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(28, 10, 28, 6),
                  children: [
                    for (final c in [null, ...categories])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c ?? 'All'),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                          showCheckmark: false,
                          shape: const StadiumBorder(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: Listenable.merge([store.apps, store.states]),
                builder: (context, _) {
                  final cats = store.categories.value;
                  final apps = [
                    for (final a in store.apps.value)
                      if (_category == null || a.category == _category) a,
                  ];
                  return LayoutBuilder(
                    builder: (context, box) {
                      final cols = (box.maxWidth / 380).floor().clamp(1, 4);
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          mainAxisExtent: 172,
                        ),
                        itemCount: apps.length,
                        itemBuilder: (context, i) => _AppCard(
                          app: apps[i],
                          state: store.stateOf(apps[i].package),
                          colors: Phx.badges[cats.indexOf(apps[i].category).clamp(0, 99) % Phx.badges.length],
                          onInstall: () => unawaited(store.install(apps[i])),
                          onOpen: () => unawaited(widget.container.commands.execute('launchApp', {'package': apps[i].package})),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({required this.app, required this.state, required this.colors, required this.onInstall, required this.onOpen});
  final StoreApp app;
  final StoreItemState state;
  final List<Color> colors;
  final VoidCallback onInstall;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: colors),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(_icons[app.icon] ?? Icons.apps_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    app.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
                  ),
                  const Spacer(),
                  _Action(state: state, onInstall: onInstall, onOpen: onOpen),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.state, required this.onInstall, required this.onOpen});
  final StoreItemState state;
  final VoidCallback onInstall;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final Widget child = switch (state.phase) {
      StorePhase.resolving || StorePhase.installing => Row(
        key: ValueKey(state.phase),
        children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 10),
          Text(state.phase == StorePhase.resolving ? 'Finding the latest version…' : 'Installing…', style: small),
        ],
      ),
      StorePhase.downloading => Column(
        key: const ValueKey('dl'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: state.progress, minHeight: 8),
          ),
          const SizedBox(height: 6),
          Text(
            state.progress == null ? 'Downloading…' : 'Downloading ${(state.progress! * 100).round()}%',
            style: small,
          ),
        ],
      ),
      StorePhase.confirm => Text(
        'Confirm the install on the screen',
        key: const ValueKey('confirm'),
        style: small?.copyWith(color: scheme.secondary, fontWeight: FontWeight.w600),
      ),
      StorePhase.failed => Row(
        key: const ValueKey('failed'),
        children: [
          Expanded(
            child: Text(state.message ?? 'Install failed', maxLines: 2, overflow: TextOverflow.ellipsis, style: small?.copyWith(color: scheme.error)),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onInstall, child: const Text('Retry')),
        ],
      ),
      StorePhase.idle => Row(
        key: ValueKey(state.installed),
        children: [
          if (state.installed) ...[
            Icon(Icons.check_circle_rounded, color: scheme.tertiary, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text('Installed ${state.version}', maxLines: 1, overflow: TextOverflow.ellipsis, style: small)),
            FilledButton.tonal(onPressed: onOpen, child: const Text('Open')),
          ] else ...[
            const Spacer(),
            FilledButton(onPressed: onInstall, child: const Text('Install')),
          ],
        ],
      ),
    };
    return AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: child);
  }
}
