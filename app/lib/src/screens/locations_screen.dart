import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../state/providers.dart';

/// Manage training locations and which one applies on each day (PRD §5.2 —
/// multiple equipment locations). E.g. "Gym" Mon/Wed/Fri, "Home" Saturday.
/// Each session is then generated against the equipment available that day.
class LocationsScreen extends ConsumerStatefulWidget {
  const LocationsScreen({super.key});

  @override
  ConsumerState<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends ConsumerState<LocationsScreen> {
  late List<TrainingLocation> _locations;
  late Map<String, String> _dayLocation;

  @override
  void initState() {
    super.initState();
    final p = ref.read(profileProvider);
    // Seed from configured locations, or from the flat equipment list as a
    // single "Home" location to get the user started.
    _locations = p.locations.isNotEmpty
        ? p.locations.map((l) => l.copyWith()).toList()
        : [TrainingLocation(name: 'Home', equipment: [...p.equipment])];
    _dayLocation = {...p.dayLocation};
  }

  void _commit() {
    ref.read(profileProvider.notifier).patch((p) => p.copyWith(
          locations: _locations,
          dayLocation: _dayLocation,
        ));
  }

  void _addLocation() async {
    final name = await _nameDialog('New location', '');
    if (name == null || name.trim().isEmpty) return;
    setState(() => _locations = [..._locations, TrainingLocation(name: name.trim())]);
    _commit();
  }

  void _rename(int i) async {
    final old = _locations[i].name;
    final name = await _nameDialog('Rename location', old);
    if (name == null || name.trim().isEmpty || name.trim() == old) return;
    final next = [..._locations];
    next[i] = next[i].copyWith(name: name.trim());
    setState(() {
      _locations = next;
      // Keep day assignments pointing at the renamed location.
      _dayLocation = {
        for (final e in _dayLocation.entries) e.key: e.value == old ? name.trim() : e.value
      };
    });
    _commit();
  }

  void _delete(int i) {
    if (_locations.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep at least one location.')),
      );
      return;
    }
    final removed = _locations[i].name;
    final next = [..._locations]..removeAt(i);
    final fallback = next.first.name;
    setState(() {
      _locations = next;
      _dayLocation = {
        for (final e in _dayLocation.entries) e.key: e.value == removed ? fallback : e.value
      };
    });
    _commit();
  }

  void _toggleEquip(int i, String id) {
    final loc = _locations[i];
    final eq = [...loc.equipment];
    eq.contains(id) ? eq.remove(id) : eq.add(id);
    final next = [..._locations];
    next[i] = loc.copyWith(equipment: eq);
    setState(() => _locations = next);
    _commit();
  }

  void _assignDay(String day, String locationName) {
    setState(() => _dayLocation = {..._dayLocation, day: locationName});
    _commit();
  }

  Future<String?> _nameDialog(String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Gym, Home, Hotel, Pool'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
  }

  String _locationName(String day) {
    final assigned = _dayLocation[day];
    if (assigned != null && _locations.any((l) => l.name == assigned)) return assigned;
    return _locations.first.name;
  }

  @override
  Widget build(BuildContext context) {
    final trainingDays = ref.watch(profileProvider.select((p) => p.trainingDays));

    return Scaffold(
      appBar: AppBar(title: const Text('Equipment by day')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addLocation,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add location'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Text(
            'Set up the places you train and what gear each has. Then pick which '
            'location you’re at on each training day — your plan will only use the '
            'equipment available that day.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),

          Text('Locations', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < _locations.length; i++) _locationCard(i),

          const SizedBox(height: 24),
          Text('Which location each day', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (trainingDays.isEmpty)
            Text('Pick your training days in the You tab first.',
                style: Theme.of(context).textTheme.bodySmall)
          else
            Card(
              child: Column(
                children: [
                  for (final day in trainingDays)
                    ListTile(
                      title: Text(day),
                      trailing: DropdownButton<String>(
                        value: _locationName(day),
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final l in _locations)
                            DropdownMenuItem(value: l.name, child: Text(l.name)),
                        ],
                        onChanged: (v) {
                          if (v != null) _assignDay(day, v);
                        },
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _locationCard(int i) {
    final loc = _locations[i];
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(loc.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(loc.equipment.isEmpty
              ? 'Bodyweight only'
              : '${loc.equipment.length} item${loc.equipment.length == 1 ? '' : 's'}'),
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'rename') _rename(i);
              if (v == 'delete') _delete(i);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            for (final group in EquipmentCatalogue.groups) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Text(group.title, style: Theme.of(context).textTheme.labelMedium),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in group.items)
                    FilterChip(
                      selected: loc.equipment.contains(item.id),
                      label: Text('${item.emoji} ${item.label}'),
                      onSelected: (_) => _toggleEquip(i, item.id),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
