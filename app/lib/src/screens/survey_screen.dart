import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/logs.dart';
import '../state/providers.dart';

/// Post-workout micro-survey (PRD §5.9). ~10 seconds, always skippable. Feeds
/// the weekly adaptation engine. Skipping degrades adaptation gracefully.
class SurveyScreen extends ConsumerStatefulWidget {
  final SessionLog log;
  const SurveyScreen({super.key, required this.log});

  @override
  ConsumerState<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends ConsumerState<SurveyScreen> {
  int? _difficulty; // 1-10
  int _energy = 3; // 1-5
  int _enjoyment = 3; // 1-5
  final Set<String> _pain = {};
  final _note = TextEditingController();

  static const _bodyAreas = ['Knee', 'Lower back', 'Shoulder', 'Wrist', 'Hip', 'Ankle', 'Neck'];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save({required bool skipped}) {
    final survey = Survey(
      difficulty: _difficulty,
      energy: _energy,
      enjoyment: _enjoyment,
      painAreas: _pain.toList(),
      note: _note.text.trim(),
      skipped: skipped,
    );
    ref.read(logsProvider.notifier).upsert(widget.log.copyWith(survey: survey));
    // Capture the messenger before popping — context is about to be defunct.
    final messenger = ScaffoldMessenger.of(context);
    final showPainNudge = _pain.isNotEmpty && !skipped;
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (showPainNudge) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Noted. If pain persists, ease off and consider seeing a professional.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('How did that go?'),
        actions: [TextButton(onPressed: () => _save(skipped: true), child: const Text('Skip'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Nice work — logged ${widget.log.completedSetCount} sets.',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 24),

          _label('How hard was it overall?'),
          Wrap(
            spacing: 8,
            children: [
              _quick('Easy', 3),
              _quick('Just right', 6),
              _quick('Hard', 9),
            ],
          ),
          const SizedBox(height: 8),
          Text(_difficulty == null ? 'Tap one — or fine-tune below'
              : 'RPE $_difficulty / 10', style: Theme.of(context).textTheme.bodySmall),
          Slider(
            value: (_difficulty ?? 5).toDouble(),
            min: 1, max: 10, divisions: 9,
            label: '${_difficulty ?? 5}',
            onChanged: (v) => setState(() => _difficulty = v.round()),
          ),

          const SizedBox(height: 16),
          _label('Energy today'),
          _faces(_energy, (v) => setState(() => _energy = v)),

          const SizedBox(height: 16),
          _label('Did you enjoy it?'),
          _faces(_enjoyment, (v) => setState(() => _enjoyment = v)),

          const SizedBox(height: 20),
          _label('Any pain or discomfort? (tap areas)'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in _bodyAreas)
                FilterChip(
                  selected: _pain.contains(a),
                  label: Text(a),
                  onSelected: (_) => setState(() => _pain.contains(a) ? _pain.remove(a) : _pain.add(a)),
                ),
            ],
          ),

          const SizedBox(height: 20),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Anything else? (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => _save(skipped: false), child: const Text('Save')),
        ],
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _quick(String label, int value) => ChoiceChip(
        selected: _difficulty == value,
        label: Text(label),
        onSelected: (_) => setState(() => _difficulty = value),
      );

  Widget _faces(int value, void Function(int) onPick) {
    const icons = [
      Icons.sentiment_very_dissatisfied,
      Icons.sentiment_dissatisfied,
      Icons.sentiment_neutral,
      Icons.sentiment_satisfied,
      Icons.sentiment_very_satisfied,
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        for (var i = 0; i < 5; i++)
          IconButton(
            iconSize: 34,
            color: value == i + 1 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
            icon: Icon(icons[i]),
            onPressed: () => onPick(i + 1),
          ),
      ],
    );
  }
}
