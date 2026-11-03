import 'package:flutter/material.dart';
import 'charging_dashboard.dart';
import 'controller.dart';

/// A minimal root for Android's system-owned DreamService window.
class ChargingDreamApp extends StatefulWidget {
  const ChargingDreamApp({super.key, required this.controller});
  final BatteryController controller;
  @override
  State<ChargingDreamApp> createState() => _ChargingDreamAppState();
}

class _ChargingDreamAppState extends State<ChargingDreamApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.controller.setAppActive(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: ChargingDashboardPage(c: widget.controller, isDream: true),
  );
}
