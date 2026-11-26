import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../app_container.dart';
import '../../managers/home/phoenix_home_manager.dart';
import '../../managers/launcher/app_launcher_manager.dart';
import '../toast.dart';
import 'home_apps.dart';

/// The family's own tiles on the Tiles home screen (see [CustomTile]): a
/// Home Assistant entity (its state; tap to switch it), a web page, a Home
/// Assistant camera (a still that refreshes; tap for a bigger view) or an
/// app. Made and changed with [showCustomTileEditor].

/// What each kind is called, and its icon.
const customTileKinds = {
  'entity': ('Smart home device', Icons.lightbulb_outline_rounded),
  'web': ('Web page', Icons.public_rounded),
  'camera': ('Camera', Icons.videocam_rounded),
  'app': ('App', Icons.apps_rounded),
};

/// Entities a tap switches (or runs); others only show their state.
const _tappable = {
  'light', 'switch', 'fan', 'input_boolean', 'lock', 'cover', 'scene', 'script', 'climate', 'media_player', 'automation',
};

IconData _entityIcon(String entityId, String state) {
  final domain = entityId.split('.').first;
  final on = const {'on', 'open', 'unlocked', 'playing', 'home'}.contains(state);
  return switch (domain) {
    'light' => on ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded,
    'switch' || 'input_boolean' => on ? Icons.toggle_on_rounded : Icons.toggle_off_outlined,
    'fan' => Icons.mode_fan_off_outlined,
    'lock' => state == 'locked' ? Icons.lock_rounded : Icons.lock_open_rounded,
    'cover' => on ? Icons.garage_rounded : Icons.garage_outlined,
    'climate' => Icons.thermostat_rounded,
    'media_player' => Icons.speaker_rounded,
    'scene' => Icons.palette_rounded,
    'script' || 'automation' => Icons.play_circle_outline_rounded,
    'binary_sensor' => on ? Icons.sensors_rounded : Icons.sensors_off_rounded,
    'person' || 'device_tracker' => Icons.person_rounded,
    'weather' => Icons.wb_cloudy_rounded,
    _ => Icons.speed_rounded,
  };
}

/// An entity's state as shown on a tile: the value with its unit, or a
/// friendly word.
String entityStateText(String state, Map<String, Object?> attributes) {
  final unit = attributes['unit_of_measurement'];
  if (unit is String && unit.isNotEmpty && double.tryParse(state) != null) {
    final n = double.parse(state);
    final shown = n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
    return '$shown $unit';
  }
  return switch (state) {
    'on' => 'On',
    'off' => 'Off',
    'open' => 'Open',
    'closed' => 'Closed',
    'locked' => 'Locked',
    'unlocked' => 'Unlocked',
    'home' => 'Home',
    'not_home' => 'Away',
    'unavailable' => 'Unavailable',
    'unknown' => '—',
    final s => s.isEmpty ? '—' : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' '),
  };
}

/// The face of a custom tile.
class CustomTileFace extends StatefulWidget {
  const CustomTileFace({super.key, required this.container, required this.tile, required this.small});
  final AppContainer container;
  final CustomTile tile;

  /// A one-cell tile: the title goes under the icon.
  final bool small;

  @override
  State<CustomTileFace> createState() => _CustomTileFaceState();
}

class _CustomTileFaceState extends State<CustomTileFace> {
  Timer? _timer;
  String _state = '';
  Map<String, Object?> _attributes = const {};
  Uint8List? _frame;
  bool _failed = false;

  CustomTile get t => widget.tile;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(CustomTileFace old) {
    super.didUpdateWidget(old);
    if (old.tile.target != t.target || old.tile.kind != t.kind) {
      _timer?.cancel();
      _frame = null;
      _state = '';
      _start();
    }
  }

