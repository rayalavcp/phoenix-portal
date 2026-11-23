import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiosk_satellite/ui/timers_overlay.dart';

void main() {
  testWidgets('a quick-start tile starts a timer of its minutes', (tester) async {
    final started = <int>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TimerQuickStart(onStart: started.add))));
    for (final m in timerQuickMinutes) {
      expect(find.text('$m min'), findsOneWidget);
    }
    await tester.tap(find.text('5 min'));
    await tester.tap(find.text('15 min'));
    expect(started, [300, 900]);
  });
}
