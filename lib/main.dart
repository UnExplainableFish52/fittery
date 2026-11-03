import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'src/app.dart';
import 'src/controller.dart';
import 'src/charging_dream.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF181F27),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  // Only the immediate sticky battery snapshot precedes the first frame.
  // Database reads and optional hardware probes run after the UI starts.
  final controller = BatteryController();
  await controller.loadInitial();
  runApp(FitteryApp(controller: controller));
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.connect());
}

@pragma('vm:entry-point')
Future<void> chargingDreamMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = BatteryController()..setChargingDashboardVisible(true);
  await controller.loadInitial();
  runApp(ChargingDreamApp(controller: controller));
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => controller.connect(readingsOnly: true),
  );
}
