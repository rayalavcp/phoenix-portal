import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Dart side of the native camera motion detector (`CameraMotion.kt`).
///
/// Listening starts the camera and binds the analyzer; each event is a motion
/// tick, a face sighting or a raised-hand report (the native side does the
/// frame-diffing and the inference, and rate-limits the first two to 1/s).
/// Cancelling the subscription unbinds the camera and frees it. Tuning
/// changes re-listen with fresh arguments.
class NativeMotion {
  static const _channel = EventChannel('kiosk_satellite/motion');
  static const _control = MethodChannel('kiosk_satellite/motion/control');

  /// Idle (or wake) the analysis of a running session without a rebind:
  /// the camera stays open and the motion grid keeps its baseline, but
  /// no tick, sighting or hand report is emitted and no model runs.
  /// Used for the span of a voice interaction. Throws where the plugin
  /// is missing (tests without a mock); callers treat that as best
  /// effort.
  static Future<void> setPaused(bool paused) =>
      _control.invokeMethod<void>('setPaused', {'paused': paused});

  /// Open the camera preview window on a running session (discussion
  /// #371): for the next [duration] the native side also encodes the
  /// analyzed frames as small JPEGs and emits them as preview ticks
  /// (see [NativeMotionTick.previewJpeg]), paced to about ten a second
  /// and by their own encoding cost. A no-op without a session. Throws
  /// where the plugin is missing; callers treat that as best effort.
  static Future<void> showPreview(Duration duration) => _control
      .invokeMethod<void>('showPreview', {'ms': duration.inMilliseconds});

  /// Finish a release the native side still has queued after the
  /// stream was cancelled, so the camera is free when this returns. The
  /// barcode scanner calls it before it opens the camera itself. Throws
  /// where the plugin is missing; callers treat that as best effort.
  static Future<void> release() => _control.invokeMethod<void>('release');

  /// Vision Match: Ground Control's vision socket is ready and keeps up
  /// with [face] face looks and [hands] hand looks a second (null when it
  /// didn't say). The analyzer paces its looks to them. Throws where the
  /// plugin is missing; callers treat that as best effort.
  static Future<void> visionReady(double? face, double? hands) => _control
      .invokeMethod<void>('visionReady', {'face': face, 'hands': hands});

  /// Vision Match: Ground Control's answer to a look ([VisionLook.id]):
  /// `faces` and `hand` as the vision socket sent them, or `failed: true`
  /// when the look got no answer. Throws where the plugin is missing;
  /// callers treat that as best effort.
  static Future<void> visionResult(Map<String, Object?> answer) =>
      _control.invokeMethod<void>('visionResult', answer);

  static Stream<NativeMotionTick> stream({
    required double fps,
    required int sensitivity,
    required String camera,
    required int snapshotWidth,
    required int snapshotHeight,
    int startDelayMs = 0,
    bool motion = true,
    bool faces = false,
    double faceMinWidth = 0.1,
    bool fingers = false,
    bool heads = false,
    bool gameHands = false,
    bool gameBody = false,
    bool gamePose = false,
    bool gameLive = false,
    bool remoteFaces = false,
    bool remoteHands = false,
    bool enroll = false,
    bool paused = false,
    bool preview = false,
    bool rtsp = false,
    Map<String, Object>? intercom,
    ({int width, int height})? plugin,
  }) {
    return _channel
        .receiveBroadcastStream(<String, Object?>{
          'fps': fps,
          'sensitivity': sensitivity,
          'camera': camera,
          // For the snapshot capture use case pre-bound into this session, so
          // a frame taken mid-screensaver matches the configured resolution.
          'snapshotWidth': snapshotWidth,
          'snapshotHeight': snapshotHeight,
          // Extra blindness after the stream starts, for cameras that move as
          // they open (discussion #159). Applied natively so the analyzer keeps
          // tracking frames without letting the movement train its noise model.
          'startDelayMs': startDelayMs,
          // Which legs want events (issue #304): motion ticks, face
          // sightings, or both. The frame analysis runs regardless (its
          // exposure-hunt watchdog guards the CPU either way); only the
          // emissions are gated.
          'motion': motion,
          'faces': faces,
          // Smallest face worth reporting, as a fraction of the frame's
          // longer side; see [faceMinWidthFor].
          'faceMinWidth': faceMinWidth,
          // Hands (the Show fingers gesture): found, confirmed and counted
          // natively, reported as a hand count and a finger count.
          'fingers': fingers,
          // The Kids Portal's head-steered games: the face's position,
          // about ten times a second, while a game is open.
          'heads': heads,
          // A Kids Portal game is open: its hands (up to two, with their
          // points) and its body outline, on every frame (GameVision.kt).
          'game': {'hands': gameHands, 'body': gameBody, 'pose': gamePose, 'live': gameLive},
          // Vision Match: the face looks, the hand looks or both go to
          // Ground Control. The native side hands each due frame over as a
          // vision tick instead of running its own models for them.
          'remoteFaces': remoteFaces,
          'remoteHands': remoteHands,
          // Face Recognition's guided capture: a frame every quarter second.
          if (enroll) 'enroll': true,
          // Whether a voice interaction is running as the session starts
          // (see [setPaused]): the flag rides the bind too, so a session
          // rebound mid-turn, on a native side recreated with the
          // Activity, starts idle like the one it replaces.
          'paused': paused,
          // The camera preview (discussion #371) may be asked for on this
          // session (see [showPreview]): the analysis stream is sized up
          // for it, since its frames are what the preview is made of.
          'preview': preview,
          'rtsp': rtsp,
          // An intercom call's video: the size, rate and bitrate it wants.
          'intercom': intercom,
          // A plugin holds the camera: the analysis stream is sized for
          // it and its frames go to the plugin natively.
          if (plugin != null)
            'plugin': {'width': plugin.width, 'height': plugin.height},
        })
        .map(NativeMotionTick.fromNative);
  }
}

