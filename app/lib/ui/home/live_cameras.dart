import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../app_container.dart';
import '../../managers/camera/models.dart';
import '../camera_view_overlay.dart' show CameraPlayer;

/// The Today screen's camera card: Home Assistant cameras, live. Swipe
/// across the card to go from one camera to the next (the doorbell first);
/// tap to open it full screen. Only the camera on the card streams.
class LiveCamerasCard extends StatefulWidget {
  const LiveCamerasCard({super.key, required this.container, required this.entities});

  final AppContainer container;
  final List<String> entities;

  @override
  State<LiveCamerasCard> createState() => _LiveCamerasCardState();
}

class _LiveCamerasCardState extends State<LiveCamerasCard> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entities = widget.entities;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF0B0F18)),
          PageView.builder(
            controller: _pages,
            itemCount: entities.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => _LiveCamera(key: ValueKey(entities[i]), container: widget.container, entity: entities[i]),
          ),
          if (entities.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < entities.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _page ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: i == _page ? 0.95 : 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "camera.front_door" → "Front door".
String cameraLabel(String entity, [String? name]) {
  if (name != null && name.trim().isNotEmpty) return name.trim();
  final raw = entity.split('.').last.replaceAll('_', ' ').trim();
  return raw.isEmpty ? 'Camera' : raw[0].toUpperCase() + raw.substring(1);
}

class _LiveCamera extends StatefulWidget {
  const _LiveCamera({super.key, required this.container, required this.entity});

  final AppContainer container;
  final String entity;

  @override
  State<_LiveCamera> createState() => _LiveCameraState();
}

class _LiveCameraState extends State<_LiveCamera> {
  CameraViewConfig? _view;
  String? _name;
  bool _snapshots = false;

  // Snapshot fallback: when the live view cannot be set up.
  Uint8List? _frame;
  DateTime? _at;
  bool _failed = false;
  Timer? _timer;

  AppContainer get c => widget.container;

  @override
  void initState() {
    super.initState();
    unawaited(_setUp());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  CameraSource? _source() {
    for (final cam in c.camera.config.cameras) {
      if (cam.kind == 'ha' && cam.entityId == widget.entity) return cam;
    }
    return null;
  }

  /// Finds (or makes) a one-camera view of this entity in the app's camera
  /// setup, which plays it live over WebRTC, HLS or MJPEG.
  Future<void> _setUp() async {
    try {
      var source = _source();
      if (source == null) {
        await c.commands.execute('cameraImportHomeAssistant', const {});
        source = _source();
      }
      if (source == null) throw 'not in Home Assistant';
      _name = source.name;
      CameraViewConfig? view;
      for (final v in c.camera.config.views) {
        if (v.cameraIds.length == 1 && v.cameraIds.first == source.id) view = v;
      }
      if (view == null) {
        final result = await c.commands.execute('cameraPutView', {
          'id': '',
          'name': '${cameraLabel(widget.entity, source.name)} (live)',
          'cameraIds': [source.id],
          'showCameraNames': false,
        });
        if (!result.ok || result.data is! Map) throw result.error ?? 'no view';
        view = CameraViewConfig.fromJson((result.data as Map).cast<String, Object?>());
      }
      if (mounted) setState(() => _view = view);
    } catch (_) {
      if (!mounted) return;
      setState(() => _snapshots = true);
      unawaited(_grab());
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_grab()));
    }
  }

  Future<void> _grab() async {
    final auth = c.phoenixHome.homeAssistantAuth;
    final base = auth.base.trim().replaceFirst(RegExp(r'/+$'), '');
    if (base.isEmpty || auth.token.isEmpty) return;
    try {
      final res = await http
          .get(Uri.parse('$base/api/camera_proxy/${widget.entity}'), headers: {'Authorization': 'Bearer ${auth.token}'})
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _failed = res.statusCode != 200 || res.bodyBytes.isEmpty;
        if (!_failed) {
          _frame = res.bodyBytes;
          _at = DateTime.now();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _openFull() {
    final view = _view;
    if (view != null) {
      c.camera.showView(view.id);
    } else {
      unawaited(_grab());
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = cameraLabel(widget.entity, _name);
    final view = _view;
    return GestureDetector(
      onTap: _openFull,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (view != null)
            IgnorePointer(child: CameraPlayer(container: c, view: view, interactive: false))
          else if (_snapshots && _frame != null)
            Image.memory(_frame!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.shrink())
          else
            Center(
              child: _snapshots
                  ? Icon(_failed ? Icons.videocam_off_rounded : Icons.videocam_rounded, color: Colors.white38, size: 40)
                  : const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white54)),
            ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Colors.transparent], stops: [0, 0.4]),
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: 10,
            right: 14,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: view != null ? Colors.redAccent : Colors.white24,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(view != null ? 'LIVE' : 'PHOTO', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5))),
                if (_snapshots && _at != null) Text(DateFormat.jms().format(_at!), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const Icon(Icons.open_in_full_rounded, color: Colors.white70, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Every camera in Home Assistant, for the camera picker: (entity, name).
/// Asks the app's camera setup to import them first.
Future<List<(String, String)>> homeAssistantCameras(AppContainer c) async {
  await c.commands.execute('cameraImportHomeAssistant', const {});
  return [
    for (final cam in c.camera.config.cameras)
      if (cam.kind == 'ha' && (cam.entityId ?? '').isNotEmpty) (cam.entityId!, cam.name),
  ];
}
