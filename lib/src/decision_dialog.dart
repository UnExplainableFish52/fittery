import 'package:flutter/material.dart';

/// Full-width decisions keep long labels readable at large text sizes.
class DecisionDialog extends StatelessWidget {
  const DecisionDialog({super.key, this.title, this.content, this.actions});
  final Widget? title, content;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final buttons = [...?actions];
    final destructive = buttons.any(
      (w) =>
          w is TextButton &&
          w.child is Text &&
          const ['Delete', 'Clear history'].contains((w.child as Text).data),
    );
    if (!destructive && buttons.length == 2) {
      final first = buttons.removeAt(0);
      buttons.add(first);
    }
    return AlertDialog(
      title: title,
      content: content == null ? null : SingleChildScrollView(child: content),
      actions: buttons.isEmpty
          ? null
          : [
              SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < buttons.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      if (buttons[i] is ButtonStyleButton)
                        i == 0
                            ? FilledButton(
                                onPressed:
                                    (buttons[i] as ButtonStyleButton).onPressed,
                                child: (buttons[i] as ButtonStyleButton).child,
                              )
                            : OutlinedButton(
                                onPressed:
                                    (buttons[i] as ButtonStyleButton).onPressed,
                                child: (buttons[i] as ButtonStyleButton).child,
                              )
                      else
                        buttons[i],
                    ],
                  ],
                ),
              ),
            ],
    );
  }
}
