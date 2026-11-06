import 'decision_dialog.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'controller.dart';
import 'models.dart';
import 'threshold_control.dart';
import 'about_section.dart';
import 'current_chart.dart';
import 'onboarding.dart';
import 'charging_dashboard.dart';
import 'smooth_toggle.dart';

part 'monitor_history.dart';
part 'saved_metric_graph.dart';
part 'metric_chart.dart';

class FitteryApp extends StatefulWidget {
  const FitteryApp({super.key, this.controller});
  final BatteryController? controller;
  @override
  State<FitteryApp> createState() => _FitteryAppState();
}

class _FitteryAppState extends State<FitteryApp> with WidgetsBindingObserver {
  late final BatteryController controller;
  int index = 0;
  bool _animateTab = false;
  final _navigator = GlobalKey<NavigatorState>();
  bool _showingSessionPrompt = false, _showingSettingsIntro = false;
  bool _launchResolved = false, _showWelcome = false;
  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? BatteryController();
    controller.addListener(_controllerChanged);
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller == null) unawaited(controller.initialize());
    _resolveLaunch();
    _checkSessionPrompt();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_controllerChanged);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.setAppActive(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      _checkSessionPrompt();
      _checkSettingsIntro();
    }
  }

  void _checkSessionPrompt() {
    if (!mounted ||
        !_launchResolved ||
        _showWelcome ||
        controller.onboardingVisible ||
        controller.chargingDashboardVisible ||
        _showingSessionPrompt ||
        _showingSettingsIntro ||
        !controller.appActive ||
        controller.sessionPrompt == null) {
      return;
    }
    _showingSessionPrompt = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final prompt = controller.sessionPrompt;
        final context = _navigator.currentContext;
        if (!mounted ||
            context == null ||
            prompt == null ||
            !controller.appActive) {
          return;
        }
        await controller.dismissSessionPrompt(prompt['token'] as num);
        if (!context.mounted) return;
        final enable = prompt['kind'] == 'enableMonitor';
        if (enable &&
            (controller.monitoring ||
                controller.reading?.number('plugged') == 0)) {
          return;
        }
        final open =
            prompt['kind'] == 'openReport' ||
            await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => DecisionDialog(
                    title: Text(
                      enable
                          ? 'Record this charging session?'
                          : 'Your charging report is ready',
                    ),
                    content: Text(
                      enable
                          ? 'Monitor mode is off. Enable it to save readings and graphs from now until you stop monitoring.'
                          : 'Your charger is disconnected and your readings are saved. View the charging graphs in your monitor recording. Monitor mode stays on.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Later'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: Text(
                          enable ? 'Enable monitor mode' : 'View report',
                        ),
                      ),
                    ],
                  ),
                ) ==
                true;
        if (!mounted || !context.mounted || !open) return;
        if (enable) {
          if (controller.monitoring ||
              controller.reading?.number('plugged') == 0) {
            return;
          }
          await runAction(context, () => controller.setMonitoring(true));
        } else {
          unawaited(
            _navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => MonitorRecordingPage(
                  c: controller,
                  id: (prompt['recordingId'] as num).toInt(),
                  chargingSince: (prompt['startTime'] as num).toInt(),
                  chargingUntil: (prompt['endTime'] as num).toInt(),
                ),
              ),
            ),
          );
        }
      } catch (e) {
        final context = _navigator.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text(
                'Could not open the charging prompt. Try again from History.',
              ),
            ),
          );
        }
      } finally {
        _showingSessionPrompt = false;
        if (mounted) {
          _checkSessionPrompt();
          _checkSettingsIntro();
        }
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _checkSettingsIntro() {
    if (!mounted ||
        index != 2 ||
        !controller.ready ||
        _showWelcome ||
        !controller.appActive ||
        _showingSessionPrompt ||
        _showingSettingsIntro ||
        controller.onboardingVisible ||
        controller.chargingDashboardVisible ||
        (controller.settingsIntroAcknowledged &&
            controller.backgroundAlertsOffered)) {
      return;
    }
    _showingSettingsIntro = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final context = _navigator.currentContext;
      try {
        if (!mounted || context == null || !context.mounted || index != 2) {
          return;
        }
        if (_navigator.currentState?.canPop() == true) return;
        if (!controller.settingsIntroAcknowledged) {
          final accepted = await showDialog<bool>(
            context: context,
            builder: (ctx) => DecisionDialog(
              title: const Text('Make Fittery yours'),
              content: const Text(
                'Explore Settings to personalize your battery experience.\n\n'
                '• Charging Dashboard and lock-screen options\n'
                '• Battery-level and temperature alerts\n'
                '• Custom alarm thresholds and sounds\n'
                '• Background Alerts without recording\n'
                '• Monitor Mode and notification refresh intervals\n'
                '• Charging history, graphs, and display preferences',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Explore Settings'),
                ),
              ],
            ),
          );
          if (accepted != true) return;
          await controller.acknowledgeRelease('settingsIntroAcknowledged');
        }
        if (!mounted ||
            !context.mounted ||
            index != 2 ||
            !controller.appActive ||
            controller.backgroundAlertsOffered) {
          return;
        }
        if (controller.backgroundAlertsEnabled) {
          await controller.acknowledgeRelease('backgroundAlertsOffered');
          return;
        }
        final enable = await showDialog<bool>(
          context: context,
          builder: (ctx) => DecisionDialog(
            title: const Text('Alerts, even when Fittery is closed'),
            content: const Text(
              'Background Alerts watches battery level and temperature using Android battery updates. It uses your existing thresholds and sounds without recording statistics or enabling Monitor Mode. A quiet status notification stays available; Android may delay updates or restrict background activity.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not Now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enable Background Alerts'),
              ),
            ],
          ),
        );
        if (enable == null) return;
        if (enable) await controller.setBackgroundAlerts(true);
        await controller.acknowledgeRelease('backgroundAlertsOffered');
      } catch (e) {
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your preference could not be saved. Try again in Settings.',
              ),
            ),
          );
        }
      } finally {
        _showingSettingsIntro = false;
      }
    });
  }

  bool _resolveLaunch() {
    if (_launchResolved || !controller.ready) return false;
    _launchResolved = true;
    _showWelcome = controller.shouldShowOnboarding;
    controller.setDashboardVisible(!_showWelcome);
    return true;
  }

  void _controllerChanged() {
    if (_resolveLaunch() && mounted) setState(() {});
    _checkSessionPrompt();
    _checkSettingsIntro();
  }

  void _finishWelcome() {
    setState(() => _showWelcome = false);
    controller.setDashboardVisible(index == 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkSessionPrompt();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final theme = controller.settings['theme'];
      ThemeData makeTheme(Brightness brightness) {
        final dark = brightness == Brightness.dark;
        final black = theme == 'AMOLED Black';
        final scheme =
            ColorScheme.fromSeed(
              seedColor: mint,
              brightness: brightness,
            ).copyWith(
              primary: dark ? mint : const Color(0xFF007E70),
              surface: dark
                  ? (black ? Colors.black : const Color(0xFF0D1117))
                  : const Color(0xFFF6F8FA),
              surfaceContainer: dark ? const Color(0xFF181F27) : Colors.white,
              onSurfaceVariant: dark
                  ? const Color(0xFF94A4B5)
                  : const Color(0xFF546575),
            );
        return ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          scaffoldBackgroundColor: scheme.surface,
          fontFamily: 'sans-serif',
          appBarTheme: AppBarTheme(
            backgroundColor: scheme.surface,
            scrolledUnderElevation: 0,
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: scheme.surfaceContainer,
            indicatorColor: scheme.primary.withValues(alpha: .15),
          ),
          sliderTheme: const SliderThemeData(trackHeight: 3),
          dividerColor: scheme.onSurface.withValues(alpha: .07),
        );
      }

      return MaterialApp(
        restorationScopeId: 'fittery',
        navigatorKey: _navigator,
        title: 'Fittery',
        debugShowCheckedModeBanner: false,
        theme: makeTheme(Brightness.light),
        darkTheme: makeTheme(Brightness.dark),
        themeMode: theme == 'System default'
            ? ThemeMode.system
            : ThemeMode.dark,
        home: !_launchResolved
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _showWelcome
            ? OnboardingPage(c: controller, onFinished: _finishWelcome)
            : Builder(
                builder: (context) => Scaffold(
                  appBar: AppBar(
                    titleSpacing: 24,
                    title: Row(
                      children: [
                        if (index == 0) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: Image.asset(
                              'store-assets/app-icon-512.png',
                              width: 28,
                              height: 28,
                              excludeFromSemantics: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            ['Fittery', 'History', 'Settings'][index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  body: SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Column(
                          children: [
                            if (controller.error != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  4,
                                  24,
                                  8,
                                ),
                                child: Text(
                                  controller.error!,
                                  style: const TextStyle(color: coral),
                                ),
                              ),
                            Expanded(
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey('tab-transition-$index'),
                                tween: Tween(
                                  begin: _animateTab ? 0 : 1,
                                  end: 1,
                                ),
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                builder: (context, progress, child) =>
                                    Transform.translate(
                                      offset: Offset(0, 6 * (1 - progress)),
                                      child: Opacity(
                                        opacity: .75 + .25 * progress,
                                        child: child,
                                      ),
                                    ),
                                child: switch (index) {
                                  0 => DashboardPage(c: controller),
                                  1 => HistoryPage(c: controller),
                                  _ => SettingsPage(c: controller),
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  bottomNavigationBar: NavigationBar(
                    height: 72,
                    animationDuration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    selectedIndex: index,
                    onDestinationSelected: (value) {
                      if (index == value) return;
                      setState(() {
                        index = value;
                        _animateTab = true;
                      });
                      controller.setDashboardVisible(value == 0);
                      controller.setHistoryVisible(value == 1);
                      _checkSettingsIntro();
                    },
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.dashboard_outlined),
                        selectedIcon: Icon(Icons.dashboard_rounded),
                        label: 'Dashboard',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.show_chart_rounded),
                        label: 'History',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: 'Settings',
                      ),
                    ],
                  ),
                ),
              ),
      );
    },
  );
}

Future<void> runAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is PlatformException
                ? e.message ?? 'Could not complete action.'
                : 'Could not complete action: $e',
          ),
        ),
      );
    }
  }
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.outlined = false,
  });
  final Widget child;
  final EdgeInsets padding;
  final bool outlined;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(outlined ? 14 : 20),
      border: Border.all(
        color: outlined
            ? mint.withValues(alpha: .38)
            : Theme.of(context).dividerColor,
      ),
    ),
    child: child,
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

