import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/app.dart';
import 'package:fittery/src/controller.dart';
import 'package:fittery/src/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BatteryController.channel, (call) async {
          calls.add(call);
          if (call.method == 'initial') {
            return {'plugged': 1, 'monitoring': true};
          }
          if (call.method == 'history') {
            return {'points': [], 'sessions': [], 'daily': []};
          }
          if (call.method == 'recordings') return {'recordings': []};
          if (call.method == 'recordingDetail') {
            return {
              'recording': {
                'id': 7,
                'startTime': 1000,
                'endTime': 9000,
                'active': 1,
                'sampleCount': 3,
                'observedMs': 8000,
                'gapCount': 0,
              },
              'points': [],
              'charging': [],
              'rangeSampleCount': 0,
            };
          }
          return null;
        });
  });

  testWidgets(
    'Plug prompt enables monitoring explicitly and is consumed once',
    (tester) async {
      final c = BatteryController()
        ..ready = true
        ..reading = Reading({'plugged': 1})
        ..sessionPrompt = {'kind': 'enableMonitor', 'token': 1};
      await tester.pumpWidget(
        FitteryApp(
          controller: c
            ..ready = true
            ..onboardingCompleted = true
            ..showOnboardingOnLaunch = false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Record this charging session?'), findsOneWidget);
      expect(calls.where((c) => c.method == 'monitoring'), isEmpty);
      await tester.tap(find.text('Enable monitor mode'));
      await tester.pumpAndSettle();
      expect(
        calls.singleWhere((c) => c.method == 'monitoring').arguments,
        true,
      );
      expect(c.monitoring, isTrue);
      c.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'Unplugging before accepting a reminder does not enable monitoring',
    (tester) async {
      final c = BatteryController()
        ..ready = true
        ..reading = Reading({'plugged': 1})
        ..sessionPrompt = {'kind': 'enableMonitor', 'token': 1};
      await tester.pumpWidget(
        FitteryApp(
          controller: c
            ..ready = true
            ..onboardingCompleted = true
            ..showOnboardingOnLaunch = false,
        ),
      );
      await tester.pumpAndSettle();
      c.reading = Reading({'plugged': 0});
      c.notifyListeners();
      await tester.tap(find.text('Enable monitor mode'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'monitoring'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  for (final kind in ['chargingReport', 'openReport']) {
    testWidgets(
      '$kind opens saved graphs at the charging range without stopping monitoring',
      (tester) async {
        final c = BatteryController()
          ..ready = true
          ..monitoring = true
          ..reading = Reading({'plugged': 0})
          ..sessionPrompt = {
            'kind': kind,
            'token': 2,
            'recordingId': 7,
            'startTime': 3000,
            'endTime': 6000,
          };
        await tester.pumpWidget(
          FitteryApp(
            controller: c
              ..ready = true
              ..onboardingCompleted = true
              ..showOnboardingOnLaunch = false,
          ),
        );
        await tester.pumpAndSettle();
        if (kind == 'chargingReport') {
          expect(find.text('Your charging report is ready'), findsOneWidget);
          await tester.tap(find.text('View report'));
          await tester.pumpAndSettle();
        }
        expect(find.text('Charging session report'), findsOneWidget);
        expect(
          calls.firstWhere((c) => c.method == 'recordingDetail').arguments,
          {'id': 7, 'since': 3000, 'until': 6000},
        );
        expect(c.monitoring, isTrue);
        expect(calls.where((c) => c.method == 'monitoring'), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
