/// Domain models for a generated weekly plan. These mirror the backend's
/// workout JSON schema (see backend/src/schema.js). Hand-written JSON so the app
/// builds with no code generation step.

int? _asInt(dynamic v) => v == null ? null : (v is int ? v : (v as num).toInt());

class Exercise {
  final String name;
  final String equipment;
  final int? sets;
  final int? reps;
  final int? durationSec;
  final String? targetLoad;
  final int? targetRpe;
  final int? restSec;
  final bool timed;
  final String notes;
  final String howTo;
  final String cues;

  const Exercise({
    required this.name,
    required this.equipment,
    this.sets,
    this.reps,
    this.durationSec,
    this.targetLoad,
    this.targetRpe,
    this.restSec,
    this.timed = false,
    this.notes = '',
    this.howTo = '',
    this.cues = '',
  });

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        name: j['name'] as String? ?? 'Exercise',
        equipment: j['equipment'] as String? ?? 'bodyweight',
        sets: _asInt(j['sets']),
        reps: _asInt(j['reps']),
        durationSec: _asInt(j['duration_sec']),
        targetLoad: j['target_load'] as String?,
        targetRpe: _asInt(j['target_rpe']),
        restSec: _asInt(j['rest_sec']),
        timed: j['timed'] as bool? ?? false,
        notes: j['notes'] as String? ?? '',
        howTo: j['how_to'] as String? ?? '',
        cues: j['cues'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'equipment': equipment,
        'sets': sets,
        'reps': reps,
        'duration_sec': durationSec,
        'target_load': targetLoad,
        'target_rpe': targetRpe,
        'rest_sec': restSec,
        'timed': timed,
        'notes': notes,
        'how_to': howTo,
        'cues': cues,
      };

  /// How many "sets" this exercise contributes to the player. Timed holds with
  /// no explicit set count still count as one tracked round.
  int get setCount => sets ?? 1;

  /// A short one-line prescription summary, e.g. "4 × 8 @ RPE 7" or "3 × 45s".
  String get prescription {
    final s = sets;
    if (timed || (durationSec != null && reps == null)) {
      final dur = durationSec != null ? '${durationSec}s' : '';
      return s != null ? '$s × $dur' : dur;
    }
    final r = reps != null ? '$reps' : '';
    final base = s != null && r.isNotEmpty ? '$s × $r' : r;
    if (targetLoad != null && targetLoad!.isNotEmpty && targetLoad != 'bodyweight') {
      return '$base @ $targetLoad';
    }
    return base;
  }
}

class Block {
  final String kind; // warmup | main | finisher | cooldown
  final List<Exercise> exercises;

  const Block({required this.kind, required this.exercises});

  factory Block.fromJson(Map<String, dynamic> j) => Block(
        kind: j['kind'] as String? ?? 'main',
        exercises: ((j['exercises'] as List?) ?? [])
            .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };

  String get label {
    switch (kind) {
      case 'warmup':
        return 'Warm-up';
      case 'finisher':
        return 'Finisher';
      case 'cooldown':
        return 'Cool-down';
      default:
        return 'Main work';
    }
  }
}

class PlannedSession {
  final String day; // Monday..Sunday
  final String type; // training | rest
  final String focus;
  final String rationale;
  final int? estimatedMinutes;
  final List<Block> blocks;

  const PlannedSession({
    required this.day,
    required this.type,
    required this.focus,
    required this.rationale,
    this.estimatedMinutes,
    this.blocks = const [],
  });

  bool get isTraining => type == 'training';

  factory PlannedSession.fromJson(Map<String, dynamic> j) => PlannedSession(
        day: j['day'] as String? ?? 'Monday',
        type: j['type'] as String? ?? 'rest',
        focus: j['focus'] as String? ?? '',
        rationale: j['rationale'] as String? ?? '',
        estimatedMinutes: _asInt(j['estimated_minutes']),
        blocks: ((j['blocks'] as List?) ?? [])
            .map((b) => Block.fromJson(b as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'day': day,
        'type': type,
        'focus': focus,
        'rationale': rationale,
        'estimated_minutes': estimatedMinutes,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  /// Flat list of every exercise in player order.
  List<Exercise> get allExercises => [for (final b in blocks) ...b.exercises];

  int get totalSets => allExercises.fold(0, (sum, e) => sum + e.setCount);
}

class WeeklyPlan {
  final String weekStart;
  final String rationale;
  final List<PlannedSession> sessions;

  const WeeklyPlan({
    required this.weekStart,
    required this.rationale,
    required this.sessions,
  });

  factory WeeklyPlan.fromJson(Map<String, dynamic> j) => WeeklyPlan(
        weekStart: j['week_start'] as String? ?? '',
        rationale: j['rationale'] as String? ?? '',
        sessions: ((j['sessions'] as List?) ?? [])
            .map((s) => PlannedSession.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'week_start': weekStart,
        'rationale': rationale,
        'sessions': sessions.map((s) => s.toJson()).toList(),
      };

  PlannedSession? sessionForDay(String day) {
    for (final s in sessions) {
      if (s.day == day) return s;
    }
    return null;
  }

  List<PlannedSession> get trainingSessions =>
      sessions.where((s) => s.isTraining).toList();
}
