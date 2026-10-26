import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/app.dart';
import 'package:fittery/src/controller.dart';
import 'package:fittery/src/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  final now = DateTime.now().millisecondsSinceEpoch;
  final points = [
    {
      'time': now - 60000,
      'sessionId': 1,
      'temperatureC': 30.0,
      'voltageMv': 4100,
      'currentMa': 1000,
      'powerW': 4.1,
    },
    {
      'time': now - 30000,
      'sessionId': 1,
      'temperatureC': 31.0,
      'voltageMv': 4120,
      'currentMa': 900,
      'powerW': 3.708,
    },
  ];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('fittery/preview'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BatteryController.channel, (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'previewAlarm' => true,
            'stopPreview' => false,
            'history' => {'points': points, 'sessions': [], 'daily': []},
            _ => null,
          };
        });
  });

  BatteryController controller() => BatteryController()
    ..ready = true
    ..historyLoaded = true
    ..points = points
    ..reading = Reading({
      'level': 84,
      'status': 'Charging',
      'plugged': 1,
      'voltageMv': 4120,
      'currentMa': 900,
      'temperatureC': 31.0,
    });

  testWidgets(
    'The preview icon plays, stops, and resets when native playback ends',
    (tester) async {
      final c = controller();
      await tester.pumpWidget(FitteryApp(controller: c));
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('alarm-preview-button'));
      await tester.scrollUntilVisible(
        button,
        450,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(c.previewPlaying, isTrue);
      expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(c.previewPlaying, isFalse);
      expect(calls.where((c) => c == 'previewAlarm' || c == 'stopPreview'), [
        'previewAlarm',
        'stopPreview',
      ]);

      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'fittery/preview',
        const StandardMethodCodec().encodeSuccessEnvelope(false),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(c.previewPlaying, isFalse);
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'A metric opens Telemetry and each graph can be toggled independently',
    (tester) async {
      final c = controller();
      await tester.pumpWidget(FitteryApp(controller: c));
      final voltage = find.byKey(const ValueKey('metric-voltageMv'));
      await tester.ensureVisible(voltage);
      await tester.pumpAndSettle();
      await tester.tap(voltage);
      await tester.pumpAndSettle();
      expect(find.text('Telemetry'), findsOneWidget);
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('graph-toggle-voltageMv')),
            )
            .selected,
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('graph-panel-voltageMv')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('graph-toggle-temperatureC')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('graph-panel-temperatureC')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('graph-toggle-voltageMv')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('graph-panel-voltageMv')), findsNothing);
      expect(
        find.byKey(const ValueKey('graph-panel-temperatureC')),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDestination), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
