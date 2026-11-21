import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/core/command_registry.dart';
import 'package:kiosk_satellite/core/event_bus.dart';
import 'package:kiosk_satellite/core/events.dart';
import 'package:kiosk_satellite/core/logging.dart';
import 'package:kiosk_satellite/managers/kids/kids_manager.dart';
import 'package:kiosk_satellite/managers/settings/definitions.dart' as defs;
import 'package:kiosk_satellite/managers/settings/settings_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EventBus bus;
  late CommandRegistry commands;
  late SettingsManager settings;
  late KidsManager kids;
  KidsManager? built;
  late List<KidsStatusChanged> events;
  var now = DateTime(2026, 11, 21, 15, 0);

  Future<void> build(Map<String, Object> initial, {String? usage}) async {
    SharedPreferences.setMockInitialValues({
      ...initial,
      'phx.kids.usage': ?usage,
    });
    bus = EventBus();
    final log = Logger();
    commands = CommandRegistry(log);
    // The kiosk commands the portal asks for when it opens.
    for (final name in ['screenOn', 'bringToFront']) {
      commands.register(
        Command(name: name, description: 'stub', handler: (_) async => const CommandResult.ok()),
      );
    }
    settings = SettingsManager(bus, commands, log);
    await settings.init();
    events = [];
    bus.on<KidsStatusChanged>().listen(events.add);
    built = kids = KidsManager(bus, commands, log, settings, clock: () => now);
    await kids.init();
  }

  tearDown(() async {
    await built?.dispose();
    built = null;
  });

  group('bedtime window', () {
    test('a window inside one day', () {
      expect(KidsManager.inBedtime(DateTime(2026, 1, 1, 13), '12:00', '14:00'), isTrue);
      expect(KidsManager.inBedtime(DateTime(2026, 1, 1, 14), '12:00', '14:00'), isFalse);
    });
    test('a window across midnight', () {
      expect(KidsManager.inBedtime(DateTime(2026, 1, 1, 20, 30), '20:00', '07:00'), isTrue);
      expect(KidsManager.inBedtime(DateTime(2026, 1, 1, 3), '20:00', '07:00'), isTrue);
      expect(KidsManager.inBedtime(DateTime(2026, 1, 1, 7), '20:00', '07:00'), isFalse);
      expect(KidsManager.inBedtime(DateTime(2026, 1, 1, 12), '20:00', '07:00'), isFalse);
    });
    test('off or malformed never matches', () {
      expect(KidsManager.inBedtime(DateTime(2026, 1, 1, 21), '', '07:00'), isFalse);
      expect(KidsManager.inBedtime(DateTime(2026, 1, 1, 21), 'soon', '07:00'), isFalse);
    });
  });

  test('defaults: Family profile, portal hidden, on in the menu', () async {
    now = DateTime(2026, 11, 21, 15, 0);
    await build({});
    expect(kids.profile, 'family');
    expect(kids.enabled, isTrue);
    expect(kids.screen.value, KidsScreen.hidden);
    expect(kids.locked, isFalse);
  });

  test('the menu opens the play screen and Family leaves freely', () async {
    now = DateTime(2026, 11, 21, 15, 0);
    await build({});
    expect((await commands.execute('openKids', const {})).ok, isTrue);
    expect(kids.screen.value, KidsScreen.play);
    await kids.leave();
    expect(kids.screen.value, KidsScreen.hidden);
    expect(kids.profile, 'family');
  });

  test('Home closes a portal opened from the menu, never a locked one', () async {
    now = DateTime(2026, 11, 21, 15, 0);
    await build({});
    expect(kids.closeIfFree(), isFalse); // nothing open
    await commands.execute('openKids', const {});
    expect(kids.closeIfFree(), isTrue);
    expect(kids.screen.value, KidsScreen.hidden);
    await commands.execute('setProfile', {'profile': 'kids'});
    expect(kids.closeIfFree(), isFalse);
    expect(kids.screen.value, KidsScreen.play);
    expect(kids.profile, 'kids');
  });

  test('the Kids profile locks the portal; leaving returns to Family', () async {
    now = DateTime(2026, 11, 21, 15, 0);
    await build({});
    await commands.execute('setProfile', {'profile': 'kids'});
    expect(kids.screen.value, KidsScreen.play);
    expect(kids.locked, isTrue);
    await Future<void>.delayed(Duration.zero); // let the bus deliver
    expect(events.last.profile, 'kids');
    await commands.execute('closeKids', const {});
    expect(kids.profile, 'family');
    expect(kids.screen.value, KidsScreen.hidden);
  });

  test('the Night profile shows the bedtime screen at any hour', () async {
    now = DateTime(2026, 11, 21, 15, 0);
    await build({});
    await commands.execute('setProfile', {'profile': 'night'});
    expect(kids.screen.value, KidsScreen.bedtime);
  });

  test('an unknown profile is refused', () async {
    await build({});
    final result = await commands.execute('setProfile', {'profile': 'party'});
    expect(result.ok, isFalse);
    expect(kids.profile, 'family');
  });

  test('inside the bedtime window the Kids profile shows bedtime', () async {
    now = DateTime(2026, 11, 21, 21, 0);
    await build({'ks.${defs.kidsBedtime.key}': '20:00'});
    await commands.execute('setProfile', {'profile': 'kids'});
    expect(kids.screen.value, KidsScreen.bedtime);
  });

  test('spent screen time shows the done screen; a parent can add more', () async {
    now = DateTime(2026, 11, 21, 15, 0);
    // 30 minutes allowed, all 30 already played today.
    await build(
      {'ks.${defs.kidsDailyMinutes.key}': '30'},
      usage: '2026-11-21:1800:0',
    );
    await commands.execute('setProfile', {'profile': 'kids'});
    expect(kids.screen.value, KidsScreen.done);
    expect(kids.minutesLeft, 0);
    await commands.execute('kidsAddTime', {'minutes': '15'});
    expect(kids.screen.value, KidsScreen.play);
    expect(kids.minutesLeft, 15);
    await Future<void>.delayed(Duration.zero); // let the bus deliver
    expect(events.last.minutesLeft, 15);
  });

  test("yesterday's usage does not count today", () async {
    now = DateTime(2026, 11, 21, 15, 0);
    await build(
      {'ks.${defs.kidsDailyMinutes.key}': '30'},
      usage: '2026-11-20:1800:0',
    );
    await commands.execute('setProfile', {'profile': 'kids'});
    expect(kids.screen.value, KidsScreen.play);
    expect(kids.minutesLeft, 30);
  });

  test('No limit reports no time left value', () async {
    await build({'ks.${defs.kidsDailyMinutes.key}': '0'});
    expect(kids.minutesLeft, isNull);
    expect((await commands.execute('kidsStatus', const {})).data, containsPair('minutesLeft', null));
  });

  test('the parent PIN gates leaving only when set', () async {
    await build({});
    expect(kids.hasPin, isFalse);
    expect(kids.checkPin('anything'), isTrue);
    await settings.set(defs.kidsPin, '2468');
    expect(kids.hasPin, isTrue);
    expect(kids.checkPin('1111'), isFalse);
    expect(kids.checkPin('2468'), isTrue);
  });

  test('adding time is bounded', () async {
    await build({});
    expect((await commands.execute('kidsAddTime', {'minutes': '0'})).ok, isFalse);
    expect((await commands.execute('kidsAddTime', {'minutes': '500'})).ok, isFalse);
  });
}
