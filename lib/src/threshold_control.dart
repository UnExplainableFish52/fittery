import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One bounded value shared by the number field, presets, and slider.
class ThresholdControl extends StatefulWidget {
  const ThresholdControl({
    super.key,
    required this.id,
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.presets,
    required this.enabled,
    required this.onEnabledChanged,
    required this.onChanged,
    this.statusText,
  });

  final String id, label, description, unit;
  final int value, min, max;
  final List<int> presets;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final FutureOr<void> Function(int) onChanged;
  final String? statusText;

  @override
  State<ThresholdControl> createState() => _ThresholdControlState();
}

class _ThresholdControlState extends State<ThresholdControl> {
  late int _value;
  late final TextEditingController _text;
  final _focus = FocusNode();
  bool _dragging = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _value = widget.value.clamp(widget.min, widget.max);
    _text = TextEditingController(text: '$_value');
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
    } else {
      setState(() {
        _text.text = '$_value';
        _error = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ThresholdControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _value = widget.value.clamp(widget.min, widget.max);
      if (!_focus.hasFocus) _text.text = '$_value';
    }
  }

  void _choose(int value, {bool save = true}) {
    final next = value.clamp(widget.min, widget.max);
    setState(() {
      _value = next;
      _text.text = '$next';
      _error = null;
    });
    if (save) unawaited(_commit(next));
  }

  Future<void> _commit(int value) async {
    try {
      await widget.onChanged(value);
    } catch (e) {
      if (!mounted) return;
      if (_value == value) {
        setState(() {
          _value = widget.value;
          _text.text = '$_value';
          _error = null;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is PlatformException
                ? e.message ?? 'Target could not be saved.'
                : 'Target could not be saved.',
          ),
        ),
      );
    }
  }

  void _typed(String text) {
    final number = int.tryParse(text);
    final valid =
        number != null && number >= widget.min && number <= widget.max;
    setState(() {
      _error = valid || text.isEmpty
          ? null
          : '${widget.min}–${widget.max} only';
      if (valid) _value = number;
    });
    if (valid) unawaited(_commit(number));
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              widget.label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Switch(
            key: ValueKey('${widget.id}-enabled'),
            value: widget.enabled,
            onChanged: widget.onEnabledChanged,
          ),
        ],
      ),
      Text(
        widget.description,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        widget.statusText ??
            (widget.enabled ? 'Alarm on' : 'Alarm off · target saved'),
        style: TextStyle(
          fontSize: 11,
          color: widget.enabled
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: TextField(
              key: ValueKey('${widget.id}-input'),
              controller: _text,
              focusNode: _focus,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                labelText: 'Target',
                suffixText: widget.unit,
                helperText: '${widget.min}–${widget.max}${widget.unit}',
                errorText: _error,
                helperStyle: const TextStyle(fontSize: 10),
                errorStyle: const TextStyle(fontSize: 10),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _typed,
              onSubmitted: (_) => _focus.unfocus(),
              onTapOutside: (_) => _focus.unfocus(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: widget.presets
                  .map(
                    (preset) => ChoiceChip(
                      key: ValueKey('${widget.id}-preset-$preset'),
                      label: Text(
                        '$preset${widget.unit}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: _value == preset,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      padding: EdgeInsets.zero,
                      onSelected: (_) {
                        _focus.unfocus();
                        _choose(preset);
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
      TweenAnimationBuilder<double>(
        tween: Tween(end: _value.toDouble()),
        duration: Duration(
          milliseconds: _dragging || MediaQuery.disableAnimationsOf(context)
              ? 0
              : 200,
        ),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => Slider(
          key: ValueKey('${widget.id}-slider'),
          value: value.clamp(widget.min.toDouble(), widget.max.toDouble()),
          min: widget.min.toDouble(),
          max: widget.max.toDouble(),
          divisions: widget.max - widget.min,
          label: '$_value${widget.unit}',
          onChangeStart: (_) {
            _focus.unfocus();
            setState(() => _dragging = true);
          },
          onChanged: (v) => _choose(v.round(), save: false),
          onChangeEnd: (v) {
            _choose(v.round());
            setState(() => _dragging = false);
          },
        ),
      ),
    ],
  );
}
