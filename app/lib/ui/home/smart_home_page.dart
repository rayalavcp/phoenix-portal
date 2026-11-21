import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_container.dart';
import '../../managers/home/phoenix_home_manager.dart';
import '../../managers/settings/definitions.dart' as defs;
import '../theme.dart';

/// Phoenix Home's Smart Home page: Home Assistant as an add-on. Quick
/// controls for lights, switches, covers, locks, climate, players, scenes
/// and scripts, pinned favourites on top, and the full dashboard one tap
/// away. Without Home Assistant it says how to connect it, and nothing
/// else on Phoenix Home is affected.
class SmartHomePage extends StatefulWidget {
  const SmartHomePage({
    super.key,
    required this.container,
    required this.onOpenSettings,
  });

  final AppContainer container;

  /// Opens the app's settings (behind the PIN, when one is set).
  final VoidCallback onOpenSettings;

  @override
  State<SmartHomePage> createState() => _SmartHomePageState();
}

class _SmartHomePageState extends State<SmartHomePage> {
  String _area = '';
  Timer? _refresh;

  AppContainer get c => widget.container;

  @override
  void initState() {
    super.initState();
    if (c.phoenixHome.homeAssistantConfigured) {
      unawaited(c.phoenixHome.loadEntities());
      // States change behind our back (someone flips a wall switch):
      // refresh while the page is up.
      _refresh = Timer.periodic(
        const Duration(seconds: 20),
        (_) => unawaited(c.phoenixHome.loadEntities()),
      );
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = c.phoenixHome;
    final hasDashboard = c.settings.get(defs.startUrl).isNotEmpty;
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
                    onPressed: () => home.smartHomeOpen.value = false,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.home_work_rounded, color: Phx.ember, size: 30),
                  const SizedBox(width: 12),
                  const Text(
                    'Smart Home',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  if (home.homeAssistantConfigured)
                    IconButton(
                      color: Colors.white70,
                      tooltip: 'Refresh',
                      onPressed: () => unawaited(home.loadEntities()),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  if (hasDashboard) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Phx.ember,
                        foregroundColor: const Color(0xFF2A0A00),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      onPressed: home.openDashboard,
                      icon: const Icon(Icons.dashboard_rounded),
                      label: const Text('Open dashboard'),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: home.homeAssistantConfigured
                  ? _controls(home)
                  : _NotConnected(onOpenSettings: widget.onOpenSettings),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(PhoenixHomeManager home) => ListenableBuilder(
    listenable: Listenable.merge([
      home.entities,
      home.entitiesLoading,
      home.entitiesError,
      home.pinnedEntities,
    ]),
    builder: (context, _) {
      final all = home.entities.value;
      if (all == null) {
        if (home.entitiesError.value case final error?) {
          return _Message(
            icon: Icons.cloud_off_rounded,
            title: error,
            body:
                'Everything else on Phoenix Home keeps working. '
                'Check that Home Assistant is running, then refresh.',
          );
        }
        return const Center(child: CircularProgressIndicator());
      }
      if (all.isEmpty) {
        return const _Message(
          icon: Icons.lightbulb_outline_rounded,
          title: 'No devices to control yet',
          body:
              'Lights, switches, covers, locks, climate, players, scenes and '
              'scripts from Home Assistant show up here.',
        );
      }
      final areas = {
        for (final e in all)
          if ((e.area ?? '').isNotEmpty) e.area!,
      }.toList()..sort();
      final shown = [
        for (final e in all)
          if (_area.isEmpty || e.area == _area) e,
      ];
      final pinned = [
        for (final id in home.pinnedEntities.value)
          for (final e in all)
            if (e.id == id) e,
      ];
      final groups = <String, List<HomeEntity>>{};
      for (final domain in homeEntityDomains) {
        final list = [
          for (final e in shown)
            if (e.domain == domain) e,
        ];
        if (list.isNotEmpty) groups[domain] = list;
      }
      return CustomScrollView(
        slivers: [
          if (home.entitiesError.value case final error?)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
                child: Text(
                  '$error Showing the last known states.',
                  style: const TextStyle(color: Phx.gold),
                ),
              ),
            ),
          if (areas.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    _AreaChip(
                      label: 'All rooms',
                      selected: _area.isEmpty,
                      onTap: () => setState(() => _area = ''),
                    ),
                    for (final a in areas)
                      _AreaChip(
                        label: a,
                        selected: _area == a,
                        onTap: () => setState(() => _area = a),
                      ),
                  ],
                ),
              ),
            ),
          if (pinned.isNotEmpty && _area.isEmpty) ...[
            const _GroupLabel('Favourites'),
            _grid(home, pinned),
          ],
          for (final entry in groups.entries) ...[
            _GroupLabel(_domainTitle(entry.key)),
            _grid(home, entry.value),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(28, 0, 28, 32),
              child: Text(
                'Tip: press and hold a device to add it to Favourites.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _grid(PhoenixHomeManager home, List<HomeEntity> list) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    sliver: SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 230,
        mainAxisExtent: 112,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) => _EntityTile(
          entity: list[i],
          pinned: home.isPinnedEntity(list[i].id),
          onTap: () async {
            final ok = await home.activate(list[i]);
            if (!ok && context.mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(content: Text("Couldn't reach ${list[i].name}")),
              );
            }
          },
          onLongPress: () => unawaited(home.togglePinnedEntity(list[i].id)),
        ),
        childCount: list.length,
      ),
    ),
  );
}

