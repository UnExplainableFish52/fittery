import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/app.dart';
import 'package:fittery/src/models.dart';

void main() {
  for (final metric in [
    ('temperatureC', 'Temperature · °F', '°F', 30.0, 86.0),
    ('powerW', 'Net power · W', 'W', -4.25, -4.25),
    ('voltageMv', 'Voltage · V', 'V', 4100.0, 4.1),
    ('currentMa', 'Net current · mA', 'mA', -800.0, -800.0),
    ('chargeCounterMah', 'Remaining charge · mAh', 'mAh', 2400.0, 2400.0),
    ('level', 'Battery · %', '%', 52.0, 52.0),
  ]) {
    testWidgets(
      '${metric.$1} has scaled axes, signed touch values, timestamps and gaps',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final start = DateTime(2026, 10, 30, 10, 20).millisecondsSinceEpoch;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: MetricChart(
                  metric: metric.$1,
                  label: metric.$2,
                  color: mint,
                  transform: (v) => metric.$1 == 'temperatureC'
                      ? v * 1.8 + 32
                      : metric.$1 == 'voltageMv'
                      ? v / 1000
                      : v,
                  points: [
                    {'time': start, metric.$1: metric.$4},
                    {'time': start + 3000, metric.$1: metric.$4},
                    {'time': start + 6000, metric.$1: null},
                    {'time': start + 9000, metric.$1: metric.$4},
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final data = tester.widget<LineChart>(find.byType(LineChart)).data;
        final bar = data.lineBarsData.single;
        expect(data.titlesData.leftTitles.sideTitles.showTitles, isTrue);
        expect(data.minY, lessThan(metric.$5));
        expect(data.maxY, greaterThan(metric.$5));
        expect(bar.spots.where((s) => s.isNull()), hasLength(1));
        expect(bar.spots.first.y, closeTo(metric.$5, .00001));
        expect(bar.spots.last.x, 9);
        expect(data.lineTouchData.enabled, isTrue);
        expect(data.lineTouchData.handleBuiltInTouches, isTrue);
        final tooltip = data.lineTouchData.touchTooltipData.getTooltipItems([
          LineBarSpot(bar, 0, bar.spots.first),
        ]).single!;
        expect(tooltip.text, contains(metric.$3));
        expect(tooltip.text, contains('10:20:00'));
        if (metric.$5 < 0) expect(tooltip.text, startsWith('-'));
        expect(
          data.lineTouchData.touchTooltipData.fitInsideHorizontally,
          isTrue,
        );
        expect(data.lineTouchData.touchTooltipData.fitInsideVertically, isTrue);
        final rect = tester.getRect(find.byType(LineChart));
        final gesture = await tester.startGesture(rect.center);
        await gesture.moveBy(const Offset(25, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
