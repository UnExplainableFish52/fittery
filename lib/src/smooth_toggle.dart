import 'package:flutter/material.dart';

/// A compact switch with a generous touch target and a calm thumb transition.
class SmoothToggle extends StatelessWidget {
  const SmoothToggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 360);
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: SizedBox(
          width: 52,
          height: 48,
          child: Center(
            child: AnimatedContainer(
              width: 44,
              height: 26,
              padding: const EdgeInsets.all(3),
              duration: duration,
              curve: Curves.easeInOutCubic,
              decoration: BoxDecoration(
                color: value
                    ? scheme.primary.withValues(
                        alpha: onChanged == null ? .3 : .8,
                      )
                    : scheme.onSurface.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: value ? .5 : .2),
                ),
              ),
              child: AnimatedAlign(
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                duration: duration,
                curve: Curves.easeInOutCubic,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
