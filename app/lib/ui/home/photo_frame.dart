import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_container.dart';
import 'clock_faces.dart';
import '../../managers/home/phoenix_home_manager.dart' show scenicWallpapers;
import '../../managers/home/photo_service.dart';
import '../../managers/settings/definitions.dart' as defs;
import '../theme.dart';

/// A slideshow of the Phoenix photos (Immich or a network folder): the
/// Photo Frame screensaver full screen, and the Photos tile small.
class PhoenixPhotoFrame extends StatefulWidget {
  const PhoenixPhotoFrame({super.key, required this.container, this.showClock = true, this.seconds});

  final AppContainer container;

  /// The big clock and date in the corner (the screensaver), or none (the
  /// tile).
  final bool showClock;

  /// Seconds per photo; the photo settings' when null.
  final int? seconds;

  @override
  State<PhoenixPhotoFrame> createState() => _PhoenixPhotoFrameState();
}

class _PhoenixPhotoFrameState extends State<PhoenixPhotoFrame> {
  PhotoService get photos => widget.container.phoenixHome.photos;
  List<PhotoRef> _list = const [];
  int _index = 0;
  Uint8List? _shown;
  Timer? _timer;
  bool _loading = true;

  /// No photos set up (or none found): the built-in 4K landscapes instead,
  /// slowly drifting, with their credit. Nothing to configure.
  bool _scenic = false;
  List<(String, String, String)> _scenicOrder = const [];
  String _credit = '';

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    _list = photos.configured ? await photos.photos() : const [];
    if (!mounted) return;
    if (_list.isEmpty) {
      _scenic = true;
      _scenicOrder = [...scenicWallpapers]..shuffle();
    }
    setState(() => _loading = false);
    if (_list.isEmpty && _scenicOrder.isEmpty) return;
    await _advance();
    _timer = Timer.periodic(
      Duration(seconds: widget.seconds ?? photos.settings.value.seconds),
      (_) => unawaited(_advance()),
    );
  }

  Future<void> _advance() async {
    if (_scenic) return _advanceScenic();
    if (_list.isEmpty) return;
    // Skip what will not load (a removed file) rather than stall on it.
    for (var tries = 0; tries < 5; tries++) {
      final bytes = await photos.bytes(_list[_index % _list.length]);
      _index++;
      if (bytes != null && mounted) {
        setState(() => _shown = bytes);
        return;
      }
    }
  }

  Future<void> _advanceScenic() async {
    for (var tries = 0; tries < _scenicOrder.length; tries++) {
      final (id, _, credit) = _scenicOrder[_index % _scenicOrder.length];
      _index++;
      final bytes = await widget.container.phoenixHome.scenicPhoto(id);
      if (bytes != null && mounted) {
        setState(() {
          _shown = bytes;
          _credit = credit;
        });
        return;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (shown != null && _scenic)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 2400),
              child: _Drift(
                key: ValueKey(shown.hashCode),
                bytes: shown,
                seconds: widget.seconds ?? photos.settings.value.seconds,
                // Alternate the drift, so it never feels like a loop.
                fromLeft: _index.isEven,
              ),
            )
          else if (shown != null)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 900),
              child: Stack(
                key: ValueKey(shown.hashCode),
                fit: StackFit.expand,
                children: [
                  // The photo blurred behind itself fills the bars a
                  // portrait photo leaves on a landscape screen.
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Opacity(opacity: 0.55, child: Image.memory(shown, fit: BoxFit.cover, gaplessPlayback: true)),
                  ),
                  Image.memory(shown, fit: BoxFit.contain, gaplessPlayback: true, filterQuality: FilterQuality.medium),
                ],
              ),
            )
          else if (_scenic)
            // The first landscape is still on its way: quiet black.
            const SizedBox.shrink()
          else
            Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_library_outlined, color: Colors.white38, size: 64),
                        const SizedBox(height: 8),
                        Text(
                          photos.problem.value ?? 'Set up photos on Phoenix Home',
                          style: const TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                      ],
                    ),
            ),
          if (widget.showClock) Positioned(left: 40, bottom: 32, child: _FrameClock(face: widget.container.phoenixHome.clockFace)),
          // The landscape's credit (their licences ask for it), small.
          if (_scenic && _credit.isNotEmpty && widget.showClock)
            Positioned(
              right: 24,
              bottom: 18,
              child: Text(
                _credit,
                style: const TextStyle(color: Colors.white54, fontSize: 12, shadows: [Shadow(blurRadius: 8, color: Colors.black87)]),
              ),
            ),
        ],
      ),
    );
  }
}

/// One landscape, slowly zooming and drifting across (the "Ken Burns"
/// effect) for as long as it shows: calm movement, never a jump.
class _Drift extends StatelessWidget {
  const _Drift({super.key, required this.bytes, required this.seconds, required this.fromLeft});
  final Uint8List bytes;
  final int seconds;
  final bool fromLeft;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(seconds: seconds.clamp(8, 600) + 3),
    curve: Curves.easeInOut,
    builder: (context, t, child) => Transform.scale(
      scale: 1.04 + 0.06 * t,
      alignment: Alignment(fromLeft ? -0.6 + 1.2 * t : 0.6 - 1.2 * t, 0),
      child: child,
    ),
    child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium),
  );
}

