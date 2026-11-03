part of 'app.dart';

String recordingName(Map<String, dynamic> r) =>
    (r['name'] as String?) ?? 'Monitor · ${timeLabel(r['startTime'] as num)}';

String recordingStatus(Map<String, dynamic> r, BatteryController c) =>
    r['active'] != 1
    ? 'Saved'
    : c.monitoring
    ? 'Ongoing'
    : 'Interrupted · resume monitoring';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.c});
  final BatteryController c;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  DateTimeRange? _dates;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh({bool more = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      widget.c.recordingsSince = _dates?.start.millisecondsSinceEpoch;
      widget.c.recordingsUntil = _dates == null
          ? null
          : DateTime(
              _dates!.end.year,
              _dates!.end.month,
              _dates!.end.day + 1,
            ).millisecondsSinceEpoch;
      await widget.c.refreshRecordings(more: more);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Recordings could not load. Pull down to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _filter() async {
    final now = DateTime.now();
    final dates = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _dates,
    );
    if (dates == null || !mounted) return;
    setState(() => _dates = dates);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.c,
    builder: (_, _) => RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        children: [
          const SectionLabel('Monitor recordings'),
          const Text(
            'Temperature, power and battery use across charging and discharging. Start monitoring to create a recording.',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _filter,
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: Text(
                  _dates == null
                      ? 'Filter by date'
                      : '${_dates!.start.day}/${_dates!.start.month}/${_dates!.start.year} – ${_dates!.end.day}/${_dates!.end.month}/${_dates!.end.year}',
                ),
              ),
              if (_dates != null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() => _dates = null);
                          unawaited(_refresh());
                        },
                  child: const Text('All dates'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            widget.c.flag('keepRecordings')
                ? 'Saved on this device until you delete them.'
                : 'Completed recordings expire 30 days after creation. Change this in Settings.',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_error ?? widget.c.historyError case final String error)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(error, style: const TextStyle(color: coral)),
            ),
          if (widget.c.recordings.isEmpty && !_busy)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.timeline_rounded, color: mint),
                  const SizedBox(height: 12),
                  Text(
                    _dates == null
                        ? 'No monitor recordings yet'
                        : 'No recordings in these dates',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Each time you enable monitoring, Fittery saves a named recording. Charger changes stay inside it; brief connections do not fill this list.',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                ],
              ),
            ),
          ...widget.c.recordings.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MonitorRecordingPage(
                          c: widget.c,
                          id: (r['id'] as num).toInt(),
                        ),
                      ),
                    );
                    if (mounted) await _refresh();
                  },
                  child: Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.timeline_rounded,
                              color: mint,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                recordingName(r),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.chevron_right, size: 20),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${recordingStatus(r, widget.c)} · ${durationLabel((r['endTime'] as num) - (r['startTime'] as num))} · ${r['sampleCount']} readings',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${r['startLevel'] ?? '—'}% → ${r['endLevel'] ?? '—'}% · ${timeLabel(r['startTime'] as num)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        if ((r['gapCount'] as num? ?? 0) > 0)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Contains recording gaps',
                              style: TextStyle(fontSize: 11, color: coral),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.c.moreRecordings)
            TextButton(
              onPressed: _busy ? null : () => _refresh(more: true),
              child: const Text('Load older recordings'),
            ),
        ],
      ),
    ),
  );
}

class MonitorRecordingPage extends StatefulWidget {
  const MonitorRecordingPage({
    super.key,
    required this.c,
    required this.id,
    this.chargingSince,
    this.chargingUntil,
  });
  final BatteryController c;
  final int id;
  final int? chargingSince, chargingUntil;
  @override
  State<MonitorRecordingPage> createState() => _MonitorRecordingPageState();
}

