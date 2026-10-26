import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/threshold_control.dart';

void main() {
  for (final spec in [
    (
      id: 'chargeLimit',
      min: 50,
      max: 100,
      initial: 80,
      presets: [75, 80, 85],
      unit: '%',
    ),
    (
      id: 'lowLimit',
      min: 5,
      max: 50,
      initial: 20,
      presets: [10, 15, 20],
      unit: '%',
    ),
    (
      id: 'heatLimit',
      min: 35,
      max: 50,
      initial: 40,
      presets: [38, 40, 45],
      unit: '°C',
    ),
  ]) {
    testWidgets(
      '${spec.id}: input, presets and slider stay synchronized within bounds',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var value = spec.initial;
        final writes = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(44),
                child: StatefulBuilder(
                  builder: (context, setState) => ThresholdControl(
                    id: spec.id,
                    label: 'Alert threshold',
                    description: 'Choose the alert target',
                    value: value,
                    min: spec.min,
                    max: spec.max,
                    unit: spec.unit,
                    presets: spec.presets,
                    enabled: false,
                    onEnabledChanged: (_) {},
                    onChanged: (v) {
                      writes.add(v);
                      setState(() => value = v);
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        final field = find.byKey(ValueKey('${spec.id}-input'));
        final slider = find.byKey(ValueKey('${spec.id}-slider'));
        String fieldValue() => tester.widget<TextField>(field).controller!.text;

        await tester.tap(
          find.byKey(ValueKey('${spec.id}-preset-${spec.presets.last}')),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<Slider>(slider).value,
          spec.presets.last.toDouble(),
        );
        expect(fieldValue(), '${spec.presets.last}');
        expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

        await tester.enterText(field, '${spec.min + 1}');
        await tester.pumpAndSettle();
        expect(value, spec.min + 1);
        expect(tester.widget<Slider>(slider).value, (spec.min + 1).toDouble());
        final validWrites = writes.length;
        await tester.enterText(field, '${spec.max + 1}');
        await tester.pumpAndSettle();
        expect(writes.length, validWrites);
        expect(find.text('${spec.min}–${spec.max} only'), findsOneWidget);
        expect(tester.widget<Slider>(slider).value, (spec.min + 1).toDouble());

        await tester.enterText(field, '');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(fieldValue(), '${spec.min + 1}');
        expect(writes.length, validWrites);

        await tester.enterText(field, '${spec.min - 1}');
        await tester.pumpAndSettle();
        expect(writes.length, validWrites);
        await tester.tap(
          find.byKey(ValueKey('${spec.id}-preset-${spec.presets.first}')),
        );
        await tester.pumpAndSettle();
        expect(fieldValue(), '${spec.presets.first}');
        expect(
          tester.widget<Slider>(slider).value,
          spec.presets.first.toDouble(),
        );

        final beforeDrag = writes.length;
        await tester.drag(slider, const Offset(35, 0));
        await tester.pumpAndSettle();
        final displayed = tester.widget<Slider>(slider).value.round();
        expect(fieldValue(), '$displayed');
        expect(value, displayed);
        expect(
          writes.length,
          beforeDrag + 1,
          reason: 'Persist once after dragging, rather than on every pixel',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
