import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fittery/src/app.dart';
import 'package:fittery/src/controller.dart';
import 'package:fittery/src/current_telemetry.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native live current, range switching, inspection and persisted reload on Android',
    (tester) async {
      final controller = BatteryController();
      await controller.initialize();
      await tester.pumpWidget(
        FitteryApp(
          controller: controller
            ..ready = true
            ..onboardingCompleted = true
            ..showOnboardingOnLaunch = false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('metric-currentMa')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('metric-currentMa')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      final observed = controller.currentTelemetry
          .frame(CurrentRange.minute)
          .latest;
      expect(observed, isNotNull);
      expect(
        observed!.current,
        isNotNull,
        reason:
            'This connected phone must expose a supported current property for the real-sensor check.',
      );
      expect(observed.rawCurrent, isNotNull);
      final convention = observed.convention!.split('/');
      final expected =
          observed.rawCurrent! /
          double.parse(convention.first) *
          (convention.last == 'true' ? -1 : 1);
      expect(observed.current, closeTo(expected, 1e-6));
      expect(observed.intervalMs, 1000);
      expect(
        controller.currentTelemetry.frame(CurrentRange.minute).fresh,
        isTrue,
      );
      expect(
        controller.currentTelemetry.frame(CurrentRange.minute).count,
        greaterThan(2),
      );
      debugPrint(
        'REAL_CURRENT raw=${observed.rawCurrent} convention=${observed.convention} mA=${observed.current} mV=${observed.voltage}',
      );
      final range = find.byKey(const ValueKey('current-range-1m'));
      await tester.ensureVisible(range);
      await tester.pumpAndSettle();
      for (final label in ['1m', '10m', '1h', '6h', '1m']) {
        await tester.tap(find.byKey(ValueKey('current-range-$label')));
        await tester.pumpAndSettle();
        expect(find.byType(LineChart), findsOneWidget);
      }
      await tester.ensureVisible(find.byType(LineChart));
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byType(LineChart));
      final gesture = await tester.startGesture(
        Offset(bounds.right - 6, bounds.center.dy),
      );
      await gesture.moveBy(const Offset(-8, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('graph-panel-currentMa')),
      );
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('current-chart-android');
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      final timestamp = observed.time;
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.pump(const Duration(milliseconds: 300));
      final reopened = BatteryController();
      await reopened.initialize();
      await reopened.refreshCurrentHistory();
      expect(
        reopened.currentTelemetry.sampleAt(timestamp)?.current,
        observed.current,
        reason: 'A fresh controller must reload this real sample from SQLite.',
      );
      reopened.dispose();
    },
  );
}
