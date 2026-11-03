import 'package:flutter_test/flutter_test.dart';
import 'package:fittery/src/current_telemetry.dart';

void main() {
  late int now;
  late CurrentTelemetry telemetry;
  setUp(() {
    now = 1800000000000;
    telemetry = CurrentTelemetry(clock: () => now);
  });
  tearDown(() => telemetry.dispose());
  Map<String, dynamic> sample(
    int time,
    double? current, {
    int session = 1,
    int interval = 1000,
  }) => {
    'time': time,
    'currentMa': current,
    'voltageMv': 4000,
    'sampleIntervalMs': interval,
    'sessionId': session,
  };

  test(
    'Twenty seconds of history stay at the right of every real time window',
    () {
      telemetry.mergeHistory([
        for (var second = 20; second >= 0; second--)
          sample(now - second * 1000, 352),
      ]);
      for (final range in CurrentRange.values) {
        final frame = telemetry.frame(range);
        expect(frame.start, now - range.milliseconds);
        expect(frame.count, 21);
        expect(frame.plot.whereType<CurrentSample>().first.time, now - 20000);
        expect(frame.plot.whereType<CurrentSample>().last.time, now);
        expect(frame.average, 352);
      }
      expect(telemetry.frame(CurrentRange.hour).start, lessThan(now - 20000));
    },
  );

  test(
    'Signed raw samples and genuine zero determine exact stats; missing is excluded',
    () {
      final values = <double?>[0, 125, 250, 500, 1000, -400, null, 0, -5];
      telemetry.mergeHistory([
        for (var i = 0; i < values.length; i++)
          sample(now - (values.length - 1 - i) * 1000, values[i]),
      ]);
      final frame = telemetry.frame(CurrentRange.minute);
      expect(frame.count, 8);
      expect(frame.average, 183.75);
      expect(frame.minimum, -400);
      expect(frame.maximum, 1000);
      expect(frame.latest!.power, -.02);
      expect(frame.plot, contains(null));
      expect(CurrentSample.fromMap(sample(now, 0))!.current, 0);
      expect(CurrentSample.fromMap(sample(now, -250))!.power, -1);
    },
  );

  test('All windows expire incrementally without clearing shared history', () {
    telemetry.mergeHistory([sample(now - 120000, 100), sample(now, 300)]);
    expect(telemetry.frame(CurrentRange.minute).count, 1);
    expect(telemetry.frame(CurrentRange.tenMinutes).count, 2);
    now += 61000;
    telemetry.advance();
    expect(telemetry.frame(CurrentRange.minute).count, 0);
    expect(telemetry.frame(CurrentRange.hour).count, 2);
    expect(telemetry.length, 2);
    now += CurrentRange.sixHours.milliseconds;
    telemetry.advance();
    expect(telemetry.length, 0);
    expect(telemetry.frame(CurrentRange.sixHours).average, isNull);
  });

  test(
    'Six-hour downsampling preserves single-sample peaks/troughs and full-resolution stats',
    () {
      final rows = <Map<String, dynamic>>[];
      var sum = 0.0;
      for (var i = 0; i <= 21600; i++) {
        final value = i == 5123
            ? 7000.0
            : i == 15483
            ? -3200.0
            : 352.0;
        sum += value;
        rows.add(sample(now - 21600000 + i * 1000, value));
      }
      telemetry.mergeHistory(rows);
      final frame = telemetry.frame(CurrentRange.sixHours);
      expect(frame.count, 21601);
      expect(frame.average, closeTo(sum / 21601, 1e-9));
      expect(frame.minimum, -3200);
      expect(frame.maximum, 7000);
      expect(
        frame.plot.whereType<CurrentSample>().map((s) => s.current),
        containsAll([7000, -3200]),
      );
      expect(frame.plot.length, lessThan(750));
      expect(telemetry.length, 21601);
    },
  );

  test(
    'Missing values, session boundaries, clock gaps and convention changes break lines',
    () {
      telemetry.mergeHistory([
        sample(now - 20000, 100),
        sample(now - 19000, null),
        sample(now - 18000, 200),
        sample(now - 17000, 300, session: 2),
        sample(now - 1000, 400, session: 2),
        {...sample(now, 500, session: 2), 'currentConvention': '1000/true'},
      ]);
      final plot = telemetry.frame(CurrentRange.minute).plot;
      expect(plot.where((s) => s == null).length, greaterThanOrEqualTo(3));
      expect(telemetry.frame(CurrentRange.minute).count, 5);
      telemetry.clear();
      telemetry.mergeHistory([
        sample(now - 30000, -100, interval: 30000),
        sample(now, -200, interval: 30000),
      ]);
      expect(
        telemetry.frame(CurrentRange.minute).plot.where((s) => s == null),
        isEmpty,
      );
    },
  );

  test('History merges cannot duplicate points or reset live samples', () {
    telemetry.ingest(sample(now - 1000, 100));
    telemetry.ingest(sample(now, 200));
    telemetry.mergeHistory([sample(now - 2000, 50), sample(now - 1000, 100)]);
    telemetry.ingest(sample(now, 200));
    expect(telemetry.length, 3);
    expect(
      telemetry.frame(CurrentRange.minute).average,
      closeTo(350 / 3, 1e-9),
    );
    expect(telemetry.frame(CurrentRange.hour).latest!.current, 200);
  });

  test(
    'Stale, unsupported and malformed readings never become artificial zeros',
    () {
      telemetry.ingest(sample(now, 352));
      expect(telemetry.frame(CurrentRange.minute).fresh, isTrue);
      now += 6000;
      telemetry.advance();
      expect(telemetry.frame(CurrentRange.minute).fresh, isFalse);
      expect(telemetry.frame(CurrentRange.minute).average, 352);
      telemetry.ingest(sample(now, double.nan));
      expect(telemetry.frame(CurrentRange.minute).latest!.current, isNull);
      expect(telemetry.frame(CurrentRange.minute).count, 1);
      expect(CurrentSample.fromMap({'time': 0}), isNull);
      expect(
        CurrentSample.fromMap({
          ...sample(now, -2147483648),
          'sampleIntervalMs': double.nan,
          'sessionId': 'bad',
        })!.current,
        isNull,
      );
    },
  );

  test(
    'Nice signed axes include zero, adapt beyond 500 mA, and resist shrinking jitter',
    () {
      final small = CurrentAxis.fitting(125, 450);
      expect(small.minimum, 0);
      expect(small.maximum, 500);
      expect(small.interval, 125);
      expect(CurrentAxis.fitting(-5000, 7000).minimum, lessThan(-5000));
      expect(CurrentAxis.fitting(-5000, 7000).maximum, greaterThan(7000));
      final stable = StableCurrentAxis();
      CurrentFrame frame(int time, double maximum) => CurrentFrame(
        now: time,
        range: CurrentRange.minute,
        plot: [],
        count: 1,
        minimum: 0,
        maximum: maximum,
      );
      final big = stable.update(frame(now, 7000));
      expect(stable.update(frame(now + 1000, 300)).maximum, big.maximum);
      expect(stable.update(frame(now + 19000, 310)).maximum, big.maximum);
      expect(
        stable.update(frame(now + 22000, 310)).maximum,
        lessThan(big.maximum),
      );
    },
  );

  test(
    'Seven hours of incremental input keeps bounded plots and exact sliding statistics',
    () {
      final start = now;
      final original = <Map<String, dynamic>>[];
      for (var second = 0; second <= 25200; second++) {
        now = start + second * 1000;
        final value = second % 133 == 0
            ? null
            : second % 701 == 0
            ? 7000.0
            : (second % 100 - 50) * 12.5;
        final row = sample(now, value);
        original.add(row);
        telemetry.ingest(row);
        if (second % 3600 == 0 || second == 25200) {
          for (final range in CurrentRange.values) {
            final valid = original
                .where(
                  (row) =>
                      row['time'] as int >= now - range.milliseconds &&
                      row['currentMa'] != null,
                )
                .map((row) => (row['currentMa'] as num).toDouble())
                .toList();
            final frame = telemetry.frame(range);
            expect(frame.count, valid.length);
            if (valid.isNotEmpty) {
              expect(
                frame.average,
                closeTo(valid.reduce((a, b) => a + b) / valid.length, 1e-7),
              );
            }
            expect(frame.plot.length, lessThan(3000));
          }
        }
      }
      expect(telemetry.length, lessThanOrEqualTo(21601));
    },
  );
}
