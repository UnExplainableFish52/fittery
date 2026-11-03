part of 'app.dart';

/// Owns its displayed snapshot so temperature never follows unrelated page or
/// controller rebuilds. Only this element rebuilds when its minute expires.
class SavedMetricGraph extends StatefulWidget {
  const SavedMetricGraph({
    super.key,
    required this.source,
    required this.initialPoints,
    required this.metric,
    required this.label,
    required this.color,
    required this.transform,
    required this.active,
    this.viewKey,
    this.recentHour = false,
  });
  final ValueListenable<List<Map<String, dynamic>>> source;
  final List<Map<String, dynamic>> initialPoints;
  final String metric, label;
  final Color color;
  final double Function(double) transform;
  final bool Function() active;
  final Object? viewKey;
  final bool recentHour;
  @override
  State<SavedMetricGraph> createState() => _SavedMetricGraphState();
}

class _SavedMetricGraphState extends State<SavedMetricGraph> {
  late List<Map<String, dynamic>> _shown, _pending;
  Timer? _timer;
  Widget? _rendered;
  bool get _temperature => widget.metric == 'temperatureC';

  @override
  void initState() {
    super.initState();
    _pending = widget.source.value.isEmpty
        ? widget.initialPoints
        : widget.source.value;
    _shown = _pending;
    widget.source.addListener(_receive);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_temperature) {
      _timer = Timer(const Duration(minutes: 1), () {
        _timer = null;
        if (widget.active() && !identical(_pending, _shown)) {
          _publish();
          _schedule();
        }
      });
    }
  }

  void _receive() {
    _pending = widget.source.value;
    if (!widget.active()) return;
    // Initial data, explicit range/unit changes and clear-history are immediate.
    if (!_temperature || _shown.isEmpty || _pending.isEmpty || _timer == null) {
      _publish();
      _schedule();
    }
  }

  void _publish() {
    if (!mounted) return;
    setState(() {
      _shown = _pending;
      _rendered = null;
    });
  }

  @override
  void didUpdateWidget(covariant SavedMetricGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      oldWidget.source.removeListener(_receive);
      widget.source.addListener(_receive);
    }
    if (oldWidget.source != widget.source ||
        oldWidget.viewKey != widget.viewKey ||
        oldWidget.metric != widget.metric) {
      _pending = widget.source.value;
      _shown = _pending;
      _rendered = null;
      _schedule();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.source.removeListener(_receive);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final points = widget.recentHour
        ? _shown
              .where(
                (p) =>
                    p['time'] is num &&
                    (p['time'] as num) > now - 3600000 &&
                    (p['time'] as num) <= now,
              )
              .toList()
        : _shown;
    return RepaintBoundary(
      child: _rendered ??= Column(
        children: [
          telemetryGraph(
            context,
            points,
            widget.metric,
            widget.label,
            widget.color,
            widget.transform,
          ),
          if (_temperature)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Graph updates once a minute',
                style: TextStyle(fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}
