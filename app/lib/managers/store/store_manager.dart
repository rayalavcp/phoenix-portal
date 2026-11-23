import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/command_registry.dart';
import '../../core/manager.dart';

/// One app in Phoenix Portal's curated store (assets/store/catalog.json).
@immutable
class StoreApp {
  const StoreApp({
    required this.package,
    required this.name,
    required this.category,
    required this.icon,
    required this.summary,
    this.github,
    this.asset,
  });

  factory StoreApp.fromJson(Map<String, Object?> j) => StoreApp(
    package: '${j['package']}',
    name: '${j['name']}',
    category: '${j['category']}',
    icon: '${j['icon'] ?? 'apps'}',
    summary: '${j['summary'] ?? ''}',
    github: j['github'] as String?,
    asset: j['asset'] as String?,
  );

  final String package;
  final String name;
  final String category;
  final String icon;
  final String summary;

  /// For an app released on GitHub rather than F-Droid: the repository
  /// (owner/name) and a pattern for the APK among its release's files.
  final String? github;
  final String? asset;
}

enum StorePhase { idle, resolving, downloading, installing, confirm, failed }

@immutable
class StoreItemState {
  const StoreItemState({this.version, this.phase = StorePhase.idle, this.progress, this.message, this.latest});

  /// Installed versionName, null when not installed.
  final String? version;

  /// The newest release's version (GitHub apps), when known.
  final String? latest;

  /// A newer release than the one installed is out.
  bool get updatable => version != null && latest != null && newerVersion(latest!, version!);
  final StorePhase phase;

  /// Download progress 0..1 while downloading.
  final double? progress;
  final String? message;

  bool get installed => version != null;
  bool get busy =>
      phase == StorePhase.resolving || phase == StorePhase.downloading || phase == StorePhase.installing;

  StoreItemState copyWith({String? version, bool clearVersion = false, StorePhase? phase, double? progress, String? message, String? latest}) =>
      StoreItemState(
        version: clearVersion ? null : (version ?? this.version),
        phase: phase ?? this.phase,
        progress: progress,
        message: message,
        latest: latest ?? this.latest,
      );

  Map<String, Object?> toJson() => {
    'version': version,
    'latest': latest,
    'updatable': updatable,
    'phase': phase.name,
    'progress': progress,
    'message': message,
  };
}

/// Whether version [a] is newer than [b], comparing their numbers in order
/// (a leading "v" and any suffix ignored). Pure, for tests.
bool newerVersion(String a, String b) {
  List<int> nums(String v) => [for (final m in RegExp(r'\d+').allMatches(v)) int.parse(m[0]!)];
  final x = nums(a), y = nums(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
    if (p != q) return p > q;
  }
  return false;
}

/// From a GitHub "latest release" answer: its version (the tag, without a
/// leading "v") and the download link of the first file matching [asset].
/// Pure, for tests.
({String version, Uri? apk}) githubRelease(Map<String, Object?> release, String asset) {
  final tag = '${release['tag_name'] ?? ''}';
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  final pattern = RegExp(asset);
  for (final a in (release['assets'] as List? ?? const [])) {
    if (a is! Map) continue;
    final name = '${a['name'] ?? ''}';
    final url = a['browser_download_url'];
    if (pattern.hasMatch(name) && url is String) return (version: version, apk: Uri.parse(url));
  }
  return (version: version, apk: null);
}

/// Parse the catalog document. Pure, for tests.
({List<String> categories, List<StoreApp> apps}) parseStoreCatalog(String json) {
  final doc = jsonDecode(json) as Map<String, Object?>;
  final apps = [
    for (final a in (doc['apps'] as List? ?? const []))
      if (a is Map) StoreApp.fromJson(a.cast<String, Object?>()),
  ];
  final categories = [for (final c in (doc['categories'] as List? ?? const [])) '$c'];
  return (categories: categories, apps: apps);
}

/// The APK URL F-Droid serves for [package] from its package API answer.
/// Pure, for tests.
Uri? fdroidApkUrl(String package, Map<String, Object?> api) {
  final code = api['suggestedVersionCode'];
  if (code == null) return null;
  return Uri.parse('https://f-droid.org/repo/${package}_$code.apk');
}

/// Phoenix Portal's app store: a curated catalog of free apps for a Portal,
/// installed from F-Droid's current builds through Android's own installer
/// (StoreInstaller on the native side).
class StoreManager extends Manager {
  StoreManager(super.bus, super.commands, super.log);

