import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/app.dart';
import 'package:fittery/src/controller.dart';
import 'package:fittery/src/onboarding.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var completed = false, showOnLaunch = true, failSave = false;
  final calls = <MethodCall>[];
  setUp(() {
    completed = false;
    showOnLaunch = true;
    failSave = false;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BatteryController.channel, (call) async {
          calls.add(call);
          if (call.method == 'initial') {
            return {
              'onboarding': {
                'onboardingCompleted': completed,
                'showOnboardingOnLaunch': showOnLaunch,
              },
            };
          }
          if (call.method == 'completeOnboarding') {
            if (failSave) {
              throw PlatformException(
                code: 'ONBOARDING',
                message:
                    'Your welcome preference could not be saved. Please try again.',
              );
            }
            completed = true;
            showOnLaunch = call.arguments['showOnLaunch'] as bool;
            return {
              'onboardingCompleted': completed,
              'showOnboardingOnLaunch': showOnLaunch,
            };
          }
          if (call.method == 'history') {
            return {'points': [], 'sessions': [], 'daily': []};
          }
          return null;
        });
  });

  final next = find.byKey(const ValueKey('onboarding-continue'));
  final skip = find.byKey(const ValueKey('onboarding-skip'));
  Future<void> close(WidgetTester tester, BatteryController c) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    c.dispose();
  }

  Future<void> finishWithoutMonitoring(WidgetTester tester) async {
    await tester.tap(next);
    // Saving animates behind the monitoring consent dialog. Respond before
    // waiting for animations to settle, including on a failed-save retry.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    if (find.text('Not now').evaluate().isNotEmpty) {
      await tester.tap(find.text('Not now'));
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Fresh launch shows welcome without flashing home; skip does not complete it',
    (tester) async {
      final c = BatteryController()..ready = true;
      await tester.pumpWidget(FitteryApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Fittery!'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      await tester.tap(skip);
      await tester.pumpAndSettle();
      expect(find.text("You're all set!"), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('onboarding-dont-show')),
            )
            .value,
        true,
      );
      expect(completed, isFalse);
      expect(calls.where((c) => c.method == 'completeOnboarding'), isEmpty);
      await finishWithoutMonitoring(tester);
      expect(completed, isTrue);
      expect(showOnLaunch, isFalse);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        calls.where(
          (c) => c.method == 'monitoring' || c.method == 'notificationSettings',
        ),
        isEmpty,
      );
      await close(tester, c);
      final reopened = BatteryController();
      await reopened.loadInitial();
      await tester.pumpWidget(FitteryApp(controller: reopened));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      await close(tester, reopened);
    },
  );

  testWidgets(
    'Unchecking dont show again repeats onboarding on the next launch',
    (tester) async {
      final c = BatteryController()..ready = true;
      await tester.pumpWidget(FitteryApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(skip);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('onboarding-dont-show')));
      await finishWithoutMonitoring(tester);
      expect(completed, isTrue);
      expect(showOnLaunch, isTrue);
      await close(tester, c);
      final reopened = BatteryController();
      await reopened.loadInitial();
      await tester.pumpWidget(FitteryApp(controller: reopened));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Fittery!'), findsOneWidget);
      await close(tester, reopened);
    },
  );

  testWidgets(
    'Countdown survives rebuild and lifecycle pause; visited slides have no second wait',
    (tester) async {
      final c = BatteryController()..ready = true;
      await tester.pumpWidget(FitteryApp(controller: c));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Continue in 2s'), findsOneWidget);
      c.notifyListeners();
      await tester.pump();
      expect(find.text('Continue in 2s'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 8));
      expect(find.text('Continue in 2s'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Tell me more'), findsOneWidget);
      await tester.tap(next);
      await tester.pumpAndSettle();
      if (find.text('Not now').evaluate().isNotEmpty) {
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Powerful features. Zero clutter.'), findsOneWidget);
      expect(find.text('Continue in 3s'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Tell me more'), findsOneWidget);
      await tester.tap(next);
      await tester.pumpAndSettle();
      if (find.text('Not now').evaluate().isNotEmpty) {
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
      }
      expect(find.text("Okay, that's awesome!"), findsOneWidget);
      await close(tester, c);
    },
  );

  testWidgets(
    'Restoration retains the slide, unfinished countdown and final checkbox',
    (tester) async {
      final c = BatteryController()..ready = true;
      await tester.pumpWidget(FitteryApp(controller: c));
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(next);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Continue in 2s'), findsOneWidget);
      await tester.restartAndRestore();
      expect(find.text('Powerful features. Zero clutter.'), findsOneWidget);
      expect(find.text('Continue in 2s'), findsOneWidget);
      await tester.tap(skip);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('onboarding-dont-show')));
      await tester.pump();
      await tester.restartAndRestore();
      expect(find.text("You're all set!"), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('onboarding-dont-show')),
            )
            .value,
        false,
      );
      await close(tester, c);
    },
  );

  testWidgets(
    'Settings replay has no forced waits and canceling preserves the preference',
    (tester) async {
      final c = BatteryController()
        ..ready = true
        ..onboardingCompleted = true
        ..settingsIntroAcknowledged = true
        ..backgroundAlertsOffered = true
        ..showOnboardingOnLaunch = false;
      await tester.pumpWidget(FitteryApp(controller: c));
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final welcome = find.byKey(const ValueKey('view-welcome-tutorial'));
      await tester.scrollUntilVisible(
        welcome,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(welcome);
      await tester.pumpAndSettle();
      expect(find.text('Tell me more'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('onboarding-back')));
      await tester.pumpAndSettle();
      expect(c.showOnboardingOnLaunch, isFalse);
      expect(calls.where((c) => c.method == 'completeOnboarding'), isEmpty);
      await tester.tap(welcome);
      await tester.pumpAndSettle();
      await tester.tap(skip);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('onboarding-dont-show')));
      await tester.tap(next);
      await tester.pumpAndSettle();
      if (find.text('Not now').evaluate().isNotEmpty) {
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
      }
      expect(c.showOnboardingOnLaunch, isTrue);
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.text('Settings'), findsWidgets);
      await close(tester, c);
    },
  );

  testWidgets('A failed save stays on setup and can be retried', (
    tester,
  ) async {
    final c = BatteryController()..ready = true;
    failSave = true;
    await tester.pumpWidget(FitteryApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(skip);
    await tester.pumpAndSettle();
    await finishWithoutMonitoring(tester);
    expect(
      find.text(
        'Your welcome preference could not be saved. Please try again.',
      ),
      findsOneWidget,
    );
    expect(c.onboardingCompleted, isFalse);
    expect(find.byType(NavigationBar), findsNothing);
    failSave = false;
    await finishWithoutMonitoring(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    await close(tester, c);
  });

  testWidgets(
    'Accessible navigation bypasses the reading timer and honors reduced motion',
    (tester) async {
      final c = BatteryController();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              accessibleNavigation: true,
              disableAnimations: true,
            ),
            child: OnboardingPage(c: c, onFinished: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tell me more'), findsOneWidget);
      expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
      await tester.tap(next);
      await tester.pumpAndSettle();
      if (find.text('Not now').evaluate().isNotEmpty) {
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
      }
      expect(find.text("Okay, that's awesome!"), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester, c);
    },
  );

  testWidgets(
    'Startup waits for saved preferences before choosing home or onboarding',
    (tester) async {
      final c = BatteryController();
      final initial = Completer<Map<String, dynamic>>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            BatteryController.channel,
            (call) async => call.method == 'initial' ? initial.future : null,
          );
      await tester.pumpWidget(FitteryApp(controller: c));
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      final load = c.loadInitial();
      initial.complete({
        'onboarding': {
          'onboardingCompleted': true,
          'showOnboardingOnLaunch': false,
        },
      });
      await load;
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      await close(tester, c);
    },
  );

  for (final spec in [
    (const Size(320, 568), 2.0, Brightness.dark),
    (const Size(640, 320), 1.5, Brightness.dark),
    (const Size(400, 850), 1.0, Brightness.light),
  ]) {
    testWidgets(
      'All four pages fit and remain navigable at ${spec.$1}, text scale ${spec.$2}',
      (tester) async {
        tester.view.physicalSize = spec.$1;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = spec.$2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final c = BatteryController();
        await tester.pumpWidget(
          MaterialApp(
            restorationScopeId: 'layout-test',
            theme: ThemeData(brightness: spec.$3, useMaterial3: true),
            home: OnboardingPage(c: c, replay: true, onFinished: () {}),
          ),
        );
        await tester.pumpAndSettle();
        for (var page = 0; page < 4; page++) {
          expect(find.byKey(ValueKey('onboarding-art-$page')), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
          if (page < 3) {
            await tester.tap(next);
            await tester.pumpAndSettle();
          }
        }
        await close(tester, c);
      },
    );
  }
}
