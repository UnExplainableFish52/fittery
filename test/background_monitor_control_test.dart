import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/app.dart';
import 'package:fittery/src/controller.dart';
import 'package:fittery/src/models.dart';
import 'package:fittery/src/smooth_toggle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final toggle = find.byKey(const ValueKey('background-monitor-toggle'));
  BatteryController controller() => BatteryController()
    ..ready = true
    ..onboardingCompleted = true
    ..showOnboardingOnLaunch = false
    ..reading = Reading({'level': 64, 'plugged': 0, 'status': 'Discharging'});

  testWidgets(
    'Dashboard toggle sends explicit on/off requests and follows external service changes',
    (tester) async {
      final c = controller();
      var enabled = false;
      final requests = <bool>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BatteryController.channel, (call) async {
            if (call.method == 'monitoring') {
              enabled = call.arguments as bool;
              requests.add(enabled);
            }
            if (call.method == 'initial') {
              return {'level': 64, 'monitoring': enabled, 'plugged': 0};
            }
            if (call.method == 'history') {
              return {'points': [], 'sessions': [], 'daily': []};
            }
            return null;
          });
      await tester.pumpWidget(FitteryApp(controller: c));
      expect(find.text('Get to know your battery'), findsOneWidget);
      expect(find.text('Live statistics'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('LIVE')),
        findsNothing,
      );
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SmoothToggle>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(requests, [true]);
      expect(tester.widget<SmoothToggle>(toggle).value, isTrue);
      expect(find.byTooltip('Recording and alerts on'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(requests, [true, false]);
      expect(tester.widget<SmoothToggle>(toggle).value, isFalse);
      expect(find.byTooltip('Recording and alerts off'), findsOneWidget);
      c.monitoring = true;
      c.notifyListeners();
      await tester.pumpAndSettle();
      expect(tester.widget<SmoothToggle>(toggle).value, isTrue);
      expect(requests, [true, false]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Pending permission disables repeated taps and a rejected request keeps monitoring off',
    (tester) async {
      final c = controller();
      final permission = Completer<void>();
      var requests = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BatteryController.channel, (call) async {
            if (call.method == 'monitoring') {
              requests++;
              await permission.future;
            }
            return null;
          });
      await tester.pumpWidget(FitteryApp(controller: c));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pump();
      expect(tester.widget<SmoothToggle>(toggle).onChanged, isNull);
      expect(find.text('Enabling…'), findsOneWidget);
      expect(requests, 1);
      permission.completeError(
        PlatformException(
          code: 'NOTIFICATIONS',
          message: 'Allow notifications to enable monitoring.',
        ),
      );
      await tester.pumpAndSettle();
      expect(c.monitoring, isFalse);
      expect(tester.widget<SmoothToggle>(toggle).value, isFalse);
      expect(tester.widget<SmoothToggle>(toggle).onChanged, isNotNull);
      expect(
        find.text('Allow notifications to enable monitoring.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  for (final (width, scale) in [(393.0, 1.0), (400.0, 1.3), (320.0, 1.5)]) {
    testWidgets(
      'Thin monitor row and outlined dashboard fit at $width / $scale',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final c = controller()..settings['chargingDashboard'] = true;
        await tester.pumpWidget(FitteryApp(controller: c));
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        expect(find.text('Monitor Battery'), findsOneWidget);
        expect(find.text('Fullscreen Dashboard'), findsOneWidget);
        expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