/// One event off the native stream: a motion tick, a face sighting
/// carrying the face's width as a fraction of the frame's longer side, or
/// a hand report carrying the hand count (0 when the hand has gone) and
/// the fingers shown.
class NativeMotionTick {
  const NativeMotionTick._(
    this.faceWidth,
    this.palms,
    this.fingers, {
    this.fingersUp,
    this.preview,
    this.handX,
    this.handY,
    this.head,
    this.gameHands,
    this.body,
    this.vision,
    this.gamePoses,
    this.live,
  });

  /// A camera game's live picture is ready (or, id -1, refused).
  final LiveCamera? live;
  bool get isLive => live != null;

  /// A game's people, as the child sees them (an empty list: nobody).
  final List<BodyPose>? gamePoses;
  bool get isGamePoses => gamePoses != null;

  /// A game's hands, as the child sees them (an empty list: none in view).
  final List<GameHand>? gameHands;
  bool get isGameHands => gameHands != null;

  /// A game's body outline mask.
  final BodyMask? body;
  bool get isBody => body != null;

  /// A head-tracking report: whether a face is in view (its position in
  /// [handX], [handY] as the person sees it). Null for other events.
  final bool? head;
  bool get isHead => head != null;

  /// Where that hand's palm is, 0..1 across and down the picture as the
  /// person in front of the camera sees it (null when unknown).
  final double? handX;
  final double? handY;

  /// Extended fingers on the largest hand, when the landmark stage judged
  /// it (null otherwise).
  final int? fingers;

  /// Which digits of that hand are up, thumb first then index to pinky,
  /// when judged (null otherwise). The thumb is up only when it counts,
  /// on an open hand.
  final List<bool>? fingersUp;

  final double? faceWidth;
  final int? palms;

  /// A camera preview frame (see [NativeMotion.showPreview]).
  final FacePreviewFrame? preview;

  /// A frame for Ground Control to look at (Vision Match).
  final VisionLook? vision;

  bool get isFace => faceWidth != null;
  bool get isPalms => palms != null;
  bool get isPreview => preview != null;
  bool get isVision => vision != null;

