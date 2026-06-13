import 'package:flutter/material.dart';

/// Expandable "why this" card. Education is a feature, not a footnote
/// (PRD product principle) — every plan and session can explain its reasoning.
class RationaleCard extends StatelessWidget {
  final String title;
  final String rationale;
  final bool initiallyExpanded;

  const RationaleCard({
    super.key,
    this.title = 'Why this?',
    required this.rationale,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    if (rationale.trim().isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer.withValues(alpha: 0.4),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: const Icon(Icons.lightbulb_outline),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(rationale, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}
