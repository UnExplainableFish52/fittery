import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/app.dart';
import 'package:fittery/src/controller.dart';
import 'package:fittery/src/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BatteryController.channel, (call) async {
          if (call.method == 'history') {
            return {'points': [], 'sessions': [], 'daily': []};
          }
          return null;
        });
  });

  test(
    'Unavailable hardware stays unavailable and dual-cell power is consistent',
    () {
      final missing = Reading({});
      expect(missing.level, isNull);
      expect(missing.power(true), isNull);
      expect(metric(null, 'mA'), '—');
      final reading = Reading({'voltageMv': 4171, 'currentMa': -545});
      expect(reading.power(false), closeTo(-2.273195, 0.000001));
      expect(reading.power(true), closeTo(-4.54639, 0.000001));
    },
  );

  for (final size in [const Size(400, 850), const Size(320, 640)]) {
    testWidgets('Three tabs and readable telemetry at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = BatteryController()
        ..ready = true
        ..reading = Reading({
          'level': 84,
          'status': 'Charging',
          'plugged': 1,
          'voltageMv': 4150,
          'currentMa': 2350,
          'temperatureC': 32.0,
          'health': 'Good',
          'source': 'AC charger',
          'model': 'Phone',
          'manufacturer': 'Manufacturer',
        });
      await tester.pumpWidget(FitteryApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('84'), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(3));
      expect(find.text('4.15 V'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('Daily charging'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance & units'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets('Clear history requires explicit confirmation', (tester) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BatteryController.channel, (call) async {
          calls.add(call.method);
          return call.method == 'history'
              ? {'points': [], 'sessions': [], 'daily': []}
              : null;
        });
    final controller = BatteryController()..ready = true;
    await tester.pumpWidget(FitteryApp(controller: controller));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Clear charge history'),
      450,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear charge history'));
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('clearHistory')));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('clearHistory')));
    await tester.tap(find.text('Clear charge history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    expect(calls, contains('clearHistory'));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
