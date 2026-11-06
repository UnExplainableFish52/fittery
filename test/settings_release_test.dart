import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/app.dart';
import 'package:fittery/src/controller.dart';
import 'package:fittery/src/models.dart';

void main() {
  testWidgets('Settings introduction and alert offer are acknowledged once', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    final c = BatteryController()
      ..ready = true
      ..onboardingCompleted = true
      ..showOnboardingOnLaunch = false
      ..reading = Reading({'plugged': 0});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BatteryController.channel, (call) async {
          calls.add(call);
          if (call.method == 'history') {
            return {'points': [], 'sessions': [], 'daily': []};
          }
          return null;
        });
    await tester.pumpWidget(FitteryApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Make Fittery yours'), findsOneWidget);
    await tester.tap(find.text('Explore Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Enable Background Alerts'), findsOneWidget);
    final primary = tester.getRect(
      find.widgetWithText(FilledButton, 'Enable Background Alerts'),
    );
    final secondary = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Not Now'),
    );
    expect(primary.bottom, lessThan(secondary.top));
    expect(primary.width, secondary.width);
    await tester.tap(find.text('Not Now'));
    await tester.pumpAndSettle();
    expect(c.settingsIntroAcknowledged, isTrue);
    expect(c.backgroundAlertsOffered, isTrue);
    expect(c.backgroundAlertsEnabled, isFalse);
    expect(
      calls.where(
        (call) =>
            call.method == 'monitoring' || call.method == 'backgroundAlerts',
      ),
      isEmpty,
    );
    await tester.tap(find.text('Dashboard').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Make Fittery yours'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('Enabling Background Alerts never sends a Monitor Mode command', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    final c = BatteryController();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BatteryController.channel, (call) async {
          calls.add(call);
          if (call.method == 'initial') {
            return {
              'backgroundAlertsEnabled': true,
              'backgroundAlertsRunning': true,
            };
          }
          return null;
        });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => SettingsPage(c: c),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('background-alerts-settings')));
    await tester.pumpAndSettle();
    expect(c.backgroundAlertsEnabled, isTrue);
    expect(
      calls.where((call) => call.method == 'backgroundAlerts').single.arguments,
      true,
    );
    expect(calls.where((call) => call.method == 'monitoring'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
