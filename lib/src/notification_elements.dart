import 'package:flutter/material.dart';
import 'controller.dart';

class NotificationElementsTile extends StatelessWidget {
  const NotificationElementsTile({super.key, required this.controller});
  final BatteryController controller;
  static const metrics = ['Current', 'Power', 'Temperature', 'Time remaining'];

  List<String> get selected {
    final saved = controller.settings['notificationElements'];
    if (saved is List &&
        (saved.length == 1 && saved.first == 'All metrics' ||
            saved.isNotEmpty &&
                saved.length <= 3 &&
                saved.toSet().length == saved.length &&
                saved.every(metrics.contains))) {
      return List<String>.from(saved);
    }
    final legacy = controller.settings['notificationFormat'];
    return [metrics.contains(legacy) ? legacy as String : 'All metrics'];
  }

  @override
  Widget build(BuildContext context) => ListTile(
    key: const ValueKey('notification-elements'),
    leading: const Icon(Icons.notifications_outlined),
    title: const Text('Notification elements', style: TextStyle(fontSize: 14)),
    subtitle: Text(selected.join(' · '), style: const TextStyle(fontSize: 11)),
    trailing: const Icon(Icons.chevron_right),
    onTap: () async {
      var draft = selected.toSet();
      final result = await showDialog<List<String>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: const Text('Notification elements'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Choose All metrics, or select one to three elements for the live monitor notification.',
                  ),
                  CheckboxListTile(
                    title: const Text('All metrics'),
                    value: draft.contains('All metrics'),
                    onChanged: draft.contains('All metrics')
                        ? null
                        : (_) => update(() => draft = {'All metrics'}),
                  ),
                  for (final metric in metrics)
                    CheckboxListTile(
                      title: Text(metric),
                      value: draft.contains(metric),
                      onChanged:
                          !draft.contains('All metrics') &&
                              (draft.contains(metric) && draft.length == 1 ||
                                  !draft.contains(metric) && draft.length == 3)
                          ? null
                          : (checked) => update(() {
                              if (draft.contains('All metrics')) {
                                draft = {metric};
                              } else if (checked == true) {
                                draft.add(metric);
                              } else {
                                draft.remove(metric);
                              }
                            }),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  ctx,
                  draft.contains('All metrics')
                      ? ['All metrics']
                      : metrics.where(draft.contains).toList(),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (result == null || !context.mounted) return;
      try {
        await controller.save('notificationElements', result);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not save notification elements. Please try again.',
              ),
            ),
          );
        }
      }
    },
  );
}