  @override
  String get name => 'store';

  static const _channel = MethodChannel('phoenix/store');

  final visible = ValueNotifier<bool>(false);
  final apps = ValueNotifier<List<StoreApp>>(const []);
  final categories = ValueNotifier<List<String>>(const []);
  final states = ValueNotifier<Map<String, StoreItemState>>(const {});

  StoreItemState stateOf(String package) => states.value[package] ?? const StoreItemState();

  void _set(String package, StoreItemState s) {
    states.value = {...states.value, package: s};
  }

  @override
  Future<void> init() async {
    try {
      final parsed = parseStoreCatalog(await rootBundle.loadString('assets/store/catalog.json'));
      apps.value = parsed.apps;
      categories.value = parsed.categories;
    } catch (e) {
      log.warn(name, 'store catalog unreadable: $e');
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'status') return;
      final args = (call.arguments as Map).cast<String, Object?>();
      final pkg = '${args['package']}';
      if (sideload.value['package'] == pkg) {
        final st = '${args['state']}';
        _side({'phase': st == 'confirm' ? 'confirm' : (st == 'installed' ? 'installed' : 'failed'), if (st != 'confirm' && st != 'installed') 'message': '${args['message'] ?? 'Install failed'}'});
      }
      switch ('${args['state']}') {
        case 'confirm':
          _set(pkg, stateOf(pkg).copyWith(phase: StorePhase.confirm));
        case 'installed':
          _set(pkg, stateOf(pkg).copyWith(phase: StorePhase.idle));
          await refresh();
        default:
          _set(pkg, stateOf(pkg).copyWith(phase: StorePhase.failed, message: '${args['message'] ?? 'Install failed'}'));
      }
    });
    commands
      ..register(
        Command(
          name: 'openStore',
          description: "Open Phoenix Portal's app store on the kiosk.",
          handler: (_) async {
            await commands.execute('bringToFront', const {});
            visible.value = true;
            unawaited(refresh());
            unawaited(checkUpdates());
            return const CommandResult.ok();
          },
        ),
      )
      ..register(
        Command(
          name: 'hideStore',
          description: 'Close the app store.',
          handler: (_) async {
            visible.value = false;
            return const CommandResult.ok();
          },
        ),
      )
      ..register(
        Command(
          name: 'storeInstall',
          description: 'Install an app from the store catalog by package name.',
          params: const {'package': 'the package name, as in the catalog'},
          handler: (params) async {
            final pkg = '${params['package'] ?? ''}';
            final app = apps.value.where((a) => a.package == pkg).firstOrNull;
            if (app == null) return CommandResult.fail('"$pkg" is not in the store');
            unawaited(install(app));
            return const CommandResult.ok();
          },
        ),
      )
      ..register(
        Command(
          name: 'storeStatus',
          description: 'The store apps released on GitHub (installed and latest versions) and the last side-loaded app.',
          handler: (_) async {
            await refresh();
            return CommandResult.ok({
              'apps': [
                for (final a in apps.value.where((a) => a.github != null))
                  {'package': a.package, 'name': a.name, 'summary': a.summary, 'github': a.github, ...stateOf(a.package).toJson()},
              ],
              'sideload': sideload.value,
            });
          },
        ),
      )
      ..register(
        Command(
          name: 'storeCheckUpdates',
          description: 'Look up the newest GitHub release of the store apps released there.',
          handler: (_) async {
            await checkUpdates();
            return const CommandResult.ok();
          },
        ),
      )
      ..register(
        Command(
          name: 'storeInstallUrl',
          description: 'Download an APK from a link on the Portal itself and install it (any app).',
          params: const {'url': 'an http(s) link to an .apk file'},
          handler: (params) async {
            final url = Uri.tryParse('${params['url'] ?? ''}'.trim());
            if (url == null || !(url.isScheme('http') || url.isScheme('https'))) {
              return const CommandResult.fail('Give an http or https link to an APK');
            }
            unawaited(installFromUrl(url));
            return const CommandResult.ok();
          },
        ),
      )
      ..register(
        Command(
          name: 'receiveSideloadApk',
          description: 'Install an APK uploaded through POST /api/apps/upload (any app). In-process only: the APK is the raw body.',
          params: const {'stream': 'the APK bytes (in-process only)', 'length': 'the byte count, if known'},
          quiet: true,
          handler: (p) async {
            final stream = p['stream'];
            if (stream is! Stream<List<int>>) return const CommandResult.fail('the APK travels as the raw body of POST /api/apps/upload');
            final length = p['length'];
            try {
              await installUploaded(stream, length is int && length > 0 ? length : null);
            } on StateError catch (e) {
              return CommandResult.fail(e.message);
            }
            return CommandResult.ok(sideload.value);
          },
        ),
      );
  }

  /// Re-read which catalog apps are installed and at which version.
  Future<void> refresh() async {
    try {
      final versions = await _channel.invokeMapMethod<String, String?>('versions', {
        'packages': [for (final a in apps.value) a.package],
      });
      if (versions == null) return;
      final next = Map<String, StoreItemState>.of(states.value);
      for (final a in apps.value) {
        final s = next[a.package] ?? const StoreItemState();
        final v = versions[a.package];
        next[a.package] = v == null ? s.copyWith(clearVersion: true, phase: s.phase) : s.copyWith(version: v, phase: s.phase);
      }
      states.value = next;
    } on MissingPluginException {
      // Tests and platforms without the native side.
    } catch (e) {
      log.warn(name, 'could not read installed versions: $e');
    }
  }

  /// Resolve, download and hand an app to Android's installer.
  Future<void> install(StoreApp app) async {
    if (stateOf(app.package).busy) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      _set(app.package, stateOf(app.package).copyWith(phase: StorePhase.resolving));
      final Uri? url;
      if (app.github != null) {
        final rel = githubRelease(await _getJson(client, Uri.parse('https://api.github.com/repos/${app.github}/releases/latest')), app.asset ?? r'\.apk$');
        url = rel.apk;
        if (url == null) throw StateError('The latest ${app.name} release has no APK');
        _set(app.package, stateOf(app.package).copyWith(phase: StorePhase.resolving, latest: rel.version));
      } else {
        final api = await _getJson(client, Uri.parse('https://f-droid.org/api/v1/packages/${app.package}'));
        url = fdroidApkUrl(app.package, api);
        if (url == null) throw StateError('F-Droid has no build of ${app.name} right now');
      }

      final dir = Directory('${(await getTemporaryDirectory()).path}/store');
      await dir.create(recursive: true);
      final file = File('${dir.path}/${app.package}.apk');
      final req = await client.getUrl(url);
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('download answered ${res.statusCode}', uri: url);
      final total = res.contentLength;
      var received = 0;
      final sink = file.openWrite();
      var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (received > maxSideloadBytes) throw StateError('That file is too big for an app (over 1 GB)');
        final now = DateTime.now();
        // Progress at most ten times a second: smooth without flooding the UI.
        if (now.difference(lastReport) > const Duration(milliseconds: 100)) {
          lastReport = now;
          _set(app.package, stateOf(app.package).copyWith(
            phase: StorePhase.downloading,
            progress: total > 0 ? received / total : null,
          ));
        }
      }
      await sink.close();

      _set(app.package, stateOf(app.package).copyWith(phase: StorePhase.installing));
      await _channel.invokeMethod<bool>('install', {'path': file.path, 'package': app.package});
    } catch (e) {
      log.warn(name, 'install of ${app.package} failed: $e');
      _set(app.package, stateOf(app.package).copyWith(phase: StorePhase.failed, message: _friendly(e)));
    } finally {
      client.close();
    }
  }

  static String _friendly(Object e) => switch (e) {
    SocketException() => 'No connection. Check the Wi-Fi.',
    HttpException(:final message) => 'Download failed: $message',
    StateError(:final message) => message,
    PlatformException(:final message) => message ?? 'Android refused the install',
    _ => '$e',
  };

  Future<Map<String, Object?>> _getJson(HttpClient client, Uri uri) async {
    final req = await client.getUrl(uri);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      final who = uri.host.contains('github') ? 'GitHub' : 'F-Droid';
      throw StateError(res.statusCode == 404 ? '$who no longer lists this app' : '$who answered ${res.statusCode}');
    }
    return (jsonDecode(body) as Map).cast<String, Object?>();
  }

  /// Look up the newest release of every GitHub app, for "Update".
  Future<void> checkUpdates() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      for (final app in apps.value.where((a) => a.github != null)) {
        try {
          final rel = githubRelease(await _getJson(client, Uri.parse('https://api.github.com/repos/${app.github}/releases/latest')), app.asset ?? r'\.apk$');
          if (rel.version.isNotEmpty) _set(app.package, stateOf(app.package).copyWith(phase: stateOf(app.package).phase, latest: rel.version));
        } catch (e) {
          log.debug(name, 'no release info for ${app.package}: $e');
        }
      }
    } finally {
      client.close();
    }
  }

  // ── Any app: from a link or an uploaded file ──────────────────────────────

  /// The last side-loaded app: what it is and how far it got.
  final sideload = ValueNotifier<Map<String, Object?>>(const {'phase': 'idle'});

  void _side(Map<String, Object?> s) => sideload.value = {...sideload.value, ...s};

  /// Download an APK from [url] (the Portal fetches it itself, so the
  /// browser's block on APK downloads does not apply) and install it.
  Future<void> installFromUrl(Uri url) async {
    if (sideload.value['phase'] == 'downloading' || sideload.value['phase'] == 'installing') return;
    sideload.value = {'phase': 'downloading', 'progress': 0.0, 'source': url.toString()};
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final file = await _sideloadFile();
      final res = await (await client.getUrl(url)).close();
      if (res.statusCode != 200) throw HttpException('download answered ${res.statusCode}', uri: url);
      await _save(res, file, res.contentLength);
      await _installFile(file);
    } catch (e) {
      log.warn(name, 'install from $url failed: $e');
      _side({'phase': 'failed', 'message': _friendly(e)});
    } finally {
      client.close();
    }
  }

  /// Take in an APK uploaded to the remote admin and install it.
  Future<void> installUploaded(Stream<List<int>> stream, int? length) async {
    if (sideload.value['phase'] == 'downloading' || sideload.value['phase'] == 'installing') {
      throw StateError('another install is running');
    }
    sideload.value = {'phase': 'downloading', 'progress': 0.0, 'source': 'upload'};
    try {
      final file = await _sideloadFile();
      await _save(stream, file, length);
      await _installFile(file);
    } catch (e) {
      log.warn(name, 'install of an uploaded APK failed: $e');
      _side({'phase': 'failed', 'message': _friendly(e)});
    }
  }

  Future<File> _sideloadFile() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/store');
    await dir.create(recursive: true);
    return File('${dir.path}/sideload.apk');
  }

  /// The biggest sideloaded APK taken in, so a wrong link or a runaway
  /// upload cannot fill the Portal's storage.
  static const maxSideloadBytes = 1024 * 1024 * 1024;

  Future<void> _save(Stream<List<int>> data, File file, int? total) async {
    if (total != null && total > maxSideloadBytes) throw StateError('That file is too big for an app (over 1 GB)');
    final sink = file.openWrite();
    var received = 0;
    var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await for (final chunk in data) {
        sink.add(chunk);
        received += chunk.length;
        if (received > maxSideloadBytes) throw StateError('That file is too big for an app (over 1 GB)');
        final now = DateTime.now();
        if (now.difference(lastReport) > const Duration(milliseconds: 200)) {
          lastReport = now;
          _side({'progress': total != null && total > 0 ? received / total : null, 'bytes': received});
        }
      }
    } finally {
      await sink.close();
    }
    if (received < 1024) throw StateError('That is not an APK (only $received bytes)');
    // Every APK is a zip: anything else (an HTML error page behind a link)
    // is turned away before Android's installer sees it.
    final head = await file.openRead(0, 4).fold<List<int>>([], (a, b) => a..addAll(b));
    if (head.length < 4 || head[0] != 0x50 || head[1] != 0x4b || head[2] != 0x03 || head[3] != 0x04) {
      throw StateError('That file is not an Android app (APK)');
    }
  }

  Future<void> _installFile(File file) async {
    final info = await _channel.invokeMapMethod<String, Object?>('inspect', {'path': file.path});
    final pkg = info?['package'] as String?;
    if (pkg == null || pkg.isEmpty) throw StateError('That file is not an Android app (APK). A split bundle (APKM, APKS, XAPK) has to be merged first.');
    _side({'phase': 'installing', 'package': pkg, 'label': info?['label'] ?? pkg, 'version': info?['version'], 'progress': null});
    await _channel.invokeMethod<bool>('install', {'path': file.path, 'package': pkg});
  }
}
