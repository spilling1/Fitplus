import 'package:flutter/material.dart';

/// A wrap of selectable chips for multi-select fields.
class MultiSelectChips extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;
  final void Function(String) onToggle;
  final String Function(String)? labelOf;

  const MultiSelectChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
    this.labelOf,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          FilterChip(
            selected: selected.contains(o),
            label: Text(labelOf?.call(o) ?? o),
            onSelected: (_) => onToggle(o),
          ),
      ],
    );
  }
}
