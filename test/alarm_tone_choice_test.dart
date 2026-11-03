import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/app.dart';
import 'package:fittery/src/controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final event in ['heat', 'low']) {
    testWidgets('$event file selection changes only that alert', (
      tester,
    ) async {
      final c = BatteryController()
        ..settings['chargeToneName'] = 'Charging limit voice';
      final settings = Map<String, dynamic>.from(c.settings);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BatteryController.channel, (call) async {
            if (call.method == 'pickAudioFile') {
              expect(call.arguments, {'event': event});
              settings['${event}ToneName'] = '$event custom.mp3';
              settings['${event}ToneSource'] = 'file';
            }
            if (call.method == 'initial') return {'settings': settings};
            return null;
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => SettingsPage(c: c),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(ValueKey('alarm-tone-$event')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('alarm-tone-file')));
      await tester.pumpAndSettle();
      expect(c.settings['${event}ToneName'], '$event custom.mp3');
      expect(c.settings['chargeToneName'], 'Charging limit voice');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }

  testWidgets(
    'Sound choices remain reachable on a small screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = BatteryController()
        ..settings['chargeToneName'] =
            'My carefully recorded charging announcement.mp3';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SettingsPage(c: c)),
        ),
      );
      final choice = find.byKey(const ValueKey('alarm-tone-charge'));
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('alarm-tone-silent')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('alarm-tone-silent')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  for (final selection in [
    ('alarm-tone-file', 'pickAudioFile', 'My favorite song.mp3'),
    ('alarm-tone-system', 'pickTone', 'System chime'),
    ('alarm-tone-default', 'defaultTone', 'Charging limit voice'),
    ('alarm-tone-silent', 'silentTone', 'Silent'),
  ]) {
    testWidgets('${selection.$2} refreshes the selected tone name', (
      tester,
    ) async {
      final c = BatteryController();
      final calls = <String>[];
      var name = 'Default alarm';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BatteryController.channel, (call) async {
            calls.add(call.method);
            if (call.method == selection.$2) {
              expect(call.arguments, {'event': 'charge'});
              name = selection.$3;
            }
            if (call.method == 'initial') {
              return {
                'settings': {'chargeToneName': name},
              };
            }
            return null;
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => SettingsPage(c: c),
            ),
          ),
        ),
      );
      final choice = find.byKey(const ValueKey('alarm-tone-charge'));
      await tester.scrollUntilVisible(
        choice,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(find.text('Charging limit sound'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey(selection.$1)));
      await tester.pumpAndSettle();
      expect(calls, [selection.$2, 'initial']);
      expect(find.text(selection.$3), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }

  testWidgets(
    'A file error keeps the existing tone and gives actionable feedback',
    (tester) async {
      final c = BatteryController()
        ..settings['chargeToneName'] = 'Existing tone';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BatteryController.channel, (call) async {
            if (call.method == 'pickAudioFile') {
              throw PlatformException(
                code: 'AUDIO_FILE',
                message:
                    'This audio file cannot be played. Choose another audio file.',
              );
            }
            return null;
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SettingsPage(c: c)),
        ),
      );
      final choice = find.byKey(const ValueKey('alarm-tone-charge'));
      await tester.scrollUntilVisible(
        choice,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('alarm-tone-file')));
      await tester.pumpAndSettle();
      expect(c.settings['chargeToneName'], 'Existing tone');
      expect(
        find.text(
          'This audio file cannot be played. Choose another audio file.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
