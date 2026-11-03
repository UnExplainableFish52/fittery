import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'charging_estimate.dart';
import 'models.dart';

/// Uses the existing readings stream. Opening this view never enables recording.
class ChargingDashboardEntry extends StatelessWidget {
  const ChargingDashboardEntry({
    super.key,
    required this.c,
    this.compact = false,
  });
  final BatteryController c;
  final bool compact;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => OutlinedButton.icon(
      key: const ValueKey('open-charging-dashboard'),
      onPressed:
          c.flag('chargingDashboard') &&
              c.reading?.plugged == true &&
              !c.chargingDashboardVisible
          ? () => showChargingDashboard(context, c)
          : null,
      icon: const Icon(Icons.battery_charging_full_rounded),
      label: Text(
        compact
            ? 'Fullscreen Dashboard'
            : c.reading?.plugged == true
            ? 'Open charging dashboard'
            : 'Connect a charger to open dashboard',
        textAlign: TextAlign.center,
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        side: BorderSide(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .38),
        ),
        textStyle: const TextStyle(fontSize: 13, height: 1.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

Future<void> showChargingDashboard(
  BuildContext context,
  BatteryController c,
) async {
  if (!c.flag('chargingDashboard') ||
      c.reading?.plugged != true ||
      c.chargingDashboardVisible) {
    return;
  }
  c.setChargingDashboardVisible(true);
  try {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/charging-dashboard'),
        builder: (_) => ChargingDashboardPage(c: c),
      ),
    );
  } finally {
    c.setChargingDashboardVisible(false);
  }
}

class ChargingDashboardPage extends StatefulWidget {
  const ChargingDashboardPage({
    super.key,
    required this.c,
    this.isDream = false,
  });
  final BatteryController c;
  final bool isDream;

  @override
  State<ChargingDashboardPage> createState() => _ChargingDashboardPageState();
}

class _ChargingDashboardPageState extends State<ChargingDashboardPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _orbit;
  bool _closing = false, _canPop = false, _active = true;
  bool _nativeReady = false;
  String? _error;
  double _slide = 0;
  Animation<double>? _entrance;
  final _estimate = ChargingEstimate();