const graphMetrics = <String, String>{
  'Voltage': 'voltageMv',
  'Current': 'currentMa',
  'Wattage': 'powerW',
  'Temperature': 'temperatureC',
};

String chargingAlarmStatus(BatteryController c) {
  if (!c.flag('chargeAlert')) return 'Alarm off · turn on to notify';
  if (!c.notificationsAllowed) {
    return 'Alarm on · notification permission needed';
  }
  final r = c.reading;
  if (r?.plugged != true) return 'Alarm on · waiting for a power connection';
  final level = r?.level;
  final limit = (c.settings['chargeLimit'] as num).toInt();
  if (level != null && level >= limit) {
    if (r?.data['alarmActive'] == true) {
      return c.flag('sound')
          ? 'Target reached · alert active'
          : 'Target reached · alarm sound is off';
    }
    if (r?.data['chargeAlertLatched'] == true) {
      return 'Target acknowledged · select a target again to re-arm';
    }
    return 'Target reached · checking alert';
  }
  return 'Alarm on · current ${level ?? '—'}%, target $limit%';
}

class MetricPanel extends Panel {
  const MetricPanel({
    super.key,
    required this.c,
    required this.label,
    required super.child,
    super.padding,
    super.outlined,
  });
  final BatteryController c;
  final String label;
  @override
  Widget build(BuildContext context) {
    final metric = graphMetrics[label];
    final panel = super.build(context);
    if (label == 'Health') {
      return Semantics(
        button: true,
        label: 'Explain battery health',
        child: InkWell(
          key: const ValueKey('battery-health-details'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => showDialog<void>(
            context: context,
            builder: (ctx) => DecisionDialog(
              title: const Text('About battery health'),
              content: SingleChildScrollView(
                child: Text(
                  'Android health status: ${c.reading?.text('health') ?? 'Unavailable'}.\n\n'
                  'A percentage is shown only when the same battery controller exposes both full and design capacities. It is a firmware capacity estimate, not an independent measurement of degradation.\n\n'
                  'Remaining charge and a single partial charging session cannot reliably establish battery health. A low cycle count alone cannot validate a capacity estimate. Some phones expose incomplete or inconsistent battery data.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
          child: panel,
        ),
      );
    }
    if (metric == null) return panel;
    return Semantics(
      button: true,
      label: 'View $label graph',
      child: InkWell(
        key: ValueKey('metric-$metric'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TelemetryPage(c: c, initialMetric: metric),
          ),
        ),
        child: panel,
      ),
    );
  }
}

class BatteryHero extends StatelessWidget {
  const BatteryHero({super.key, this.level});
  final int? level;
  @override
  Widget build(BuildContext context) => Semantics(
    label: level == null
        ? 'Battery percentage unavailable'
        : 'Battery $level percent',
    child: SizedBox(
      width: 244,
      height: 112,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: 0,
            top: 38,
            bottom: 38,
            child: Container(
              width: 8,
              decoration: BoxDecoration(
                color: mint.withValues(alpha: .35),
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(5),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 12,
            top: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                border: Border.all(color: mint.withValues(alpha: .4), width: 4),
                borderRadius: BorderRadius.circular(24),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: (level ?? 0).clamp(0, 100) / 100),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    builder: (context, fraction, child) => FractionallySizedBox(
                      widthFactor: fraction,
                      child: child,
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF079D9E), Color(0xFF25C9C3)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ExcludeSemantics(
              child: FittedBox(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      level?.toString() ?? '—',
                      style: const TextStyle(
                        fontSize: 62,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -2,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      '%',
                      style: TextStyle(
                        fontSize: 44,
                        height: 1,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class BackgroundMonitorControl extends StatefulWidget {
  const BackgroundMonitorControl({super.key, required this.c});
  final BatteryController c;
  @override
  State<BackgroundMonitorControl> createState() =>
      _BackgroundMonitorControlState();
}

class _BackgroundMonitorControlState extends State<BackgroundMonitorControl> {
  bool? _requested;

  Future<void> _change(bool enabled) async {
    if (_requested != null || enabled == widget.c.monitoring) return;
    setState(() => _requested = enabled);
    try {
      await runAction(context, () => widget.c.setMonitoring(enabled));
    } finally {
      if (mounted) setState(() => _requested = null);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.c,
    builder: (context, _) {
      final scheme = Theme.of(context).colorScheme;
      final on = widget.c.monitoring;
      final available = widget.c.reading != null || on;
      final duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 360);
      return AnimatedContainer(
        key: const ValueKey('background-monitor-card'),
        duration: duration,
        curve: Curves.easeInOutCubic,
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: on
              ? scheme.primary.withValues(alpha: .06)
              : Colors.transparent,
          border: Border.all(color: scheme.primary.withValues(alpha: .38)),
        ),
        child: MergeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(left: 10, right: 2),
            child: Row(
              children: [
                Icon(
                  Icons.sensors_rounded,
                  size: 18,
                  color: on ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _requested == null
                        ? 'Monitor Battery'
                        : _requested!
                        ? 'Enabling…'
                        : 'Stopping…',
                    style: const TextStyle(fontSize: 13, height: 1.25),
                  ),
                ),
                Tooltip(
                  message: !available
                      ? 'Waiting for battery readings'
                      : on
                      ? 'Recording and alerts on'
                      : 'Recording and alerts off',
                  child: SmoothToggle(
                    key: const ValueKey('background-monitor-toggle'),
                    value: on,
                    onChanged: _requested != null || !available
                        ? null
                        : _change,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ChargingControls extends StatelessWidget {
  const _ChargingControls({required this.c});
  final BatteryController c;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final monitor = BackgroundMonitorControl(c: c);
      if (!c.flag('chargingDashboard')) return monitor;
      final dashboard = ChargingDashboardEntry(c: c, compact: true);
      if (box.maxWidth < 320 ||
          MediaQuery.textScalerOf(context).scale(13) > 18) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [monitor, const SizedBox(height: 10), dashboard],
        );
      }
      return Row(
        children: [
          Expanded(child: monitor),
          const SizedBox(width: 10),
          Expanded(child: dashboard),
        ],
      );
    },
  );
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.c});
  final BatteryController c;
  @override
  Widget build(BuildContext context) {
    final r = c.reading;
    final dual = c.flag('dualCell');
    final power = r?.power(dual);
    final color = r?.plugged == true ? mint : coral;
    final full = r?.text('status') == 'Full';
    final temp = r?.number('temperatureC');
    final voltage = r?.voltage(dual);
    final capacity = r?.number('fullCapacityMah');
    final design = r?.number('designCapacityMah');
    final health = r?.number('healthPercent');
    final items = <(IconData, String, String, String)>[
      (
        Icons.electric_bolt_outlined,
        'Voltage',
        metric(
          c.flag('millivolts')
              ? voltage
              : voltage == null
              ? null
              : voltage / 1000,
          c.flag('millivolts') ? 'mV' : 'V',
          decimals: c.flag('millivolts') ? 0 : 2,
        ),
        dual ? 'Dual-cell adjustment' : 'Battery voltage',
      ),
      (
        Icons.swap_horiz_rounded,
        'Current',
        metric(r?.current, 'mA', signed: true),
        'Net battery current',
      ),
      (
        Icons.bolt_rounded,
        'Wattage',
        metric(power, 'W', decimals: 2, signed: true),
        'Power at the battery',
      ),
      (
        Icons.thermostat_outlined,
        'Temperature',
        metric(
          temp == null
              ? null
              : c.flag('fahrenheit')
              ? temp * 1.8 + 32
              : temp,
          c.flag('fahrenheit') ? '°F' : '°C',
          decimals: 1,
        ),
        'Battery temperature',
      ),
      (
        Icons.favorite_border_rounded,
        'Health',
        health == null ? r?.text('health') ?? '—' : '≈${health.round()}%',
        health == null
            ? 'System health status'
            : '${r?.text('health')} · ${r?.text('healthEstimateSource', 'Estimate')}',
      ),
      (
        Icons.power_outlined,
        'Power source',
        r?.text('source') ?? '—',
        r?.text('status') ?? 'Waiting for reading',
      ),
      (
        Icons.battery_charging_full_rounded,
        capacity == null && design != null ? 'Design capacity' : 'Capacity',
        capacity == null && design == null
            ? 'Unavailable'
            : metric(capacity ?? design, 'mAh'),
        capacity == null && design != null
            ? r?.text('designCapacitySource') ?? 'Factory design'
            : '${r?.text('fullCapacitySource', 'Unavailable')} · ${design == null ? 'Design unavailable' : 'Design: ${metric(design, 'mAh')}'}',
      ),
      (
        Icons.sync_rounded,
        'Charge cycles',
        r?.number('cycles')?.toStringAsFixed(0) ?? 'Unavailable',
        'Hardware cycle count',
      ),
    ];
    final eta = r?.number('remainingMs');
    return RefreshIndicator(
      onRefresh: c.refreshReading,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        children: [
          Text(
            'Get to know your battery',
            style: TextStyle(
              fontSize: 21,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            r == null ? 'Connecting to your battery…' : 'Live statistics',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: c.flag('chargingDashboard')
                ? Tooltip(
                    message: r?.plugged == true
                        ? 'Open charging dashboard'
                        : 'Connect a charger to open dashboard',
                    child: InkWell(
                      key: const ValueKey(
                        'battery-charging-dashboard-shortcut',
                      ),
                      borderRadius: BorderRadius.circular(24),
                      onTap: r?.plugged == true && !c.chargingDashboardVisible
                          ? () => showChargingDashboard(context, c)
                          : null,
                      child: BatteryHero(level: r?.level),
                    ),
                  )
                : BatteryHero(level: r?.level),
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                '${r?.text('status') ?? 'Connecting'}${power == null ? '' : '  ·  ${metric(power, 'W', decimals: 2, signed: true)}'}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          _ChargingControls(c: c),
          const SectionLabel('Live readings'),
          DashboardMetricGrid(c: c, items: items),
          const SizedBox(height: 14),
          Panel(
            child: Row(
              children: [
                const Icon(Icons.timelapse_rounded, color: mint),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        full
                            ? 'Charge complete'
                            : r?.plugged == true
                            ? 'Time until full'
                            : 'Estimated battery life',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        full
                            ? 'Ready to unplug'
                            : eta == null
                            ? switch (r?.text('remainingState')) {
                                'notGaining' => 'Not gaining charge',
                                'tooSlow' => 'Charging too slowly to estimate',
                                _ =>
                                  r?.plugged == true
                                      ? 'Measuring charging speed…'
                                      : 'Collecting discharge data…',
                              }
                            : '${durationLabel(eta)}${r?.charging == true ? '' : ' left'}',
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r?.text(
                              'remainingSource',
                              'Estimates appear when supported',
                            ) ??
                            'Estimates appear when supported',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: c.networkChanges,
            builder: (context, _) => DashboardNetwork(c: c),
          ),
          const SectionLabel('Miscellaneous'),
          ListenableBuilder(
            listenable: c.networkChanges,
            builder: (context, _) => DashboardMiscellaneous(c: c),
          ),
          const SizedBox(height: 20),
          Text(
            'Private by design. All readings and history stay on this device.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardMetricGrid extends StatelessWidget {
  const DashboardMetricGrid({super.key, required this.c, required this.items});
  final BatteryController c;
  final List<(IconData, String, String, String)> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth > 540 && items.length > 2 ? 4 : 2;
      final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final item in items)
            SizedBox(
              width: width,
              child: MetricPanel(
                c: c,
                label: item.$2,
                outlined: true,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(item.$1, color: mint, size: 17),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            item.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.$3,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.$4,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class DashboardNetwork extends StatelessWidget {
  const DashboardNetwork({super.key, required this.c});
  final BatteryController c;

  @override
  Widget build(BuildContext context) {
    final enabled = c.flag('networkEnabled');
    final connection =
        c.network?.text('connectionType', 'Connecting') ?? 'Connecting';
    final subtitle = !enabled
        ? 'Enable to see live traffic'
        : c.networkError != null
        ? 'Unavailable'
        : c.network?.number('downloadBytesPerSecond') == null
        ? 'Waiting for next sample'
        : connection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          'Network activity',
          trailing: Semantics(
            label: 'Enable dashboard network activity',
            child: Switch.adaptive(
              key: const ValueKey('network-enabled'),
              value: enabled,
              onChanged: c.reading == null
                  ? null
                  : (value) => runAction(
                      context,
                      () => c.save('networkEnabled', value),
                    ),
            ),
          ),
        ),
        DashboardMetricGrid(
          c: c,
          items: [
            (
              Icons.south_rounded,
              'Download',
              enabled
                  ? networkRate(c.network?.number('downloadBytesPerSecond'))
                  : 'Off',
              subtitle,
            ),
            (
              Icons.north_rounded,
              'Upload',
              enabled
                  ? networkRate(c.network?.number('uploadBytesPerSecond'))
                  : 'Off',
              subtitle,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          c.networkError ??
              (enabled
                  ? 'Device-wide traffic · refreshes every second while Dashboard is open. Includes local traffic and other apps.'
                  : 'Optional live readings while Dashboard is open.'),
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class DashboardMiscellaneous extends StatelessWidget {
  const DashboardMiscellaneous({super.key, required this.c});
  final BatteryController c;

  @override
  Widget build(BuildContext context) {
    final device = c.deviceInfo;
    final network = c.network;
    final enabled = c.flag('networkEnabled');
    final connected = network?.data['connected'] == true;
    String text(String key) => device?.text(key) ?? 'Unavailable';
    Widget group(String title, List<Widget> rows) => Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        group('Network information', [
          infoRow(
            context,
            'Default connection',
            !enabled
                ? 'Monitoring off'
                : network?.text('connectionType') ?? 'Connecting',
          ),
          if (enabled && network != null) ...[
            infoRow(
              context,
              'Internet access',
              !connected
                  ? 'Disconnected'
                  : network.data['internetValidated'] == true
                  ? 'Validated by Android'
                  : 'Not validated',
            ),
            if (connected)
              infoRow(
                context,
                'Data usage',
                network.data['metered'] == true
                    ? 'Metered connection'
                    : 'Unmetered connection',
              ),
            if (network.data['wifi'] == true) ...[
              infoRow(
                context,
                'Wi-Fi name',
                network.text('accessPoint', 'Hidden by Android'),
              ),
              infoRow(context, 'Wi-Fi band', network.text('wifiBand')),
              infoRow(
                context,
                'Frequency',
                network.number('frequencyMhz') == null
                    ? 'Unavailable'
                    : metric(network.number('frequencyMhz'), 'MHz'),
              ),
              infoRow(
                context,
                'Wi-Fi link rate',
                network.number('linkSpeedMbps') == null
                    ? 'Unavailable'
                    : metric(network.number('linkSpeedMbps'), 'Mbps'),
              ),
              Text(
                'Android may hide the Wi-Fi name. Link rate is the Wi-Fi connection rate, not measured internet speed.',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            infoRow(
              context,
              'Combined traffic',
              networkRate(network.number('combinedBytesPerSecond')),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        group('Device information', [
          infoRow(
            context,
            'Device',
            device?.text('model') ?? c.reading?.text('model') ?? 'Unavailable',
          ),
          infoRow(
            context,
            'Manufacturer',
            device?.text('manufacturer') ??
                c.reading?.text('manufacturer') ??
                'Unavailable',
          ),
          infoRow(
            context,
            'Android',
            device == null
                ? 'Unavailable'
                : '${text('androidVersion')} · API ${text('apiLevel')}',
          ),
          infoRow(context, 'Security patch', text('securityPatch')),
          infoRow(context, 'SoC model', text('socModel')),
          infoRow(context, 'SoC manufacturer', text('socManufacturer')),
          infoRow(context, 'CPU architectures', text('architectures')),
          infoRow(context, 'Available CPU cores', text('availableProcessors')),
          infoRow(
            context,
            'Usable RAM',
            memorySize(device?.number('totalRamBytes')),
          ),
          if (device?.number('advertisedRamBytes') != null)
            infoRow(
              context,
              'Advertised RAM',
              memorySize(device?.number('advertisedRamBytes')),
            ),
          infoRow(
            context,
            'Data partition size',
            memorySize(device?.number('dataTotalBytes')),
          ),
          infoRow(
            context,
            'Data partition available',
            memorySize(device?.number('dataAvailableBytes')),
          ),
          infoRow(
            context,
            'Display mode',
            device?.number('displayWidth') == null
                ? 'Unavailable'
                : '${text('displayWidth')} × ${text('displayHeight')} · ${metric(device?.number('displayRefreshRate'), 'Hz')}',
          ),
          infoRow(
            context,
            'Board',
            device?.text('board') ?? c.reading?.text('board') ?? 'Unavailable',
          ),
          infoRow(
            context,
            'Battery technology',
            c.reading?.text('technology') ?? 'Unavailable',
          ),
          if (c.deviceInfoError != null)
            Text(c.deviceInfoError!, style: const TextStyle(fontSize: 11)),
        ]),
      ],
    );
  }
}

Widget infoRow(BuildContext context, String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 7),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 2,
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        flex: 3,
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    ],
  ),
);

class TelemetryPage extends StatefulWidget {
  const TelemetryPage({
    super.key,
    required this.c,
    required this.initialMetric,
  });
  final BatteryController c;
  final String initialMetric;
  @override
  State<TelemetryPage> createState() => _TelemetryPageState();
}

class _TelemetryPageState extends State<TelemetryPage> {
  late final Set<String> selected = {widget.initialMetric};
  int _revision = 0;
  void _visibility() => widget.c.setTelemetryVisible(
    true,
    needsHistory: selected.any((key) => key != 'currentMa'),
    historySeconds:
        selected.any((key) => key != 'currentMa' && key != 'temperatureC')
        ? 5
        : 60,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _visibility();
    });
  }

  @override
  void dispose() {
    widget.c.setTelemetryVisible(false);
    super.dispose();
  }

  Future<void> _refresh() async {
    await widget.c.refreshHistory();
    if (mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Scaffold(
      appBar: AppBar(title: const Text('Telemetry')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const Text(
                    'Choose the readings to compare',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    selected.length == 1 && selected.contains('currentMa')
                        ? 'Live current · choose a range below'
                        : 'Other metrics: last hour · current has its own range',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: graphMetrics.entries
                        .map(
                          (metric) => FilterChip(
                            key: ValueKey('graph-toggle-${metric.value}'),
                            label: Text(metric.key),
                            selected: selected.contains(metric.value),
                            onSelected: (on) {
                              setState(() {
                                if (on) {
                                  selected.add(metric.value);
                                } else {
                                  selected.remove(metric.value);
                                }
                              });
                              _visibility();
                            },
                          ),
                        )
                        .toList(),
                  ),
                  if (selected.any((key) => key != 'currentMa'))
                    ListenableBuilder(
                      listenable: c.historyChanges,
                      builder: (_, _) => Column(
                        children: [
                          if (!c.historyLoaded && c.historyLoading)
                            const LinearProgressIndicator(minHeight: 2),
                          if (c.historyError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                c.historyError!,
                                style: const TextStyle(color: coral),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (selected.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Text(
                        'Select a metric to display its recorded graph.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ...graphMetrics.entries
                      .where((e) => selected.contains(e.value))
                      .map((metric) {
                        if (metric.value == 'currentMa') {
                          return Padding(
                            key: const ValueKey('graph-panel-currentMa'),
                            padding: const EdgeInsets.only(top: 18),
                            child: Panel(child: CurrentChart(c: c)),
                          );
                        }
                        final (
                          label,
                          color,
                          transform,
                        ) = switch (metric.value) {
                          'temperatureC' => (
                            c.flag('fahrenheit')
                                ? 'Temperature · °F'
                                : 'Temperature · °C',
                            mint,
                            (double v) =>
                                c.flag('fahrenheit') ? v * 1.8 + 32 : v,
                          ),
                          'powerW' => (
                            'Net power · W',
                            coral,
                            (double v) => v * (c.flag('dualCell') ? 2 : 1),
                          ),
                          'voltageMv' => (
                            c.flag('millivolts')
                                ? 'Voltage · mV'
                                : 'Voltage · V',
                            const Color(0xFFE3B86A),
                            (double v) =>
                                v *
                                (c.flag('dualCell') ? 2 : 1) /
                                (c.flag('millivolts') ? 1 : 1000),
                          ),
                          _ => throw StateError('Unknown telemetry metric'),
                        };
                        return Padding(
                          key: ValueKey('graph-panel-${metric.value}'),
                          padding: const EdgeInsets.only(top: 18),
                          child: Panel(
                            child: SavedMetricGraph(
                              source: c.historyPoints,
                              initialPoints: c.points,
                              metric: metric.value,
                              label: label,
                              color: color,
                              transform: transform,
                              active: () => c.appActive,
                              recentHour: true,
                              viewKey:
                                  '$_revision/${c.flag('fahrenheit')}/${c.flag('dualCell')}/${c.flag('millivolts')}',
                            ),
                          ),
                        );
                      }),
                  if (selected.any((key) => key != 'currentMa'))
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: Text(
                        'Saved readings from the last hour. Gaps and unsupported readings stay blank.',
                        style: TextStyle(fontSize: 11, height: 1.6),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String clockLabel(num millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis.toInt());
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
}

Widget telemetryGraph(
  BuildContext context,
  List<Map<String, dynamic>> points,
  String key,
  String label,
  Color color,
  double Function(double) transform,
) => MetricChart(
  points: points,
  metric: key,
  label: label,
  color: color,
  transform: transform,
);

String timeLabel(num millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis.toInt());
  return '${d.day}/${d.month} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

Widget sessionCard(
  BuildContext context,
  Map<String, dynamic> s, {
  bool dualCell = false,
}) {
  final charging = s['kind'] == 'Charging';
  final active = s['active'] == true;
  final color = charging ? mint : coral;
  final start = (s['startLevel'] as num?)?.toInt(),
      end = (s['endLevel'] as num?)?.toInt();
  final delta = start == null || end == null ? null : end - start;
  final averagePower = (s['averagePowerW'] as num?)?.abs();
  return Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              charging ? Icons.bolt_rounded : Icons.battery_3_bar,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                active
                    ? charging
                          ? s['status'] == 'Charging'
                                ? 'Charging now'
                                : 'Plugged in now'
                          : 'Discharging now'
                    : charging
                    ? 'Plugged-in session'
                    : 'Discharging session',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              delta == null ? '—' : '${delta > 0 ? '+' : ''}$delta%',
              style: TextStyle(color: color, fontSize: 20),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          durationLabel((s['endTime'] as num) - (s['startTime'] as num)),
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ((end ?? 0) / 100).clamp(0, 1),
            minHeight: 5,
            color: color,
            backgroundColor: color.withValues(alpha: .12),
          ),
        ),
        const SizedBox(height: 10),
        infoRow(
          context,
          '${start ?? '—'}% → ${end ?? '—'}%',
          metric(
            averagePower == null ? null : averagePower * (dualCell ? 2 : 1),
            s['averagePowerKind'] == 'single reading' ? 'W reading' : 'W avg',
            decimals: 2,
          ),
        ),
        infoRow(
          context,
          'Start · ${timeLabel(s['startTime'] as num)}',
          active ? 'Active' : 'End · ${timeLabel(s['endTime'] as num)}',
        ),
        if (s['gap'] == true)
          const Text(
            'Recording paused; unobserved time is excluded.',
            style: TextStyle(fontSize: 10),
          ),
        if (s['averagePowerKind'] == 'sample average')
          const Text(
            'Power is the average of the saved samples.',
            style: TextStyle(fontSize: 10),
          ),
      ],
    ),
  );
}

class BarsPainter extends CustomPainter {
  BarsPainter(this.values, this.labelColor);
  final List<double?> values;
  final Color labelColor;
  @override
  void paint(Canvas canvas, Size size) {
    final max = math.max(100.0, values.whereType<double>().fold(0.0, math.max));
    final paint = Paint()
      ..color = labelColor.withValues(alpha: .12)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final slot = size.width / values.length;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null || value <= 0) continue;
      final rect = Rect.fromLTWH(
        i * slot + slot * .2,
        size.height * (1 - value / max),
        slot * .6,
        size.height * value / max,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = mint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BarsPainter oldDelegate) => true;
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.c});
  final BatteryController c;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                'store-assets/app-icon-512.png',
                width: 68,
                height: 68,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fittery',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Know Your Battery',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SectionLabel('Background Alerts'),
      Panel(child: _BackgroundAlertsControl(c: c)),
      const SectionLabel('Charging dashboard'),
      Panel(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          children: [
            toggle(
              context,
              'Enable charging dashboard',
              'chargingDashboard',
              subtitle:
                  'Open manually while plugged in. Can appear above the lock screen; your device stays locked. Normal screen timeout applies.',
            ),
            toggle(
              context,
              'Charging dashboard on lock screen',
              'chargingScreenSaver',
              subtitle:
                  'Use Android’s screen saver while charging and idle. Select Fittery in system settings. Start timing and lock behavior depend on your phone.',
            ),
            if (c.flag('chargingScreenSaver'))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: OutlinedButton.icon(
                  key: const ValueKey('screen-saver-setup'),
                  onPressed: () =>
                      runAction(context, () => c.action('screenSaverSettings')),
                  icon: const Icon(Icons.settings_display_outlined),
                  label: const Text('Set up Android screen saver'),
                ),
              ),
            if (c.flag('chargingDashboard'))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: ChargingDashboardEntry(c: c),
              ),
          ],
        ),
      ),
      const SectionLabel('Alert sounds'),
      Panel(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          children: [
            toggle(context, 'Alarm sound', 'sound'),
            _alertSound(
              context,
              'charge',
              'Charging limit',
              'Charging limit voice',
            ),
            _alertSound(
              context,
              'heat',
              'Battery temperature',
              'Battery temperature voice',
            ),
            _alertSound(context, 'low', 'Low battery', 'Low battery voice'),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 9),
        child: Text(
          'Tap an alert to choose an audio file or system tone. Preview plays once, up to 30 seconds, at alarm volume.',
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      const SectionLabel('Appearance & units'),
      Panel(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          children: [
            choice(context, 'Theme', 'theme', [
              'System default',
              'Dark',
              'AMOLED Black',
            ], Icons.dark_mode_outlined),
            toggle(
              context,
              'Fahrenheit',
              'fahrenheit',
              subtitle: 'Display temperature in °F',
            ),
            toggle(
              context,
              'Millivolts',
              'millivolts',
              subtitle: 'Display voltage in mV',
            ),
            toggle(
              context,
              'Dual-cell battery',
              'dualCell',
              subtitle: 'Double voltage and power for series cells',
            ),
            choice(context, 'Current reporting', 'currentUnit', [
              'Auto',
              'µA',
              'mA',
            ], Icons.swap_horiz_rounded),
            choice(context, 'Current polarity', 'currentPolarity', [
              'Auto',
              'Standard',
              'Inverted',
            ], Icons.swap_vert_rounded),
          ],
        ),
      ),
      const SizedBox(height: 9),
      Text(
        'Auto uses stable units and checks sustained charge-counter changes. A negative value means net charge is leaving the battery, even when power is connected. See Diagnostics below for raw readings.',
        style: TextStyle(
          fontSize: 10,
          height: 1.6,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SectionLabel('Alerts & thresholds'),
      Panel(
        child: Column(
          children: [
            alert(
              context,
              'Charging limit',
              'chargeAlert',
              'chargeLimit',
              50,
              100,
              '%',
              'Notify when charging reaches the target',
            ),
            const Divider(height: 32),
            alert(
              context,
              'Low battery',
              'lowAlert',
              'lowLimit',
              5,
              50,
              '%',
              'Optional extra alert · off by default',
            ),
            const Divider(height: 32),
            alert(
              context,
              'Battery temperature',
              'heatAlert',
              'heatLimit',
              35,
              50,
              '°C',
              'Warn when the battery gets too warm',
            ),
            ListTile(
              key: const ValueKey('heat-reminder-interval'),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Temperature reminder interval',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                'Remind again after snoozing: ${c.settings['heatReminderMinutes']} minutes',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () async {
                final minutes = await showDialog<int>(
                  context: context,
                  builder: (ctx) => SimpleDialog(
                    title: const Text('Temperature reminder interval'),
                    children: List.generate(
                      30,
                      (i) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, i + 1),
                        child: Text(
                          '${i + 1} ${i == 0 ? 'minute' : 'minutes'}',
                        ),
                      ),
                    ),
                  ),
                );
                if (minutes != null && context.mounted) {
                  await runAction(
                    context,
                    () => c.save('heatReminderMinutes', minutes),
                  );
                }
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Enable background monitoring for alerts while the app is closed. Alerts notify you; they cannot stop charging.',
        style: TextStyle(
          fontSize: 10,
          height: 1.6,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SectionLabel('Notifications'),
      Panel(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          children: [
            choice(
              context,
              'Notification format',
              'notificationFormat',
              [
                'All metrics',
                'Current',
                'Power',
                'Temperature',
                'Time remaining',
              ],
              Icons.notifications_outlined,
            ),
            ListTile(
              leading: const Icon(Icons.update_rounded),
              titleAlignment: ListTileTitleAlignment.top,
              title: const Text(
                'Notification refresh interval',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Updates the monitor notification. Recording stays at 3 seconds. Android may delay updates while asleep.',
                    style: TextStyle(fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  DropdownButton<int>(
                    isExpanded: true,
                    itemHeight: null,
                    key: const ValueKey('notification-refresh-interval'),
                    value:
                        (c.settings['notificationIntervalSeconds'] as num?)
                            ?.toInt() ??
                        1,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 second')),
                      DropdownMenuItem(value: 3, child: Text('3 seconds')),
                      DropdownMenuItem(value: 5, child: Text('5 seconds')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        runAction(
                          context,
                          () => c.save('notificationIntervalSeconds', value),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            toggle(context, 'Show on lock screen', 'lockScreen'),
            ListTile(
              title: const Text(
                'System notifications',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                c.notificationsAllowed
                    ? 'Allowed'
                    : 'Allow notifications for visible alerts',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.open_in_new, size: 16),
              onTap: () =>
                  runAction(context, () => c.action('notificationSettings')),
            ),
          ],
        ),
      ),
      const SectionLabel('Recording history'),
      Panel(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          children: [
            toggle(
              context,
              'Keep recordings until I delete them',
              'keepRecordings',
              subtitle:
                  'Off by default: completed recordings expire 30 days after creation. Active recordings are protected. Turning this off removes expired recordings.',
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text(
                'Past recordings',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                'Browse by date, view graphs, rename or delete',
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Past recordings')),
                    body: AnimatedBuilder(
                      animation: c,
                      builder: (_, _) => HistoryPage(c: c),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SectionLabel('System & reliability'),
      Panel(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          children: [
            SwitchListTile(
              key: const ValueKey('background-monitor-settings'),
              title: const Text(
                'Background monitoring',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                'Record battery history and run enabled alerts while Fittery is closed. Resume after restarting your phone.',
                style: TextStyle(fontSize: 11),
              ),
              value: c.monitoringEnabled,
              onChanged: (enabled) =>
                  runAction(context, () => c.setMonitoring(enabled)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                !c.monitoringEnabled
                    ? 'Background alerts and recording are off. Enable monitoring to use them while Fittery is closed.'
                    : !c.monitoring
                    ? 'Monitoring could not start. Open Fittery again or turn monitoring off and on to retry.'
                    : 'Monitoring is running. Android battery restrictions may delay updates.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Panel(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.shield_outlined, color: mint),
              title: const Text(
                'Battery optimization',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                c.optimized
                    ? 'Unrestricted background access'
                    : 'Review background restrictions in Android settings',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.open_in_new, size: 16),
              onTap: () =>
                  runAction(context, () => c.action('batteryOptimization')),
            ),
            ListTile(
              leading: const Icon(Icons.settings_suggest_outlined),
              title: const Text(
                'Autostart & background access',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                'Help for Xiaomi, OnePlus and other devices',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () async {
                await showDialog<void>(
                  context: context,
                  builder: (ctx) => DecisionDialog(
                    title: const Text('Keep monitoring running'),
                    content: const Text(
                      'In your phone’s app settings, allow autostart or auto-launch, set battery usage to unrestricted, and allow notifications. On MIUI / HyperOS, also lock Fittery in recent apps if monitoring is interrupted.\n\nNames and availability vary by manufacturer.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          runAction(context, () => c.action('appSettings'));
                        },
                        child: const Text('App settings'),
                      ),
                    ],
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: coral),
              title: const Text(
                'Clear all recordings',
                style: TextStyle(fontSize: 14, color: coral),
              ),
              onTap: () async {
                final clear = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => DecisionDialog(
                    title: const Text('Clear all history?'),
                    content: const Text(
                      'This permanently removes all recordings and saved readings from this device. If monitoring is on, a new recording will begin.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text(
                          'Clear history',
                          style: TextStyle(color: coral),
                        ),
                      ),
                    ],
                  ),
                );
                if (clear == true && context.mounted) {
                  await runAction(context, () => c.action('clearHistory'));
                }
              },
            ),
          ],
        ),
      ),
      const SectionLabel('Welcome'),
      Panel(
        padding: EdgeInsets.zero,
        child: ListTile(
          key: const ValueKey('view-welcome-tutorial'),
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text(
            'View Welcome Tutorial',
            style: TextStyle(fontSize: 14),
          ),
          subtitle: const Text(
            'Explore Fittery and change your welcome preference',
            style: TextStyle(fontSize: 11),
          ),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (routeContext) => OnboardingPage(
                c: c,
                replay: true,
                onFinished: () => Navigator.of(routeContext).pop(),
              ),
            ),
          ),
        ),
      ),
      AboutSection(c: c),
      const SizedBox(height: 28),
      Text(
        'FITTERY  ·  PRIVATE BY DESIGN\nNo ads. No account. Just your battery.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          height: 2,
          letterSpacing: 1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );

  Widget toggle(
    BuildContext context,
    String label,
    String key, {
    String? subtitle,
  }) => MergeSemantics(
    child: ListTile(
      key: ValueKey('setting-$key'),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 11)),
      trailing: SmoothToggle(
        value: c.flag(key),
        onChanged: (v) => runAction(context, () => c.save(key, v)),
      ),
      onTap: () => runAction(context, () => c.save(key, !c.flag(key))),
    ),
  );

  Widget _alertSound(
    BuildContext context,
    String event,
    String title,
    String defaultName,
  ) {
    final playing = c.previewPlaying && c.previewEvent == event;
    final silent = c.settings['${event}ToneSource'] == 'silent';
    return ListTile(
      key: ValueKey('alarm-tone-$event'),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        c.settings['${event}ToneName']?.toString() ?? defaultName,
        style: const TextStyle(fontSize: 11),
      ),
      leading: IconButton(
        key: ValueKey('alarm-preview-$event'),
        tooltip: playing ? 'Stop $title preview' : 'Preview $title sound',
        onPressed: c.previewBusy || silent
            ? null
            : () => runAction(context, () => c.togglePreview(event)),
        icon: Icon(
          playing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
          color: silent ? null : mint,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => _chooseAlarmTone(context, event, title),
    );
  }

  Future<void> _chooseAlarmTone(
    BuildContext context,
    String event,
    String title,
  ) async {
    final method = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '$title sound',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ListTile(
                  key: const ValueKey('alarm-tone-default'),
                  leading: const Icon(Icons.record_voice_over_outlined),
                  title: const Text('Default voice'),
                  subtitle: const Text(
                    'Use the included recording for this alert',
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'defaultTone'),
                ),
                ListTile(
                  key: const ValueKey('alarm-tone-system'),
                  leading: const Icon(Icons.alarm_rounded),
                  title: const Text('System alarm tones'),
                  subtitle: const Text(
                    'Choose a system tone, default alarm, or Silent',
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'pickTone'),
                ),
                ListTile(
                  key: const ValueKey('alarm-tone-file'),
                  leading: const Icon(Icons.audio_file_outlined),
                  title: const Text('Choose audio file'),
                  subtitle: const Text(
                    'Choose music or another audio file saved on your phone',
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'pickAudioFile'),
                ),
                ListTile(
                  key: const ValueKey('alarm-tone-silent'),
                  leading: const Icon(Icons.volume_off_outlined),
                  title: const Text('Silent'),
                  subtitle: const Text(
                    'Keep the notification without an alarm sound',
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'silentTone'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (method != null && context.mounted) {
      await runAction(context, () => c.action(method, event: event));
    }
  }

  Widget choice(
    BuildContext context,
    String label,
    String key,
    List<String> options,
    IconData icon,
  ) => ListTile(
    title: Text(label, style: const TextStyle(fontSize: 14)),
    subtitle: Text(
      c.settings[key].toString(),
      style: const TextStyle(fontSize: 11),
    ),
    trailing: const Icon(Icons.chevron_right, size: 18),
    onTap: () async {
      final value = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ...options.map(
                  (o) => ListTile(
                    title: Text(o),
                    trailing: c.settings[key] == o
                        ? const Icon(Icons.check, color: mint)
                        : null,
                    onTap: () => Navigator.pop(ctx, o),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (value != null && context.mounted) {
        await runAction(context, () => c.save(key, value));
      }
    },
  );

  Widget alert(
    BuildContext context,
    String label,
    String enabledKey,
    String valueKey,
    double min,
    double max,
    String unit,
    String description,
  ) {
    return ThresholdControl(
      key: ValueKey(valueKey),
      id: valueKey,
      label: label,
      description: description,
      value: (c.settings[valueKey] as num).round(),
      min: min.round(),
      max: max.round(),
      unit: unit,
      presets: switch (valueKey) {
        'chargeLimit' => const [75, 80, 85],
        'lowLimit' => const [10, 15, 20],
        _ => const [38, 40, 45],
      },
      enabled: c.flag(enabledKey),
      onEnabledChanged: (v) => runAction(context, () => c.save(enabledKey, v)),
      onChanged: (v) => c.save(valueKey, v),
      statusText: valueKey == 'chargeLimit'
          ? chargingAlarmStatus(c)
          : c.flag(enabledKey)
          ? 'Alarm on'
          : 'Alarm off · target saved',
    );
  }
}

class _BackgroundAlertsControl extends StatefulWidget {
  const _BackgroundAlertsControl({required this.c});
  final BatteryController c;
  @override
  State<_BackgroundAlertsControl> createState() =>
      _BackgroundAlertsControlState();
}

class _BackgroundAlertsControlState extends State<_BackgroundAlertsControl> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: const ValueKey('background-alerts-settings'),
    contentPadding: EdgeInsets.zero,
    title: const Text('Background Alerts'),
    subtitle: Text(
      widget.c.backgroundAlertsEnabled
          ? widget.c.backgroundAlertsRunning
                ? 'Watching battery level and temperature. Monitor Mode is independent.'
                : 'Waiting to start. Reopen Fittery or turn this off and on to retry.'
          : 'Run your configured alarms while Fittery is closed, without recording or enabling Monitor Mode.',
    ),
    value: widget.c.backgroundAlertsEnabled,
    onChanged: busy
        ? null
        : (value) async {
            setState(() => busy = true);
            try {
              await runAction(
                context,
                () => widget.c.setBackgroundAlerts(value),
              );
            } finally {
              if (mounted) setState(() => busy = false);
            }
          },
  );
}
