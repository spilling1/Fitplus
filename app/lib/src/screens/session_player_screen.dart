import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/plan.dart';
import '../models/logs.dart';
import '../state/providers.dart';
import '../widgets/countdown_timer.dart';
import 'survey_screen.dart';

/// The workout player (PRD §5.4). Steps through exercises one at a time with
/// set-by-set logging, timers for timed holds, and a rest timer between sets.
/// Works fully offline; progress auto-saves after every logged set.
class SessionPlayerScreen extends ConsumerStatefulWidget {
  final String weekStart;
  final PlannedSession session;
  const SessionPlayerScreen({super.key, required this.weekStart, required this.session});

  @override
  ConsumerState<SessionPlayerScreen> createState() => _SessionPlayerScreenState();
}

class _Item {
  final String block;
  final Exercise ex;
  _Item(this.block, this.ex);
}

class _SessionPlayerScreenState extends ConsumerState<SessionPlayerScreen> {
  late final List<_Item> _items;
  late SessionLog _log;
  final Map<int, int> _done = {}; // exercise index -> completed sets
  final Set<int> _skipped = {};

  int _i = 0;
  final _reps = TextEditingController();
  final _weight = TextEditingController();
  bool _resting = false;

  @override
  void initState() {
    super.initState();
    _items = [
      for (final b in widget.session.blocks)
        for (final ex in b.exercises) _Item(b.label, ex),
    ];
    _log = SessionLog(
      id: '${widget.weekStart}|${widget.session.day}|${DateTime.now().millisecondsSinceEpoch}',
      weekStart: widget.weekStart,
      day: widget.session.day,
      focus: widget.session.focus,
      startedAt: DateTime.now(),
      status: 'partial',
    );
    _prefillFor(0);
  }

  @override
  void dispose() {
    _reps.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _prefillFor(int index) {
    if (index >= _items.length) return;
    final ex = _items[index].ex;
    _reps.text = ex.reps?.toString() ?? '';
    // Leave weight to the user; pre-fill from last logged set of this exercise.
    final last = _log.sets.where((s) => s.exerciseName == ex.name && s.load != null).toList();
    _weight.text = last.isNotEmpty ? (last.last.load!).toString() : '';
    _resting = false;
  }

  _Item get _current => _items[_i];
  int get _completedForCurrent => _done[_i] ?? 0;
  int get _targetSetsForCurrent => _current.ex.setCount;

  void _logSet() {
    final ex = _current.ex;
    final idx = _completedForCurrent;
    final set = SetLog(
      exerciseName: ex.name,
      setIndex: idx,
      reps: ex.timed ? null : int.tryParse(_reps.text),
      load: double.tryParse(_weight.text),
      durationSec: ex.timed ? ex.durationSec : null,
      timestamp: DateTime.now(),
    );
    _log = _log.copyWith(sets: [..._log.sets, set]);
    ref.read(logsProvider.notifier).upsert(_log);

    setState(() {
      _done[_i] = idx + 1;
      // Start a rest timer if there are more sets and a rest is prescribed.
      _resting = (_done[_i]! < _targetSetsForCurrent) && (ex.restSec ?? 0) > 0;
    });
  }

  void _go(int delta) {
    final next = _i + delta;
    if (next < 0 || next >= _items.length) return;
    setState(() => _i = next);
    _prefillFor(next);
  }

  void _skipExercise() {
    setState(() => _skipped.add(_i));
    if (_i < _items.length - 1) {
      _go(1);
    }
  }

  Future<void> _finish() async {
    final allSetsDone = _items.asMap().entries.every((e) =>
        _skipped.contains(e.key) || (_done[e.key] ?? 0) >= e.value.ex.setCount);
    _log = _log.copyWith(
      completedAt: DateTime.now(),
      status: _log.sets.isEmpty ? 'skipped' : (allSetsDone ? 'completed' : 'partial'),
    );
    ref.read(logsProvider.notifier).upsert(_log);

    if (!mounted) return;
    // Hand off to the post-workout survey, then back to the plan.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SurveyScreen(log: _log)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ex = _current.ex;
    final isLast = _i == _items.length - 1;
    final timed = ex.timed || (ex.durationSec != null && ex.reps == null);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.session.day),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'skip') _skipExercise();
              if (v == 'finish') _finish();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'skip', child: Text('Skip this exercise')),
              PopupMenuItem(value: 'finish', child: Text('Finish & end early')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: (_i + 1) / _items.length),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('${_current.block} · ${_i + 1} of ${_items.length}',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(ex.name, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(ex.prescription, style: Theme.of(context).textTheme.titleMedium),
                if (ex.targetRpe != null)
                  Text('Target effort: RPE ${ex.targetRpe}/10',
                      style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                _howToCard(ex),
                const SizedBox(height: 16),

                if (timed)
                  Center(
                    child: CountdownTimer(
                      key: ValueKey('timer-$_i-${_done[_i] ?? 0}'),
                      seconds: ex.durationSec ?? 30,
                      label: 'Hold',
                    ),
                  ),

                if (_resting)
                  Center(
                    child: CountdownTimer(
                      key: ValueKey('rest-$_i-${_done[_i]}'),
                      seconds: ex.restSec ?? 60,
                      autoStart: true,
                      label: 'Rest',
                      onComplete: () => setState(() => _resting = false),
                    ),
                  ),

                const SizedBox(height: 16),
                _setLogger(ex, timed),
              ],
            ),
          ),
          _bottomBar(isLast),
        ],
      ),
    );
  }

  Widget _howToCard(Exercise ex) {
    if (ex.howTo.isEmpty && ex.cues.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ex.howTo.isNotEmpty) Text(ex.howTo, style: Theme.of(context).textTheme.bodyMedium),
            if (ex.cues.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.tips_and_updates_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(ex.cues, style: Theme.of(context).textTheme.bodySmall)),
              ]),
            ],
            if (ex.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(ex.notes, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _setLogger(Exercise ex, bool timed) {
    final done = _completedForCurrent;
    final target = _targetSetsForCurrent;
    final allLogged = done >= target;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Sets', style: Theme.of(context).textTheme.titleMedium),
                Text('$done / $target done'),
              ],
            ),
            const SizedBox(height: 12),
            if (!timed)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reps,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Reps', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _weight,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Weight (kg)', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            if (timed)
              Text('Log each completed hold (${ex.durationSec ?? 0}s).',
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: allLogged ? null : _logSet,
              icon: const Icon(Icons.check),
              label: Text(allLogged ? 'All sets logged' : 'Log set ${done + 1}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(bool isLast) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (_i > 0)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _go(-1),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Previous'),
                ),
              ),
            if (_i > 0) const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: isLast ? _finish : () => _go(1),
                icon: Icon(isLast ? Icons.flag : Icons.arrow_forward),
                label: Text(isLast ? 'Finish' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
