import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging.dart';
import '../screensaver/immich_manager.dart';

/// Phoenix Home's photos: the Photos tile and the Phoenix Photo Frame
/// screensaver. Two sources:
///
/// - **Immich** (the photo server most Unraid setups run): the server and
///   API key set under Settings > Screensaver > Immich, so the existing
///   album and people filters apply.
/// - **A network folder over the web**: any folder a server lists in a web
///   page, such as an Unraid share behind nginx, Apache, Caddy's file
///   server, rclone serve http or a WebDAV server with listings on. A login
///   in the link (http://user:password@host/photos/) is sent as basic auth.
///   Windows/SMB shares are not reachable from Android apps directly: serve
///   the folder over http, or sync it to the Portal (Syncthing) and use the
///   Local Media screensaver.

@immutable
class PhotoSettings {
  const PhotoSettings({this.source = 'immich', this.folderUrl = '', this.seconds = 12});

  /// 'immich' or 'folder'.
  final String source;
  final String folderUrl;

  /// Seconds each photo shows.
  final int seconds;

  Map<String, Object?> toJson() => {'source': source, 'folder': folderUrl, 'seconds': seconds};

  static PhotoSettings fromJson(Object? raw) => raw is Map
      ? PhotoSettings(
          source: raw['source'] == 'folder' ? 'folder' : 'immich',
          folderUrl: '${raw['folder'] ?? ''}',
          seconds: raw['seconds'] is int ? (raw['seconds'] as int).clamp(4, 600) : 12,
        )
      : const PhotoSettings();
}

/// One photo: an Immich asset, or a URL in the network folder.
@immutable
class PhotoRef {
  const PhotoRef.immich(this.asset) : url = null;
  const PhotoRef.url(this.url) : asset = null;
  final ImmichAsset? asset;
  final Uri? url;
}

class PhotoService {
  PhotoService(this._client, this._prefs, this._log, this._immich);

  final http.Client _client;
  final Future<SharedPreferences> Function() _prefs;
  final Logger _log;
  final ImmichManager _immich;

  static const _key = 'phx.home.photos';
  static final _imageExt = RegExp(r'\.(jpe?g|png|webp|gif|heic|bmp)$', caseSensitive: false);

  final settings = ValueNotifier<PhotoSettings>(const PhotoSettings());

  /// Why there are no photos, for the tile and the frame.
  final problem = ValueNotifier<String?>(null);

  List<PhotoRef>? _list;
  DateTime? _listedAt;
  final _rng = math.Random();

  bool get configured => switch (settings.value.source) {
    'folder' => settings.value.folderUrl.trim().isNotEmpty,
    _ => _immich.configured,
  };

  Future<void> init() async {
    final raw = (await _prefs()).getString(_key);
    if (raw == null) return;
    try {
      settings.value = PhotoSettings.fromJson(jsonDecode(raw));
    } catch (_) {}
  }

  Future<void> save(PhotoSettings next) async {
    settings.value = next;
    _list = null;
    await (await _prefs()).setString(_key, jsonEncode(next.toJson()));
  }

  /// The photos, shuffled, listed again every half hour.
  Future<List<PhotoRef>> photos() async {
    final at = _listedAt;
    final list = _list;
    if (list != null && at != null && DateTime.now().difference(at) < const Duration(minutes: 30)) return list;
    try {
      final next = switch (settings.value.source) {
        'folder' => [for (final u in await listFolder(Uri.parse(settings.value.folderUrl.trim()))) PhotoRef.url(u)],
        _ => [
          for (final a in await _immich.playlist())
            if (!a.isVideo) PhotoRef.immich(a),
        ],
      }..shuffle(_rng);
      _list = next;
      _listedAt = DateTime.now();
      problem.value = next.isEmpty ? 'No photos found' : null;
      return next;
    } catch (e) {
      _log.warn('phoenix_home', 'photos: $e');
      problem.value = configured ? "Couldn't reach the photos" : 'Set up photos';
      return list ?? const [];
    }
  }

  Map<String, String> _auth(Uri u) => u.userInfo.isEmpty
      ? const {}
      : {'authorization': 'Basic ${base64Encode(utf8.encode(Uri.decodeComponent(u.userInfo)))}'};

  Uri _clean(Uri u) => u.replace(userInfo: '');

  /// The images a web folder listing links to, and those of its subfolders
  /// down to [depth] levels.
  Future<List<Uri>> listFolder(Uri folder, {int depth = 2}) async {
    final base = folder.path.endsWith('/') ? folder : folder.replace(path: '${folder.path}/');
    final res = await _client.get(_clean(base), headers: _auth(base)).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
    final links = folderLinks(utf8.decode(res.bodyBytes, allowMalformed: true), base);
    final images = [for (final l in links) if (_imageExt.hasMatch(l.path)) l];
    if (depth > 0) {
      for (final sub in links.where((l) => l.path.endsWith('/') && l.path.length > base.path.length).take(30)) {
        try {
          images.addAll(await listFolder(sub.replace(userInfo: base.userInfo), depth: depth - 1));
        } catch (_) {}
      }
    }
    return images;
  }

  Future<Uint8List?> bytes(PhotoRef photo) async {
    try {
      if (photo.asset case final a?) return await _immich.imageBytes(a);
      final u = photo.url!;
      final auth = Uri.parse(settings.value.folderUrl.trim());
      final res = await _client.get(_clean(u), headers: _auth(auth)).timeout(const Duration(seconds: 30));
      return res.statusCode == 200 ? res.bodyBytes : null;
    } catch (e) {
      _log.warn('phoenix_home', 'photo: $e');
      return null;
    }
  }

  void dispose() {
    settings.dispose();
    problem.dispose();
  }
}

/// The links of a web server's folder listing, resolved against [base] and
/// kept inside it (no parent folder, no other sites, no sort links).
List<Uri> folderLinks(String html, Uri base) {
  final out = <Uri>{};
  for (final m in RegExp(r'''href\s*=\s*["']([^"'#?]+)["']''', caseSensitive: false).allMatches(html)) {
    final href = m[1]!.replaceAll('&amp;', '&');
    Uri u;
    try {
      u = base.resolve(href);
    } catch (_) {
      continue;
    }
    if (u.host != base.host || !u.path.startsWith(base.path) || u.path == base.path) continue;
    out.add(u.replace(userInfo: ''));
  }
  return out.toList();
}