  void _start() {
    if (t.kind == 'entity') {
      unawaited(_readState());
      _timer = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_readState()));
    } else if (t.kind == 'camera') {
      unawaited(_readFrame());
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_readFrame()));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _readState() async {
    final r = await readEntityState(widget.container, t.target);
    if (!mounted) return;
    setState(() {
      _failed = r == null;
      if (r != null) {
        _state = r.$1;
        _attributes = r.$2;
      }
    });
  }

  Future<void> _readFrame() async {
    final bytes = await readCameraFrame(widget.container, t.target);
    if (!mounted) return;
    setState(() {
      _failed = bytes == null && _frame == null;
      if (bytes != null) _frame = bytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (t.kind) {
      case 'camera':
        final frame = _frame;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (frame != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.memory(frame, fit: BoxFit.cover, gaplessPlayback: true),
              )
            else
              Center(
                child: Icon(_failed ? Icons.videocam_off_rounded : Icons.videocam_rounded, color: Colors.white70, size: 36),
              ),
            Positioned(left: 12, bottom: 10, right: 12, child: _label(t.title, shadow: true)),
          ],
        );
      case 'app':
        return Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, box) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HomeAppIcon(
                  container: widget.container,
                  app: LauncherApp(package: t.target, label: t.title),
                  size: box.maxHeight >= 100 ? 40 : 28,
                ),
                const Spacer(),
                _label(t.title),
              ],
            ),
          ),
        );
      case 'web':
        return _face(Icons.public_rounded, t.title, Uri.tryParse(t.target)?.host ?? t.target);
      default:
        return _face(
          _entityIcon(t.target, _state),
          t.title,
          _failed ? 'Not reachable' : (_state.isEmpty ? '…' : entityStateText(_state, _attributes)),
          big: true,
        );
    }
  }

  Widget _label(String text, {bool shadow = false}) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.w800,
      shadows: shadow ? const [Shadow(blurRadius: 8, color: Colors.black54)] : null,
    ),
  );

  Widget _face(IconData icon, String title, String line, {bool big = false}) => Padding(
    padding: const EdgeInsets.all(14),
    child: LayoutBuilder(
      builder: (context, box) {
        final roomy = box.maxHeight >= 100;
        final text = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (big)
              Text(line, style: TextStyle(color: Colors.white, fontSize: roomy ? 24 : 18, fontWeight: FontWeight.w800)),
            ConstrainedBox(constraints: BoxConstraints(maxWidth: box.maxWidth), child: _label(title)),
            if (!big && roomy)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth),
                child: Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                ),
              ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: roomy ? 28 : 22),
            const Spacer(),
            Flexible(
              flex: 4,
              child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.bottomLeft, child: text),
            ),
          ],
        );
      },
    ),
  );
}

/// An entity's state and attributes from Home Assistant (null: not
/// reachable).
Future<(String, Map<String, Object?>)?> readEntityState(AppContainer c, String entityId) async {
  final auth = c.phoenixHome.homeAssistantAuth;
  if (auth.base.isEmpty || auth.token.isEmpty) return null;
  try {
    final res = await http
        .get(Uri.parse('${auth.base}/api/states/$entityId'), headers: {'Authorization': 'Bearer ${auth.token}'})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    if (data is! Map) return null;
    final attrs = data['attributes'];
    return ('${data['state'] ?? ''}', attrs is Map ? attrs.cast<String, Object?>() : const <String, Object?>{});
  } catch (_) {
    return null;
  }
}

/// A still from a Home Assistant camera (null: none).
Future<Uint8List?> readCameraFrame(AppContainer c, String entityId) async {
  final auth = c.phoenixHome.homeAssistantAuth;
  if (auth.base.isEmpty || auth.token.isEmpty) return null;
  try {
    final res = await http
        .get(Uri.parse('${auth.base}/api/camera_proxy/$entityId'), headers: {'Authorization': 'Bearer ${auth.token}'})
        .timeout(const Duration(seconds: 8));
    return res.statusCode == 200 && res.bodyBytes.isNotEmpty ? res.bodyBytes : null;
  } catch (_) {
    return null;
  }
}

/// What a tap on a custom tile does.
Future<void> openCustomTile(BuildContext context, AppContainer c, CustomTile t) async {
  final overlay = Overlay.maybeOf(context);
  void problem(String title, String? message) {
    if (overlay != null && overlay.mounted) showToastIn(overlay, title: title, message: message, kind: ToastKind.error);
  }

  switch (t.kind) {
    case 'web':
      final r = await c.commands.execute('showLinkPage', {'url': t.target});
      if (!r.ok) problem("Couldn't open ${t.title}", r.error);
    case 'app':
      if (!await c.phoenixHome.launch(t.target)) problem("Couldn't open ${t.title}", 'Is the app still installed?');
    case 'camera':
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _CameraView(container: c, tile: t)),
      );
    default:
      final domain = t.target.split('.').first;
      if (!_tappable.contains(domain)) return;
      final now = await readEntityState(c, t.target);
      final ok = await c.phoenixHome.activate(
        HomeEntity(id: t.target, name: t.title, state: now?.$1 ?? 'off', domain: domain),
      );
      if (!ok) problem("Couldn't switch ${t.title}", 'Home Assistant is not reachable right now.');
  }
}

/// A camera, bigger, refreshing every two seconds; tap to close.
class _CameraView extends StatefulWidget {
  const _CameraView({required this.container, required this.tile});
  final AppContainer container;
  final CustomTile tile;

  @override
  State<_CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<_CameraView> {
  Timer? _timer;
  Uint8List? _frame;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_read()));
  }

  Future<void> _read() async {
    final f = await readCameraFrame(widget.container, widget.tile.target);
    if (mounted && f != null) setState(() => _frame = f);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_frame case final f?)
            Image.memory(f, fit: BoxFit.contain, gaplessPlayback: true)
          else
            const Center(child: CircularProgressIndicator()),
          Positioned(
            left: 24,
            top: 20,
            child: Text(widget.tile.title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          const Positioned(right: 20, top: 16, child: Icon(Icons.close_rounded, color: Colors.white, size: 32)),
        ],
      ),
    ),
  );
}

