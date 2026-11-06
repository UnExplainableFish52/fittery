import 'package:fittery/src/app.dart';
import 'package:fittery/src/charging_dashboard.dart';
import 'package:fittery/src/controller.dart';
import 'package:fittery/src/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  BatteryController controller() => BatteryController()
    ..ready = true
    ..settings['chargingDashboard'] = true
    ..reading = Reading({
      'level': 72,
      'plugged': 1,
      'status': 'Charging',
      'source': 'USB',
      'currentMa': -525,
      'voltageMv': 4200,
      'temperatureC': 30,
    });

  Widget harness(BatteryController c, {bool reducedMotion = false}) =>
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
        home: Scaffold(body: ChargingDashboardEntry(c: c)),
      );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('open-charging-dashboard')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  Future<void> clean(WidgetTester tester, BatteryController c) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    c.dispose();
  }

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BatteryController.channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  testWidgets(
    'Opt-in and power connection gate entry without starting monitoring',
    (tester) async {
      final c = controller()..settings['chargingDashboard'] = false;
      await tester.pumpWidget(harness(c));
      await open(tester);
      expect(find.byType(ChargingDashboardPage), findsNothing);
      c.settings['chargingDashboard'] = true;
      c.reading = Reading({'plugged': 0});
      c.notifyListeners();
      await tester.pump();
      await open(tester);
      expect(find.byType(ChargingDashboardPage), findsNothing);
      c.reading = Reading({'plugged': 1, 'status': 'Full', 'level': 100});
      c.notifyListeners();
      await tester.pump();
      await open(tester);
      expect(find.text('100%'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'Battery 100 percent' &&
              w.properties.value == 'Full',
        ),
        findsOneWidget,
      );
      expect(c.chargingDashboardVisible, isTrue);
      expect(c.monitoring, isFalse);
      expect(calls.where((call) => call.method == 'monitoring'), isEmpty);
      expect(
        calls
            .where((call) => call.method == 'chargingDashboardVisible')
            .first
            .arguments,
        true,
      );
      await tester.tap(find.byTooltip('Close charging dashboard'));
      await tester.pumpAndSettle();
      expect(c.chargingDashboardVisible, isFalse);
      expect(
        calls
            .where((call) => call.method == 'chargingDashboardVisible')
            .last
            .arguments,
        false,
      );
      await clean(tester, c);
    },
  );

  testWidgets(
    'Signed readings, units, adjustment and unavailable measurements stay honest',
    (tester) async {
      final c = controller();
      await tester.pumpWidget(harness(c));
      await open(tester);
      expect(find.text('-525 mA'), findsOneWidget);
      expect(find.text('-2.21 W'), findsOneWidget);
      expect(find.text('Voltage'), findsNothing);
      expect(find.text('Est. to 80%'), findsOneWidget);
      expect(find.text('30.0 °C'), findsOneWidget);
      c.settings.addAll({
        'dualCell': true,
        'millivolts': true,
        'fahrenheit': true,
      });
      c.notifyListeners();
      await tester.pump();
      expect(find.text('8400 mV'), findsNothing);
      expect(find.text('-4.41 W'), findsOneWidget);
      expect(find.text('86.0 °F'), findsOneWidget);
      c.reading = Reading({
        'plugged': 1,
        'status': 'Not charging',
        'level': 101,
        'currentMa': double.nan,
        'temperatureC': double.infinity,
      });
      c.notifyListeners();
      await tester.pump();
      expect(find.text('—'), findsNWidgets(5));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'Battery percentage unavailable' &&
              w.properties.value == 'Not charging',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await clean(tester, c);
    },
  );

  testWidgets('Closing during entry never enables lock-screen visibility', (
    tester,
  ) async {
    final c = controller();
    await tester.pumpWidget(harness(c));
    await tester.tap(find.byKey(const ValueKey('open-charging-dashboard')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      calls.where(
        (call) =>
            call.method == 'chargingDashboardVisible' && call.arguments == true,
      ),
      isEmpty,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ChargingDashboardPage), findsNothing);
    expect(
      calls.where(
        (call) =>
            call.method == 'chargingDashboardVisible' && call.arguments == true,
      ),
      isEmpty,
    );
    await clean(tester, c);
  });

  testWidgets(
    'Live five-second estimate, clock, connection caption, and installed version',
    (tester) async {
      final c = controller();
      void reading(int time) {
        c.reading = Reading({
          'level': 60,
          'plugged': 1,
          'status': 'Charging',
          'source': 'AC charger',
          'elapsedRealtimeMs': time,
          'currentMa': 1000,
          'currentConvention': '1000/false',
          'designCapacityMah': 5000,
          'voltageMv': 4200,
          'temperatureC': 30,
          'chargeConnectedAt': DateTime(
            2026,
            10,
            31,
            10,
            30,
          ).millisecondsSinceEpoch,
          'chargeConnectedDurationMs': time,
          'chargeConnectionConfirmed': true,
          'appVersion': '1.0.0',
          'appBuild': 24,
        });
        c.notifyListeners();
      }

      reading(0);
      await tester.pumpWidget(harness(c));
      await open(tester);
      reading(3000);
      await tester.pump();
      expect(find.text('~60 m'), findsNothing);
      reading(6000);
      await tester.pump();
      expect(find.text('~60 m'), findsOneWidget);
      expect(find.text('Est. to 80%'), findsOneWidget);
      expect(find.text('Connected 10:30 AM · 0 m'), findsOneWidget);
      expect(find.text('v1.0.0 · build 24'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('charging-dashboard-clock')),
        findsOneWidget,
      );
      c.reading = Reading({
        ...c.reading!.data,
        'chargeConnectionConfirmed': false,
      });
      c.notifyListeners();
      await tester.pump();
      expect(find.text('Tracking since 10:30 AM · 0 m'), findsOneWidget);
      c.reading = Reading({
        ...c.reading!.data,
        'chargeConnectedAt': DateTime(
          2026,
          10,
          31,
          13,
          5,
        ).millisecondsSinceEpoch,
      });
      c.notifyListeners();
      await tester.pump();
      expect(find.text('Tracking since 1:05 PM · 0 m'), findsOneWidget);
      await clean(tester, c);
    },
  );

  testWidgets(
    'Battery shortcut opens the dashboard and obeys opt-in and connection state',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = controller()
        ..onboardingCompleted = true
        ..showOnboardingOnLaunch = false;
      await tester.pumpWidget(FitteryApp(controller: c));
      await tester.pumpAndSettle();
      final shortcut = find.byKey(
        const ValueKey('battery-charging-dashboard-shortcut'),
      );
      expect(shortcut, findsOneWidget);
      await tester.tap(shortcut);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.byType(ChargingDashboardPage), findsOneWidget);
      expect(c.monitoring, isFalse);
      await tester.tap(find.byTooltip('Close charging dashboard'));
      await tester.pumpAndSettle();
      c.reading = Reading({'plugged': 0});
      c.notifyListeners();
      await tester.pump();
      expect(tester.widget<InkWell>(shortcut).onTap, isNull);
      c.settings['chargingDashboard'] = false;
      c.notifyListeners();
      await tester.pump();
      expect(shortcut, findsNothing);
      expect(tester.takeException(), isNull);
      await clean(tester, c);
    },
  );

  testWidgets(
    'Live percentage controls both neon fill and its moving highlight',
    (tester) async {
      final c = controller();
      await tester.pumpWidget(harness(c));
      await open(tester);
      for (final level in [0, 25, 50, 75, 100]) {
        c.reading = Reading({
          'level': level,
          'plugged': 1,
          'status': level == 100 ? 'Full' : 'Charging',
          'source': 'AC charger',
        });
        c.notifyListeners();
        await tester.pump();
        final track =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('charging-dashboard-track')),
                    )
                    .painter
                as dynamic;
        final highlight =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('charging-dashboard-ring')),
                    )
                    .painter
                as dynamic;
        expect(track.progress, level / 100);
        expect(highlight.progress, level / 100);
        expect(highlight.charging, level != 100);
        expect(
          (highlight.animation as AnimationController).isAnimating,
          level > 0 && level < 100,
        );
        expect(find.text('$level%'), findsOneWidget);
      }
      c.reading = Reading({'plugged': 1, 'status': 'Not charging'});
      c.notifyListeners();
      await tester.pump();
      final track =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('charging-dashboard-track')),
                  )
                  .painter
              as dynamic;
      final highlight =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('charging-dashboard-ring')),
                  )
                  .painter
              as dynamic;
      expect(track.progress, 0);
      expect(highlight.progress, 0);
      expect(highlight.charging, isFalse);
      expect(
        find.bySemanticsLabel('Battery percentage unavailable'),
        findsOneWidget,
      );
      await clean(tester, c);
    },
  );

  testWidgets('A short slide returns without dismissing', (tester) async {
    final c = controller();
    await tester.pumpWidget(harness(c));
    await open(tester);
    final slider = find.byKey(const ValueKey('charging-dashboard-slide'));
    await tester.ensureVisible(slider);
    await tester.pump();
    await tester.drag(slider, const Offset(50, 0));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(ChargingDashboardPage), findsOneWidget);
    expect(c.chargingDashboardVisible, isTrue);
    await clean(tester, c);
  });

  testWidgets(
    'A lock-screen API failure preserves manual viewing and dismissal',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BatteryController.channel, (call) async {
            calls.add(call);
            if (call.method == 'chargingDashboardVisible' &&
                call.arguments == true) {
              throw PlatformException(code: 'ANDROID', message: 'Unavailable');
            }
            return null;
          });
      final c = controller();
      await tester.pumpWidget(harness(c));
      await open(tester);
      expect(find.text('72%'), findsOneWidget);
      expect(
        find.textContaining('Lock-screen display is unavailable'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close charging dashboard'));
      await tester.pumpAndSettle();
      expect(find.byType(ChargingDashboardPage), findsNothing);
      await clean(tester, c);
    },
  );

  for (final reason in ['unplug', 'disable', 'back', 'slide']) {
    testWidgets('$reason dismisses and clears native visibility', (
      tester,
    ) async {
      final c = controller();
      await tester.pumpWidget(harness(c));
      await open(tester);
      if (reason == 'unplug') {
        c.reading = Reading({'plugged': 0});
        c.notifyListeners();
      } else if (reason == 'disable') {
        await c.save('chargingDashboard', false);
      } else if (reason == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        final slider = find.byKey(const ValueKey('charging-dashboard-slide'));
        await tester.ensureVisible(slider);
        await tester.pump();
        await tester.drag(slider, const Offset(650, 0));
      }
      await tester.pumpAndSettle();
      expect(find.byType(ChargingDashboardPage), findsNothing);
      expect(c.chargingDashboardVisible, isFalse);
      expect(
        calls
            .where((call) => call.method == 'chargingDashboardVisible')
            .last
            .arguments,
        false,
      );
      await clean(tester, c);
    });
  }

  testWidgets('Animation pauses in background and honors reduced motion', (
    tester,
  ) async {
    final c = controller();
    await tester.pumpWidget(harness(c));
    await open(tester);
    final ring = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('charging-dashboard-ring')),
    );
    final animation =
        (ring.painter as dynamic).animation as AnimationController;
    expect(animation.isAnimating, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(animation.isAnimating, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(animation.isAnimating, isTrue);
    await tester.pumpWidget(harness(c, reducedMotion: true));
    await tester.pump();
    expect(animation.isAnimating, isFalse);
    await clean(tester, c);
  });

  for (final (size, scale) in [
    (const Size(320, 640), 1.0),
    (const Size(320, 640), 2.0),
    (const Size(850, 390), 1.0),
    (const Size(768, 1024), 1.5),
  ]) {
    testWidgets('Dashboard fits $size at text scale $scale', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = controller();
      await tester.pumpWidget(harness(c, reducedMotion: true));
      await open(tester);
      expect(find.text('72%'), findsOneWidget);
      if (scale == 1) {
        expect(
          find.byKey(const ValueKey('charging-dashboard-overflow')),
          findsNothing,
        );
      }
      await tester.ensureVisible(
        find.byKey(const ValueKey('charging-dashboard-slide')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await clean(tester, c);
    });
  }

  testWidgets('Settings toggle persists through the existing settings bridge', (
    tester,
  ) async {
    final c = controller()..settings['chargingDashboard'] = false;
    expect(defaults['chargingDashboard'], isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (context, _) => SettingsPage(c: c),
          ),
        ),
      ),
    );
    final toggle = find.byKey(const ValueKey('setting-chargingDashboard'));
    await tester.scrollUntilVisible(toggle, 250);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(c.flag('chargingDashboard'), isTrue);
    expect(
      calls.singleWhere((call) => call.method == 'updateSetting').arguments,
      {'key': 'chargingDashboard', 'value': true},
    );
    await clean(tester, c);
  });

  testWidgets(
    'Phone layout shows all four values and dismissal without scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(393, 873);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final c = controller();
      await tester.pumpWidget(harness(c, reducedMotion: true));
      await open(tester);
      expect(
        find.byKey(const ValueKey('charging-dashboard-overflow')),
        findsNothing,
      );
      final slider = tester.getRect(
        find.byKey(const ValueKey('charging-dashboard-slide')),
      );
      expect(slider.bottom, lessThanOrEqualTo(873));
      for (final value in ['-525 mA', '-2.21 W', '—', '30.0 °C']) {
        final valueRect = tester.getRect(find.text(value).first);
        expect(valueRect.top, greaterThan(32));
        expect(valueRect.bottom, lessThan(slider.top));
      }
      expect(find.text('Charging · USB'), findsNothing);
      final clock = tester.getRect(
        find.byKey(const ValueKey('charging-dashboard-clock')),
      );
      final ring = tester.getRect(
        find.byKey(const ValueKey('charging-dashboard-track')),
      );
      expect(clock.top, greaterThan(ring.bottom));
      expect(ring.width, lessThanOrEqualTo(300));
      final brand = tester.getCenter(
        find.byKey(const ValueKey('charging-dashboard-brand')),
      );
      expect(brand.dx, closeTo(393 / 2, .5));
      expect(
        find.byKey(const ValueKey('cosmic-dashboard-artwork')),
        findsOneWidget,
      );
      final artwork = tester.getRect(
        find.byKey(const ValueKey('cosmic-dashboard-artwork')),
      );
      expect(artwork, const Rect.fromLTWH(0, 0, 393, 873));
      expect(ring.width, closeTo(ring.height, .01));
      final clockText = tester
          .widget<Text>(find.byKey(const ValueKey('charging-dashboard-clock')))
          .data!;
      expect(clockText, matches(RegExp(r'^\d{1,2}:\d{2} (AM|PM)$')));
      expect(find.textContaining('Positive current flows'), findsNothing);
      expect(find.text('Net battery current'), findsNothing);
      expect(find.text('Battery voltage'), findsNothing);
      expect(find.text('Battery temperature'), findsNothing);
      expect(find.text('Your device lock stays in place'), findsNothing);
      expect(find.byIcon(Icons.battery_charging_full_rounded), findsNothing);
      expect(tester.takeException(), isNull);
      await clean(tester, c);
    },
  );

  testWidgets(
    'Cosmic portrait uses live charge and an intentional upward swipe',
    (tester) async {
      tester.view.physicalSize = const Size(393, 873);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = controller();
      await tester.pumpWidget(harness(c, reducedMotion: true));
      await open(tester);
      for (final level in [0, 25, 72, 100]) {
        c.reading = Reading({
          ...c.reading!.data,
          'level': level,
          'status': level == 100 ? 'Full' : 'Charging',
        });
        c.notifyListeners();
        await tester.pump();
        final track =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('charging-dashboard-track')),
                    )
                    .painter
                as dynamic;
        final glint =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('charging-dashboard-ring')),
                    )
                    .painter
                as dynamic;
        expect(track.progress, level / 100);
        expect(glint.progress, level / 100);
        expect(glint.charging, level != 100);
        expect(find.text('$level%'), findsOneWidget);
      }
      final dismiss = find.byKey(const ValueKey('charging-dashboard-slide'));
      await tester.drag(dismiss, const Offset(0, -20));
      await tester.pump();
      expect(c.chargingDashboardVisible, isTrue);
      await tester.drag(dismiss, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(c.chargingDashboardVisible, isFalse);
      expect(calls.where((call) => call.method == 'monitoring'), isEmpty);
      expect(tester.takeException(), isNull);
      await clean(tester, c);
    },
  );
}
