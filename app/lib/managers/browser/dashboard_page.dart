import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/event_bus.dart';
import '../../core/events.dart';
import '../navigation/compass_layout.dart';
import '../screensaver/screensaver_manager.dart' show parseScreensaverSchedule;
import '../settings/definitions.dart' as defs;
import '../settings/settings_manager.dart';

/// The settings [dashboardPageNeeded] reads.
final dashboardPageKeys = {
  defs.navStyle.key,
  defs.navCompassLayout.key,
  defs.screensaverMode.key,
  defs.screensaverScheduleEnabled.key,
  defs.screensaverSchedule.key,
  defs.voiceRuntime.key,
  defs.homeScreen.key,
};

/// Whether the kiosk has a use for the dashboard page. Classic with the
/// Home Assistant dashboard as home always shows it. Compass needs it only for a dashboard view in its layout, the
/// Home Assistant Dashboard screensaver (set, or on the schedule) and
/// Voice Satellite running in the dashboard. Without any of them the page
/// is never loaded.
///
/// Phoenix Home (Classic with the Phoenix home screen) needs it only while
/// the dashboard is open over it ([dashboardOpen]), or for the same voice
/// and screensaver uses: Home Assistant is an add-on there, and without it
/// the page is never loaded.
bool dashboardPageNeeded(
  SettingsManager settings, {
  bool dashboardOpen = false,
}) {
  final compass = settings.get(defs.navStyle) == 'compass';
  final phoenix = !compass && settings.get(defs.homeScreen) == 'phoenix';
  if (!compass && !phoenix) return true;
  if (phoenix && dashboardOpen) return true;
  if (compass) {
    final layout = CompassLayout.decode(settings.get(defs.navCompassLayout));
    if (layout.dashboards.isNotEmpty) return true;
  }
  if (settings.get(defs.voiceRuntime) == 'dashboard') return true;
  if (settings.get(defs.screensaverMode) == 'dashboard') return true;
  if (!settings.get(defs.screensaverScheduleEnabled)) return false;
  return parseScreensaverSchedule(
    settings.get(defs.screensaverSchedule),
  ).any((entry) => entry['mode'] == 'dashboard');
}

/// Keeps [needed] on [dashboardPageNeeded] as the settings change.
StreamSubscription<SettingChanged> followDashboardPage(
  SettingsManager settings,
  EventBus bus,
  ValueNotifier<bool> needed, {
  ValueListenable<bool>? dashboardOpen,
}) {
  void update() => needed.value = dashboardPageNeeded(
    settings,
    dashboardOpen: dashboardOpen?.value ?? false,
  );
  update();
  dashboardOpen?.addListener(update);
  return bus.on<SettingChanged>().listen((e) {
    if (dashboardPageKeys.contains(e.key)) update();
  });
}
