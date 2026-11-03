import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/app.dart';
import 'package:fittery/src/controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = DateTime.now()
      .subtract(const Duration(days: 2))
      .millisecondsSinceEpoch;
  final record = <String, dynamic>{
    'id': 7,
    'name': 'Overnight test',
    'startTime': start,
    'endTime': start + 7200000,
    'active': 0,
    'sampleCount': 2401,
    'startLevel': 50,
    'endLevel': 44,
    'observedMs': 7200000,
    'gapCount': 0,
    'powerMs': 7200000,
    'powerWms': -28800000,
    'currentMs': 7200000,
    'temperatureMs': 7200000,
    'chargeMah': 0.0,
    'dischargeMah': 2000.0,
    'maxPowerW': -3.0,
    'minPowerW': -5.0,
    'maxTemperatureC': 36.0,
    'peakTemperatureTime': start + 3600000,
    'above35Ms': 60000,
  };

  testWidgets(
    'A past recording opens its complete report and stored graph range',
    (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BatteryController.channel, (call) async {
            calls.add(call);
            if (call.method == 'recordings') {
              return {
                'recordings': [record],
                'hasMore': false,
              };
            }
            if (call.method == 'recordingDetail') {
              return {
                'recording': record,
                'charging': [],
                'rangeSampleCount': 2401,
                'points': [
                  {
                    'time': start,
                    'sessionId': 1,
                    'monitorPoint': true,
                    'temperatureC': 30.0,
                    'powerW': -4.0,
                  },
                  {
                    'time': start + 7200000,
                    'sessionId': 1,
                    'monitorPoint': true,
                    'temperatureC': 36.0,
                    'powerW': -4.0,
                  },
                ],
              };
            }
            return null;
          });
      final c = BatteryController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HistoryPage(c: c)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Overnight test'), findsOneWidget);
      expect(find.text('Filter by date'), findsOneWidget);
      await tester.tap(find.text('Overnight test'));
      await tester.pumpAndSettle();
      expect(find.text('Recording report'), findsOneWidget);
      expect(find.text('-4.00 W'), findsOneWidget);
      final query = calls.singleWhere((c) => c.method == 'recordingDetail');
      expect(query.arguments, {'id': 7, 'since': null, 'until': null});
      await tester.scrollUntilVisible(find.text('Saved measurements'), 300);
      await tester.pumpAndSettle();
      expect(find.text('Saved measurements'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  test('Date filters and pagination are sent to native storage', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BatteryController.channel, (call) async {
          calls.add(call);
          return {
            'recordings': [record],
            'hasMore': true,
          };
        });
    final c = BatteryController()
      ..recordingsSince = start
      ..recordingsUntil = start + 86400000;
    await c.refreshRecordings();
    await c.refreshRecordings(more: true);
    expect(calls.first.arguments['since'], start);
    expect(calls.first.arguments['until'], start + 86400000);
    expect(calls.last.arguments['before'], 7);
    c.dispose();
  });
}