  /// Anything that is not a face sighting, a hand report or a preview
  /// frame is a motion tick, which keeps the wire compatible with the
  /// original null events.
  static NativeMotionTick fromNative(Object? raw) {
    if (raw is Map) {
      if (raw['live'] is num) {
        return NativeMotionTick._(null, null, null, live: LiveCamera.fromNative(raw));
      }
      final gposes = raw['gposes'];
      if (gposes is List) {
        return NativeMotionTick._(null, null, null, gamePoses: [
          for (final p in gposes)
            ?BodyPose.fromNative(p, aspect: raw['aspect'] is num && (raw['aspect'] as num) > 0 ? (raw['aspect'] as num).toDouble() : 0.75),
        ]);
      }
      final ghands = raw['ghands'];
      if (ghands is List) {
        return NativeMotionTick._(null, null, null, gameHands: [
          for (final h in ghands)
            if (h is Map && h['x'] is num && h['y'] is num) GameHand.fromNative(h),
        ]);
      }
      final body = raw['body'];
      if (body is Uint8List && raw['bw'] is num && raw['bh'] is num) {
        final w = (raw['bw'] as num).toInt(), h = (raw['bh'] as num).toInt();
        if (w > 0 && h > 0 && body.length == w * h) {
          return NativeMotionTick._(null, null, null, body: BodyMask(w, h, body));
        }
      }
      final head = raw['head'];
      if (head is bool) {
        return NativeMotionTick._(
          null,
          null,
          null,
          head: head,
          handX: raw['x'] is num ? (raw['x'] as num).toDouble() : null,
          handY: raw['y'] is num ? (raw['y'] as num).toDouble() : null,
        );
      }
      final face = raw['face'];
      if (face is num) {
        return NativeMotionTick._(face.toDouble(), null, null);
      }
      final palms = raw['palms'];
      if (palms is num) {
        final fingers = raw['fingers'];
        final up = raw['up'];
        return NativeMotionTick._(
          null,
          palms.toInt(),
          fingers is num && fingers >= 0 ? fingers.toInt() : null,
          fingersUp: up is List && up.length == 5 && up.every((b) => b is bool)
              ? up.cast<bool>()
              : null,
          handX: raw['x'] is num ? (raw['x'] as num).toDouble() : null,
          handY: raw['y'] is num ? (raw['y'] as num).toDouble() : null,
        );
      }
      final vision = raw['vision'];
      final id = raw['id'];
      if (vision is Uint8List && id is num) {
        final rotation = raw['rotation'];
        final want = raw['want'];
        final encodeMs = raw['encode_ms'];
        final enroll = raw['enroll'] == true;
        return NativeMotionTick._(
          null,
          null,
          null,
          vision: VisionLook(
            id: id.toInt(),
            jpeg: vision,
            rotation: rotation is num ? rotation.toInt() : 0,
            want: want is List ? want.whereType<String>().toList() : const [],
            encodeMs: encodeMs is num ? encodeMs.toDouble() : null,
            enroll: enroll,
            mirror: raw['mirror'] == true,
          ),
        );
      }
      final preview = raw['preview'];
      if (preview is Uint8List) {
        final rotation = raw['rotation'];
        return NativeMotionTick._(
          null,
          null,
          null,
          preview: FacePreviewFrame(
            jpeg: preview,
            rotation: rotation is num ? rotation.toInt() : 0,
            mirror: raw['mirror'] == true,
          ),
        );
      }
    }
    return const NativeMotionTick._(null, null, null);
  }
}

/// A frame the analyzer wants Ground Control to look at (Vision Match): a
/// JPEG of the analysis frame as the sensor delivered it, the clockwise
/// rotation that turns it upright, what to look for (`face`, `hands`) and
/// how long the frame took to encode. Every look must be answered with
/// [NativeMotion.visionResult].
class VisionLook {
  const VisionLook({
    required this.id,
    required this.jpeg,
    required this.rotation,
    required this.want,
    this.encodeMs,
    this.enroll = false,
    this.mirror = false,
  });

  final int id;
  final Uint8List jpeg;
  final int rotation;
  final List<String> want;
  final double? encodeMs;

  /// A frame of Face Recognition's guided capture, not a look.
  final bool enroll;

  /// The camera faces the person: the frame is shown mirrored.
  final bool mirror;
}

/// One frame of the camera preview (discussion #371), as the native side
/// hands it over: a JPEG of the analysis frame in sensor orientation,
/// the rotation that turns it upright on this display (the frame's
/// rotationDegrees, a multiple of 90) and whether it should be mirrored,
/// which it is for a front camera so the view reads like a mirror to the
/// person in it.
class FacePreviewFrame {
  const FacePreviewFrame({
    required this.jpeg,
    required this.rotation,
    required this.mirror,
  });

  final Uint8List jpeg;
  final int rotation;
  final bool mirror;
}

