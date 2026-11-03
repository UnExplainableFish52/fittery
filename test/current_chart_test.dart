import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/controller.dart';
import 'package:fittery/src/current_chart.dart';
import 'package:fittery/src/models.dart';

void main() {
  for (final width in [320.0, 400.0]) {
    testWidgets(
      'Current chart keeps true time positions, ranges and tooltip bounds at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final now = DateTime.now().millisecondsSinceEpoch;
        final c = BatteryController()
          ..ready = true
          ..reading = Reading({'currentMa': 352});
        c.currentTelemetry.mergeHistory([
          for (var i = 20; i >= 0; i--)
            {
              'time': now - i * 1000,
              'currentMa': i == 10 ? 454.0 : 352.0,
              'voltageMv': 3943,
              'sampleIntervalMs': 1000,
            },
        ]);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: CurrentChart(c: c),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        LineChartData data() =>
            tester.widget<LineChart>(find.byType(LineChart)).data;
        expect(data().minX, -3600);
        expect(data().maxX, 0);
        final spots = data().lineBarsData.single.spots.where(
          (s) => !s.isNull(),
        );
        expect(spots.first.x, greaterThanOrEqualTo(-21));
        expect(spots.last.x, closeTo(0, 1));
        expect(find.text('352 mA'), findsWidgets);
        expect(find.text('Average'), findsOneWidget);
        for (final entry in {
          '1m': -60.0,
          '10m': -600.0,
          '1h': -3600.0,
          '6h': -21600.0,
        }.entries) {
          await tester.tap(find.byKey(ValueKey('current-range-${entry.key}')));
          await tester.pumpAndSettle();
          expect(data().minX, entry.value);
          expect(c.currentTelemetry.length, 21);
        }
        await tester.tap(find.byKey(const ValueKey('current-range-1m')));
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byType(LineChart));
        final gesture = await tester.startGesture(
          Offset(rect.right - 8, rect.center.dy),
        );
        await tester.pump();
        await gesture.moveBy(const Offset(-15, 0));
        await tester.pump();
        expect(data().extraLinesData.verticalLines, isNotEmpty);
        expect(
          data().lineTouchData.touchTooltipData.fitInsideHorizontally,
          isTrue,
        );
        expect(
          data().lineTouchData.touchTooltipData.fitInsideVertically,
          isTrue,
        );
        await gesture.up();
        await tester.pumpAndSettle();
        expect(data().extraLinesData.verticalLines, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
