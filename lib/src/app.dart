import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'controller.dart';
import 'models.dart';
import 'threshold_control.dart';
import 'history_data.dart';
import 'about_section.dart';

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
  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? BatteryController();
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller == null) unawaited(controller.initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.setAppActive(state == AppLifecycleState.resumed);
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
        title: 'Fittery',
        debugShowCheckedModeBanner: false,
        theme: makeTheme(Brightness.light),
        darkTheme: makeTheme(Brightness.dark),
        themeMode: theme == 'System default'
            ? ThemeMode.system
            : ThemeMode.dark,
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              titleSpacing: 24,
              title: Row(
                children: [
                  if (index == 0) ...[
                    const Icon(Icons.bolt_rounded, color: mint, size: 27),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    ['Fittery', 'History', 'Settings'][index],
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.6,
                    ),
                  ),
                ],
              ),
              actions: [
                if (index != 2)
                  Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: controller.reading == null
                                ? Colors.grey
                                : mint,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          controller.reading == null ? 'CONNECTING' : 'LIVE',
                          style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
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
                          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                          child: Text(
                            controller.error!,
                            style: const TextStyle(color: coral),
                          ),
                        ),
                      Expanded(
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey('tab-transition-$index'),
                          tween: Tween(begin: _animateTab ? 0 : 1, end: 1),
                          duration: MediaQuery.disableAnimationsOf(context)
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
            'YOUR BATTERY, AT A GLANCE',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 2,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 22),
          Center(child: BatteryHero(level: r?.level)),
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
          FilledButton.tonalIcon(
            onPressed: r == null
                ? null
                : () => runAction(context, c.toggleMonitoring),
            icon: Icon(
              c.monitoring ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 18,
            ),
            label: Text(
              c.monitoring
                  ? 'Background monitoring is on'
                  : 'Turn on background monitoring',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
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

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.c});
  final BatteryController c;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final since = now.subtract(const Duration(days: 3));
    // A rolling 72-hour range spans partial calendar days at both ends.
    final days =
        DateTime.utc(
          now.year,
          now.month,
          now.day,
        ).difference(DateTime.utc(since.year, since.month, since.day)).inDays +
        1;
    final window = HistoryWindow(
      daily: widget.c.daily,
      sessions: widget.c.sessions,
      days: days,
      now: now,
      since: since,
    );
    final firstDay = window.firstDay;
    final points = widget.c.points;
    final bars = window.chargedPerDay;
    final charged = window.chargedPercent;
    final pluggedMs = window.pluggedMs;
    final recent = points
        .where(
          (p) =>
              p['time'] is num &&
              (p['time'] as num).isFinite &&
              (p['time'] as num) >
                  now
                      .subtract(const Duration(hours: 1))
                      .millisecondsSinceEpoch &&
              (p['time'] as num) <= now.millisecondsSinceEpoch,
        )
        .toList();
    return RefreshIndicator(
      onRefresh: widget.c.refreshHistory,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        children: [
          if (widget.c.historyLoading)
            const LinearProgressIndicator(minHeight: 2),
          if (widget.c.historyError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                widget.c.historyError!,
                style: const TextStyle(color: coral, fontSize: 12),
              ),
            ),
          const SectionLabel('Last 3 days'),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'Up to 10 sessions. Sessions expire 72 hours after they start, together with their readings and daily totals.',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Panel(
            child: Wrap(
              spacing: 22,
              runSpacing: 20,
              children: [
                stat(
                  window.hasObservations
                      ? (charged / 100).toStringAsFixed(2)
                      : '—',
                  'Est. cycles',
                ),
                stat(
                  window.hasObservations ? '+${charged.round()}%' : '—',
                  'Charged',
                ),
                stat(
                  window.hasObservations ? durationLabel(pluggedMs) : '—',
                  'Plugged in',
                ),
                stat(
                  pluggedMs > 0
                      ? '${(charged / (pluggedMs / 3600000)).toStringAsFixed(1)}%/h'
                      : '—',
                  'Avg. plugged rate',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              window.hasObservations
                  ? 'Based on recorded intervals · cycles = charged % ÷ 100'
                  : widget.c.historyLoaded
                  ? 'No recorded intervals in this period yet.'
                  : 'Loading saved history…',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SectionLabel(
            'Daily charging',
            trailing: Text(
              '% gained',
              style: TextStyle(fontSize: 11, color: mint),
            ),
          ),
          Panel(
            child: Column(
              children: [
                SizedBox(
                  height: 150,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: BarsPainter(
                          bars,
                          Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (charged == 0)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Text(
                              'No charging recorded in this period',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(days, (i) {
                    final d = DateTime(
                      firstDay.year,
                      firstDay.month,
                      firstDay.day + i,
                    );
                    return Text(
                      '${d.day}/${d.month}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    );
                  }),
                ),
                if (charged == 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                      'Charge while recording to build this chart. Blank days have no charging bars.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          SectionLabel(
            'Recent telemetry',
            trailing: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      TelemetryPage(c: widget.c, initialMetric: 'temperatureC'),
                ),
              ),
              child: const Text('Explore'),
            ),
          ),
          Panel(
            child: Column(
              children: [
                if (recent.length < 2)
                  const SizedBox(
                    height: 110,
                    child: Center(
                      child: Text(
                        'Your readings will appear here as they arrive.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                else ...[
                  telemetryGraph(
                    context,
                    recent,
                    'temperatureC',
                    widget.c.flag('fahrenheit')
                        ? 'Temperature · °F'
                        : 'Temperature · °C',
                    mint,
                    widget.c.flag('fahrenheit')
                        ? (v) => v * 1.8 + 32
                        : (v) => v,
                  ),
                  const SizedBox(height: 20),
                  telemetryGraph(
                    context,
                    recent,
                    'powerW',
                    'Net power · W',
                    coral,
                    (v) => v * (widget.c.flag('dualCell') ? 2 : 1),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  widget.c.monitoring
                      ? 'Recording in the background every 30 seconds'
                      : 'Recording while open. Enable monitoring to record in the background.',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  recent.isEmpty
                      ? 'No readings recorded in the last hour'
                      : '${recent.length} saved readings · latest ${timeLabel(recent.last['time'] as num)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SectionLabel('Sessions'),
          if (window.sessions.isEmpty)
            const Panel(
              child: Text(
                'No sessions recorded in this period. Sessions are recorded while the app is open or background monitoring is enabled.',
                style: TextStyle(fontSize: 13, height: 1.7),
              ),
            ),
          ...window.sessions.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: sessionCard(
                context,
                s,
                dualCell: widget.c.flag('dualCell'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget stat(String value, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w500,
          letterSpacing: -.6,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.c.setTelemetryVisible(true);
    });
  }

  @override
  void dispose() {
    widget.c.setTelemetryVisible(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Telemetry')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: widget.c,
        builder: (context, _) {
          final c = widget.c;
          final now = DateTime.now().millisecondsSinceEpoch;
          final points = c.points
              .where(
                (p) =>
                    p['time'] is num &&
                    (p['time'] as num) > now - 3600000 &&
                    (p['time'] as num) <= now,
              )
              .toList();
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: RefreshIndicator(
                onRefresh: c.refreshHistory,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text(
                      'Choose the readings to compare',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Last hour · separate scales, shared timestamps',
                      style: TextStyle(fontSize: 12),
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
                              onSelected: (on) => setState(() {
                                if (on) {
                                  selected.add(metric.value);
                                } else {
                                  selected.remove(metric.value);
                                }
                              }),
                            ),
                          )
                          .toList(),
                    ),
                    if (c.historyLoading)
                      const LinearProgressIndicator(minHeight: 2),
                    if (c.historyError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          c.historyError!,
                          style: const TextStyle(color: coral),
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
                            _ => (
                              'Current · mA',
                              const Color(0xFFA5A0FF),
                              (double v) => v,
                            ),
                          };
                          return Padding(
                            key: ValueKey('graph-panel-${metric.value}'),
                            padding: const EdgeInsets.only(top: 18),
                            child: Panel(
                              child: Column(
                                children: [
                                  telemetryGraph(
                                    context,
                                    points,
                                    metric.value,
                                    label,
                                    color,
                                    transform,
                                  ),
                                  if (points.length > 1) ...[
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          clockLabel(
                                            points.first['time'] as num,
                                          ),
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                        Text(
                                          clockLabel(
                                            points.last['time'] as num,
                                          ),
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                    const SizedBox(height: 20),
                    Text(
                      '${points.length} saved readings in this window. Gaps and unsupported readings are left blank.',
                      style: const TextStyle(fontSize: 11, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
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
) {
  final values = points
      .where((p) => p[key] is num && (p[key] as num).isFinite)
      .map((p) => transform((p[key] as num).toDouble()))
      .toList();
  return Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 11, color: color)),
          ),
          Text(
            values.isEmpty
                ? 'Unavailable'
                : '${values.reduce(math.min).toStringAsFixed(1)} – ${values.reduce(math.max).toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 10),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 72,
        width: double.infinity,
        child: values.length < 2
            ? const Center(
                child: Text(
                  'Collecting supported readings…',
                  style: TextStyle(fontSize: 11),
                ),
              )
            : CustomPaint(painter: LinePainter(points, key, color, transform)),
      ),
    ],
  );
}

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

class LinePainter extends CustomPainter {
  LinePainter(this.points, this.keyName, this.color, this.transform);
  final List<Map<String, dynamic>> points;
  final String keyName;
  final Color color;
  final double Function(double) transform;
  @override
  void paint(Canvas canvas, Size size) {
    final valid = points
        .where(
          (p) =>
              p[keyName] is num &&
              (p[keyName] as num).isFinite &&
              p['time'] is num,
        )
        .toList();
    if (valid.length < 2) return;
    final values = valid
        .map((p) => transform((p[keyName] as num).toDouble()))
        .toList();
    final minimum = values.reduce(math.min), maximum = values.reduce(math.max);
    final padding = math.max((maximum - minimum) * .1, .05);
    final low = minimum - padding, high = maximum + padding;
    final timed = points.where((p) => p['time'] is num).toList();
    final first = (timed.first['time'] as num).toDouble(),
        last = (timed.last['time'] as num).toDouble();
    final path = Path();
    Map<String, dynamic>? previous;
    for (final point in points) {
      final raw = point[keyName];
      if (raw is! num || !raw.isFinite || point['time'] is! num) {
        previous = null;
        continue;
      }
      final x =
          ((point['time'] as num) - first) /
          math.max(1, last - first) *
          size.width;
      final y =
          size.height -
          (transform(raw.toDouble()) - low) / (high - low) * size.height;
      final gap =
          previous == null ||
          ((point['time'] as num) - (previous['time'] as num) > 120000 ||
              point['sessionId'] != previous['sessionId']);
      if (gap) {
        path.moveTo(x, y);
        canvas.drawCircle(Offset(x, y), 2, Paint()..color = color);
      } else {
        path.lineTo(x, y);
      }
      previous = point;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant LinePainter oldDelegate) => true;
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.c});
  final BatteryController c;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
    children: [
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
              'Notify when battery drops to the limit',
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
      const SectionLabel('Alarm & notifications'),
      Panel(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          children: [
            toggle(context, 'Alarm sound', 'sound'),
            ListTile(
              title: const Text('Alarm tone', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                c.settings['toneName']?.toString() ?? 'Default alarm',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => runAction(context, () => c.action('pickTone')),
            ),
            ListTile(
              key: const ValueKey('alarm-preview'),
              leading: IconButton(
                key: const ValueKey('alarm-preview-button'),
                tooltip: c.previewPlaying ? 'Stop preview' : 'Play preview',
                icon: Icon(
                  c.previewPlaying
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                  color: mint,
                ),
                onPressed: c.previewBusy
                    ? null
                    : () => runAction(context, c.togglePreview),
              ),
              title: Text(
                c.previewPlaying ? 'Stop preview' : 'Preview alarm',
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                c.previewPlaying
                    ? 'Playing · tap pause to stop'
                    : 'Plays for 3 seconds at alarm volume',
                style: const TextStyle(fontSize: 11),
              ),
              onTap: c.previewBusy
                  ? null
                  : () => runAction(context, c.togglePreview),
            ),
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
      const SectionLabel('System & reliability'),
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
                    : 'Allow unrestricted battery use',
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
                  builder: (ctx) => AlertDialog(
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
                'Clear charge history',
                style: TextStyle(fontSize: 14, color: coral),
              ),
              onTap: () async {
                final clear = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear all history?'),
                    content: const Text(
                      'This permanently removes recorded sessions and charts from this device. A new session will begin with the next reading.',
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
  }) => SwitchListTile(
    title: Text(label, style: const TextStyle(fontSize: 14)),
    subtitle: subtitle == null
        ? null
        : Text(subtitle, style: const TextStyle(fontSize: 11)),
    value: c.flag(key),
    onChanged: (v) => runAction(context, () => c.save(key, v)),
  );

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
