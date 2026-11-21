import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/command_registry.dart';
import '../../core/events.dart';
import '../../core/manager.dart';
import '../settings/definitions.dart' as defs;
import '../settings/settings_manager.dart';

/// What the Kids Portal overlay shows.
enum KidsScreen {
  /// Not on screen.
  hidden,

  /// The play home: activities, games and allowed apps.
  play,

  /// Today's screen time ran out.
  done,

  /// Inside the bedtime window, or the Night profile.
  bedtime,
}

/// Phoenix Portal's Kids Portal: a full screen, child-safe home with offline
/// activities and the apps a parent allows, plus the Family / Kids / Night
/// profile Home Assistant switches.
///
/// - Family: the normal kiosk. The portal opens from the menu and closes
///   freely.
/// - Kids: the portal is up and locked. Leaving it takes the parent PIN (or a
///   three-second press without one) and returns the profile to Family.
/// - Night: the bedtime screen, locked the same way.
///
/// Screen time counts while the play screen is up and the panel is on, per
/// calendar day, kept in shared preferences so a restart does not reset it.
class KidsManager extends Manager {
  KidsManager(super.bus, super.commands, super.log, this._settings, {
    DateTime Function()? clock,
    Future<SharedPreferences> Function()? prefs,
  }) : _clock = clock ?? DateTime.now,
       _prefs = prefs ?? SharedPreferences.getInstance;

  final SettingsManager _settings;
  final DateTime Function() _clock;
  final Future<SharedPreferences> Function() _prefs;

  @override
  String get name => 'kids';

  /// What the overlay shows; [KidsScreen.hidden] keeps it unmounted.
  final screen = ValueNotifier<KidsScreen>(KidsScreen.hidden);

  /// Screen time left today in seconds, null without a limit.
  final secondsLeft = ValueNotifier<int?>(null);

  static const _usageKey = 'phx.kids.usage';
  static const _tick = Duration(seconds: 15);

  final _subs = <StreamSubscription<Object>>[];
  Timer? _timer;
  bool _screenOn = true;
  bool _openedByMenu = false;

  /// Seconds played on [_day], and the bonus a parent added that day.
  String _day = '';
  int _used = 0;
  int _bonus = 0;

  String get profile => _settings.get(defs.phoenixProfile);

  /// Whether leaving needs a parent: any profile but Family.
  bool get locked => profile != 'family';

  bool get enabled => _settings.get(defs.kidsEnabled);

  String get childName => _settings.get(defs.kidsName).trim();

  int get _limitSeconds =>
      (int.tryParse(_settings.get(defs.kidsDailyMinutes)) ?? 0) * 60;

  @override
  Future<void> init() async {
    await _loadUsage();
    _subs
      ..add(
        bus.on<SettingChanged>().listen((e) {
          if (e.key == defs.phoenixProfile.key ||
              e.key == defs.kidsBedtime.key ||
              e.key == defs.kidsWakeTime.key ||
              e.key == defs.kidsDailyMinutes.key ||
              e.key == defs.kidsEnabled.key) {
            _evaluate();
          }
        }),
      )
      ..add(
        bus.on<ScreenStateChanged>().listen((e) => _screenOn = e.on),
      );
    commands
      ..register(
        Command(
          name: 'openKids',
          description: 'Open the Kids Portal on the kiosk.',
          handler: (_) async {
            if (!enabled && profile == 'family') {
              return const CommandResult.fail('the Kids Portal is off');
            }
            _openedByMenu = true;
            await commands.execute('screenOn', const {});
            await commands.execute('bringToFront', const {});
            _evaluate();
            return const CommandResult.ok();
          },
        ),
      )
      ..register(
        Command(
          name: 'closeKids',
          description:
              'Close the Kids Portal. Under the Kids or Night profile this '
              'also returns the profile to Family.',
          handler: (_) async {
            await leave();
            return const CommandResult.ok();
          },
        ),
      )
      ..register(
        Command(
          name: 'setProfile',
          description: 'Switch the Phoenix profile: family, kids or night.',
          params: const {'profile': 'family, kids or night'},
          handler: (params) async {
            final value = '${params['profile'] ?? ''}'.trim().toLowerCase();
            if (!defs.phoenixProfile.options!.contains(value)) {
              return CommandResult.fail('unknown profile "$value"');
            }
            await _settings.set(defs.phoenixProfile, value);
            // Settle now: callers (Home Assistant, the remote) read the
            // state right after, before the change event arrives.
            _evaluate();
            return const CommandResult.ok();
          },
        ),
      )
      ..register(
        Command(
          name: 'kidsAddTime',
          description: "Add minutes to today's Kids Portal screen time.",
          params: const {'minutes': 'minutes to add, 1 to 240'},
          handler: (params) async {
            final minutes = int.tryParse('${params['minutes']}') ?? 0;
            if (minutes < 1 || minutes > 240) {
              return const CommandResult.fail('minutes must be 1 to 240');
            }
            await addMinutes(minutes);
            return const CommandResult.ok();
          },
        ),
      )
      ..register(
        Command(
          name: 'kidsStatus',
          description: 'The profile, what the Kids Portal shows and the time left.',
          quiet: true,
          handler: (_) async => CommandResult.ok(status()),
        ),
      );
    _timer = Timer.periodic(_tick, (_) => _onTick());
    _evaluate();
  }