String _domainTitle(String domain) => switch (domain) {
  'light' => 'Lights',
  'switch' => 'Switches',
  'fan' => 'Fans',
  'cover' => 'Blinds & doors',
  'climate' => 'Climate',
  'lock' => 'Locks',
  'media_player' => 'Speakers & TVs',
  'input_boolean' => 'Toggles',
  'scene' => 'Scenes',
  'script' => 'Scripts',
  _ => domain,
};

IconData _domainIcon(HomeEntity e) => switch (e.domain) {
  'light' => e.active ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded,
  'switch' => e.active ? Icons.toggle_on_rounded : Icons.toggle_off_outlined,
  'fan' => Icons.mode_fan_off_outlined,
  'cover' => e.active ? Icons.blinds_rounded : Icons.blinds_closed_rounded,
  'climate' => Icons.thermostat_rounded,
  'lock' => e.active ? Icons.lock_open_rounded : Icons.lock_rounded,
  'media_player' => e.active ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
  'scene' => Icons.palette_rounded,
  'script' => Icons.play_arrow_rounded,
  _ => e.active ? Icons.check_circle_rounded : Icons.circle_outlined,
};

class _EntityTile extends StatelessWidget {
  const _EntityTile({
    required this.entity,
    required this.pinned,
    required this.onTap,
    required this.onLongPress,
  });

  final HomeEntity entity;
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final on = entity.active && !entity.runs;
    return Material(
      color: on ? const Color(0xFF3A1C0E) : const Color(0xFF1C2028),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: on ? Phx.ember : Colors.white.withValues(alpha: 0.06),
              width: on ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _domainIcon(entity),
                    color: on ? Phx.gold : Colors.white70,
                    size: 30,
                  ),
                  const Spacer(),
                  if (pinned)
                    const Icon(Icons.star_rounded, color: Phx.gold, size: 18),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entity.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    entity.runs ? 'Tap to run' : entity.state,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: on ? Phx.gold : Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AreaChip extends StatelessWidget {
  const _AreaChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: Phx.ember,
      backgroundColor: const Color(0xFF1C2028),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF2A0A00) : Colors.white,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide.none,
      showCheckmark: false,
    ),
  );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 10),
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

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Phx.ember, size: 64),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    ),
  );
}

class _NotConnected extends StatelessWidget {
  const _NotConnected({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.home_work_outlined, color: Phx.ember, size: 72),
          const SizedBox(height: 16),
          const Text(
            'Home Assistant is optional',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Connect Home Assistant to control lights, switches, locks, '
            'climate and scenes from here, and to open your dashboard. '
            'Apps, the Kids Portal, timers and the weather work without it.',
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
            onPressed: onOpenSettings,
            icon: const Icon(Icons.link_rounded),
            label: const Text('Connect Home Assistant'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Or from a computer: open the admin page at port 2324 and go to '
            'Home Assistant.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    ),
  );
}
