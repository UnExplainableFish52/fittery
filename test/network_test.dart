import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/app.dart';
import 'package:fittery/src/controller.dart';
import 'package:fittery/src/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final networkCalls = <String>[];
  final methodCalls = <String>[];

  setUp(() {
    networkCalls.clear();
    methodCalls.clear();
    messenger.setMockMethodCallHandler(BatteryController.channel, (call) async {
      methodCalls.add(call.method);
      return switch (call.method) {
        'initial' || 'refresh' => {'level': 80, 'status': 'Discharging'},
        'history' => {'points': [], 'sessions': [], 'daily': []},
        'deviceInfo' => {'model': 'Test phone', 'totalRamBytes': 8589934592},
        _ => null,
      };
    });
    for (final name in ['fittery/readings', 'fittery/preview']) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(const MethodChannel('fittery/network'), (
      call,
    ) async {
      networkCalls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(BatteryController.channel, null);
    for (final name in [
      'fittery/readings',
      'fittery/preview',
      'fittery/network',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);
  Future<void> emitNetwork() async {
    await messenger.handlePlatformMessage(
      'fittery/network',
      const StandardMethodCodec().encodeSuccessEnvelope({
        'downloadBytesPerSecond': 125000,
        'uploadBytesPerSecond': 1250,
        'connectionType': 'Wi-Fi',
      }),
      (_) {},
    );
    await settle();
  }

  test(
    'Network activity defaults off and respects tabs, graphs, lifecycle and rapid changes',
    () async {
      final c = BatteryController();
      await c.initialize();
      await settle();
      expect(c.flag('networkEnabled'), isFalse);
      expect(networkCalls, isEmpty);

      await c.save('networkEnabled', true);
      await settle();
      expect(networkCalls, ['listen']);
      var batteryUiChanges = 0;
      var networkUiChanges = 0;
      c.addListener(() => batteryUiChanges++);
      c.networkChanges.addListener(() => networkUiChanges++);
      await emitNetwork();
      expect(batteryUiChanges, 0);
      expect(networkUiChanges, 1);
      expect(c.network?.number('downloadBytesPerSecond'), 125000);

      c.setDashboardVisible(false);
      expect(c.network, isNull);
      await settle();
      expect(networkCalls.last, 'cancel');
      c.setDashboardVisible(true);
      await settle();
      await emitNetwork();
      expect(c.network, isNotNull);

      // Pending cancellation must finish before a replacement listener starts.
      c.setDashboardVisible(false);
      c.setDashboardVisible(true);
      c.setDashboardVisible(false);
      c.setDashboardVisible(true);
      await settle();
      await emitNetwork();
      expect(c.network, isNotNull);
      expect(networkCalls.last, 'listen');

      c.setTelemetryVisible(true);
      await settle();
      expect(c.network, isNull);
      expect(networkCalls.last, 'cancel');
      c.setTelemetryVisible(false);
      await settle();
      expect(networkCalls.last, 'listen');

      c.setAppActive(false);
      await settle();
      expect(networkCalls.last, 'cancel');
      c.setAppActive(true);
      await settle();
      expect(networkCalls.last, 'listen');

      await c.save('networkEnabled', false);
      await settle();
      expect(c.network, isNull);
      expect(networkCalls.last, 'cancel');
      final count = networkCalls.length;
      c.setAppActive(false);
      c.setAppActive(true);
      await settle();
      expect(networkCalls.length, count);
      expect(methodCalls, isNot(contains('monitoring')));
      c.dispose();
      await settle();
    },
  );

  test('Device information is cached until manual refresh', () async {
    final c = BatteryController();
    await c.initialize();
    await settle();
    expect(c.deviceInfo?.text('model'), 'Test phone');
    c.setDashboardVisible(false);
    c.setDashboardVisible(true);
    await settle();
    expect(methodCalls.where((method) => method == 'deviceInfo').length, 1);
    await c.refreshReading();
    expect(methodCalls.where((method) => method == 'deviceInfo').length, 2);
    c.dispose();
    await settle();
  });

  test(
    'Disposing an active dashboard cancels its native network observer',
    () async {
      final c = BatteryController();
      await c.initialize();
      await c.save('networkEnabled', true);
      await settle();
      expect(networkCalls.last, 'listen');
      c.dispose();
      await settle();
      expect(networkCalls.last, 'cancel');
    },
  );

  test(
    'Rate units are decimal bits per second and missing values stay unknown',
    () {
      expect(networkRate(null), '—');
      expect(networkRate(-1), '—');
      expect(networkRate(double.infinity), '—');
      expect(networkRate(0), '0.0 Kbps');
      expect(networkRate(1250), '10.0 Kbps');
      expect(networkRate(125000), '1.00 Mbps');
      expect(memorySize(8589934592), '8.0 GiB');
    },
  );

  for (final width in [320.0, 400.0]) {
    testWidgets(
      'Dashboard cards and miscellaneous information fit at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = BatteryController()
          ..ready = true
          ..reading = Reading({'level': 80, 'status': 'Discharging'})
          ..settings['networkEnabled'] = true
          ..network = Reading({
            'downloadBytesPerSecond': 12500000,
            'uploadBytesPerSecond': 1250,
            'combinedBytesPerSecond': 12501250,
            'connectionType': 'Wi-Fi',
            'wifi': true,
            'connected': true,
            'internetValidated': true,
            'frequencyMhz': 5180,
            'wifiBand': '5 GHz',
          })
          ..deviceInfo = Reading({
            'model': 'Test phone',
            'totalRamBytes': 8589934592,
          });
        await tester.pumpWidget(FitteryApp(controller: c));
        await tester.pumpAndSettle();
        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('Details'), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('network-enabled')),
          400,
        );
        await tester.pumpAndSettle();
        expect(find.text('Download'), findsOneWidget);
        expect(find.text('Upload'), findsOneWidget);
        expect(find.text('100.00 Mbps'), findsOneWidget);
        expect(find.text('10.0 Kbps'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('Miscellaneous'), 250);
        await tester.pumpAndSettle();
        expect(find.text('Miscellaneous'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Hidden by Android'), 250);
        await tester.pumpAndSettle();
        expect(find.text('Hidden by Android'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('8.0 GiB'), 250);
        await tester.pumpAndSettle();
        expect(find.text('8.0 GiB'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
