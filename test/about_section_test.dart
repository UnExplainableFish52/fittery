import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/about_section.dart';
import 'package:fittery/src/controller.dart';

void main() {
  testWidgets(
    'Developer credits, runtime version and local privacy policy are available',
    (tester) async {
      final controller = BatteryController()
        ..appInfo = {
          'version': '9.8.7',
          'build': 12345,
          'package': 'com.fittery.tid52',
        };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AboutSection(c: controller)),
          ),
        ),
      );
      expect(find.text('Frequently asked questions'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('app-version')));
      await tester.pumpAndSettle();
      expect(find.text('TheIdealDev52'), findsOneWidget);
      expect(find.text('Saksham Sharma'), findsOneWidget);
      expect(find.text('9.8.7 · build 12345'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('privacy-policy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('privacy-policy')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('does not upload'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
