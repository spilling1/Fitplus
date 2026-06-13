/// Chat message model for the AI coach conversation (PRD §5.5).

class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime createdAt;

  /// Set on assistant messages that carried a plan edit, so the UI can show a
  /// "Plan updated" affordance.
  final bool changedPlan;

  const ChatMessage({
    required this.role,
    required this.content,
    required this.createdAt,
    this.changedPlan = false,
  });

  bool get isUser => role == 'user';

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: j['role'] as String? ?? 'assistant',
        content: j['content'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        changedPlan: j['changedPlan'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'changedPlan': changedPlan,
      };

  /// Compact form sent to the backend as conversation history.
  Map<String, dynamic> toWire() => {'role': role, 'content': content};
}
