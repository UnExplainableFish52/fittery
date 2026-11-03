import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/app.dart';
import 'package:fittery/src/controller.dart';
import 'package:fittery/src/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  List<Map<String, dynamic>> points(double temperature) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      {'time': now - 3000, 'sessionId': 1, 'temperatureC': temperature},
      {'time': now, 'sessionId': 1, 'temperatureC': temperature + 1},
    ];
  }

  LineChartData painter(WidgetTester tester) =>
      tester.widget<LineChart>(find.byType(LineChart)).data;

  testWidgets('Temperature updates only its own graph once a minute', (
    tester,
  ) async {
    final source = ValueNotifier(points(30));
    var parentBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (_) {
              parentBuilds++;
              return SavedMetricGraph(
                source: source,
                initialPoints: source.value,
                metric: 'temperatureC',
                label: 'Temperature',
                color: mint,
                transform: (v) => v,
                active: () => true,
              );
            },
          ),
        ),
      ),
    );
    final original = painter(tester);
    source.value = points(35);
    await tester.pump(const Duration(seconds: 59));
    expect(identical(painter(tester), original), isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(painter(tester).lineBarsData.single.spots.first.y, 35);
    expect(parentBuilds, 1);
    await tester.pumpWidget(const SizedBox());
    source.dispose();
  });

  testWidgets(
    'A minute fetch arriving after the graph deadline displays immediately',
    (tester) async {
      final source = ValueNotifier(points(30));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedMetricGraph(
              source: source,
              initialPoints: source.value,
              metric: 'temperatureC',
              label: 'Temperature',
              color: mint,
              transform: (v) => v,
              active: () => true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(minutes: 1));
      source.value = points(36);
      await tester.pump();
      expect(painter(tester).lineBarsData.single.spots.first.y, 36);
      await tester.pumpWidget(const SizedBox());
      source.dispose();
    },
  );

  testWidgets(
    'Background history refresh leaves the telemetry container stable',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Completer<Map<String, dynamic>>? pending;
      messenger.setMockMethodCallHandler(BatteryController.channel, (
        call,
      ) async {
        if (call.method == 'history') {
          return pending?.future ??
              {'points': points(30), 'sessions': [], 'daily': []};
        }
        return null;
      });
      final c = BatteryController()
        ..historyLoaded = true
        ..points = points(30);
      await tester.pumpWidget(
        MaterialApp(
          home: TelemetryPage(c: c, initialMetric: 'temperatureC'),
        ),
      );
      await tester.pumpAndSettle();
      final heading = tester.widget(
        find.text('Choose the readings to compare'),
      );
      final graph = painter(tester);
      pending = Completer();
      final refresh = c.refreshHistory();
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      pending.complete({'points': points(38), 'sessions': [], 'daily': []});
      await refresh;
      c.notifyListeners();
      await tester.pump();
      expect(
        identical(
          tester.widget(find.text('Choose the readings to compare')),
          heading,
        ),
        isTrue,
      );
      expect(identical(painter(tester), graph), isTrue);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Notification refresh setting defaults to one second and saves a selection',
    (tester) async {
      MethodCall? saved;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BatteryController.channel, (call) async {
            if (call.method == 'updateSetting') saved = call;
            return null;
          });
      final c = BatteryController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SettingsPage(c: c)),
        ),
      );
      final control = find.byKey(
        const ValueKey('notification-refresh-interval'),
      );
      await tester.scrollUntilVisible(
        control,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      expect(tester.widget<DropdownButton<int>>(control).value, 1);
      await tester.tap(control);
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 seconds').last);
      await tester.pumpAndSettle();
      expect(saved!.arguments, {
        'key': 'notificationIntervalSeconds',
        'value': 5,
      });
      expect(c.settings['notificationIntervalSeconds'], 5);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
