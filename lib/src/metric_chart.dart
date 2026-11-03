part of 'app.dart';

/// Shared saved-reading chart for telemetry and monitor reports.
class MetricChart extends StatelessWidget {
  const MetricChart({
    super.key,
    required this.points,
    required this.metric,
    required this.label,
    required this.color,
    required this.transform,
  });
  final List<Map<String, dynamic>> points;
  final String metric, label;
  final Color color;
  final double Function(double) transform;

  @override
  Widget build(BuildContext context) {
    final timed =
        points
            .where((p) => p['time'] is num && (p['time'] as num).isFinite)
            .toList()
          ..sort((a, b) => (a['time'] as num).compareTo(b['time'] as num));
    final first = timed.isEmpty ? 0 : (timed.first['time'] as num).toDouble();
    final last = timed.isEmpty ? first : (timed.last['time'] as num).toDouble();
    final span = math.max(1.0, (last - first) / 1000);
    final spots = <FlSpot>[];
    final values = <double>[];
    Map<String, dynamic>? previous;
    for (final point in timed) {
      final raw = point[metric];
      final value = raw is num && raw.isFinite
          ? transform(raw.toDouble())
          : null;
      if (value == null || !value.isFinite) {
        if (spots.isNotEmpty && !spots.last.isNull()) {
          spots.add(FlSpot.nullSpot);
        }
        previous = null;
        continue;
      }
      final gap =
          previous != null &&
          (point['gapBefore'] == true ||
              point['gapBefore'] == 1 ||
              point['sessionId'] != previous['sessionId'] ||
              point['monitorPoint'] != true &&
                  (point['time'] as num) - (previous['time'] as num) > 120000);
      if (gap && spots.isNotEmpty && !spots.last.isNull()) {
        spots.add(FlSpot.nullSpot);
      }
      spots.add(FlSpot(((point['time'] as num) - first) / 1000, value));
      values.add(value);
      previous = point;
    }
    final minimum = values.isEmpty ? 0.0 : values.reduce(math.min);
    final maximum = values.isEmpty ? 1.0 : values.reduce(math.max);
    final padding = math.max(
      (maximum - minimum) * .1,
      math.max(maximum.abs() * .01, .05),
    );
    final roughStep = (maximum - minimum + padding * 2) / 4;
    final magnitude = math
        .pow(10, (math.log(roughStep) / math.ln10).floor())
        .toDouble();
    final fraction = roughStep / magnitude;
    final step =
        (fraction <= 1
            ? 1
            : fraction <= 2
            ? 2
            : fraction <= 5
            ? 5
            : 10) *
        magnitude;
    final low = ((minimum - padding) / step).floor() * step;
    final high = ((maximum + padding) / step).ceil() * step;
    final decimals = math.max(
      0,
      math.min(4, -(math.log(step) / math.ln10).floor()),
    );
    final unit = label.contains(' · ') ? label.split(' · ').last : '';
    final precision = metric == 'powerW' || metric == 'voltageMv' && unit == 'V'
        ? 2
        : 1;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final isolated = <FlSpot>{};
    for (var i = 0; i < spots.length; i++) {
      if (!spots[i].isNull() &&
          (i == 0 || spots[i - 1].isNull()) &&
          (i == spots.length - 1 || spots[i + 1].isNull())) {
        isolated.add(spots[i]);
      }
    }
    String axisLabel(double v) => v.abs() >= 10000
        ? '${(v / 1000).toStringAsFixed(1)}k'
        : (v.abs() < step * .001 ? 0.0 : v).toStringAsFixed(decimals);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 12, color: color)),
            ),
            Text(
              values.isEmpty
                  ? 'Unavailable'
                  : '${minimum.toStringAsFixed(precision)} – ${maximum.toStringAsFixed(precision)}',
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (values.isEmpty)
          const SizedBox(
            height: 150,
            child: Center(
              child: Text(
                'Collecting supported readings…',
                style: TextStyle(fontSize: 11),
              ),
            ),
          )
        else ...[
          SizedBox(
            height: 230,
            child: Padding(
              padding: const EdgeInsets.only(top: 12, right: 20, bottom: 4),
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: span,
                  minY: low,
                  maxY: high,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    horizontalInterval: step,
                    verticalInterval: span / 2,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: muted.withValues(alpha: .12),
                      strokeWidth: .7,
                      dashArray: [3, 5],
                    ),
                    getDrawingVerticalLine: (_) => FlLine(
                      color: muted.withValues(alpha: .12),
                      strokeWidth: .7,
                      dashArray: [3, 5],
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 62,
                        interval: step,
                        getTitlesWidget: (value, meta) => Padding(
                          padding: const EdgeInsets.only(right: 7),
                          child: Text(
                            axisLabel(value),
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 10, color: muted),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: span / 2,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          space: 8,
                          child: Text(
                            span < 120
                                ? clockLabel(first + value * 1000)
                                : clockLabel(
                                    first + value * 1000,
                                  ).substring(0, 5),
                            style: TextStyle(fontSize: 10, color: muted),
                          ),
                        ),
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      color: color,
                      barWidth: 1.8,
                      isCurved: false,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        checkToShowDot: (spot, _) =>
                            isolated.contains(spot) || spot == spots.last,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                              radius: 3,
                              color: color,
                              strokeWidth: 1,
                              strokeColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                            ),
                      ),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchSpotThreshold: 24,
                    touchTooltipData: LineTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      maxContentWidth: 130,
                      tooltipBorderRadius: BorderRadius.circular(8),
                      tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      getTooltipColor: (_) =>
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      getTooltipItems: (touched) => touched
                          .map(
                            (spot) => LineTooltipItem(
                              '${spot.y.toStringAsFixed(precision)}${unit.isEmpty ? '' : ' $unit'}\n${clockLabel(first + spot.x * 1000)}',
                              TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                duration: Duration.zero,
              ),
            ),
          ),
          Text(
            'Touch and drag to inspect readings${unit.isEmpty ? '' : ' · $unit'}',
            style: TextStyle(fontSize: 10, color: muted),
          ),
        ],
      ],
    );
  }
}
