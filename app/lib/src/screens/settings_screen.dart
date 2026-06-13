import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../state/providers.dart';
import '../widgets/multi_select.dart';

/// Profile editing + data ownership (PRD §5.1 edit-later, §9 export/delete, §10
/// safety). Any change here is respected by the next plan generation.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('You')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(context, 'Experience level'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Beginner', label: Text('Beginner')),
              ButtonSegment(value: 'Intermediate', label: Text('Inter.')),
              ButtonSegment(value: 'Advanced', label: Text('Advanced')),
            ],
            selected: {profile.level},
            onSelectionChanged: (s) => notifier.patch((p) => p.copyWith(level: s.first)),
          ),

          _section(context, 'Goals'),
          MultiSelectChips(
            options: kGoals,
            selected: profile.goals.toSet(),
            onToggle: (g) => notifier.patch((p) => p.copyWith(goals: _toggled(p.goals, g))),
          ),

          _section(context, 'Training days'),
          MultiSelectChips(
            options: kWeekDays,
            selected: profile.trainingDays.toSet(),
            labelOf: (d) => d.substring(0, 3),
            onToggle: (d) => notifier.patch((p) => p.copyWith(
                  trainingDays: kWeekDays.where(_toggled(p.trainingDays, d).contains).toList(),
                )),
          ),

          _section(context, 'Session length: ${profile.sessionMinutes} min'),
          Slider(
            value: profile.sessionMinutes.toDouble(),
            min: 15,
            max: 90,
            divisions: 15,
            label: '${profile.sessionMinutes} min',
            onChanged: (v) => notifier.patch((p) => p.copyWith(sessionMinutes: v.round())),
          ),

          _section(context, 'Equipment'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in EquipmentCatalogue.all)
                FilterChip(
                  selected: profile.equipment.contains(item.id),
                  label: Text('${item.emoji} ${item.label}'),
                  onSelected: (_) =>
                      notifier.patch((p) => p.copyWith(equipment: _toggled(p.equipment, item.id))),
                ),
            ],
          ),

          _section(context, 'Injuries & limitations'),
          MultiSelectChips(
            options: kCommonInjuries,
            selected: profile.injuries.toSet(),
            onToggle: (i) => notifier.patch((p) => p.copyWith(injuries: _toggled(p.injuries, i))),
          ),

          const Divider(height: 40),
          _section(context, 'Backend'),
          _BackendField(),

          const Divider(height: 40),
          _section(context, 'Your data'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: const Text('Export my data'),
            subtitle: const Text('Profile, plan, logs and chat as JSON'),
            onTap: () => _export(context, ref),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text('Delete everything', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            subtitle: const Text('Permanently erase all data on this device'),
            onTap: () => _delete(context, ref),
          ),

          const SizedBox(height: 24),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Row(children: [
                Icon(Icons.health_and_safety_outlined),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'FitPlus is a coach, not a doctor. It does not provide medical advice. '
                    'Stop and consult a professional if you feel pain (beyond normal soreness).',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<String> _toggled(List<String> list, String v) {
    final s = list.toList();
    s.contains(v) ? s.remove(v) : s.add(v);
    return s;
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      );

  void _export(BuildContext context, WidgetRef ref) {
    final data = const JsonEncoder.withIndent('  ').convert(ref.read(localStoreProvider).exportAll());
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Your data'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(data, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: data));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
            },
            child: const Text('Copy'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete everything?'),
        content: const Text('This permanently erases your profile, plan, logs and chat from this device. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(localStoreProvider).wipe();
    // Reload every provider from the now-empty store; FitPlusApp will route back
    // to onboarding because profile.onboarded is false again.
    ref.invalidate(profileProvider);
    ref.invalidate(planProvider);
    ref.invalidate(logsProvider);
    ref.invalidate(chatProvider);
  }
}

class _BackendField extends ConsumerStatefulWidget {
  @override
  ConsumerState<_BackendField> createState() => _BackendFieldState();
}

class _BackendFieldState extends ConsumerState<_BackendField> {
  late final TextEditingController _ctrl;
  String? _status;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: ref.read(localStoreProvider).baseUrl ?? kDefaultBaseUrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    await ref.read(localStoreProvider).setBaseUrl(_ctrl.text.trim());
    ref.invalidate(apiClientProvider);
    final ok = await ref.read(apiClientProvider).health();
    if (mounted) setState(() => _status = ok ? 'Connected ✓' : 'Could not reach backend');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ctrl,
          decoration: const InputDecoration(
            labelText: 'Backend URL',
            border: OutlineInputBorder(),
            helperText: 'Android emulator: http://10.0.2.2:8080 · iOS/web: http://localhost:8080',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.tonal(onPressed: _saveAndTest, child: const Text('Save & test')),
            const SizedBox(width: 12),
            if (_status != null) Text(_status!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}
