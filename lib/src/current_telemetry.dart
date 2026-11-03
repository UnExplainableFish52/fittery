import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

enum CurrentRange {
  minute('1m', 60),
  tenMinutes('10m', 600),
  hour('1h', 3600),
  sixHours('6h', 21600);

  const CurrentRange(this.label, this.seconds);
  final String label;
  final int seconds;
  int get milliseconds => seconds * 1000;
}

class CurrentSample {
  const CurrentSample({
    required this.time,
    this.current,
    this.voltage,
    this.sessionId,
    this.intervalMs = 30000,
    this.convention,
    this.gapBefore = false,
    this.rawCurrent,
  });
  final int time, intervalMs;
  final double? current, voltage;
  final int? sessionId;
  final String? convention;
  final bool gapBefore;
  final int? rawCurrent;
  double? get power =>
      current == null || voltage == null ? null : current! * voltage! / 1000000;

  static CurrentSample? fromMap(Map<dynamic, dynamic> data) {
    final time = data['time'];
    if (time is! num || !time.isFinite || time <= 0) return null;
    final current = data['currentMa'], voltage = data['voltageMv'];
    final period = data['sampleIntervalMs'], session = data['sessionId'];
    return CurrentSample(
      time: time.toInt(),
      current: current is num && current.isFinite && current.abs() <= 50000
          ? current.toDouble()
          : null,
      voltage: voltage is num && voltage.isFinite && voltage > 0
          ? voltage.toDouble()
          : null,
      intervalMs: period is num && period.isFinite
          ? period.toInt().clamp(1000, 30000)
          : 30000,
      sessionId: session is num && session.isFinite ? session.toInt() : null,
      convention: data['currentConvention'] is String
          ? data['currentConvention'] as String
          : null,
      gapBefore: data['gapBefore'] == true,
      rawCurrent:
          data['rawCurrent'] is num && (data['rawCurrent'] as num).isFinite
          ? (data['rawCurrent'] as num).toInt()
          : null,
    );
  }

  bool sameAs(CurrentSample other) =>
      time == other.time &&
      current == other.current &&
      voltage == other.voltage &&
      sessionId == other.sessionId &&
      intervalMs == other.intervalMs &&
      convention == other.convention &&
      gapBefore == other.gapBefore;
}

class CurrentFrame {
  const CurrentFrame({
    required this.now,
    required this.range,
    required this.plot,
    required this.count,
    this.average,
    this.minimum,
    this.maximum,
    this.latest,
    this.latestValid,
  });
  final int now, count;
  final CurrentRange range;
  final List<CurrentSample?> plot;
  final double? average, minimum, maximum;
  final CurrentSample? latest, latestValid;
  int get start => now - range.milliseconds;
  bool get fresh =>
      latest?.current != null &&
      now >= latest!.time &&
      now - latest!.time <= 5000;
}

class _Entry {
  const _Entry(this.sample, this.breakBefore);
  final CurrentSample sample;
  final bool breakBefore;
}

class _Run {
  _Entry? first, last, minimum, maximum;
  void add(_Entry entry) {
    final value = entry.sample.current;
    if (value == null) return;
    first ??= entry;
    last = entry;
    if (minimum == null || value < minimum!.sample.current!) minimum = entry;
    if (maximum == null || value > maximum!.sample.current!) maximum = entry;
  }

  List<_Entry> get representatives {
    final unique = <int, _Entry>{};
    for (final entry in [first, minimum, maximum, last]) {
      if (entry != null) unique[entry.sample.time] = entry;
    }
    return unique.values.toList()
      ..sort((a, b) => a.sample.time.compareTo(b.sample.time));
  }
}

class _Bucket {
  final entries = ListQueue<_Entry>();
  final runs = <_Run>[];
  _Run extrema = _Run();
  bool _interrupted = true;
  void add(_Entry entry) {
    entries.addLast(entry);
    _include(entry);
  }

  void _include(_Entry entry) {
    if (entry.sample.current == null) {
      _interrupted = true;
      return;
    }
    extrema.add(entry);
    if (_interrupted || entry.breakBefore || runs.isEmpty) runs.add(_Run());
    runs.last.add(entry);
    _interrupted = false;
  }

  void removeFirst() {
    entries.removeFirst();
    runs.clear();
    extrema = _Run();
    _interrupted = true;
    for (final entry in entries) {
      _include(entry);
    }
  }

