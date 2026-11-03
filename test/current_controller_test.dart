import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/controller.dart';
import 'package:fittery/src/current_telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  var loads = 0;
  setUp(() {
    calls.clear();
    loads = 0;
    messenger.setMockMethodCallHandler(BatteryController.channel, (call) async {
      switch (call.method) {
        case 'initial':
          return {'level': 80, 'settings': <String, dynamic>{}};
        case 'history':
          return {'points': [], 'sessions': [], 'daily': []};
        case 'currentHistory':
          loads++;
          return <dynamic>[];
        default:
          return null;
      }
    });
    for (final name in ['fittery/readings', 'fittery/preview']) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(const MethodChannel('fittery/current'), (
      call,
    ) async {
      calls.add(call.method);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(BatteryController.channel, null);
    for (final name in [
      'fittery/readings',
      'fittery/preview',
      'fittery/current',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  test(
    'Charging dashboard suspends hidden high-frequency current sampling',
    () async {
      final c = BatteryController();
      await c.initialize();
      c.setCurrentChartVisible(true);
      await settle();
      expect(calls.last, 'listen');
      c.setChargingDashboardVisible(true);
      await settle();
      expect(calls.last, 'cancel');
      c.setChargingDashboardVisible(false);
      await settle();
      expect(calls.last, 'listen');
      c.dispose();
      await settle();
    },
  );
  test(
    'Current events redraw only the chart and obey visibility/lifecycle without range resets',
    () async {
      final c = BatteryController();
      await c.initialize();
      await settle();
      expect(calls, isEmpty);
      c.setTelemetryVisible(true, needsHistory: false);
      c.setCurrentChartVisible(true);
      await settle();
      expect(calls, ['listen']);
      expect(loads, 1);
      var pageRebuilds = 0, chartRebuilds = 0;
      c.addListener(() => pageRebuilds++);
      c.currentTelemetry.addListener(() => chartRebuilds++);
      await messenger.handlePlatformMessage(
        'fittery/current',
        const StandardMethodCodec().encodeSuccessEnvelope({
          'time': DateTime.now().millisecondsSinceEpoch,
          'currentMa': -545.0,
          'voltageMv': 4000,
          'sampleIntervalMs': 1000,
        }),
        (_) {},
      );
      await settle();
      expect(pageRebuilds, 0);
      expect(chartRebuilds, greaterThan(0));
      expect(
        c.currentTelemetry.frame(CurrentRange.minute).latest!.current,
        -545,
      );
      for (final range in CurrentRange.values) {
        c.currentTelemetry.frame(range);
      }
      expect(calls, ['listen']);
      expect(loads, 1);
      c.setAppActive(false);
      await settle();
      expect(calls.last, 'cancel');
      c.setAppActive(true);
      await settle();
      expect(calls.last, 'listen');
      expect(loads, 2);
      c.setCurrentChartVisible(false);
      c.setCurrentChartVisible(true);
      await settle();
      expect(calls.last, 'listen');
      expect(c.currentTelemetry.length, 1);
      c.dispose();
      await settle();
      expect(calls.last, 'cancel');
    },
  );

  test(
    'Clearing history invalidates an older pending current-history reply',
    () async {
      final pending = Completer<List<dynamic>>();
      messenger.setMockMethodCallHandler(BatteryController.channel, (
        call,
      ) async {
        if (call.method == 'currentHistory') return pending.future;
        if (call.method == 'history') {
          return {'points': [], 'sessions': [], 'daily': []};
        }
        return null;
      });
      final c = BatteryController();
      final loading = c.refreshCurrentHistory();
      await settle();
      await c.action('clearHistory');
      pending.complete([
        {
          'time': DateTime.now().millisecondsSinceEpoch - 1000,
          'currentMa': 300,
        },
      ]);
      await loading;
      expect(c.currentTelemetry.length, 0);
      c.dispose();
    },
  );
}
