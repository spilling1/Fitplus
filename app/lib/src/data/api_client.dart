import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/plan.dart';
import '../models/profile.dart';
import '../models/chat.dart';

/// Result of a plan generation, including any guardrail adjustments the backend
/// made (e.g. "substituted a bodyweight option") and whether it came from the
/// AI or the offline stub.
class PlanResult {
  final WeeklyPlan plan;
  final List<String> warnings;
  final String source; // ai | stub | stub-fallback
  PlanResult(this.plan, this.warnings, this.source);
}

class ChatResult {
  final String reply;
  final WeeklyPlan? updatedPlan;
  final List<String> warnings;
  ChatResult(this.reply, this.updatedPlan, this.warnings);
}

/// Talks to the FitPlus backend AI proxy. The Anthropic key lives on the
/// backend, never here (PRD §6 critical security rule).
class ApiClient {
  final String baseUrl;
  final http.Client _http;

  ApiClient({required this.baseUrl, http.Client? client})
      : _http = client ?? http.Client();

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<bool> health() async {
    try {
      final res = await _http
          .get(_uri('/health'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<PlanResult> generatePlan({
    required Profile profile,
    String? weekStart,
    Map<String, dynamic>? history,
    WeeklyPlan? previousPlan,
  }) async {
    final body = {
      'profile': profile.toAiContext(),
      'equipment': profile.equipment,
      if (weekStart != null) 'weekStart': weekStart,
      if (history != null) 'history': history,
      if (previousPlan != null) 'previousPlan': previousPlan.toJson(),
    };

    final res = await _http
        .post(_uri('/api/plan/generate'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));

    if (res.statusCode != 200) {
      throw ApiException('Plan generation failed (${res.statusCode}).');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return PlanResult(
      WeeklyPlan.fromJson(json['plan'] as Map<String, dynamic>),
      ((json['warnings'] as List?) ?? []).cast<String>(),
      json['source'] as String? ?? 'ai',
    );
  }

  Future<ChatResult> chat({
    required WeeklyPlan currentPlan,
    required List<ChatMessage> history,
    required String message,
    required List<String> equipment,
  }) async {
    final body = {
      'currentPlan': currentPlan.toJson(),
      'history': history.map((m) => m.toWire()).toList(),
      'message': message,
      'equipment': equipment,
    };

    final res = await _http
        .post(_uri('/api/chat'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw ApiException(json['error'] as String? ?? 'Chat failed.');
    }
    return ChatResult(
      json['reply'] as String? ?? '',
      json['updatedPlan'] != null
          ? WeeklyPlan.fromJson(json['updatedPlan'] as Map<String, dynamic>)
          : null,
      ((json['warnings'] as List?) ?? []).cast<String>(),
    );
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