  List<CurrentSample?> get plotted {
    final result = <CurrentSample?>[];
    // Pathological dropouts remain bounded without drawing false continuity.
    if (runs.length > 4) {
      for (final entry in extrema.representatives) {
        result.add(entry.sample);
        result.add(null);
      }
    } else {
      for (final run in runs) {
        if (result.isNotEmpty) result.add(null);
        result.addAll(run.representatives.map((entry) => entry.sample));
      }
      if (_interrupted || result.isEmpty) result.add(null);
    }
    return result;
  }
}

/// Incremental exact statistics plus fixed time buckets for drawing only.
/// Buckets keep first/last/extrema. A bucket with interruptions never draws a
/// continuous line across those interruptions, even at the coarsest range.
class _Window {
  _Window(this.range);
  final CurrentRange range;
  final samples = ListQueue<_Entry>();
  final valid = ListQueue<_Entry>();
  final lows = ListQueue<_Entry>(), highs = ListQueue<_Entry>();
  final buckets = SplayTreeMap<int, _Bucket>();
  double sum = 0;
  int get bucketMs => math.max(1000, range.milliseconds ~/ 180);
  void add(_Entry entry) {
    samples.addLast(entry);
    (buckets[entry.sample.time ~/ bucketMs] ??= _Bucket()).add(entry);
    final value = entry.sample.current;
    if (value == null) return;
    valid.addLast(entry);
    sum += value;
    while (lows.isNotEmpty && lows.last.sample.current! > value) {
      lows.removeLast();
    }
    while (highs.isNotEmpty && highs.last.sample.current! < value) {
      highs.removeLast();
    }
    lows.addLast(entry);
    highs.addLast(entry);
  }

  void expire(int now, {int? oldest}) {
    final cutoff = math.max(now - range.milliseconds, oldest ?? 0);
    while (samples.isNotEmpty && samples.first.sample.time < cutoff) {
      final entry = samples.removeFirst();
      final key = entry.sample.time ~/ bucketMs;
      final bucket = buckets[key]!;
      bucket.removeFirst();
      if (bucket.entries.isEmpty) buckets.remove(key);
      if (entry.sample.current != null) {
        valid.removeFirst();
        sum -= entry.sample.current!;
        if (identical(lows.first, entry)) lows.removeFirst();
        if (identical(highs.first, entry)) highs.removeFirst();
      }
    }
  }

  CurrentFrame frame(int now) {
    final plot = <CurrentSample?>[];
    for (final bucket in buckets.values) {
      if (bucket.entries.first.breakBefore &&
          plot.isNotEmpty &&
          plot.last != null) {
        plot.add(null);
      }
      plot.addAll(bucket.plotted);
    }
    return CurrentFrame(
      now: now,
      range: range,
      plot: plot,
      count: valid.length,
      average: valid.isEmpty ? null : sum / valid.length,
      minimum: lows.isEmpty ? null : lows.first.sample.current,
      maximum: highs.isEmpty ? null : highs.first.sample.current,
      latest: samples.isEmpty ? null : samples.last.sample,
      latestValid: valid.isEmpty ? null : valid.last.sample,
    );
  }
}

