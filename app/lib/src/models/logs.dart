/// Session logging + post-workout survey models (PRD §5.4, §5.9). The session
/// log is the source of truth that feeds progress charts and weekly adaptation.

class SetLog {
  final String exerciseName;
  final int setIndex;
  final int? reps;
  final double? load; // kg or lb depending on units
  final int? durationSec;
  final int? rpe;
  final DateTime timestamp;

  const SetLog({
    required this.exerciseName,
    required this.setIndex,
    this.reps,
    this.load,
    this.durationSec,
    this.rpe,
    required this.timestamp,
  });

  factory SetLog.fromJson(Map<String, dynamic> j) => SetLog(
        exerciseName: j['exerciseName'] as String? ?? '',
        setIndex: j['setIndex'] as int? ?? 0,
        reps: j['reps'] as int?,
        load: (j['load'] as num?)?.toDouble(),
        durationSec: j['durationSec'] as int?,
        rpe: j['rpe'] as int?,
        timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'exerciseName': exerciseName,
        'setIndex': setIndex,
        'reps': reps,
        'load': load,
        'durationSec': durationSec,
        'rpe': rpe,
        'timestamp': timestamp.toIso8601String(),
      };

  /// Estimated 1RM (Epley) for strength-trend charts. Null if not a loaded
  /// rep-based set.
  double? get estimatedOneRm {
    if (load == null || load == 0 || reps == null || reps == 0) return null;
    return load! * (1 + reps! / 30.0);
  }
}

class Survey {
  final int? difficulty; // 1-10 RPE for the whole session
  final int? energy; // 1-5
  final int? enjoyment; // 1-5
  final List<String> painAreas;
  final String note;
  final bool skipped;

  const Survey({
    this.difficulty,
    this.energy,
    this.enjoyment,
    this.painAreas = const [],
    this.note = '',
    this.skipped = false,
  });

  factory Survey.fromJson(Map<String, dynamic> j) => Survey(
        difficulty: j['difficulty'] as int?,
        energy: j['energy'] as int?,
        enjoyment: j['enjoyment'] as int?,
        painAreas: (j['painAreas'] as List?)?.cast<String>() ?? const [],
        note: j['note'] as String? ?? '',
        skipped: j['skipped'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'difficulty': difficulty,
        'energy': energy,
        'enjoyment': enjoyment,
        'painAreas': painAreas,
        'note': note,
        'skipped': skipped,
      };
}

class SessionLog {
  final String id;
  final String weekStart;
  final String day;
  final String focus;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String status; // completed | partial | skipped
  final List<SetLog> sets;
  final Survey? survey;

  const SessionLog({
    required this.id,
    required this.weekStart,
    required this.day,
    required this.focus,
    required this.startedAt,
    this.completedAt,
    this.status = 'partial',
    this.sets = const [],
    this.survey,
  });

  SessionLog copyWith({
    DateTime? completedAt,
    String? status,
    List<SetLog>? sets,
    Survey? survey,
  }) =>
      SessionLog(
        id: id,
        weekStart: weekStart,
        day: day,
        focus: focus,
        startedAt: startedAt,
        completedAt: completedAt ?? this.completedAt,
        status: status ?? this.status,
        sets: sets ?? this.sets,
        survey: survey ?? this.survey,
      );

  factory SessionLog.fromJson(Map<String, dynamic> j) => SessionLog(
        id: j['id'] as String? ?? '',
        weekStart: j['weekStart'] as String? ?? '',
        day: j['day'] as String? ?? '',
        focus: j['focus'] as String? ?? '',
        startedAt: DateTime.tryParse(j['startedAt'] as String? ?? '') ?? DateTime.now(),
        completedAt: j['completedAt'] != null ? DateTime.tryParse(j['completedAt'] as String) : null,
        status: j['status'] as String? ?? 'partial',
        sets: ((j['sets'] as List?) ?? []).map((s) => SetLog.fromJson(s as Map<String, dynamic>)).toList(),
        survey: j['survey'] != null ? Survey.fromJson(j['survey'] as Map<String, dynamic>) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'weekStart': weekStart,
        'day': day,
        'focus': focus,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'status': status,
        'sets': sets.map((s) => s.toJson()).toList(),
        'survey': survey?.toJson(),
      };

  int get completedSetCount => sets.length;
  double get totalVolume => sets.fold(0.0, (sum, s) {
        if (s.load != null && s.reps != null) return sum + s.load! * s.reps!;
        return sum;
      });
}
