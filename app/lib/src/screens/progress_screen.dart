import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../models/logs.dart';
import '../state/providers.dart';

/// Progress tracking (PRD §5.6). Renders from logged data and updates after each
/// session. Encouraging empty states; celebratory but not shame-based.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(logsProvider);
    final completed = logs.where((l) => l.status != 'skipped').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: completed.isEmpty
          ? _empty(context)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryRow(logs: completed),
                const SizedBox(height: 16),
                _ConsistencyChart(logs: completed),
                const SizedBox(height: 16),
                _StrengthChart(logs: completed),
                const SizedBox(height: 16),
                _PrList(logs: completed),
                const SizedBox(height: 16),
                _HistoryList(logs: logs),
              ],
            ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insights, size: 56),
              const SizedBox(height: 16),
              Text('Your progress starts here', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Finish a session and your consistency, strength trends and personal records will show up here.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      );
}

class _SummaryRow extends StatelessWidget {
  final List<SessionLog> logs;
  const _SummaryRow({required this.logs});

  @override
  Widget build(BuildContext context) {
    final totalSets = logs.fold<int>(0, (s, l) => s + l.completedSetCount);
    final volume = logs.fold<double>(0, (s, l) => s + l.totalVolume);
    return Row(
      children: [
        _stat(context, '${logs.length}', 'sessions'),
        _stat(context, '$totalSets', 'sets'),
        _stat(context, '${(volume / 1000).toStringAsFixed(1)}t', 'volume'),
      ],
    );
  }

  Widget _stat(BuildContext context, String value, String label) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Text(value, style: Theme.of(context).textTheme.headlineSmall),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );
}

class _ConsistencyChart extends StatelessWidget {
  final List<SessionLog> logs;
  const _ConsistencyChart({required this.logs});

  @override
  Widget build(BuildContext context) {
    // Sessions completed per ISO week-start.
    final byWeek = <String, int>{};
    for (final l in logs) {
      byWeek[l.weekStart] = (byWeek[l.weekStart] ?? 0) + 1;
    }
    final weeks = byWeek.keys.toList()..sort();
    final scheme = Theme.of(context).colorScheme;

    return _Card(
      title: 'Consistency',
      child: SizedBox(
        height: 160,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(show: true, drawVerticalLine: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= weeks.length) return const SizedBox.shrink();
                    final d = DateTime.tryParse(weeks[i]);
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(d != null ? DateFormat('d MMM').format(d) : '',
                          style: const TextStyle(fontSize: 10)),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < weeks.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: byWeek[weeks[i]]!.toDouble(),
                    color: scheme.primary,
                    width: 18,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _StrengthChart extends StatelessWidget {
  final List<SessionLog> logs;
  const _StrengthChart({required this.logs});

  @override
  Widget build(BuildContext context) {
    // Pick the exercise with the most loaded sets and trend its est. 1RM.
    final byExercise = <String, List<SetLog>>{};
    for (final l in logs) {
      for (final s in l.sets) {
        if (s.estimatedOneRm != null) {
          byExercise.putIfAbsent(s.exerciseName, () => []).add(s);
        }
      }
    }
    if (byExercise.isEmpty) {
      return _Card(
        title: 'Strength trend',
        child: Text('Log some weighted sets to see your estimated 1RM climb.',
            style: Theme.of(context).textTheme.bodySmall),
      );
    }

    final top = byExercise.entries.reduce((a, b) => a.value.length >= b.value.length ? a : b);
    final sets = [...top.value]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    // Best est-1RM per day, in order.
    final spots = <FlSpot>[];
    for (var i = 0; i < sets.length; i++) {
      spots.add(FlSpot(i.toDouble(), sets[i].estimatedOneRm!));
    }
    final scheme = Theme.of(context).colorScheme;

    return _Card(
      title: 'Strength trend · ${top.key}',
      child: SizedBox(
        height: 180,
        child: LineChart(
          LineChartData(
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(show: true, drawVerticalLine: false),
            titlesData: const FlTitlesData(
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 34)),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                barWidth: 3,
                color: scheme.primary,
                dotData: const FlDotData(show: true),
                belowBarData: BarAreaData(show: true, color: scheme.primary.withValues(alpha: 0.12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrList extends StatelessWidget {
  final List<SessionLog> logs;
  const _PrList({required this.logs});

  @override
  Widget build(BuildContext context) {
    // Best estimated 1RM per exercise = a personal record.
    final prs = <String, double>{};
    for (final l in logs) {
      for (final s in l.sets) {
        final e1rm = s.estimatedOneRm;
        if (e1rm != null && e1rm > (prs[s.exerciseName] ?? 0)) {
          prs[s.exerciseName] = e1rm;
        }
      }
    }
    if (prs.isEmpty) return const SizedBox.shrink();
    final entries = prs.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return _Card(
      title: 'Personal records',
      child: Column(
        children: [
          for (final e in entries.take(6))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Text('🏆', style: TextStyle(fontSize: 20)),
              title: Text(e.key),
              trailing: Text('${e.value.toStringAsFixed(1)} kg est. 1RM',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  final List<SessionLog> logs;
  const _HistoryList({required this.logs});

  @override
  Widget build(BuildContext context) {
    final sorted = [...logs]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return _Card(
      title: 'History',
      child: Column(
        children: [
          for (final l in sorted.take(20))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_statusIcon(l.status)),
              title: Text('${DateFormat('EEE d MMM').format(l.startedAt)} · ${l.focus.isEmpty ? l.day : l.focus}'),
              subtitle: Text('${l.completedSetCount} sets'
                  '${l.survey?.difficulty != null ? ' · RPE ${l.survey!.difficulty}' : ''}'),
              trailing: Text(l.status, style: Theme.of(context).textTheme.labelSmall),
            ),
        ],
      ),
    );
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'skipped':
        return Icons.remove_circle_outline;
      default:
        return Icons.timelapse;
    }
  }
}
