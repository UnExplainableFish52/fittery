import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/app.dart';
import 'package:fittery/src/controller.dart';
import 'package:fittery/src/notification_permission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (bit, title, action) in [
    (4, 'Battery temperature is high', 'Silence for 5 Minutes'),
    (1, 'Charging target reached', 'Silence'),
    (2, 'Battery is running low', 'Silence'),
  ]) {
    testWidgets('$title acknowledgment preserves the open page', (
      tester,
    ) async {
      var active = 0;
      var acknowledgments = 0;
      final c = BatteryController();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BatteryController.channel, (call) async {
            if (call.method == 'acknowledgeAlert') {
              expect(call.arguments, bit);
              acknowledgments++;
              active = 0;
              // Emulate the native event arriving before the method reply.
              await c.loadInitial();
            }
            if (call.method == 'initial') {
              return {
                'activeAlertMask': active,
                'temperatureC': 41.0,
                'level': 80,
                'onboarding': {
                  'onboardingCompleted': true,
                  'showOnboardingOnLaunch': false,
                },
              };
            }
            return null;
          });
      await c.loadInitial();
      await tester.pumpWidget(FitteryApp(controller: c));
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Existing detail screen')),
        ),
      );
      await tester.pumpAndSettle();
      active = bit;
      await c.loadInitial();
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      final button = tester.getCenter(
        find.widgetWithText(FilledButton, action),
      );
      await tester.tapAt(button);
      await tester.tapAt(button);
      await tester.pumpAndSettle();
      expect(acknowledgments, 1);
      expect(find.text(title), findsNothing);
      expect(find.text('Existing detail screen'), findsOneWidget);
      expect(navigator.canPop(), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }

  testWidgets(
    'Settings recovery refreshes permission without enabling monitoring',
    (tester) async {
      var allowed = false;
      var requests = 0;
      final c = BatteryController();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BatteryController.channel, (call) async {
            if (call.method == 'notificationPermission') {
              return {'allowed': allowed, 'asked': true, 'canRequest': false};
            }
            if (call.method == 'notificationSettings') allowed = true;
            if (call.method == 'requestNotifications') requests++;
            if (call.method == 'initial') {
              return {'notificationsAllowed': allowed};
            }
            return null;
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => ensureNotificationPermission(ctx, c),
              child: const Text('Recover'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Recover'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(c.notificationsAllowed, isTrue);
      expect(c.monitoring, isFalse);
      expect(requests, 0);
      c.dispose();
    },
  );
  testWidgets(
    'denial offers settings without automatically repeating requests',
    (tester) async {
      var requests = 0;
      var asked = false;
      final c = BatteryController();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BatteryController.channel, (call) async {
            if (call.method == 'notificationPermission') {
              return {'allowed': false, 'asked': asked, 'canRequest': !asked};
            }
            if (call.method == 'requestNotifications') {
              requests++;
              asked = true;
              throw PlatformException(code: 'NOTIFICATIONS');
            }
            return null;
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () =>
                  ensureNotificationPermission(ctx, c, initial: true),
              child: const Text('Setup'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Setup'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Enable Notifications'), findsNothing);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Setup'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.byType(AlertDialog), findsNothing);
      c.dispose();
    },
  );

  testWidgets(
    'foreground heat shows one dialog and acknowledges only temperature',
    (tester) async {
      var active = true;
      int? acknowledged;
      final c = BatteryController();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BatteryController.channel, (call) async {
            if (call.method == 'acknowledgeAlert') {
              acknowledged = call.arguments as int;
              active = false;
            }
            if (call.method == 'initial') {
              return {
                'activeAlertMask': active ? 4 : 0,
                'heatEpisode': 1,
                'temperatureC': 41.0,
                'settings': {'heatLimit': 40, 'heatReminderMinutes': 5},
                'onboarding': {
                  'onboardingCompleted': true,
                  'showOnboardingOnLaunch': false,
                },
              };
            }
            return null;
          });
      await c.loadInitial();
      await tester.pumpWidget(FitteryApp(controller: c));
      await c.loadInitial();
      await tester.pumpAndSettle();
      expect(find.text('Battery temperature is high'), findsOneWidget);
      await c.loadInitial();
      await tester.pumpAndSettle();
      expect(find.text('Battery temperature is high'), findsOneWidget);
      await tester.tap(find.text('Silence for 5 Minutes'));
      await tester.pumpAndSettle();
      expect(acknowledged, 4);
      expect(find.text('Battery temperature is high'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
