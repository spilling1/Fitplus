/// User fitness profile + equipment (PRD §5.1, §5.2).
///
/// Equipment is modelled as **training locations** (Home, Gym, Pool, …), each
/// with its own gear, and a mapping of weekday -> location. This lets a user say
/// "I'm at the gym Mon/Wed/Fri but home on Saturday" and have each session use
/// the equipment they actually have that day. When no locations are configured
/// the flat [equipment] list is used as a single implicit "Anywhere" location,
/// so simple setups stay simple.

class TrainingLocation {
  final String name; // Home / Gym / Pool / Hotel
  final List<String> equipment; // equipment ids available here

  const TrainingLocation({required this.name, this.equipment = const []});

  TrainingLocation copyWith({String? name, List<String>? equipment}) =>
      TrainingLocation(name: name ?? this.name, equipment: equipment ?? this.equipment);

  factory TrainingLocation.fromJson(Map<String, dynamic> j) => TrainingLocation(
        name: j['name'] as String? ?? 'Anywhere',
        equipment: (j['equipment'] as List?)?.cast<String>() ?? const [],
      );

  Map<String, dynamic> toJson() => {'name': name, 'equipment': equipment};
}

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
  final List<String> equipment; // default ("Anywhere") set, used when no locations
  final List<TrainingLocation> locations; // optional per-place equipment
  final Map<String, String> dayLocation; // weekday -> location name
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
    this.locations = const [],
    this.dayLocation = const {},
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
    List<TrainingLocation>? locations,
    Map<String, String>? dayLocation,
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
      locations: locations ?? this.locations,
      dayLocation: dayLocation ?? this.dayLocation,
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
        locations: ((j['locations'] as List?) ?? [])
            .map((e) => TrainingLocation.fromJson(e as Map<String, dynamic>))
            .toList(),
        dayLocation: ((j['dayLocation'] as Map?) ?? {}).map((k, v) => MapEntry('$k', '$v')),
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
        'locations': locations.map((l) => l.toJson()).toList(),
        'dayLocation': dayLocation,
        'notes': notes,
        'onboarded': onboarded,
      };

  /// Build a Profile from the AI intake's structured object (snake_case, with
  /// day_locations as an array). Fills sensible defaults for anything missing.
  factory Profile.fromIntake(Map<String, dynamic> j) {
    final locs = ((j['locations'] as List?) ?? [])
        .map((l) => TrainingLocation(
              name: (l as Map)['name'] as String? ?? 'Anywhere',
              equipment: (l['equipment'] as List?)?.cast<String>() ?? const [],
            ))
        .where((l) => l.name.trim().isNotEmpty)
        .toList();

    final dayLoc = <String, String>{};
    for (final d in (j['day_locations'] as List?) ?? []) {
      final m = d as Map;
      final day = m['day'] as String?;
      final loc = m['location'] as String?;
      if (day != null && loc != null) dayLoc[day] = loc;
    }

    String level = 'Beginner';
    final lvl = (j['level'] as String?)?.toLowerCase();
    if (lvl != null) {
      for (final c in ['Beginner', 'Intermediate', 'Advanced']) {
        if (c.toLowerCase() == lvl) level = c;
      }
    }

    final days = ((j['training_days'] as List?)?.cast<String>() ?? const [])
        .where(kWeekDays.contains)
        .toList();

    return Profile(
      level: level,
      goals: (j['goals'] as List?)?.cast<String>() ?? const [],
      trainingDays: days.isEmpty ? const ['Monday', 'Wednesday', 'Friday'] : days,
      sessionMinutes: (j['session_minutes'] as int?) ?? 45,
      injuries: (j['injuries'] as List?)?.cast<String>() ?? const [],
      notes: j['notes'] as String? ?? '',
      locations: locs,
      dayLocation: dayLoc,
      equipment: {for (final l in locs) ...l.equipment}.toList(),
      onboarded: true,
    );
  }

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

  // ---- Equipment resolution ----

  /// Locations to actually use: configured ones, or a single implicit
  /// "Anywhere" location from the flat [equipment] list.
  List<TrainingLocation> effectiveLocations() => locations.isNotEmpty
      ? locations
      : [TrainingLocation(name: 'Anywhere', equipment: equipment)];

  /// Which location a given day maps to (falls back to the first location).
  String locationForDay(String day) {
    final locs = effectiveLocations();
    final assigned = dayLocation[day];
    if (assigned != null && locs.any((l) => l.name == assigned)) return assigned;
    return locs.first.name;
  }

  /// Equipment available on each training day: { Monday: [...], ... }.
  Map<String, List<String>> equipmentByDay() {
    final byName = {for (final l in effectiveLocations()) l.name: l.equipment};
    final out = <String, List<String>>{};
    for (final day in trainingDays) {
      out[day] = byName[locationForDay(day)] ?? const [];
    }
    return out;
  }

  /// Union of all equipment across locations — used as the chat/global set.
  List<String> allEquipment() =>
      {for (final l in effectiveLocations()) ...l.equipment}.toList();
}

