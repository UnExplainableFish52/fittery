import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/controller.dart';
import 'package:fittery/src/notification_elements.dart';

void main() {
  testWidgets(
    'elements preserve legacy choice and enforce one to three or All metrics',
    (tester) async {
      final c = BatteryController()
        ..settings['notificationFormat'] = 'Temperature';
      final saves = <dynamic>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BatteryController.channel, (call) async {
            if (call.method == 'updateSetting') {
              saves.add(call.arguments['value']);
            }
            return null;
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => NotificationElementsTile(controller: c),
            ),
          ),
        ),
      );
      Future<void> open() async {
        await tester.tap(find.byKey(const ValueKey('notification-elements')));
        await tester.pumpAndSettle();
      }

      Finder option(String name) => find.widgetWithText(CheckboxListTile, name);
      await open();
      expect(
        tester.widget<CheckboxListTile>(option('Temperature')).value,
        isTrue,
      );
      expect(
        tester.widget<CheckboxListTile>(option('Temperature')).onChanged,
        isNull,
      );
      await tester.tap(option('Current'));
      await tester.pump();
      await tester.tap(option('Power'));
      await tester.pump();
      expect(
        tester.widget<CheckboxListTile>(option('Time remaining')).onChanged,
        isNull,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saves.last, ['Current', 'Power', 'Temperature']);
      await open();
      await tester.tap(option('All metrics'));
      await tester.pump();
      expect(
        tester.widget<CheckboxListTile>(option('Temperature')).value,
        isFalse,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saves.last, ['All metrics']);
      await open();
      await tester.tap(option('Time remaining'));
      await tester.pump();
      expect(
        tester.widget<CheckboxListTile>(option('All metrics')).value,
        isFalse,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saves.length, 2);
      expect(c.settings['notificationElements'], ['All metrics']);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
