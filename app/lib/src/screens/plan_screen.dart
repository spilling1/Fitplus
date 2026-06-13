import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/plan.dart';
import '../state/providers.dart';
import '../widgets/rationale_card.dart';
import 'session_player_screen.dart';

/// The week view (PRD §5.3): training + rest days, the week's rationale, and the
/// entry point into running a session.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider);
    final gen = ref.watch(planControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('This week'),
        actions: [
          if (plan != null)
            TextButton.icon(
              onPressed: gen.loading ? null : () => _adapt(context, ref),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Next week'),
            ),
        ],
      ),
      body: gen.loading
          ? const _Loading()
          : plan == null
              ? _EmptyState(onGenerate: () => _generate(ref))
              : _PlanBody(plan: plan, warnings: gen.warnings, source: gen.source),
    );
  }

  Future<void> _generate(WidgetRef ref) =>
      ref.read(planControllerProvider.notifier).generate();

  Future<void> _adapt(BuildContext context, WidgetRef ref) async {
    await ref.read(planControllerProvider.notifier).generate(adapt: true);
    final err = ref.read(planControllerProvider).error;
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Building your week…'),
          ],
        ),
      );
}

class _EmptyState extends ConsumerWidget {
  final VoidCallback onGenerate;
  const _EmptyState({required this.onGenerate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gen = ref.watch(planControllerProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fitness_center, size: 56),
            const SizedBox(height: 16),
            Text('Ready when you are', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              "I'll build a week around your equipment, schedule and goals — then adapt it based on how it actually goes.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onGenerate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate my plan'),
            ),
            if (gen.error != null) ...[
              const SizedBox(height: 16),
              Text(gen.error!, style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text('Is the backend running? Check the address in the You tab.',
                  style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanBody extends ConsumerWidget {
  final WeeklyPlan plan;
  final List<String> warnings;
  final String? source;
  const _PlanBody({required this.plan, required this.warnings, this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (source == 'stub' || source == 'stub-fallback')
          _OfflineBanner(),
        RationaleCard(title: 'About this week', rationale: plan.rationale, initiallyExpanded: true),
        if (warnings.isNotEmpty) _WarningsCard(warnings: warnings),
        const SizedBox(height: 8),
        for (final s in plan.sessions) _SessionTile(plan: plan, session: s),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.5),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(children: [
          Icon(Icons.cloud_off, size: 20),
          SizedBox(width: 10),
          Expanded(child: Text('Offline plan. Connect the AI backend for fully personalised, adaptive coaching.')),
        ]),
      ),
    );
  }
}

class _WarningsCard extends StatelessWidget {
  final List<String> warnings;
  const _WarningsCard({required this.warnings});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.tune, size: 18),
              const SizedBox(width: 8),
              Text('Adjustments I made', style: Theme.of(context).textTheme.titleSmall),
            ]),
            const SizedBox(height: 6),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('• $w', style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  final WeeklyPlan plan;
  final PlannedSession session;
  const _SessionTile({required this.plan, required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    ref.watch(logsProvider); // rebuild when a session is logged
    final log = ref.read(logsProvider.notifier).latestForDay(plan.weekStart, session.day);
    final done = log?.status == 'completed';

    if (!session.isTraining) {
      return ListTile(
        leading: const Icon(Icons.bedtime_outlined),
        title: Text('${session.day} · Rest'),
        subtitle: Text(session.rationale),
        dense: true,
      );
    }

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: done ? scheme.primary : scheme.primaryContainer,
          child: Icon(done ? Icons.check : Icons.fitness_center,
              color: done ? scheme.onPrimary : scheme.onPrimaryContainer),
        ),
        title: Text('${session.day} · ${session.focus}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${session.totalSets} sets · ~${session.estimatedMinutes ?? '–'} min'
          '${done ? ' · done' : ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SessionPlayerScreen(weekStart: plan.weekStart, session: session),
          ),
        ),
      ),
    );
  }
}