  @override
  void initState() {
    super.initState();
    _estimate.observe(widget.c.reading, widget.c.settings);
    _active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
    WidgetsBinding.instance.addObserver(this);
    widget.c.addListener(_readingChanged);
    // Wait for the opaque route to finish entering, so the underlying app
    // cannot become visible above keyguard during the navigation transition.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closing) return;
      if (widget.isDream) {
        _readingChanged();
        return;
      }
      _entrance = ModalRoute.of(context)?.animation;
      if (_entrance != null && !_entrance!.isCompleted) {
        _entrance!.addStatusListener(_entranceChanged);
      } else {
        unawaited(_enableLockScreen());
      }
    });
  }

  void _entranceChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _entrance?.removeStatusListener(_entranceChanged);
    _entrance = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closing) unawaited(_enableLockScreen());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _enableLockScreen() async {
    if (!mounted || _closing) return;
    try {
      await BatteryController.channel.invokeMethod<void>(
        'chargingDashboardVisible',
        true,
      );
      if (mounted) {
        _nativeReady = true;
        _readingChanged();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Lock-screen display is unavailable. You can still view readings here.',
        );
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _syncAnimation();
  }

  void _syncAnimation() {
    if (!mounted) return;
    final level = widget.c.reading?.number('level');
    final animate =
        _active &&
        !_closing &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        widget.c.reading?.charging == true &&
        widget.c.reading?.plugged == true &&
        level != null &&
        level.isFinite &&
        level > 0 &&
        level <= 100;
    if (animate && !_orbit.isAnimating) _orbit.repeat();
    if (!animate && _orbit.isAnimating) _orbit.stop();
  }

  void _readingChanged() {
    if (!mounted) return;
    _estimate.observe(widget.c.reading, widget.c.settings);
    if (!widget.c.flag('chargingDashboard') ||
        (widget.isDream && !widget.c.flag('chargingScreenSaver')) ||
        widget.c.reading?.plugged != true) {
      // Defer navigation out of a controller notification/build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_close());
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    _syncAnimation();
    setState(() {});
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _orbit.stop();
    if (widget.isDream) {
      try {
        await BatteryController.channel.invokeMethod<void>('finishDream');
      } catch (_) {
        if (mounted) {
          setState(() {
            _closing = false;
            _error = 'Could not close the screen saver. Please try again.';
          });
        }
      }
      return;
    }
    try {
      // Clear Android visibility before allowing any ordinary app UI to return.
      await BatteryController.channel.invokeMethod<void>(
        'chargingDashboardVisible',
        false,
      );
    } catch (_) {
      if (_nativeReady) {
        if (mounted) {
          setState(() {
            _closing = false;
            _error = 'Could not close the dashboard. Please try again.';
          });
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.c.removeListener(_readingChanged);
    _entrance?.removeStatusListener(_entranceChanged);
    _orbit.dispose();
    // Also cover programmatic route removal. Native destruction clears it too.
    if (!_canPop && !widget.isDream) {
      unawaited(
        BatteryController.channel
            .invokeMethod<void>('chargingDashboardVisible', false)
            .catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final r = c.reading;
    final dual = c.flag('dualCell');
    final voltage = _finite(r?.voltage(dual));
    final current = _finite(r?.current);
    final temperature = _finite(r?.number('temperatureC'));
    final level = r?.number('level');
    final validLevel =
        level != null && level.isFinite && level >= 0 && level <= 100
        ? level.toInt()
        : null;
    final stats = <(IconData, String, String, String)>[
      (
        Icons.swap_vert_rounded,
        'Current',
        metric(current, 'mA', signed: true),
        r?.data['currentNote'] as String? ?? 'Signed net battery current',
      ),
      (
        Icons.bolt_rounded,
        dual ? 'Power · calc. 2×' : 'Power · calc.',
        metric(
          voltage == null || current == null
              ? null
              : voltage * current / 1000000,
          'W',
          decimals: 2,
          signed: true,
        ),
        dual
            ? 'Calculated battery power, dual-cell adjustment'
            : 'Calculated battery power',
      ),
      (
        Icons.schedule_rounded,
        'Est. to ${_estimate.target}%',
        _estimate.minutes == null ? '—' : '~${_estimate.minutes} m',
        _estimate.reason,
      ),
      (
        Icons.thermostat_outlined,
        'Temperature',
        metric(
          temperature == null
              ? null
              : c.flag('fahrenheit')
              ? temperature * 1.8 + 32
              : temperature,
          c.flag('fahrenheit') ? '°F' : '°C',
          decimals: 1,
        ),
        'Battery temperature',
      ),
    ];
    const scheme = ColorScheme.dark(
      primary: _teal,
      surface: Color(0xFF060912),
      onSurface: Color(0xFFF1F7FF),
      onSurfaceVariant: _muted,
    );
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(colorScheme: scheme),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: PopScope(
          canPop: _canPop,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_close());
          },
          child: Scaffold(
            key: const ValueKey('charging-dashboard'),
            backgroundColor: scheme.surface,
            body: Stack(
              fit: StackFit.expand,
              children: [
                const RepaintBoundary(child: _DashboardBackground()),
                SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 940),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                        child: Column(
                          children: [
                            _DashboardHeader(onClose: _close),
                            const SizedBox(height: 4),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, box) {
                                  final scale = MediaQuery.textScalerOf(
                                    context,
                                  );
                                  final single = scale.scale(12) > 20;
                                  // Reserve two label lines and a complete value line.
                                  // Large accessibility fonts can scroll the body; exit
                                  // controls remain visible and keep their touch size.
                                  final cardHeight =
                                      24 +
                                      scale.scale(12) * 2.5 +
                                      8 +
                                      scale.scale(24) * 1.2;
                                  final gridHeight =
                                      (single ? 4 : 2) * cardHeight +
                                      (single ? 30 : 10);
                                  final clockHeight = scale.scale(20) * 1.3;
                                  final error = _error ?? c.error;
                                  final extraHeight = error == null
                                      ? 0.0
                                      : scale.scale(12) * 5 + 12;
                                  Widget metrics() => _DashboardMetrics(
                                    stats: stats,
                                    single: single,
                                    cardHeight: cardHeight,
                                  );
                                  Widget hero({required double ringSize}) =>
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _batteryRing(
                                            ringSize,
                                            validLevel,
                                            r?.charging == true,
                                          ),
                                          const SizedBox(height: 10),
                                          const _DashboardClock(),
                                          if (error != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 10,
                                              ),
                                              child: Text(
                                                error,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: coral,
                                                  fontSize: 12,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                        ],
                                      );
                                  final wide =
                                      box.maxWidth >= 620 &&
                                      box.maxWidth > box.maxHeight * 1.25 &&
                                      !single;
                                  if (wide &&
                                      box.maxHeight >=
                                          math.max(
                                            gridHeight,
                                            160 +
                                                clockHeight +
                                                10 +
                                                extraHeight,
                                          )) {
                                    return Row(
                                      children: [
                                        Expanded(
                                          child: Center(
                                            child: hero(
                                              ringSize: math.min(
                                                300,
                                                math.min(
                                                  box.maxWidth * .44,
                                                  box.maxHeight -
                                                      clockHeight -
                                                      10 -
                                                      extraHeight,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 28),
                                        Expanded(
                                          child: Center(child: metrics()),
                                        ),
                                      ],
                                    );
                                  }
                                  final remaining =
                                      box.maxHeight -
                                      gridHeight -
                                      clockHeight -
                                      26 -
                                      extraHeight;
                                  if (remaining >= 160) {
                                    return Column(
                                      children: [
                                        Expanded(
                                          child: Center(
                                            child: hero(
                                              ringSize: math.min(
                                                300,
                                                math.min(
                                                  box.maxWidth,
                                                  remaining,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        metrics(),
                                      ],
                                    );
                                  }
                                  return SingleChildScrollView(
                                    key: const ValueKey(
                                      'charging-dashboard-overflow',
                                    ),
                                    child: Column(
                                      children: [
                                        hero(
                                          ringSize: math.min(box.maxWidth, 180),
                                        ),
                                        const SizedBox(height: 16),
                                        metrics(),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            _ConnectionCaption(reading: r),
                            const SizedBox(height: 10),
                            _dismissSlider(context),
                            const SizedBox(height: 7),
                            Text(
                              'v${r?.data['appVersion'] ?? c.appInfo['version'] ?? '—'} · build ${r?.data['appBuild'] ?? c.appInfo['build'] ?? '—'}',
                              key: const ValueKey('charging-dashboard-version'),
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 10,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _batteryRing(double size, int? level, bool charging) =>
      SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned.fill(child: RepaintBoundary(child: _EnergyCore())),
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('charging-dashboard-track'),
                  painter: _ChargeRingBase(level == null ? 0 : level / 100),
                ),
              ),
            ),
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('charging-dashboard-ring'),
                  painter: _ChargeRing(
                    _orbit,
                    charging,
                    level == null ? 0 : level / 100,
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(size * .19),
              child: Semantics(
                label: level == null
                    ? 'Battery percentage unavailable'
                    : 'Battery $level percent',
                value: widget.c.reading?.text('status'),
                excludeSemantics: true,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    level == null ? '—' : '$level%',
                    style: TextStyle(
                      fontSize: size * .235,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                      letterSpacing: -2,
                      height: 1.1,
                      shadows: const [
                        Shadow(color: Color(0x5565DCFF), blurRadius: 12),
                      ],
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _dismissSlider(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final travel = math.max(1.0, box.maxWidth - 56);
      return Semantics(
        label: 'Dismiss charging dashboard',
        button: true,
        onTap: _close,
        child: ExcludeSemantics(
          child: GestureDetector(
            key: const ValueKey('charging-dashboard-slide'),
            onHorizontalDragUpdate: _closing
                ? null
                : (details) => setState(
                    () => _slide = (_slide + details.delta.dx / travel).clamp(
                      0,
                      1,
                    ),
                  ),
            onHorizontalDragEnd: (_) {
              if (_slide >= .75) {
                unawaited(_close());
              } else {
                setState(() => _slide = 0);
              }
            },
            onHorizontalDragCancel: () => setState(() => _slide = 0),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              decoration: ShapeDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xF0122330), Color(0xF00A101E)],
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                  side: BorderSide(color: _cyan.withValues(alpha: .55)),
                ),
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(60, 17, 16, 17),
                    child: Center(
                      child: Text(
                        _closing ? 'Closing…' : 'Slide to dismiss',
                        style: const TextStyle(
                          color: Color(0xFFCDDFE2),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    transform: Matrix4.translationValues(_slide * travel, 0, 0),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      width: 48,
                      height: 48,
                      decoration: const ShapeDecoration(
                        gradient: LinearGradient(colors: [_cyan, _teal]),
                        shape: CircleBorder(),
                      ),
                      child: AnimatedRotation(
                        turns: _slide * .25,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF07151F),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

const _teal = Color(0xFF5CF2CE);
const _cyan = Color(0xFF65DCFF);
const _muted = Color(0xFFAABBCF);

String _clock(DateTime time) =>
    '${time.hour % 12 == 0 ? 12 : time.hour % 12}:${time.minute.toString().padLeft(2, '0')} ${time.hour < 12 ? 'AM' : 'PM'}';

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.onClose});
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.height < 500 && screen.width > screen.height;
    return Row(
      children: [
        const SizedBox(width: 48),
        Expanded(
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 235,
                maxHeight: compact ? 48 : 68,
              ),
              child: AspectRatio(
                aspectRatio: 492 / 167,
                child: Semantics(
                  key: const ValueKey('charging-dashboard-brand'),
                  label: 'Fittery',
                  image: true,
                  child: const RepaintBoundary(
                    child: _ArtworkSlice(
                      region: Rect.fromLTRB(238, 30, 730, 197),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Close charging dashboard',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
          color: _muted,
        ),
      ],
    );
  }
}

class _DashboardClock extends StatelessWidget {
  const _DashboardClock();
  @override
  Widget build(BuildContext context) => Text(
    // Reuse reading updates for this minute clock; no separate timer runs.
    _clock(DateTime.now()),
    key: const ValueKey('charging-dashboard-clock'),
    textAlign: TextAlign.center,
    style: const TextStyle(
      fontSize: 20,
      height: 1.3,
      fontWeight: FontWeight.w500,
      letterSpacing: .8,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  );
}

class _ConnectionCaption extends StatelessWidget {
  const _ConnectionCaption({this.reading});
  final Reading? reading;
  @override
  Widget build(BuildContext context) {
    final at = reading?.number('chargeConnectedAt');
    final elapsed = reading?.number('chargeConnectedDurationMs');
    final known = reading?.data['chargeConnectionConfirmed'] == true;
    final label = at == null || !at.isFinite || at <= 0
        ? 'Connection time unavailable'
        : '${known ? 'Connected' : 'Tracking since'} ${_clock(DateTime.fromMillisecondsSinceEpoch(at.toInt()))}'
              '${elapsed != null && elapsed.isFinite && elapsed >= 0 ? ' · ${elapsed ~/ 60000} m' : ''}';
    return Text(
      label,
      key: const ValueKey('charging-dashboard-connected'),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 11, height: 1.3, color: _muted),
    );
  }
}

double? _finite(num? value) =>
    value != null && value.isFinite ? value.toDouble() : null;

/// A single decoded, static asset; no blur filter or animated wallpaper layer.
class _DashboardBackground extends StatelessWidget {
  const _DashboardBackground();
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/charging/teal_waves_v1.webp',
        // Only the peripheral environment is in the bitmap. Keep its edge
        // lighting visible while the live UI follows its own responsive layout.
        fit: BoxFit.cover,
        cacheWidth: 720,
        filterQuality: FilterQuality.low,
        excludeFromSemantics: true,
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x08040913), Color(0x18040913), Color(0x66040913)],
          ),
        ),
      ),
    ],
  );
}

/// Displays an unmodified region of the user's artwork. All slices share the
/// same cached decoded image; no image processing or polling runs per frame.
class _ArtworkSlice extends StatefulWidget {
  const _ArtworkSlice({required this.region});
  final Rect region;
  @override
  State<_ArtworkSlice> createState() => _ArtworkSliceState();
}

class _ArtworkSliceState extends State<_ArtworkSlice> {
  static const _provider = AssetImage(
    'assets/charging/proposal_brand_source_v1.webp',
  );
  ImageStream? _stream;
  ImageInfo? _info;
  late final _listener = ImageStreamListener(_accept);
  void _accept(ImageInfo info, bool synchronous) {
    if (!mounted) {
      info.dispose();
      return;
    }
    final previous = _info;
    if (synchronous) {
      _info = info;
    } else {
      setState(() => _info = info);
    }
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final stream = _provider.resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    _stream?.removeListener(_listener);
    _stream = stream;
    stream.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ArtworkSlicePainter(_info?.image, widget.region));
}

class _ArtworkSlicePainter extends CustomPainter {
  const _ArtworkSlicePainter(this.artwork, this.region);
  final ui.Image? artwork;
  final Rect region;
  @override
  void paint(Canvas canvas, Size size) {
    final image = artwork;
    if (image == null) return;
    final source = Rect.fromLTRB(
      region.left * image.width / 941,
      region.top * image.height / 1672,
      region.right * image.width / 941,
      region.bottom * image.height / 1672,
    );
    canvas.drawImageRect(
      image,
      source,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_ArtworkSlicePainter oldDelegate) =>
      artwork != oldDelegate.artwork || region != oldDelegate.region;
}

class _DashboardMetrics extends StatelessWidget {
  const _DashboardMetrics({
    required this.stats,
    required this.single,
    required this.cardHeight,
  });
  final List<(IconData, String, String, String)> stats;
  final bool single;
  final double cardHeight;
  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('charging-dashboard-metrics'),
    spacing: 10,
    children: [
      if (single)
        for (final stat in stats)
          SizedBox(
            height: cardHeight,
            width: double.infinity,
            child: _StatCard(stat),
          )
      else
        for (var i = 0; i < stats.length; i += 2)
          SizedBox(
            height: cardHeight,
            child: Row(
              children: [
                Expanded(child: _StatCard(stats[i])),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(stats[i + 1])),
              ],
            ),
          ),
    ],
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.stat);
  final (IconData, String, String, String) stat;
  @override
  Widget build(BuildContext context) {
    final accent = switch (stat.$1) {
      Icons.bolt_rounded => _cyan,
      Icons.schedule_rounded => const Color(0xFFA4B8FF),
      Icons.thermostat_outlined => const Color(0xFFFFCE80),
      _ => _teal,
    };
    return Tooltip(
      message: stat.$4,
      child: Semantics(
        label: '${stat.$4}: ${stat.$3}',
        excludeSemantics: true,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xDE123545), Color(0xEB061C2B)],
            ),
            border: Border.all(color: accent.withValues(alpha: .32)),
          ),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(stat.$1, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      stat.$2,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      stat.$3,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 24,
                        fontFamily: 'monospace',
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Static glass-wave texture behind the percentage, decoded once and isolated
/// from the animated progress layer. There is no opaque central hole.
class _EnergyCore extends StatelessWidget {
  const _EnergyCore();
  @override
  Widget build(BuildContext context) => Center(
    child: FractionallySizedBox(
      widthFactor: .77,
      heightFactor: .77,
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/charging/teal_core_v2.webp',
              key: const ValueKey('charging-dashboard-core-art'),
              fit: BoxFit.cover,
              cacheWidth: 512,
              filterQuality: FilterQuality.low,
              excludeFromSemantics: true,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x12031420), Color(0x30031420)],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ChargeRingBase extends CustomPainter {
  _ChargeRingBase(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 21;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final thickness = (size.shortestSide * .04).clamp(7.0, 13.0);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(
      center,
      radius + 12,
      line
        ..strokeWidth = .8
        ..color = _cyan.withValues(alpha: .24),
    );
    canvas.drawCircle(
      center,
      radius - 15,
      line
        ..strokeWidth = .8
        ..color = _teal.withValues(alpha: .24),
    );
    for (var i = 0; i < 80; i++) {
      final angle = i * math.pi / 40;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * (radius - 10),
        center + direction * (radius - 8),
        Paint()
          ..strokeWidth = .8
          ..color = _cyan.withValues(alpha: .36),
      );
    }
    canvas.drawCircle(
      center,
      radius,
      line
        ..strokeWidth = thickness
        ..color = const Color(0xFF10313C),
    );
    if (progress <= 0) return;
    final sweep = 2 * math.pi * progress;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = thickness + 8
        ..color = _teal.withValues(alpha: .2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = thickness + 2
        ..color = _teal.withValues(alpha: .45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    line
      ..strokeWidth = thickness
      ..shader = const SweepGradient(
        colors: [Color(0xFFA0FF99), _teal, _cyan, Color(0xFF51DBFF)],
        stops: [0, .25, .75, 1],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, line);
  }

  @override
  bool shouldRepaint(_ChargeRingBase oldDelegate) =>
      progress != oldDelegate.progress;
}

/// The light glint travels only inside the measured filled arc. It never
/// illuminates an uncharged region or paints a charge indication at zero.
class _ChargeRing extends CustomPainter {
  _ChargeRing(this.animation, this.charging, this.progress)
    : super(repaint: animation);
  final Animation<double> animation;
  final bool charging;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    if (!charging || progress <= 0) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 21;
    final phase = animation.value * 2 * math.pi * progress;
    final trail = math.min(.3, phase);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final pulse = (math.sin(animation.value * math.pi * 4) + 1) / 2;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8 + pulse * 4
        ..strokeCap = StrokeCap.round
        ..color = _teal.withValues(alpha: .035 + pulse * .035),
    );
    // A small fixed particle set, painted directly inside this boundary.
    // These decorative sparks are separate from the measured progress arc.
    for (var i = 0; i < 12; i++) {
      final angle = animation.value * math.pi * 2 + i * math.pi * 2 / 12;
      final orbit = radius + 7 + math.sin(angle * 2 + i) * 5;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * orbit;
      final opacity = .25 + .45 * (math.sin(angle + i) + 1) / 2;
      canvas.drawCircle(
        point,
        i.isEven ? 1.4 : .9,
        Paint()
          ..color = (i % 3 == 0 ? _cyan : _teal).withValues(alpha: opacity),
      );
      canvas.drawCircle(
        point,
        3.2,
        Paint()..color = _teal.withValues(alpha: opacity * .1),
      );
    }
    canvas.drawArc(
      rect,
      -math.pi / 2 + phase - trail,
      trail,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x99C8FFF5),
    );
    final angle = phase - math.pi / 2;
    canvas.drawCircle(
      center + Offset(math.cos(angle), math.sin(angle)) * radius,
      2.2,
      Paint()..color = const Color(0xFFE4FFFB),
    );
  }

  @override
  bool shouldRepaint(_ChargeRing oldDelegate) =>
      charging != oldDelegate.charging ||
      animation != oldDelegate.animation ||
      progress != oldDelegate.progress;
}
