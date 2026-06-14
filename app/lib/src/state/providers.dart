import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/local_store.dart';
import '../models/plan.dart';
import '../models/profile.dart';
import '../models/logs.dart';
import '../models/chat.dart';

/// Default backend address. 10.0.2.2 is the host loopback from the Android
/// emulator; override with --dart-define=FITPLUS_API=http://localhost:8080 for
/// iOS simulator / web, or change it in Settings at runtime.
const String kDefaultBaseUrl =
    String.fromEnvironment('FITPLUS_API', defaultValue: 'http://10.0.2.2:8080');

/// Injected in main() once SharedPreferences has loaded.
final localStoreProvider = Provider<LocalStore>((ref) {
  throw UnimplementedError('localStoreProvider must be overridden in main()');
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final store = ref.watch(localStoreProvider);
  return ApiClient(baseUrl: store.baseUrl ?? kDefaultBaseUrl);
});

// --------------------------------------------------------------------------
// Profile
// --------------------------------------------------------------------------
class ProfileNotifier extends Notifier<Profile> {
  @override
  Profile build() => ref.read(localStoreProvider).loadProfile();

  void update(Profile next) {
    state = next;
    ref.read(localStoreProvider).saveProfile(next);
  }

  void patch(Profile Function(Profile) f) => update(f(state));
}

final profileProvider =
    NotifierProvider<ProfileNotifier, Profile>(ProfileNotifier.new);

// --------------------------------------------------------------------------
// Current plan
// --------------------------------------------------------------------------
class PlanNotifier extends Notifier<WeeklyPlan?> {
  @override
  WeeklyPlan? build() => ref.read(localStoreProvider).loadPlan();

  void set(WeeklyPlan plan) {
    state = plan;
    ref.read(localStoreProvider).savePlan(plan);
  }
}

final planProvider =
    NotifierProvider<PlanNotifier, WeeklyPlan?>(PlanNotifier.new);

// --------------------------------------------------------------------------
// Session logs
// --------------------------------------------------------------------------
class LogsNotifier extends Notifier<List<SessionLog>> {
  @override
  List<SessionLog> build() => ref.read(localStoreProvider).loadLogs();

  void upsert(SessionLog log) {
    final next = [...state];
    final i = next.indexWhere((l) => l.id == log.id);
    if (i >= 0) {
      next[i] = log;
    } else {
      next.add(log);
    }
    state = next;
    ref.read(localStoreProvider).saveLogs(next);
  }

  /// Most recent completed/partial log for a given plan day, if any.
  SessionLog? latestForDay(String weekStart, String day) {
    final matches = state
        .where((l) => l.weekStart == weekStart && l.day == day)
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return matches.isEmpty ? null : matches.first;
  }
}

final logsProvider =
    NotifierProvider<LogsNotifier, List<SessionLog>>(LogsNotifier.new);

// --------------------------------------------------------------------------
// Chat history
// --------------------------------------------------------------------------
class ChatNotifier extends Notifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() => ref.read(localStoreProvider).loadChat();

  void add(ChatMessage m) {
    final next = [...state, m];
    state = next;
    ref.read(localStoreProvider).saveChat(next);
  }

  void clear() {
    state = [];
    ref.read(localStoreProvider).saveChat([]);
  }
}

final chatProvider =
    NotifierProvider<ChatNotifier, List<ChatMessage>>(ChatNotifier.new);

// --------------------------------------------------------------------------
// Plan generation orchestration
// --------------------------------------------------------------------------
class GenState {
  final bool loading;
  final String? error;
  final List<String> warnings;
  final String? source;
  const GenState({
    this.loading = false,
    this.error,
    this.warnings = const [],
    this.source,
  });
}

class PlanController extends Notifier<GenState> {
  @override
  GenState build() => const GenState();

  /// Generate (or adapt) the week's plan. When [adapt] is true, recent logs are
  /// summarised and sent so the new week reflects what actually happened.
  /// [adjustment] carries free-text from the weekly check-in ("ease off this
  /// week", "I'm feeling great", schedule notes, …).
  Future<void> generate({bool adapt = false, String? adjustment}) async {
    state = const GenState(loading: true);
    final profile = ref.read(profileProvider);
    final api = ref.read(apiClientProvider);
    final previous = ref.read(planProvider);

    try {
      final result = await api.generatePlan(
        profile: profile,
        history: adapt ? _buildHistorySummary() : null,
        previousPlan: adapt ? previous : null,
        adjustment: adjustment,
      );
      ref.read(planProvider.notifier).set(result.plan);
      state = GenState(
        loading: false,
        warnings: result.warnings,
        source: result.source,
      );
    } catch (e) {
      state = GenState(loading: false, error: e.toString());
    }
  }

  /// Aggregate recent logs into the compact summary the adaptation engine wants
  /// (PRD §5.9): adherence, average session RPE, pain flags.
  Map<String, dynamic> _buildHistorySummary() {
    final plan = ref.read(planProvider);
    final logs = ref.read(logsProvider);
    if (plan == null) return {};

    final planned = plan.trainingSessions.length;
    final completed = logs
        .where((l) => l.weekStart == plan.weekStart && l.status != 'skipped')
        .length;

    final rpes = logs
        .where((l) => l.survey?.difficulty != null)
        .map((l) => l.survey!.difficulty!)
        .toList();
    final avgRpe = rpes.isEmpty
        ? null
        : (rpes.reduce((a, b) => a + b) / rpes.length).toStringAsFixed(1);

    final painFlags = <String>{
      for (final l in logs)
        if (l.survey != null) ...l.survey!.painAreas,
    }.toList();

    return {
      'previousWeekStart': plan.weekStart,
      'plannedSessions': planned,
      'completedSessions': completed,
      'adherence': planned == 0
          ? null
          : '${((completed / planned) * 100).round()}%',
      'averageSessionRpe': avgRpe,
      'painFlags': painFlags,
      'note': avgRpe != null && double.parse(avgRpe) >= 8
          ? 'Sessions felt hard — consider easing volume/intensity.'
          : null,
    };
  }
}

final planControllerProvider =
    NotifierProvider<PlanController, GenState>(PlanController.new);