/// The Face sensitivity slider (1..100) as the minimum face width the
/// native detector reports, relative to the frame's longer side.
///
/// The slider is read as a distance: 1 means only a face right at the
/// screen (about 0.3 m), 100 means as far as the detector can see (about
/// 2.5 m), linear in between. A face about 15 cm wide seen through a
/// typical 80-degree front camera spans 0.15 / (2 d tan 40) of the frame,
/// roughly 0.09 / d, which is what the mapping returns. Beyond roughly two
/// meters the detector's own reach (faces of a dozen pixels in its 192
/// pixel input) is the limit, not the slider.
double faceMinWidthFor(int sensitivity) {
  final s = sensitivity.clamp(1, 100);
  final meters = 0.3 + (s - 1) / 99 * 2.2;
  return 0.09 / meters;
}

/// One hand in a game: its palm, the fingers it shows and its 21 points
/// (x, y pairs), all 0..1 across and down the picture as the child sees it.
class GameHand {
  const GameHand(this.palm, this.fingers, this.points, {this.size = 0, this.aspect = 0.75});

  factory GameHand.fromNative(Map<Object?, Object?> raw) {
    final lm = raw['lm'];
    final pts = lm is Float32List
        ? lm
        : lm is List
        ? Float32List.fromList([for (final v in lm) (v as num).toDouble()])
        : Float32List(0);
    final f = raw['f'];
    return GameHand(
      Offset((raw['x']! as num).toDouble(), (raw['y']! as num).toDouble()),
      f is num ? f.toInt() : 0,
      pts.length == 42 ? pts : Float32List(0),
      size: raw['s'] is num ? (raw['s']! as num).toDouble() : 0,
      aspect: raw['a'] is num && (raw['a']! as num) > 0 ? (raw['a']! as num).toDouble() : 0.75,
    );
  }

  final Offset palm;
  final int fingers;
  final Float32List points;

  /// The hand's size (wrist to middle knuckle) in frame widths; 0 when
  /// not reported (older native code).
  final double size;

  /// The frame's height over its width.
  final double aspect;

  Offset point(int i) => Offset(points[i * 2], points[i * 2 + 1]);
}

/// The live camera picture of a camera game: a Flutter texture, its size
/// as the camera delivers it, the quarter turns still needed to stand it
/// upright, and whether it already comes mirrored. [id] -1: refused.
class LiveCamera {
  const LiveCamera(this.id, this.size, this.turn, this.front, this.mirrored);

  factory LiveCamera.fromNative(Map<Object?, Object?> raw) => LiveCamera(
    (raw['live']! as num).toInt(),
    Size(((raw['w'] as num?) ?? 640).toDouble(), ((raw['h'] as num?) ?? 480).toDouble()),
    ((raw['turn'] as num?) ?? 0).toInt(),
    raw['front'] == true,
    raw['mirrored'] == true,
  );

  final int id;
  final Size size;
  final int turn;
  final bool front, mirrored;

  bool get ok => id >= 0;
}

/// One person's body as a game sees it (MediaPipe's 33 pose points): x
/// and y as the child sees the picture (0..1) and how sure the model is
/// that each point is in view.
class BodyPose {
  const BodyPose(this.points, {this.aspect = 0.75});

  static BodyPose? fromNative(Object? raw, {double aspect = 0.75}) {
    final pts = raw is Float32List
        ? raw
        : raw is List
        ? Float32List.fromList([for (final v in raw) (v as num).toDouble()])
        : null;
    return pts != null && pts.length == 99 ? BodyPose(pts, aspect: aspect) : null;
  }

  final Float32List points;

  /// The picture's height over its width.
  final double aspect;

  static const nose = 0, leftShoulder = 11, rightShoulder = 12, leftWrist = 15, rightWrist = 16;
  static const leftIndex = 19, rightIndex = 20, leftHip = 23, rightHip = 24;

  Offset point(int i) => Offset(points[i * 3], points[i * 3 + 1]);
  double seen(int i) => points[i * 3 + 2];
}

/// The body as the game sees it: [width] × [height] cells, each how sure
/// the model is that it is the person (0..255), upright and mirrored.
class BodyMask {
  const BodyMask(this.width, this.height, this.cells);
  final int width, height;
  final Uint8List cells;

  double at(int x, int y) => cells[y * width + x] / 255.0;
}
