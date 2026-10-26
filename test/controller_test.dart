import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BatteryController.channel, null);
    for (final name in ['fittery/readings', 'fittery/preview']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  test(
    'An older refresh reply cannot replace a newer live charge snapshot',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BatteryController.channel, (call) async {
            if (call.method == 'initial') {
              return {
                'sequence': 20,
                'level': 92,
                'status': 'Charging',
                'plugged': 2,
              };
            }
            if (call.method == 'refresh') {
              return {
                'sequence': 19,
                'level': 56,
                'status': 'Discharging',
                'plugged': 0,
              };
            }
            return null;
          });
      final controller = BatteryController();
      await controller.loadInitial();
      await controller.refreshReading();
      expect(controller.reading!.level, 92);
      expect(controller.reading!.text('status'), 'Charging');
      controller.dispose();
    },
  );

  test('A live event wins while an older refresh reply is in flight', () async {
    final reply = Completer<Map<String, dynamic>>();
    final requested = Completer<void>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in ['fittery/readings', 'fittery/preview']) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(BatteryController.channel, (call) async {
      switch (call.method) {
        case 'initial':
          return {'sequence': 10, 'level': 56, 'status': 'Discharging'};
        case 'history':
          return {'points': [], 'sessions': [], 'daily': []};
        case 'refresh':
          requested.complete();
          return reply.future;
        default:
          return null;
      }
    });
    final controller = BatteryController();
    addTearDown(controller.dispose);
    await controller.initialize();
    final pending = controller.refreshReading();
    await requested.future;
    Future<void> emit(Map<String, dynamic> data) async {
      await messenger.handlePlatformMessage(
        'fittery/readings',
        const StandardMethodCodec().encodeSuccessEnvelope(data),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
    }

    await emit({
      'sequence': 12,
      'level': 92,
      'status': 'Charging',
      'plugged': 2,
      'monitoring': true,
      'settings': {'fahrenheit': true},
    });
    expect(controller.reading!.level, 92);
    reply.complete({
      'sequence': 11,
      'level': 56,
      'status': 'Discharging',
      'plugged': 0,
      'monitoring': false,
      'settings': {'fahrenheit': false},
    });
    await pending;
    expect(controller.reading!.level, 92);
    expect(controller.reading!.text('status'), 'Charging');
    expect(controller.monitoring, isTrue);
    expect(controller.flag('fahrenheit'), isTrue);

    // The ordering guard must still allow the next genuine unplug update.
    await emit({
      'sequence': 13,
      'level': 91,
      'status': 'Discharging',
      'plugged': 0,
    });
    expect(controller.reading!.level, 91);
    expect(controller.reading!.text('status'), 'Discharging');
  });

  test(
    'History read failures preserve saved data and remain visible',
    () async {
      var reads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BatteryController.channel, (call) async {
            if (call.method == 'history') {
              if (++reads > 1) {
                throw PlatformException(
                  code: 'HISTORY',
                  message: 'Storage error',
                );
              }
              return {
                'points': [
                  {'time': 123, 'level': 80},
                ],
                'sessions': [],
                'daily': [],
              };
            }
            if (call.method == 'initial') return {'level': 80, 'settings': {}};
            return null;
          });
      final controller = BatteryController();
      await controller.refreshHistory();
      await expectLater(
        controller.refreshHistory(),
        throwsA(isA<PlatformException>()),
      );
      expect(controller.historyLoaded, isTrue);
      expect(controller.points.single['level'], 80);
      expect(controller.historyError, contains('last saved'));
      await controller.loadInitial();
      expect(controller.historyError, contains('last saved'));
      controller.dispose();
    },
  );

  test(
    'Silent previews keep the play state idle and permit another attempt',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('fittery/preview'),
            (_) async => null,
          );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            BatteryController.channel,
            (_) async => false,
          );
      final controller = BatteryController();
      await expectLater(
        controller.togglePreview(),
        throwsA(isA<PlatformException>()),
      );
      expect(controller.previewPlaying, isFalse);
      expect(controller.previewBusy, isFalse);
      controller.dispose();
    },
  );

  test('Overlapping settings changes persist both values', () async {
    final gate = Completer<void>();
    final writes = <Map<String, dynamic>>[];
    final stored = <String, dynamic>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BatteryController.channel, (call) async {
          if (call.method == 'updateSetting') {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            stored[args['key'] as String] = args['value'];
            writes.add({...stored});
            if (writes.length == 1) await gate.future;
          }
          return null;
        });
    final controller = BatteryController();
    final first = controller.save('fahrenheit', true);
    final second = controller.save('dualCell', true);
    await Future<void>.delayed(Duration.zero);
    expect(writes.length, 1);
    gate.complete();
    await Future.wait([first, second]);
    expect(writes.last['fahrenheit'], isTrue);
    expect(writes.last['dualCell'], isTrue);
    expect(controller.flag('fahrenheit'), isTrue);
    expect(controller.flag('dualCell'), isTrue);
    controller.dispose();
  });

  test('A failed settings save does not block the next change', () async {
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BatteryController.channel, (call) async {
          if (call.method == 'updateSetting' && ++attempts == 1) {
            throw PlatformException(
              code: 'WRITE',
              message: 'Storage unavailable',
            );
          }
          return null;
        });
    final controller = BatteryController();
    final failed = controller.save('fahrenheit', true);
    final next = controller.save('dualCell', true);
    await expectLater(failed, throwsA(isA<PlatformException>()));
    await next;
    expect(controller.flag('fahrenheit'), isFalse);
    expect(controller.flag('dualCell'), isTrue);
    controller.dispose();
  });
}
