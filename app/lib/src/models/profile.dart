/// User fitness profile + equipment (PRD §5.1, §5.2). Single equipment location
/// for the MVP. Everything is optional/skippable; the AI fills gaps with
/// sensible defaults.

class Profile {
  final String? ageRange;
  final String? sex;
  final int? heightCm;
  final String units; // 'metric' | 'imperial'
  final String level; // Beginner | Intermediate | Advanced
  final List<String> goals;
  final List<String> trainingDays; // Monday..Sunday
  final int sessionMinutes;
  final String? timePref;
  final List<String> injuries;
  final List<String> equipment; // selected equipment types
  final String notes;
  final bool onboarded;

  const Profile({
    this.ageRange,
    this.sex,
    this.heightCm,
    this.units = 'metric',
    this.level = 'Beginner',
    this.goals = const [],
    this.trainingDays = const ['Monday', 'Wednesday', 'Friday'],
    this.sessionMinutes = 45,
    this.timePref,
    this.injuries = const [],
    this.equipment = const [],
    this.notes = '',
    this.onboarded = false,
  });

  Profile copyWith({
    String? ageRange,
    String? sex,
    int? heightCm,
    String? units,
    String? level,
    List<String>? goals,
    List<String>? trainingDays,
    int? sessionMinutes,
    String? timePref,
    List<String>? injuries,
    List<String>? equipment,
    String? notes,
    bool? onboarded,
  }) {
    return Profile(
      ageRange: ageRange ?? this.ageRange,
      sex: sex ?? this.sex,
      heightCm: heightCm ?? this.heightCm,
      units: units ?? this.units,
      level: level ?? this.level,
      goals: goals ?? this.goals,
      trainingDays: trainingDays ?? this.trainingDays,
      sessionMinutes: sessionMinutes ?? this.sessionMinutes,
      timePref: timePref ?? this.timePref,
      injuries: injuries ?? this.injuries,
      equipment: equipment ?? this.equipment,
      notes: notes ?? this.notes,
      onboarded: onboarded ?? this.onboarded,
    );
  }

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        ageRange: j['ageRange'] as String?,
        sex: j['sex'] as String?,
        heightCm: j['heightCm'] as int?,
        units: j['units'] as String? ?? 'metric',
        level: j['level'] as String? ?? 'Beginner',
        goals: (j['goals'] as List?)?.cast<String>() ?? const [],
        trainingDays: (j['trainingDays'] as List?)?.cast<String>() ??
            const ['Monday', 'Wednesday', 'Friday'],
        sessionMinutes: j['sessionMinutes'] as int? ?? 45,
        timePref: j['timePref'] as String?,
        injuries: (j['injuries'] as List?)?.cast<String>() ?? const [],
        equipment: (j['equipment'] as List?)?.cast<String>() ?? const [],
        notes: j['notes'] as String? ?? '',
        onboarded: j['onboarded'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'ageRange': ageRange,
        'sex': sex,
        'heightCm': heightCm,
        'units': units,
        'level': level,
        'goals': goals,
        'trainingDays': trainingDays,
        'sessionMinutes': sessionMinutes,
        'timePref': timePref,
        'injuries': injuries,
        'equipment': equipment,
        'notes': notes,
        'onboarded': onboarded,
      };

  /// The compact bundle the backend expects under `profile` for generation.
  Map<String, dynamic> toAiContext() => {
        'ageRange': ageRange,
        'sex': sex,
        'level': level,
        'goals': goals,
        'trainingDays': trainingDays,
        'sessionMinutes': sessionMinutes,
        'timePref': timePref,
        'injuries': injuries,
        'notes': notes,
        'units': units,
      };
}

/// The pre-populated equipment catalogue (PRD §5.2). `bodyweight` is implicit
/// and always available, so it's not in the selectable list.
class EquipmentCatalogue {
  static const List<EquipmentItem> all = [
    EquipmentItem('dumbbells', 'Dumbbells', '🏋️'),
    EquipmentItem('barbell', 'Barbell + plates', '🏋️'),
    EquipmentItem('kettlebells', 'Kettlebells', '🔔'),
    EquipmentItem('resistance bands', 'Resistance bands', '➰'),
    EquipmentItem('pull-up bar', 'Pull-up bar', '🚪'),
    EquipmentItem('bench', 'Bench', '🪑'),
    EquipmentItem('squat rack', 'Squat rack', '🗜️'),
    EquipmentItem('cable machine', 'Cable machine', '🔧'),
    EquipmentItem('treadmill', 'Treadmill / cardio machine', '🏃'),
    EquipmentItem('medicine ball', 'Medicine ball', '⚽'),
    EquipmentItem('yoga mat', 'Yoga mat', '🧘'),
    EquipmentItem('jump rope', 'Jump rope', '🪢'),
  ];
}

class EquipmentItem {
  final String id;
  final String label;
  final String emoji;
  const EquipmentItem(this.id, this.label, this.emoji);
}

const kWeekDays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const kGoals = [
  'build strength',
  'build muscle',
  'improve endurance/cardio',
  'lose fat',
  'improve mobility/flexibility',
  'general health',
];

const kCommonInjuries = [
  'bad knees',
  'lower-back issues',
  'shoulder issues',
  'wrist pain',
  'neck issues',
  'ankle issues',
];
