import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../state/providers.dart';
import '../widgets/multi_select.dart';
import 'home_shell.dart';

/// Progressive onboarding (PRD §5.1). Feels like a short conversation; every
/// field is optional and editable later. Target: done in ~3 minutes.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;

  // Working draft, committed to the profile provider at the end.
  String _level = 'Beginner';
  final Set<String> _goals = {'general health'};
  final Set<String> _days = {'Monday', 'Wednesday', 'Friday'};
  int _minutes = 45;
  final Set<String> _equipment = {};
  final Set<String> _injuries = {};
  final _notes = TextEditingController();

  static const _stepCount = 5;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < _stepCount - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  void _finish() {
    ref.read(profileProvider.notifier).update(
          Profile(
            level: _level,
            goals: _goals.toList(),
            trainingDays: kWeekDays.where(_days.contains).toList(),
            sessionMinutes: _minutes,
            equipment: _equipment.toList(),
            injuries: _injuries.toList(),
            notes: _notes.text.trim(),
            onboarded: true,
          ),
        );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to FitPlus'),
        leading: _step > 0
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back)
            : null,
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: (_step + 1) / _stepCount),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: SingleChildScrollView(
                key: ValueKey(_step),
                padding: const EdgeInsets.all(20),
                child: _stepBody(),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _next,
                child: Text(_step == _stepCount - 1 ? 'Start training' : 'Continue'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _levelStep();
      case 1:
        return _goalsStep();
      case 2:
        return _scheduleStep();
      case 3:
        return _equipmentStep();
      default:
        return _injuriesStep();
    }
  }

  Widget _header(String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 20),
        ],
      );

  Widget _levelStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header('How experienced are you?', "I'll scale instruction and starting loads to match. You can change this anytime."),
          for (final lvl in ['Beginner', 'Intermediate', 'Advanced'])
            RadioListTile<String>(
              value: lvl,
              groupValue: _level,
              onChanged: (v) => setState(() => _level = v!),
              title: Text(lvl),
              subtitle: Text(_levelBlurb(lvl)),
              contentPadding: EdgeInsets.zero,
            ),
        ],
      );

  String _levelBlurb(String lvl) {
    switch (lvl) {
      case 'Intermediate':
        return 'Trained before; comfortable with the basics.';
      case 'Advanced':
        return 'Experienced; you know your lifts and like the detail.';
      default:
        return 'New or returning — clear guidance, low injury risk.';
    }
  }

  Widget _goalsStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header("What do you want from training?", 'Pick any that fit. Goals shape how I build your week.'),
          MultiSelectChips(
            options: kGoals,
            selected: _goals,
            onToggle: (g) => setState(() => _goals.toggle(g)),
          ),
        ],
      );

  Widget _scheduleStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header('When can you train?', 'Choose the days that usually work. We can flex this week to week.'),
          MultiSelectChips(
            options: kWeekDays,
            selected: _days,
            labelOf: (d) => d.substring(0, 3),
            onToggle: (d) => setState(() => _days.toggle(d)),
          ),
          const SizedBox(height: 28),
          Text('Time per session: $_minutes min', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _minutes.toDouble(),
            min: 15,
            max: 90,
            divisions: 15,
            label: '$_minutes min',
            onChanged: (v) => setState(() => _minutes = v.round()),
          ),
        ],
      );

  Widget _equipmentStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header('What equipment do you have?', "Leave it empty for bodyweight-only — that's a perfectly valid plan."),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in EquipmentCatalogue.all)
                FilterChip(
                  selected: _equipment.contains(item.id),
                  label: Text('${item.emoji}  ${item.label}'),
                  onSelected: (_) => setState(() => _equipment.toggle(item.id)),
                ),
            ],
          ),
        ],
      );

  Widget _injuriesStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header('Anything I should work around?', 'Injuries and limitations are treated as hard constraints — I will program around them.'),
          MultiSelectChips(
            options: kCommonInjuries,
            selected: _injuries,
            onToggle: (i) => setState(() => _injuries.toggle(i)),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Anything else (optional)',
              hintText: 'e.g. recovering from a sprained ankle, prefer kettlebells…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.health_and_safety_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'FitPlus is a coach, not a doctor. Check with a physician before starting, '
                      'especially with any medical condition, pregnancy/postpartum, or recent injury.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

extension _ToggleSet on Set<String> {
  void toggle(String v) => contains(v) ? remove(v) : add(v);
}
