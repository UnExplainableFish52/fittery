import 'dart:collection';

import 'models.dart';

/// A deliberately rough, time-weighted estimate from the last five seconds.
/// Receives the existing stream; never schedules reads, timers, or recordings.
class ChargingEstimate {
  final _samples = Queue<(int, double)>();
  String? _convention;
  int? _source;
  int target = 100;
  int? minutes;
  String reason = 'Collecting five seconds of charging readings';

  void observe(Reading? reading, Map<String, dynamic> settings) {
    final level = reading?.number('level')?.toDouble();
    final limit = (settings['chargeLimit'] as num?)?.toInt() ?? 80;
    target =
        settings['chargeAlert'] != false &&
            limit >= 50 &&
            limit <= 100 &&
            level != null &&
            level < limit
        ? limit
        : 100;
    minutes = null;
    final source = reading?.number('plugged')?.toInt();
    final mode = reading?.data['currentConvention']?.toString();
    final time = reading?.number('elapsedRealtimeMs')?.toInt();
    final current = reading?.current?.toDouble();
    if (reading?.plugged != true ||
        reading?.charging != true ||
        time == null ||
        current == null ||
        !current.isFinite ||
        current.abs() > 50000 ||
        level == null ||
        !level.isFinite ||
        level < 0 ||
        level > 100) {
      _samples.clear();
      reason = reading?.text('status') == 'Full'
          ? 'Battery is full'
          : 'No usable charging rate';
      if (reading?.text('status') == 'Full' && level == 100) minutes = 0;
      return;
    }
    final previous = _samples.lastOrNull;
    if (_source != source ||
        _convention != mode ||
        previous != null && (time < previous.$1 || time - previous.$1 > 6000)) {
      _samples.clear();
    }
    _source = source;
    _convention = mode;
    if (_samples.lastOrNull?.$1 != time) _samples.add((time, current));
    final boundary = time - 5000;
    while (_samples.length > 2 && _samples.elementAt(1).$1 <= boundary) {
      _samples.removeFirst();
    }
    if (_samples.length < 3 || time - _samples.first.$1 < 5000) {
      reason = 'Collecting five seconds of charging readings';
      return;
    }
    // Trapezoidal integration clips the oldest interval at the window edge.
    // Extra UI refreshes therefore cannot outweigh a three-second sample.
    var area = 0.0;
    var a = _samples.first;
    for (final b in _samples.skip(1)) {
      final start = a.$1 < boundary ? boundary : a.$1;
      final duration = b.$1 - start;
      if (duration > 0) {
        final atStart = a.$2 + (b.$2 - a.$2) * (start - a.$1) / (b.$1 - a.$1);
        area += (atStart + b.$2) * .5 * duration;
      }
      a = b;
    }
    final average = area / 5000;
    if (average <= 10 || current <= 0) {
      reason = 'Recent net current is not adding charge';
      return;
    }
    double? capacity(num? value) =>
        value != null && value.isFinite && value >= 500 && value <= 30000
        ? value.toDouble()
        : null;
    final design = capacity(reading!.number('designCapacityMah'));
    final full = capacity(reading.number('fullCapacityMah'));
    final usableFull =
        full != null &&
            (design == null || full >= design * .1 && full <= design * 1.2)
        ? full
        : null;
    final mah = usableFull ?? design;
    if (mah == null) {
      reason = 'Battery capacity is unavailable; no time estimate';
      return;
    }
    final raw = mah * (target - level) / 100 / average * 60;
    if (!raw.isFinite || raw < 0 || raw > 10080) {
      reason = 'Charging is too slow for a useful estimate';
      return;
    }
    minutes = raw.ceil();
    reason =
        'Rough time to $target% at the last five seconds of net battery current. Charging may slow near full.';
  }
}