/// Make a tile ([existing] null) or change or delete one.
Future<void> showCustomTileEditor(BuildContext context, AppContainer c, {CustomTile? existing}) =>
    showDialog<void>(context: context, builder: (_) => _Editor(container: c, existing: existing));

class _Editor extends StatefulWidget {
  const _Editor({required this.container, this.existing});
  final AppContainer container;
  final CustomTile? existing;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late String _kind = widget.existing?.kind ?? 'entity';
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _target = TextEditingController(text: widget.existing?.target ?? '');
  List<(String, String)> _entities = const []; // id, name
  bool _loading = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    unawaited(_loadEntities());
  }

  Future<void> _loadEntities() async {
    if (!widget.container.phoenixHome.homeAssistantConfigured) return;
    setState(() => _loading = true);
    final r = await widget.container.commands.execute('haListEntities', const {});
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok && r.data is List) {
        _entities = [
          for (final e in r.data as List)
            if (e is Map && '${e['entity_id'] ?? ''}'.isNotEmpty) ('${e['entity_id']}', '${e['name'] ?? e['entity_id']}'),
        ]..sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    super.dispose();
  }

  List<(String, String)> get _choices => switch (_kind) {
    'camera' => [for (final e in _entities) if (e.$1.startsWith('camera.')) e],
    'entity' => [for (final e in _entities) if (!e.$1.startsWith('camera.')) e],
    'app' => [for (final a in widget.container.phoenixHome.apps) (a.package, a.label)],
    _ => const [],
  };

  Future<void> _save() async {
    final home = widget.container.phoenixHome;
    var target = _target.text.trim();
    if (_kind == 'web' && target.isNotEmpty && !target.contains('://')) target = 'https://$target';
    final title = _title.text.trim();
    if (target.isEmpty) {
      setState(() => _error = _kind == 'web' ? 'Type the address of the page.' : 'Pick what the tile shows.');
      return;
    }
    if (_kind == 'web' && !(Uri.tryParse(target)?.hasAuthority ?? false)) {
      setState(() => _error = "That doesn't look like a web address.");
      return;
    }
    final existing = widget.existing;
    if (existing != null) {
      await home.updateCustomTile(existing.id, title: title, target: target);
    } else {
      final made = await home.addCustomTile(_kind, title, target);
      if (made == null) {
        setState(() => _error = "Couldn't make the tile.");
        return;
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await widget.container.phoenixHome.removeCustomTile(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final needsHa = _kind == 'entity' || _kind == 'camera';
    final haMissing = needsHa && !widget.container.phoenixHome.homeAssistantConfigured;
    final choices = _choices;
    return AlertDialog(
      title: Text(_editing ? 'Change tile' : 'New tile'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_editing)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final MapEntry(key: k, value: (name, icon)) in customTileKinds.entries)
                      ChoiceChip(
                        avatar: Icon(icon, size: 18),
                        label: Text(name),
                        selected: _kind == k,
                        onSelected: (_) => setState(() {
                          _kind = k;
                          _target.clear();
                          _error = null;
                        }),
                      ),
                  ],
                ),
              const SizedBox(height: 14),
              if (haMissing)
                const Text('Connect Home Assistant first (Settings > Home Assistant).')
              else if (_kind == 'web')
                TextField(
                  controller: _target,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Address', hintText: 'https://example.com'),
                )
              else if (_loading)
                const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
              else
                Autocomplete<(String, String)>(
                  initialValue: TextEditingValue(text: _target.text),
                  displayStringForOption: (o) => o.$2,
                  optionsBuilder: (v) {
                    final q = v.text.toLowerCase();
                    return choices.where((o) => q.isEmpty || o.$1.toLowerCase().contains(q) || o.$2.toLowerCase().contains(q)).take(40);
                  },
                  onSelected: (o) => setState(() {
                    _target.text = o.$1;
                    if (_title.text.trim().isEmpty) _title.text = o.$2;
                    _error = null;
                  }),
                  fieldViewBuilder: (context, field, focus, _) => TextField(
                    controller: field,
                    focusNode: focus,
                    decoration: InputDecoration(
                      labelText: switch (_kind) { 'app' => 'App', 'camera' => 'Camera', _ => 'Device or sensor' },
                      hintText: 'Start typing to search',
                      helperText: _target.text.isEmpty ? null : _target.text,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'Name on the tile')),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_editing)
          TextButton.icon(
            onPressed: () => unawaited(_delete()),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete tile'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: haMissing ? null : () => unawaited(_save()), child: Text(_editing ? 'Save' : 'Add')),
      ],
    );
  }
}