class _FrameClock extends StatefulWidget {
  const _FrameClock({required this.face});
  final ValueNotifier<String> face;

  @override
  State<_FrameClock> createState() => _FrameClockState();
}

class _FrameClockState extends State<_FrameClock> {
  late final Timer _timer = Timer.periodic(const Duration(seconds: 20), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _timer;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const shadow = [Shadow(blurRadius: 12, color: Colors.black87)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClockFace(face: widget.face.value, now: now, size: 84),
        Text(
          DateFormat('EEEE, MMMM d').format(now),
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500, shadows: shadow),
        ),
      ],
    );
  }
}

/// Photo setup: where the photos come from, how long each shows, and
/// whether the screensaver is the photo frame.
Future<void> showPhotoSetup(BuildContext context, AppContainer c) => showDialog<void>(
  context: context,
  builder: (_) => _PhotoSetup(container: c),
);

class _PhotoSetup extends StatefulWidget {
  const _PhotoSetup({required this.container});
  final AppContainer container;

  @override
  State<_PhotoSetup> createState() => _PhotoSetupState();
}

class _PhotoSetupState extends State<_PhotoSetup> {
  AppContainer get c => widget.container;
  late PhotoSettings _s = c.phoenixHome.photos.settings.value;
  late final _folder = TextEditingController(text: _s.folderUrl);
  late final _immichUrl = TextEditingController(text: c.settings.get(defs.screensaverImmichUrl));
  late final _immichKey = TextEditingController(text: c.settings.get(defs.screensaverImmichApiKey));
  late bool _screensaver = c.settings.get(defs.screensaverMode) == 'phoenix_photos' && c.settings.get(defs.screensaverEnabled);
  String? _result;
  bool _testing = false;

  @override
  void dispose() {
    _folder.dispose();
    _immichUrl.dispose();
    _immichKey.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_s.source == 'immich') {
      await c.settings.set(defs.screensaverImmichUrl, _immichUrl.text.trim());
      await c.settings.set(defs.screensaverImmichApiKey, _immichKey.text.trim());
    }
    await c.phoenixHome.photos.save(PhotoSettings(source: _s.source, folderUrl: _folder.text.trim(), seconds: _s.seconds));
    if (_screensaver) {
      await c.settings.set(defs.screensaverMode, 'phoenix_photos');
      await c.settings.set(defs.screensaverEnabled, true);
    } else if (c.settings.get(defs.screensaverMode) == 'phoenix_photos') {
      await c.settings.set(defs.screensaverMode, 'clock');
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    await _apply();
    final list = await c.phoenixHome.photos.photos();
    if (mounted) {
      setState(() {
        _testing = false;
        _result = list.isEmpty
            ? (c.phoenixHome.photos.problem.value ?? 'No photos found')
            : 'Found ${list.length} photos';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Photos'),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'immich', label: Text('Immich'), icon: Icon(Icons.cloud_rounded)),
                ButtonSegment(value: 'folder', label: Text('Network folder'), icon: Icon(Icons.folder_shared_rounded)),
              ],
              selected: {_s.source},
              onSelectionChanged: (v) => setState(() => _s = PhotoSettings(source: v.first, folderUrl: _s.folderUrl, seconds: _s.seconds)),
            ),
            const SizedBox(height: 16),
            if (_s.source == 'immich') ...[
              TextField(
                controller: _immichUrl,
                decoration: const InputDecoration(
                  labelText: 'Immich server',
                  hintText: 'http://192.168.1.10:2283',
                  helperText: "Your Unraid server's address and Immich's port",
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _immichKey,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API key',
                  helperText: 'Immich > Account Settings > API Keys > New API Key',
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Albums, people and dates to show: Settings > Screensaver > Immich Media screensaver.',
                style: TextStyle(fontSize: 12.5),
              ),
            ] else ...[
              TextField(
                controller: _folder,
                decoration: const InputDecoration(
                  labelText: 'Folder link',
                  hintText: 'http://tower.local:8080/photos/',
                  helperText:
                      'A folder your server lists over http (nginx, Apache, Caddy, rclone serve http). '
                      'Add a login as http://user:password@host/... Windows (SMB) shares need to be served over '
                      'http first.',
                  helperMaxLines: 4,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Seconds per photo'),
                Expanded(
                  child: Slider(
                    value: _s.seconds.toDouble(),
                    min: 4,
                    max: 60,
                    divisions: 14,
                    label: '${_s.seconds}s',
                    activeColor: Phx.ember,
                    onChanged: (v) => setState(() => _s = PhotoSettings(source: _s.source, folderUrl: _s.folderUrl, seconds: v.round())),
                  ),
                ),
                Text('${_s.seconds}s'),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use as the screensaver'),
              subtitle: const Text('The photo frame starts after the idle time set under Settings > Screensaver.'),
              value: _screensaver,
              onChanged: (v) => setState(() => _screensaver = v),
            ),
            if (_result != null) Text(_result!, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: _testing ? null : () => unawaited(_test()), child: Text(_testing ? 'Testing…' : 'Test')),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () async {
          final nav = Navigator.of(context);
          await _apply();
          nav.pop();
        },
        child: const Text('Save'),
      ),
    ],
  );
}
