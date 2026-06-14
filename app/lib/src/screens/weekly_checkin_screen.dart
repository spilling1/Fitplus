import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../state/providers.dart';
import '../widgets/multi_select.dart';

/// Start-of-week check-in (PRD §5.9). Before building the next week we ask the
/// few things that change week to week — how you're feeling, whether your goals
/// or schedule shifted, and anything you'd like different — and feed it into the
/// adaptation. Fast and skippable.
class WeeklyCheckInScreen extends ConsumerStatefulWidget {
  const WeeklyCheckInScreen({super.key});

  @override
  ConsumerState<WeeklyCheckInScreen> createState() => _WeeklyCheckInScreenState();
}

class _WeeklyCheckInScreenState extends ConsumerState<WeeklyCheckInScreen> {
  static const _feelings = ['Great', 'Good', 'A bit tired', 'Run-down'];

  String _feeling = 'Good';
  bool _goalsSame = true;
  bool _scheduleSame = true;
  late Set<String> _goals;
  late Set<String> _days;
  late int _minutes;
  final _changes = TextEditingController();

  @override
  void initState() {
    super.initState();
    final p = ref.read(profileProvider);
    _goals = p.goals.toSet();
    _days = p.trainingDays.toSet();
    _minutes = p.sessionMinutes;
  }

  @override
  void dispose() {
    _changes.dispose();
    super.dispose();
  }

  void _go({required bool skip}) {
    final notifier = ref.read(profileProvider.notifier);
    String? adjustment;

    if (!skip) {
      if (!_goalsSame) notifier.patch((p) => p.copyWith(goals: _goals.toList()));
      if (!_scheduleSame) {
        notifier.patch((p) => p.copyWith(
              trainingDays: kWeekDays.where(_days.contains).toList(),
              sessionMinutes: _minutes,
            ));
      }
      final parts = <String>['Weekly check-in. The user is feeling: $_feeling.'];
      if (!_goalsSame) parts.add('Updated goals: ${_goals.join(', ')}.');
      if (!_scheduleSame) parts.add('Schedule changed to ${_days.length} days, $_minutes min.');
      if (_changes.text.trim().isNotEmpty) parts.add('They asked: "${_changes.text.trim()}".');
      if (_feeling == 'Run-down') parts.add('Ease off this week — reduce volume/intensity.');
      if (_feeling == 'Great') parts.add('They feel strong — a small progression is welcome if warranted.');
      adjustment = parts.join(' ');
    }

    ref.read(planControllerProvider.notifier).generate(adapt: true, adjustment: adjustment);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly check-in'),
        actions: [TextButton(onPressed: () => _go(skip: true), child: const Text('Skip'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Before I build next week', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Takes ten seconds — it makes the plan fit the week you’re actually having.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),

          _label('How are you feeling?'),
          Wrap(
            spacing: 8,
            children: [
              for (final f in _feelings)
                ChoiceChip(
                  selected: _feeling == f,
                  label: Text(f),
                  onSelected: (_) => setState(() => _feeling = f),
                ),
            ],
          ),

          const SizedBox(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Goals still the same?'),
            value: _goalsSame,
            onChanged: (v) => setState(() => _goalsSame = v),
          ),
          if (!_goalsSame)
            MultiSelectChips(
              options: kGoals,
              selected: _goals,
              onToggle: (g) => setState(() => _goals.contains(g) ? _goals.remove(g) : _goals.add(g)),
            ),

          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Same schedule this week?'),
            value: _scheduleSame,
            onChanged: (v) => setState(() => _scheduleSame = v),
          ),
          if (!_scheduleSame) ...[
            MultiSelectChips(
              options: kWeekDays,
              selected: _days,
              labelOf: (d) => d.substring(0, 3),
              onToggle: (d) => setState(() => _days.contains(d) ? _days.remove(d) : _days.add(d)),
            ),
            const SizedBox(height: 12),
            Text('Session length: $_minutes min', style: Theme.of(context).textTheme.bodyMedium),
            Slider(
              value: _minutes.toDouble(),
              min: 15,
              max: 90,
              divisions: 15,
              label: '$_minutes min',
              onChanged: (v) => setState(() => _minutes = v.round()),
            ),
          ],

          const SizedBox(height: 12),
          _label('Anything you’d like to change?'),
          TextField(
            controller: _changes,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'e.g. more upper body, my shoulder’s niggling, swap Saturday to Sunday…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _go(skip: false),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Build next week'),
          ),
        ],
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: Theme.of(context).textTheme.titleSmall),
      );
}
