import 'package:fittery/src/app.dart';
import 'package:fittery/src/charging_dashboard.dart';
import 'package:fittery/src/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(BatteryController.channel, (call) async {
      calls.add(call);
      return call.method == 'initial'
          ? {
              'plugged': 1,
              'level': 64,
              'status': 'Charging',
              'settings': {
                'chargingDashboard': true,
                'chargingScreenSaver': true,
              },
            }
          : null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('fittery/readings'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(BatteryController.channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('fittery/readings'),
      null,
    );
  });

  test(
    'Dream connects only to live readings without history, network, or preview',
    () async {
      final c = BatteryController()..setChargingDashboardVisible(true);
      await c.loadInitial();
      await c.connect(readingsOnly: true);
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((call) => call.method), ['initial', 'listen']);
      expect(c.monitoring, isFalse);
      c.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(calls.last.method, 'cancel');
    },
  );

  test(
    'Screen saver enables the master feature and master off disables it',
    () async {
      final c = BatteryController();
      expect(c.flag('chargingScreenSaver'), isFalse);
      await c.save('chargingScreenSaver', true);
      expect(c.flag('chargingDashboard'), isTrue);
      expect(c.flag('chargingScreenSaver'), isTrue);
      await c.save('chargingDashboard', false);
      expect(c.flag('chargingScreenSaver'), isFalse);
      c.dispose();
    },
  );

  testWidgets(
    'Dream close exits its system window without toggling Activity lock flags',
    (tester) async {
      final c = BatteryController()..setChargingDashboardVisible(true);
      await c.loadInitial();
      await tester.pumpWidget(
        MaterialApp(home: ChargingDashboardPage(c: c, isDream: true)),
      );
      await tester.pump();
      expect(
        calls.where((call) => call.method == 'chargingDashboardVisible'),
        isEmpty,
      );
      await tester.tap(find.byTooltip('Close charging dashboard'));
      await tester.pump();
      expect(calls.where((call) => call.method == 'finishDream').length, 1);
      expect(
        calls.where((call) => call.method == 'chargingDashboardVisible'),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('Settings offers a separate system screen-saver setup action', (
    tester,
  ) async {
    final c = BatteryController()..ready = true;
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
    final toggle = find.byKey(const ValueKey('setting-chargingScreenSaver'));
    await tester.scrollUntilVisible(toggle, 220);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(c.flag('chargingScreenSaver'), isTrue);
    final setup = find.byKey(const ValueKey('screen-saver-setup'));
    await tester.ensureVisible(setup);
    await tester.pumpAndSettle();
    await tester.tap(setup);
    await tester.pumpAndSettle();
    expect(calls.any((call) => call.method == 'screenSaverSettings'), isTrue);
    expect(calls.where((call) => call.method == 'monitoring'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
