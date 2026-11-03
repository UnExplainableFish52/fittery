import 'package:fittery/src/charging_estimate.dart';
import 'package:fittery/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Reading sample(
    int time,
    double current, [
    Map<String, dynamic> overrides = const {},
  ]) => Reading({
    'elapsedRealtimeMs': time,
    'currentMa': current,
    'level': 60,
    'plugged': 1,
    'status': 'Charging',
    'currentConvention': '1000/false',
    'designCapacityMah': 5000,
    ...overrides,
  });
  const settings = {'chargeAlert': true, 'chargeLimit': 80};

  test(
    'Waits for a complete five-second window then estimates minutes to the target',
    () {
      final e = ChargingEstimate();
      e.observe(sample(0, 1000), settings);
      e.observe(sample(3000, 1000), settings);
      expect(e.minutes, isNull);
      e.observe(sample(6000, 1000), settings);
      expect(e.minutes, 60);
      expect(e.target, 80);
      expect(e.reason, contains('Rough'));
    },
  );

  test(
    'Time-weighted integration clips the boundary and ignores duplicate refreshes',
    () {
      final e = ChargingEstimate();
      e.observe(sample(0, 1000), settings);
      e.observe(sample(3000, 3000), settings);
      e.observe(sample(3000, 3000), settings);
      e.observe(sample(6000, 1000), settings);
      expect(e.minutes, 29);
      final dense = ChargingEstimate();
      dense.observe(sample(0, 1000), settings);
      dense.observe(sample(1000, 1000 + 2000 / 3), settings);
      dense.observe(sample(3000, 3000), settings);
      dense.observe(sample(6000, 1000), settings);
      expect(dense.minutes, e.minutes);
    },
  );

  test(
    'After reaching the target it estimates to full; disabling the target also selects full',
    () {
      final e = ChargingEstimate();
      for (final t in [0, 3000, 6000]) {
        e.observe(sample(t, 1000, {'level': 85}), settings);
      }
      expect(e.target, 100);
      expect(e.minutes, 45);
      e.observe(sample(6000, 1000), {'chargeAlert': false});
      expect(e.target, 100);
      expect(e.minutes, 120);
      e.observe(sample(9000, 0, {'level': 100, 'status': 'Full'}), settings);
      expect(e.minutes, 0);
    },
  );

  test(
    'Unknown capacity, nonpositive current, gaps, and convention changes never invent an ETA',
    () {
      final e = ChargingEstimate();
      for (final t in [0, 3000, 6000]) {
        e.observe(sample(t, 1000, {'designCapacityMah': null}), settings);
      }
      expect(e.minutes, isNull);
      expect(e.reason, contains('capacity'));
      e.observe(sample(9000, -1), settings);
      expect(e.minutes, isNull);
      e.observe(sample(12000, 1000, {'currentConvention': '1/true'}), settings);
      expect(e.minutes, isNull);
      e.observe(sample(20000, 1000), settings);
      expect(e.minutes, isNull);
      e.observe(sample(23000, double.nan), settings);
      expect(e.minutes, isNull);
      e.observe(sample(26000, 1000, {'plugged': 0}), settings);
      expect(e.minutes, isNull);
    },
  );

  test('An invalid full-capacity reading uses validated design capacity', () {
    final e = ChargingEstimate();
    for (final t in [0, 3000, 6000]) {
      e.observe(sample(t, 1000, {'fullCapacityMah': 100000}), settings);
    }
    expect(e.minutes, 60);
  });
}
