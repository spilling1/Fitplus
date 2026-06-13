import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plan.dart';
import '../models/profile.dart';
import '../models/logs.dart';
import '../models/chat.dart';

/// Offline-first local persistence (PRD §7). Everything the app needs to run a
/// workout — the profile, the current plan, logs — is stored on-device as JSON
/// so a generated session runs with no connectivity.
class LocalStore {
  static const _kProfile = 'fitplus.profile';
  static const _kPlan = 'fitplus.plan';
  static const _kLogs = 'fitplus.logs';
  static const _kChat = 'fitplus.chat';
  static const _kBaseUrl = 'fitplus.baseUrl';

  final SharedPreferences _prefs;
  LocalStore(this._prefs);

  static Future<LocalStore> create() async =>
      LocalStore(await SharedPreferences.getInstance());

  // ---- Profile ----
  Profile loadProfile() {
    final raw = _prefs.getString(_kProfile);
    if (raw == null) return const Profile();
    return Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveProfile(Profile p) =>
      _prefs.setString(_kProfile, jsonEncode(p.toJson()));

  // ---- Current plan ----
  WeeklyPlan? loadPlan() {
    final raw = _prefs.getString(_kPlan);
    if (raw == null) return null;
    return WeeklyPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> savePlan(WeeklyPlan plan) =>
      _prefs.setString(_kPlan, jsonEncode(plan.toJson()));

  // ---- Session logs ----
  List<SessionLog> loadLogs() {
    final raw = _prefs.getString(_kLogs);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => SessionLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveLogs(List<SessionLog> logs) =>
      _prefs.setString(_kLogs, jsonEncode(logs.map((e) => e.toJson()).toList()));

  // ---- Chat history ----
  List<ChatMessage> loadChat() {
    final raw = _prefs.getString(_kChat);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveChat(List<ChatMessage> messages) => _prefs.setString(
      _kChat, jsonEncode(messages.map((e) => e.toJson()).toList()));

  // ---- Backend base URL (configurable for dev) ----
  String? get baseUrl => _prefs.getString(_kBaseUrl);
  Future<void> setBaseUrl(String url) => _prefs.setString(_kBaseUrl, url);

  /// Export everything for the data-ownership requirement (PRD §9 / §10).
  Map<String, dynamic> exportAll() => {
        'profile': loadProfile().toJson(),
        'plan': loadPlan()?.toJson(),
        'logs': loadLogs().map((e) => e.toJson()).toList(),
        'chat': loadChat().map((e) => e.toJson()).toList(),
      };

  /// Delete all user data (PRD §9 "own your data").
  Future<void> wipe() async {
    await _prefs.remove(_kProfile);
    await _prefs.remove(_kPlan);
    await _prefs.remove(_kLogs);
    await _prefs.remove(_kChat);
  }
}