  Map<String, Object?> status() => {
    'profile': profile,
    'screen': screen.value.name,
    'minutesLeft': minutesLeft,
    'usedMinutes': _used ~/ 60,
  };

  int? get minutesLeft {
    final left = secondsLeft.value;
    return left == null ? null : (left / 60).ceil();
  }

  /// Leave the portal: a locked profile goes back to Family.
  Future<void> leave() async {
    _openedByMenu = false;
    if (locked) {
      await _settings.set(defs.phoenixProfile, 'family');
    }
    _evaluate();
  }

  /// Whether [pin] unlocks the portal. Without a PIN set, the UI's long
  /// press is the gate and any call passes.
  bool checkPin(String pin) {
    final want = _settings.get(defs.kidsPin).trim();
    return want.isEmpty || pin.trim() == want;
  }

  bool get hasPin => _settings.get(defs.kidsPin).trim().isNotEmpty;

  Future<void> addMinutes(int minutes) async {
    _rollDay();
    _bonus += minutes * 60;
    await _saveUsage();
    _evaluate();
  }

  /// Whether [now] falls in the bedtime window (which may cross midnight).
  @visibleForTesting
  static bool inBedtime(DateTime now, String bedtime, String wake) {
    int? parse(String hhmm) {
      final parts = hhmm.split(':');
      if (parts.length != 2) return null;
      final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
      if (h == null || m == null) return null;
      return h * 60 + m;
    }

    final start = parse(bedtime), end = parse(wake);
    if (start == null || end == null || start == end) return false;
    final t = now.hour * 60 + now.minute;
    return start < end ? (t >= start && t < end) : (t >= start || t < end);
  }

  void _onTick() {
    _rollDay();
    if (screen.value == KidsScreen.play && _screenOn && _limitSeconds > 0) {
      _used += _tick.inSeconds;
      unawaited(_saveUsage());
    }
    _evaluate();
  }

  void _evaluate() {
    _rollDay();
    final limit = _limitSeconds;
    secondsLeft.value = limit <= 0
        ? null
        : (limit + _bonus - _used).clamp(0, 1 << 30);
    final p = profile;
    final wanted = p == 'kids' || (_openedByMenu && (enabled || p != 'family'));
    final KidsScreen next;
    if (p == 'night') {
      next = KidsScreen.bedtime;
    } else if (!wanted) {
      next = KidsScreen.hidden;
    } else if (inBedtime(
      _clock(),
      _settings.get(defs.kidsBedtime),
      _settings.get(defs.kidsWakeTime),
    )) {
      next = KidsScreen.bedtime;
    } else if (secondsLeft.value == 0) {
      next = KidsScreen.done;
    } else {
      next = KidsScreen.play;
    }
    final changed = next != screen.value;
    final before = minutesLeft;
    screen.value = next;
    if (changed || before != minutesLeft || _lastProfile != p) {
      _lastProfile = p;
      bus.publish(
        KidsStatusChanged(profile: p, screen: next.name, minutesLeft: minutesLeft),
      );
    }
  }

  String? _lastProfile;

  String _today() {
    final d = _clock();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  void _rollDay() {
    final today = _today();
    if (today != _day) {
      _day = today;
      _used = 0;
      _bonus = 0;
    }
  }

  Future<void> _loadUsage() async {
    final raw = (await _prefs()).getString(_usageKey) ?? '';
    final parts = raw.split(':');
    _day = _today();
    if (parts.length == 3 && parts[0] == _day) {
      _used = int.tryParse(parts[1]) ?? 0;
      _bonus = int.tryParse(parts[2]) ?? 0;
    }
  }

  Future<void> _saveUsage() async {
    await (await _prefs()).setString(_usageKey, '$_day:$_used:$_bonus');
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
  }
}
