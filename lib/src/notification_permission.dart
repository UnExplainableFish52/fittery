import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'controller.dart';
import 'decision_dialog.dart';

bool _permissionDialogOpen = false;
bool get permissionDialogOpen => _permissionDialogOpen;

Future<void> enableBackgroundAlertsWithPermission(
  BuildContext context,
  BatteryController controller,
) async {
  try {
    await controller.setBackgroundAlerts(true);
  } on PlatformException catch (e) {
    if (e.code != 'NOTIFICATIONS') rethrow;
    if (context.mounted) {
      await ensureNotificationPermission(context, controller);
    }
  }
}

Future<void> ensureNotificationPermission(
  BuildContext context,
  BatteryController controller, {
  bool initial = false,
}) async {
  var status =
      await BatteryController.channel.invokeMapMethod<String, dynamic>(
        'notificationPermission',
      ) ??
      {};
  if (status['allowed'] == true || initial && status['asked'] == true) return;
  if (initial && status['canRequest'] == true) {
    try {
      await BatteryController.channel.invokeMethod<void>(
        'requestNotifications',
      );
      await controller.loadInitial();
      return;
    } on PlatformException catch (e) {
      if (e.code != 'NOTIFICATIONS') rethrow;
    }
  }
  if (!context.mounted || _permissionDialogOpen) return;
  _permissionDialogOpen = true;
  var retryDenied = false;
  try {
    status =
        await BatteryController.channel.invokeMapMethod<String, dynamic>(
          'notificationPermission',
        ) ??
        {};
    if (!context.mounted) return;
    final retry = status['canRequest'] == true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => DecisionDialog(
        title: const Text('Enable notifications'),
        content: const Text(
          'Fittery needs notification permission to deliver battery alerts and important monitoring updates. Without it, these features may not function properly. Please enable notifications for the best experience.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'settings'),
            child: const Text('Open Settings'),
          ),
          if (retry)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'retry'),
              child: const Text('Enable Notifications'),
            ),
        ],
      ),
    );
    if (choice == 'settings') await controller.action('notificationSettings');
    if (choice == 'retry') {
      try {
        await BatteryController.channel.invokeMethod<void>(
          'requestNotifications',
        );
      } on PlatformException catch (e) {
        if (e.code != 'NOTIFICATIONS') rethrow;
        retryDenied = true;
      }
    }
    await controller.loadInitial();
  } finally {
    _permissionDialogOpen = false;
  }
  if (retryDenied && context.mounted) {
    await ensureNotificationPermission(context, controller);
  }
}