/// The pre-populated equipment catalogue (PRD §5.2), grouped for the picker.
/// `bodyweight` is implicit and always available, so it's not selectable.
class EquipmentCatalogue {
  static const List<EquipmentGroup> groups = [
    EquipmentGroup('Free weights & basics', [
      EquipmentItem('dumbbells', 'Dumbbells', '🏋️'),
      EquipmentItem('barbell', 'Barbell + plates', '🏋️'),
      EquipmentItem('kettlebells', 'Kettlebells', '🔔'),
      EquipmentItem('resistance bands', 'Resistance bands', '➰'),
      EquipmentItem('pull-up bar', 'Pull-up bar', '🚪'),
      EquipmentItem('bench', 'Bench', '🪑'),
      EquipmentItem('squat rack', 'Squat rack', '🗜️'),
      EquipmentItem('medicine ball', 'Medicine ball', '⚽'),
      EquipmentItem('yoga mat', 'Yoga mat', '🧘'),
      EquipmentItem('jump rope', 'Jump rope', '🪢'),
      EquipmentItem('dip bars', 'Dip bars', '🤸'),
    ]),
    EquipmentGroup('Gym machines', [
      EquipmentItem('full gym', 'Full gym (all standard equipment)', '🏟️'),
      EquipmentItem('cable machine', 'Cable machine', '🔧'),
      EquipmentItem('smith machine', 'Smith machine', '🏗️'),
      EquipmentItem('leg press', 'Leg press', '🦵'),
      EquipmentItem('lat pulldown', 'Lat pulldown', '🔻'),
      EquipmentItem('chest press machine', 'Chest press machine', '💪'),
      EquipmentItem('leg curl machine', 'Leg curl', '🦿'),
      EquipmentItem('leg extension machine', 'Leg extension', '🦵'),
    ]),
    EquipmentGroup('Cardio', [
      EquipmentItem('treadmill', 'Treadmill', '🏃'),
      EquipmentItem('peloton bike', 'Peloton bike', '🚴'),
      EquipmentItem('peloton tread', 'Peloton tread', '🏃'),
      EquipmentItem('stationary bike', 'Stationary bike', '🚲'),
      EquipmentItem('spin bike', 'Spin bike', '🚴'),
      EquipmentItem('rowing machine', 'Rowing machine (erg)', '🚣'),
      EquipmentItem('elliptical', 'Elliptical', '🌀'),
      EquipmentItem('pool', 'Pool (swimming)', '🏊'),
    ]),
  ];

  /// Flat list of every selectable item, across groups.
  static List<EquipmentItem> get all => [for (final g in groups) ...g.items];

  static String labelFor(String id) {
    for (final it in all) {
      if (it.id == id) return it.label;
    }
    return id;
  }
}

class EquipmentGroup {
  final String title;
  final List<EquipmentItem> items;
  const EquipmentGroup(this.title, this.items);
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
