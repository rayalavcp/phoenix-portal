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
  });

  factory StoreApp.fromJson(Map<String, Object?> j) => StoreApp(
    package: '${j['package']}',
    name: '${j['name']}',
    category: '${j['category']}',
    icon: '${j['icon'] ?? 'apps'}',
    summary: '${j['summary'] ?? ''}',
  );

  final String package;
  final String name;
  final String category;
  final String icon;
  final String summary;
}

enum StorePhase { idle, resolving, downloading, installing, confirm, failed }

@immutable
class StoreItemState {
  const StoreItemState({this.version, this.phase = StorePhase.idle, this.progress, this.message});

  /// Installed versionName, null when not installed.
  final String? version;
  final StorePhase phase;

  /// Download progress 0..1 while downloading.
  final double? progress;
  final String? message;

  bool get installed => version != null;
  bool get busy =>
      phase == StorePhase.resolving || phase == StorePhase.downloading || phase == StorePhase.installing;

  StoreItemState copyWith({String? version, bool clearVersion = false, StorePhase? phase, double? progress, String? message}) =>
      StoreItemState(
        version: clearVersion ? null : (version ?? this.version),
        phase: phase ?? this.phase,
        progress: progress,
        message: message,
      );
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
      final api = await _getJson(client, Uri.parse('https://f-droid.org/api/v1/packages/${app.package}'));
      final url = fdroidApkUrl(app.package, api);
      if (url == null) throw StateError('F-Droid has no build of ${app.name} right now');

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
    SocketException() => 'No connection to F-Droid. Check the Wi-Fi.',
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
      throw StateError(res.statusCode == 404 ? 'F-Droid no longer lists this app' : 'F-Droid answered ${res.statusCode}');
    }
    return (jsonDecode(body) as Map).cast<String, Object?>();
  }
}
