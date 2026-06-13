import 'package:flutter_test/flutter_test.dart';
import 'package:fitplus/src/models/plan.dart';
import 'package:fitplus/src/models/logs.dart';

void main() {
  group('WeeklyPlan parsing', () {
    final json = {
      'week_start': '2026-06-15',
      'rationale': 'Build week.',
      'sessions': [
        {
          'day': 'Monday',
          'type': 'training',
          'focus': 'Lower body',
          'rationale': 'Squat early.',
          'estimated_minutes': 45,
          'blocks': [
            {
              'kind': 'main',
              'exercises': [
                {
                  'name': 'Goblet Squat',
                  'equipment': 'dumbbells',
                  'sets': 4,
                  'reps': 8,
                  'duration_sec': null,
                  'target_load': '24kg',
                  'target_rpe': 7,
                  'rest_sec': 90,
                  'timed': false,
                  'notes': '',
                  'how_to': 'Sit back and down.',
                  'cues': 'Chest up.',
                },
                {
                  'name': 'Plank',
                  'equipment': 'bodyweight',
                  'sets': 3,
                  'reps': null,
                  'duration_sec': 45,
                  'target_load': null,
                  'target_rpe': null,
                  'rest_sec': 60,
                  'timed': true,
                  'notes': '',
                  'how_to': '',
                  'cues': '',
                },
              ],
            },
          ],
        },
        {'day': 'Tuesday', 'type': 'rest', 'focus': '', 'rationale': 'Recover.', 'estimated_minutes': null, 'blocks': []},
      ],
    };

    test('round-trips through JSON', () {
      final plan = WeeklyPlan.fromJson(json);
      expect(plan.weekStart, '2026-06-15');
      expect(plan.sessions.length, 2);
      expect(plan.trainingSessions.length, 1);
      final reparsed = WeeklyPlan.fromJson(plan.toJson());
      expect(reparsed.sessions.first.allExercises.length, 2);
    });

    test('prescription formatting handles reps and timed holds', () {
      final plan = WeeklyPlan.fromJson(json);
      final exercises = plan.sessions.first.allExercises;
      expect(exercises[0].prescription, '4 × 8 @ 24kg');
      expect(exercises[1].prescription, '3 × 45s');
    });

    test('totalSets counts timed holds as sets', () {
      final plan = WeeklyPlan.fromJson(json);
      expect(plan.sessions.first.totalSets, 7); // 4 + 3
    });
  });

  group('SetLog estimated 1RM', () {
    final ts = DateTime(2026, 6, 15);

    test('Epley formula for loaded reps', () {
      final s = SetLog(exerciseName: 'Squat', setIndex: 0, reps: 5, load: 100, timestamp: ts);
      // 100 * (1 + 5/30) = 116.67
      expect(s.estimatedOneRm!.toStringAsFixed(1), '116.7');
    });

    test('null for bodyweight/timed sets', () {
      final s = SetLog(exerciseName: 'Plank', setIndex: 0, durationSec: 45, timestamp: ts);
      expect(s.estimatedOneRm, isNull);
    });
  });
}
