import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'controller.dart';
import 'current_telemetry.dart';
import 'models.dart';

String currentLabel(double? value) => value == null
    ? 'Unavailable'
    : '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)} mA';

String currentTimeLabel(int time) {
  final date = DateTime.fromMillisecondsSinceEpoch(time);
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
}

/// Replaces only the Current graph panel. Its repaint boundary and notifier
/// isolate one-second chart updates from the surrounding telemetry screen.
class CurrentChart extends StatefulWidget {
  const CurrentChart({super.key, required this.c});
  final BatteryController c;
  @override
  State<CurrentChart> createState() => _CurrentChartState();
}

class _CurrentChartState extends State<CurrentChart> {
  CurrentRange range = CurrentRange.hour;
  final axis = StableCurrentAxis();
  int? selectedTime;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.c.setCurrentChartVisible(true);
    });
  }

  @override
  void dispose() {
    widget.c.setCurrentChartVisible(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ListenableBuilder(
      listenable: widget.c.currentTelemetry,
      builder: (context, _) {
        final model = widget.c.currentTelemetry;
        final frame = model.frame(range);
        final bounds = axis.update(frame);
        final current = frame.fresh ? frame.latest : null;
        final muted = Theme.of(context).colorScheme.onSurfaceVariant;
        final plot = frame.plot;
        final selectedIndex = plot.indexWhere(
          (sample) => sample?.time == selectedTime,
        );
        final latestIndex = plot.indexWhere(
          (sample) => sample != null && sample.time == frame.latestValid?.time,
        );
        final highlighted = selectedIndex >= 0 ? selectedIndex : latestIndex;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Battery current',
              style: TextStyle(fontSize: 12, color: mint),
            ),
            const SizedBox(height: 8),
            Semantics(
              label: 'Latest current ${currentLabel(current?.current)}',
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  currentLabel(current?.current),
                  key: const ValueKey('current-live-reading'),
                  style: TextStyle(
                    fontSize: current == null ? 26 : 36,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.8,
                    color: current == null ? muted : mint,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              current == null
                  ? (frame.latest == null
                        ? 'Waiting for battery telemetry'
                        : frame.latest!.current == null
                        ? 'Current sensor unavailable'
                        : 'Reading is stale · last sample ${currentTimeLabel(frame.latest!.time)}')
                  : '${current.power == null ? 'Power unavailable' : metric(current.power, 'W', decimals: 2)} · ${current.voltage == null ? 'Voltage unavailable' : metric(current.voltage, 'mV')}',
              style: TextStyle(fontSize: 12, height: 1.5, color: muted),
            ),
            const SizedBox(height: 3),
            Text(
              'Estimated battery-side power · positive charging, negative discharging',
              style: TextStyle(fontSize: 10, height: 1.5, color: muted),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                height: constraints.maxWidth < 280 ? 235 : 270,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, right: 20, bottom: 4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: frame.now / 1000.0),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        builder: (context, renderTime, _) {
                          final spots = [
                            for (final sample in plot)
                              sample == null
                                  ? FlSpot.nullSpot
                                  : FlSpot(
                                      sample.time / 1000.0 - renderTime,
                                      sample.current!,
                                    ),
                          ];
                          final bar = LineChartBarData(
                            spots: spots,
                            isCurved: false,
                            color: mint,
                            barWidth: 1.8,
                            isStrokeCapRound: true,
                            dotData: FlDotData(
                              show: true,
                              checkToShowDot: (spot, data) =>
                                  highlighted >= 0 &&
                                  spot.x == spots[highlighted].x &&
                                  spot.y == spots[highlighted].y,
                              getDotPainter: (spot, percent, data, index) =>
                                  FlDotCirclePainter(
                                    radius: 4,
                                    color: mint,
                                    strokeWidth: 1.5,
                                    strokeColor: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                  ),
                            ),
                            belowBarData: BarAreaData(show: false),
                          );
                          return LineChart(
                            LineChartData(
                              minX: -range.seconds.toDouble(),
                              maxX: 0,
                              minY: bounds.minimum,
                              maxY: bounds.maximum,
                              backgroundColor: Colors.transparent,
                              // Only in-window samples are supplied; outer padding leaves
                              // room for the endpoint dot without extending the time axis.
                              clipData: const FlClipData.none(),
                              borderData: FlBorderData(show: false),
                              gridData: FlGridData(
                                show: true,
                                horizontalInterval: bounds.interval,
                                verticalInterval: _timeInterval,
                                getDrawingHorizontalLine: (value) => FlLine(
                                  color: muted.withValues(
                                    alpha: value == 0 ? .25 : .12,
                                  ),
                                  strokeWidth: .7,
                                  dashArray: [3, 5],
                                ),
                                getDrawingVerticalLine: (value) => FlLine(
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
                                    interval: bounds.interval,
                                    getTitlesWidget: (value, meta) => Padding(
                                      padding: const EdgeInsets.only(right: 7),
                                      child: Text(
                                        _axisLabel(value),
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: muted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 28,
                                    interval: _timeInterval,
                                    getTitlesWidget: (value, meta) =>
                                        SideTitleWidget(
                                          meta: meta,
                                          space: 8,
                                          child: Text(
                                            _elapsedLabel(value),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: muted,
                                            ),
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                              lineBarsData: [bar],
                              extraLinesData: ExtraLinesData(
                                verticalLines: selectedIndex < 0
                                    ? []
                                    : [
                                        VerticalLine(
                                          x: spots[selectedIndex].x,
                                          color: mint.withValues(alpha: .3),
                                          strokeWidth: 1,
                                          dashArray: [3, 5],
                                        ),
                                      ],
                              ),
                              showingTooltipIndicators: highlighted < 0
                                  ? []
                                  : [
                                      ShowingTooltipIndicators([
                                        LineBarSpot(bar, 0, spots[highlighted]),
                                      ]),
                                    ],
                              lineTouchData: LineTouchData(
                                enabled: true,
                                handleBuiltInTouches: false,
                                touchSpotThreshold: 24,
                                touchCallback: (event, response) {
                                  int? next;
                                  if (event.isInterestedForInteractions &&
                                      event is! FlTapUpEvent &&
                                      event is! FlPanEndEvent) {
                                    final touched = response?.lineBarSpots;
                                    if (touched != null && touched.isNotEmpty) {
                                      final index = touched.first.spotIndex;
                                      if (index >= 0 && index < plot.length) {
                                        next = plot[index]?.time;
                                      }
                                    }
                                  }
                                  if (next != selectedTime) {
                                    setState(() => selectedTime = next);
                                  }
                                },
                                touchTooltipData: LineTouchTooltipData(
                                  fitInsideHorizontally: true,
                                  fitInsideVertically: true,
                                  maxContentWidth: 110,
                                  tooltipMargin: 8,
                                  tooltipPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  tooltipBorderRadius: BorderRadius.circular(8),
                                  getTooltipColor: (_) => Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  getTooltipItems: (touched) => touched.map((
                                    spot,
                                  ) {
                                    final sample = plot[spot.spotIndex]!;
                                    return LineTooltipItem(
                                      '${currentLabel(sample.current)}\n${currentTimeLabel(sample.time)}',
                                      const TextStyle(
                                        color: mint,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            // Animate the time viewport, never interpolate current values
                            // or morph across gaps when samples/buckets are added.
                            duration: Duration.zero,
                          );
                        },
                      ),
                      if (frame.count == 0)
                        Center(
                          child: IgnorePointer(
                            child: Text(
                              'No recorded current in this range',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: mint,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  'Electric current',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final option in CurrentRange.values) ...[
                  if (option != CurrentRange.values.first)
                    const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      key: ValueKey('current-range-${option.label}'),
                      onPressed: () {
                        if (range != option) {
                          setState(() {
                            range = option;
                            selectedTime = null;
                            axis.reset();
                          });
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 40),
                        backgroundColor: range == option
                            ? mint.withValues(alpha: .15)
                            : Colors.transparent,
                        side: BorderSide(
                          color: range == option
                              ? mint
                              : muted.withValues(alpha: .35),
                        ),
                      ),
                      child: Text(
                        option.label,
                        style: TextStyle(color: range == option ? mint : muted),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _stat('Average', frame.average),
                  _stat('Minimum', frame.minimum),
                  _stat('Maximum', frame.maximum),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              model.error ??
                  (model.loading
                      ? 'Loading recorded measurements…'
                      : '${frame.count} measured samples · gaps are unrecorded time. Average uses the original readings.'),
              style: TextStyle(
                fontSize: 10,
                height: 1.5,
                color: model.error == null ? muted : coral,
              ),
            ),
          ],
        );
      },
    ),
  );
  Widget _stat(String title, double? value) => Expanded(
    child: Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value == null ? '—' : currentLabel(value),
            key: ValueKey('current-stat-${title.toLowerCase()}'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  double get _timeInterval => switch (range) {
    CurrentRange.minute => 10,
    CurrentRange.tenMinutes => 120,
    CurrentRange.hour => 600,
    CurrentRange.sixHours => 3600,
  };
  String _elapsedLabel(double value) {
    final seconds = value.abs().round();
    if (seconds == 0) return 'Now';
    return range == CurrentRange.minute
        ? '${seconds}s'
        : range == CurrentRange.sixHours
        ? '${seconds ~/ 3600}h'
        : '${seconds ~/ 60}m';
  }

  String _axisLabel(double value) {
    if (value.abs() >= 10000) {
      return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k mA';
    }
    return currentLabel(value);
  }
}