class _MonitorRecordingPageState extends State<MonitorRecordingPage> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;
  Timer? _timer;
  int _generation = 0;
  RangeValues _range = const RangeValues(0, 1);
  DateTime? _graphDay;
  DateTime? _lastLoad;
  final _graphPoints = ValueNotifier<List<Map<String, dynamic>>>([]);
  int _graphRevision = 0;
  bool _reloadAfterCurrent = false;
  late bool _chargingRange =
      widget.chargingSince != null && widget.chargingUntil != null;
  final Set<String> _metrics = {'temperatureC', 'powerW'};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      final record = _data?['recording'] as Map?;
      final longRecording =
          record != null &&
          (record['endTime'] as num) - (record['startTime'] as num) > 21600000;
      if (!_chargingRange &&
          widget.c.appActive &&
          record?['active'] == 1 &&
          (!longRecording ||
              _lastLoad == null ||
              DateTime.now().difference(_lastLoad!).inSeconds >= 30)) {
        unawaited(_load(quiet: true));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _generation++;
    _graphPoints.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (_loading) {
      if (!quiet) _reloadAfterCurrent = true;
      return;
    }
    final generation = ++_generation;
    _loading = true;
    if (_data == null || _error != null) setState(() => _error = null);
    try {
      final record = _data?['recording'] as Map?;
      final bounds = record == null ? null : _graphBounds(record);
      final span = bounds == null ? null : bounds.$2 - bounds.$1;
      final data = await widget.c.recordingDetail(
        widget.id,
        since: span == null
            ? (_chargingRange ? widget.chargingSince : null)
            : !_chargingRange && _graphDay == null && _range.start == 0
            ? null
            : (bounds!.$1 + span * _range.start).round(),
        until: span == null
            ? (_chargingRange ? widget.chargingUntil : null)
            : !_chargingRange && _graphDay == null && _range.end == 1
            ? null
            : (bounds!.$1 + span * _range.end).round(),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = data;
        if (!quiet) _graphRevision++;
      });
      _graphPoints.value = (data['points'] as List? ?? [])
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
      _lastLoad = DateTime.now();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error =
              'Recording could not load. It may have expired or been deleted. Pull down to retry.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        _loading = false;
        if (_data == null) setState(() {});
        if (_reloadAfterCurrent) {
          _reloadAfterCurrent = false;
          unawaited(_load());
        }
      }
    }
  }

  (int, int) _graphBounds(Map record) {
    final start = (record['startTime'] as num).toInt();
    final end = (record['endTime'] as num).toInt();
    if (_chargingRange) return (widget.chargingSince!, widget.chargingUntil!);
    if (_graphDay == null) return (start, end);
    final day = _graphDay!;
    return (
      math.max(start, day.millisecondsSinceEpoch),
      math.min(
        end,
        DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch - 1,
      ),
    );
  }

  Future<void> _chooseDay() async {
    final record = _data!['recording'] as Map;
    final first = DateTime.fromMillisecondsSinceEpoch(
      (record['startTime'] as num).toInt(),
    );
    final last = DateTime.fromMillisecondsSinceEpoch(
      (record['endTime'] as num).toInt(),
    );
    final day = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDate: _graphDay ?? first,
    );
    if (day == null || !mounted) return;
    setState(() {
      _graphDay = day;
      _range = const RangeValues(0, 1);
    });
    await _load();
  }

  Future<void> _rename() async {
    final record = Map<String, dynamic>.from(_data!['recording'] as Map);
    var draft = recordingName(record);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename recording'),
        content: TextFormField(
          initialValue: draft,
          onChanged: (value) => draft = value,
          maxLength: 80,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (draft.trim().isNotEmpty) {
                Navigator.pop(ctx, draft.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    await runAction(context, () async {
      await widget.c.renameRecording(widget.id, name);
      await _load();
    });
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this recording?'),
        content: const Text(
          'Its saved measurements and report will be permanently removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: coral)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await runAction(context, () async {
      await widget.c.deleteRecording(widget.id);
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final record = _data == null
        ? null
        : Map<String, dynamic>.from(_data!['recording'] as Map);
    final points = (_data?['points'] as List? ?? [])
        .map((p) => Map<String, dynamic>.from(p as Map))
        .toList();
    final segments = (_data?['charging'] as List? ?? [])
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();
    final fahrenheit = widget.c.flag('fahrenheit');
    final powerMs = record?['powerMs'] as num? ?? 0;
    final currentMs = record?['currentMs'] as num? ?? 0;
    final temperatureMs = record?['temperatureMs'] as num? ?? 0;
    final average = powerMs > 0 ? (record!['powerWms'] as num) / powerMs : null;
    final start = record?['startTime'] as num?;
    final end = record?['endTime'] as num?;
    final peak = record?['maxTemperatureC'] as num?;
    final graphBounds = record == null ? null : _graphBounds(record);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _chargingRange ? 'Charging session report' : 'Monitor recording',
        ),
        actions: [
          if (record != null)
            IconButton(
              tooltip: 'Rename recording',
              onPressed: _rename,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (record != null && record['active'] != 1)
            IconButton(
              tooltip: 'Delete recording',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            if (_loading && _data == null)
              const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(_error!, style: const TextStyle(color: coral)),
              ),
            if (record != null) ...[
              Text(
                recordingName(record),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _chargingRange
                    ? '${timeLabel(widget.chargingSince!)} → ${timeLabel(widget.chargingUntil!)}'
                    : '${recordingStatus(record, widget.c)} · ${timeLabel(start!)}${record['active'] == 1 ? '' : ' → ${timeLabel(end!)}'}',
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
              if (_chargingRange) ...[
                const SizedBox(height: 16),
                Panel(
                  child: Column(
                    children: [
                      infoRow(
                        context,
                        'Recorded charging time',
                        durationLabel(
                          widget.chargingUntil! - widget.chargingSince!,
                        ),
                      ),
                      infoRow(
                        context,
                        'Saved readings',
                        '${_data!['rangeSampleCount']}',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'These graphs cover the saved charging portion. Readings begin when monitor mode was enabled. Open the full recording for its overall summary.',
                        style: TextStyle(fontSize: 11, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ],
              if (!_chargingRange) ...[
                const SectionLabel('Recording report'),
                Panel(
                  child: Column(
                    children: [
                      infoRow(
                        context,
                        'Duration',
                        durationLabel(end! - start!),
                      ),
                      infoRow(
                        context,
                        'Battery level',
                        '${record['startLevel'] ?? '—'}% → ${record['endLevel'] ?? '—'}%',
                      ),
                      infoRow(
                        context,
                        'Observed time',
                        durationLabel(record['observedMs'] as num),
                      ),
                      infoRow(
                        context,
                        'Recording gaps',
                        '${record['gapCount']}',
                      ),
                      infoRow(
                        context,
                        'Average net battery power',
                        metric(average, 'W', decimals: 2, signed: true),
                      ),
                      infoRow(
                        context,
                        'Highest net power',
                        metric(record['maxPowerW'] as num?, 'W', decimals: 2),
                      ),
                      infoRow(
                        context,
                        'Lowest net power',
                        metric(record['minPowerW'] as num?, 'W', decimals: 2),
                      ),
                      infoRow(
                        context,
                        'Estimated charge added',
                        metric(
                          currentMs > 0 ? record['chargeMah'] as num? : null,
                          'mAh',
                          decimals: 1,
                        ),
                      ),
                      infoRow(
                        context,
                        'Estimated charge used',
                        metric(
                          currentMs > 0 ? record['dischargeMah'] as num? : null,
                          'mAh',
                          decimals: 1,
                        ),
                      ),
                      infoRow(
                        context,
                        'Highest recorded temperature',
                        metric(
                          peak == null
                              ? null
                              : fahrenheit
                              ? peak * 1.8 + 32
                              : peak,
                          fahrenheit ? '°F' : '°C',
                          decimals: 1,
                        ),
                      ),
                      if (record['peakTemperatureTime'] != null)
                        infoRow(
                          context,
                          'Temperature peak at',
                          timeLabel(record['peakTemperatureTime'] as num),
                        ),
                      infoRow(
                        context,
                        fahrenheit
                            ? 'Recorded above 95°F'
                            : 'Recorded above 35°C',
                        peak == null
                            ? 'Unavailable'
                            : peak > 35
                            ? 'Yes'
                            : 'No recorded reading',
                      ),
                      infoRow(
                        context,
                        fahrenheit
                            ? 'Est. time above 95°F'
                            : 'Est. time above 35°C',
                        temperatureMs > 0
                            ? durationLabel(record['above35Ms'] as num)
                            : 'Unavailable',
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Power is measured at the battery. Positive adds charge; negative uses charge. Averages and charge totals use observed, supported intervals. Temperature crossings between readings are estimates.',
                        style: TextStyle(fontSize: 11, height: 1.6),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Power coverage: ${durationLabel(powerMs)} · current: ${durationLabel(currentMs)} · temperature: ${durationLabel(temperatureMs)}',
                        style: const TextStyle(fontSize: 10, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
              const SectionLabel('Saved measurements'),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loading || _chargingRange ? null : _chooseDay,
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(
                      _graphDay == null
                          ? 'Inspect a day'
                          : '${_graphDay!.day}/${_graphDay!.month}/${_graphDay!.year}',
                    ),
                  ),
                  if (_graphDay != null || _chargingRange)
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              setState(() {
                                _graphDay = null;
                                _chargingRange = false;
                                _range = const RangeValues(0, 1);
                              });
                              unawaited(_load());
                            },
                      child: const Text('Full recording'),
                    ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final item in const [
                    ('temperatureC', 'Temperature'),
                    ('powerW', 'Power'),
                    ('currentMa', 'Current'),
                    ('voltageMv', 'Voltage'),
                    ('chargeCounterMah', 'Remaining mAh'),
                    ('level', 'Battery %'),
                  ])
                    FilterChip(
                      label: Text(item.$2),
                      selected: _metrics.contains(item.$1),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _metrics.add(item.$1);
                        } else {
                          _metrics.remove(item.$1);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (graphBounds!.$2 > graphBounds.$1) ...[
                const Text(
                  'Select a time range to inspect the original measurements.',
                  style: TextStyle(fontSize: 11),
                ),
                RangeSlider(
                  values: _range,
                  min: 0,
                  max: 1,
                  divisions: 100,
                  labels: RangeLabels(
                    clockLabel(
                      graphBounds.$1 +
                          (graphBounds.$2 - graphBounds.$1) * _range.start,
                    ),
                    clockLabel(
                      graphBounds.$1 +
                          (graphBounds.$2 - graphBounds.$1) * _range.end,
                    ),
                  ),
                  onChanged: _loading
                      ? null
                      : (range) {
                          if (range.end - range.start >= .01) {
                            setState(() => _range = range);
                          }
                        },
                  onChangeEnd: (_) => _load(),
                ),
              ],
              Panel(
                child: Column(
                  children: [
                    if (points.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No readings in this range.'),
                      ),
                    for (final key in _metrics)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 22),
                        child: SavedMetricGraph(
                          key: ValueKey('recording-graph-$key'),
                          source: _graphPoints,
                          initialPoints: points,
                          metric: key,
                          active: () => widget.c.appActive,
                          viewKey: '$_graphRevision/$fahrenheit',
                          label: switch (key) {
                            'temperatureC' =>
                              fahrenheit
                                  ? 'Temperature · °F'
                                  : 'Temperature · °C',
                            'powerW' => 'Net battery power · W',
                            'currentMa' => 'Net current · mA',
                            'voltageMv' => 'Voltage · V',
                            'chargeCounterMah' => 'Remaining charge · mAh',
                            _ => 'Battery · %',
                          },
                          color: key == 'powerW' || key == 'currentMa'
                              ? coral
                              : mint,
                          transform: (v) => key == 'temperatureC' && fahrenheit
                              ? v * 1.8 + 32
                              : key == 'voltageMv'
                              ? v / 1000
                              : v,
                        ),
                      ),
                    if (points.isNotEmpty)
                      Text(
                        '${timeLabel(points.first['time'] as num)} → ${timeLabel(points.last['time'] as num)}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      '${_data!['rangeSampleCount']} saved readings in this range. Graphs preserve peaks; zooming loads more detail. Gaps stay blank.',
                      style: const TextStyle(fontSize: 11, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SectionLabel('Charging within this recording'),
              const Text(
                'Connections under 5 minutes with less than 5 percentage points gained are hidden from these summaries. Their measurements remain in the graphs.',
                style: TextStyle(fontSize: 11, height: 1.6),
              ),
              const SizedBox(height: 12),
              if (segments.isEmpty)
                const Panel(
                  child: Text(
                    'No substantial charging segments recorded.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              for (final segment in segments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    child: Column(
                      children: [
                        infoRow(
                          context,
                          segment['ended'] == 0
                              ? 'Plugged in now'
                              : 'Charging segment',
                          '${segment['startLevel'] ?? '—'}% → ${segment['endLevel'] ?? '—'}%',
                        ),
                        infoRow(
                          context,
                          'Connected',
                          durationLabel(
                            (segment['endTime'] as num) -
                                (segment['startTime'] as num),
                          ),
                        ),
                        infoRow(
                          context,
                          'Actively charging',
                          durationLabel(segment['activeMs'] as num),
                        ),
                        infoRow(
                          context,
                          'Average net power',
                          metric(
                            (segment['powerMs'] as num) > 0
                                ? (segment['powerWms'] as num) /
                                      (segment['powerMs'] as num)
                                : null,
                            'W',
                            decimals: 2,
                            signed: true,
                          ),
                        ),
                        infoRow(
                          context,
                          'Started',
                          timeLabel(segment['startTime'] as num),
                        ),
                        if (segment['fullAt'] != null)
                          infoRow(
                            context,
                            'Reached full',
                            timeLabel(segment['fullAt'] as num),
                          ),
                        if (segment['partial'] == 1)
                          const Text(
                            'Partial segment: monitoring began after connection, or recording was interrupted.',
                            style: TextStyle(fontSize: 10, height: 1.5),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              const Text(
                'Recording targets one sample every 3 seconds. Android may delay readings while the phone sleeps. Missed time is not reconstructed.',
                style: TextStyle(fontSize: 11, height: 1.6),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