/// Owned by BatteryController, independent of the chart widget and its range.
/// All four rolling summaries advance incrementally on incoming samples.
class CurrentTelemetry extends ChangeNotifier {
  CurrentTelemetry({int Function()? clock})
    : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    now = _clock();
  }
  final int Function() _clock;
  final _samples = SplayTreeMap<int, CurrentSample>();
  Map<CurrentRange, _Window> _windows = {
    for (final range in CurrentRange.values) range: _Window(range),
  };
  late int now;
  String? error;
  bool loading = false;
  Timer? _clockTimer;
  static const capacity = 26000;
  int get length => _samples.length;
  CurrentSample? sampleAt(int timestamp) => _samples[timestamp];

  void setActive(bool active) {
    _clockTimer?.cancel();
    _clockTimer = null;
    if (active) {
      advance();
      _clockTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => advance(),
      );
    }
  }

  bool _break(CurrentSample? previous, CurrentSample sample) =>
      previous == null ||
      sample.gapBefore ||
      sample.time - previous.time >
          math.max(previous.intervalMs, sample.intervalMs) * 2.5 ||
      (previous.sessionId != null &&
          sample.sessionId != null &&
          previous.sessionId != sample.sessionId) ||
      (previous.convention != null &&
          sample.convention != null &&
          previous.convention != sample.convention) ||
      previous.current == null;

  void ingest(Map<dynamic, dynamic> data) {
    final sample = CurrentSample.fromMap(data);
    if (sample == null ||
        sample.time > _clock() ||
        sample.time < _clock() - CurrentRange.sixHours.milliseconds) {
      return;
    }
    now = _clock();
    final old = _samples[sample.time];
    if (old?.sameAs(sample) == true) return;
    final previous = _samples.isEmpty ? null : _samples[_samples.lastKey()];
    _samples[sample.time] = sample;
    if (previous == null || sample.time > previous.time) {
      final entry = _Entry(sample, _break(previous, sample));
      for (final window in _windows.values) {
        window.add(entry);
      }
    } else {
      _rebuild();
    }
    error = data['historyError'] as String?;
    _trim();
    for (final window in _windows.values) {
      window.expire(now, oldest: _samples.firstKey());
    }
    notifyListeners();
  }

  void mergeHistory(Iterable<Map<dynamic, dynamic>> rows) {
    now = _clock();
    for (final row in rows) {
      final sample = CurrentSample.fromMap(row);
      if (sample == null ||
          sample.time > now ||
          sample.time < now - CurrentRange.sixHours.milliseconds) {
        continue;
      }
      final previous = _samples[sample.time];
      _samples[sample.time] = CurrentSample(
        time: sample.time,
        current: sample.current,
        voltage: sample.voltage,
        intervalMs: sample.intervalMs,
        sessionId: sample.sessionId,
        convention: sample.convention,
        gapBefore: sample.gapBefore || previous?.gapBefore == true,
        rawCurrent: previous?.rawCurrent ?? sample.rawCurrent,
      );
    }
    _trim();
    _rebuild();
    notifyListeners();
  }

  void _trim() {
    while (_samples.isNotEmpty &&
        (_samples.firstKey()! < now - CurrentRange.sixHours.milliseconds ||
            _samples.length > capacity)) {
      _samples.remove(_samples.firstKey());
    }
  }

  void _rebuild() {
    _windows = {for (final range in CurrentRange.values) range: _Window(range)};
    CurrentSample? previous;
    for (final sample in _samples.values) {
      final entry = _Entry(sample, _break(previous, sample));
      for (final window in _windows.values) {
        if (sample.time >= now - window.range.milliseconds) window.add(entry);
      }
      previous = sample;
    }
  }

  void advance() {
    final next = _clock();
    if (next < now) {
      while (_samples.isNotEmpty && _samples.lastKey()! > next) {
        _samples.remove(_samples.lastKey());
      }
      now = next;
      _rebuild();
    }
    now = next;
    _trim();
    for (final window in _windows.values) {
      window.expire(now, oldest: _samples.firstKey());
    }
    notifyListeners();
  }

  CurrentFrame frame(CurrentRange range) => _windows[range]!.frame(now);
  void clear() {
    _samples.clear();
    _rebuild();
    error = null;
    notifyListeners();
  }

  void reportError(String? message) {
    error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }
}

class CurrentAxis {
  const CurrentAxis(this.minimum, this.maximum, this.interval);
  final double minimum, maximum, interval;
  static CurrentAxis fitting(double? low, double? high) {
    if (low == null || high == null || (low == 0 && high == 0)) {
      return const CurrentAxis(-50, 50, 25);
    }
    var bottom = math.min(0.0, low), top = math.max(0.0, high);
    final padding = math.max((top - bottom) * .1, 5.0);
    if (bottom < 0) bottom -= padding;
    if (top > 0) top += padding;
    final target = (top - bottom) / 4;
    final power = math
        .pow(10, (math.log(target) / math.ln10).floor())
        .toDouble();
    final interval =
        [
          1.0,
          1.25,
          2.0,
          2.5,
          5.0,
          10.0,
        ].firstWhere((v) => v * power >= target) *
        power;
    return CurrentAxis(
      (bottom / interval).floor() * interval,
      (top / interval).ceil() * interval,
      interval,
    );
  }
}

/// Expand for a real spike immediately. Shrink only after 20 seconds of headroom.
class StableCurrentAxis {
  CurrentAxis? _axis;
  int? _shrinkSince;
  void reset() {
    _axis = null;
    _shrinkSince = null;
  }

  CurrentAxis update(CurrentFrame frame) {
    final next = CurrentAxis.fitting(frame.minimum, frame.maximum);
    final old = _axis;
    if (old == null ||
        next.minimum < old.minimum ||
        next.maximum > old.maximum) {
      _shrinkSince = null;
      return _axis = next;
    }
    if (next.maximum - next.minimum < (old.maximum - old.minimum) * .65) {
      _shrinkSince ??= frame.now;
      if (frame.now - _shrinkSince! >= 20000) {
        _shrinkSince = null;
        return _axis = next;
      }
    } else {
      _shrinkSince = null;
    }
    return old;
  }
}
