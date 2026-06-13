import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat.dart';
import '../models/plan.dart';
import '../state/providers.dart';

/// The conversational coach (PRD §5.5). Ask questions, request changes. When the
/// AI proposes a plan edit, the user confirms before it overwrites the plan.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  static const _suggestions = [
    'Why am I doing these exercises?',
    'I only have 30 minutes today',
    'Make next week a bit harder',
    'Swap running for cycling',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _sending) return;
    final plan = ref.read(planProvider);
    if (plan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generate a plan first, then we can chat about it.')),
      );
      return;
    }

    final chat = ref.read(chatProvider.notifier);
    chat.add(ChatMessage(role: 'user', content: text, createdAt: DateTime.now()));
    _input.clear();
    setState(() => _sending = true);
    _scrollToEnd();

    try {
      final history = ref.read(chatProvider);
      final result = await ref.read(apiClientProvider).chat(
            currentPlan: plan,
            history: history.length > 1 ? history.sublist(0, history.length - 1) : const [],
            message: text,
            equipment: ref.read(profileProvider).equipment,
          );

      chat.add(ChatMessage(
        role: 'assistant',
        content: result.reply,
        createdAt: DateTime.now(),
        changedPlan: result.updatedPlan != null,
      ));

      if (result.updatedPlan != null && mounted) {
        await _confirmPlanChange(result.updatedPlan!, result.warnings);
      }
    } catch (e) {
      chat.add(ChatMessage(
        role: 'assistant',
        content: 'Sorry — I had trouble reaching the coach. $e',
        createdAt: DateTime.now(),
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  /// Material changes are confirmed before they overwrite the plan, and are
  /// undoable (PRD §5.5 AC).
  Future<void> _confirmPlanChange(WeeklyPlan updated, List<String> warnings) async {
    final previous = ref.read(planProvider);
    final apply = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Apply this change?', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('The coach updated your plan based on your message.'),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final w in warnings) Text('• $w', style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep current'))),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply update'))),
              ],
            ),
          ],
        ),
      ),
    );

    if (apply == true) {
      ref.read(planProvider.notifier).set(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Plan updated'),
          action: previous == null
              ? null
              : SnackBarAction(label: 'Undo', onPressed: () => ref.read(planProvider.notifier).set(previous)),
        ));
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coach'),
        actions: [
          if (messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear conversation',
              onPressed: () => ref.read(chatProvider.notifier).clear(),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? _empty()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _bubble(messages[i]),
                  ),
          ),
          if (_sending) const LinearProgressIndicator(),
          _composer(),
        ],
      ),
    );
  }

  Widget _empty() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 40),
          Icon(Icons.chat_bubble_outline, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text('Ask me anything about your training', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('I can explain the "why", swap exercises, shorten a session, or adjust intensity.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          for (final s in _suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(onPressed: () => _send(s), child: Text(s)),
            ),
        ],
      );

  Widget _bubble(ChatMessage m) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: m.isUser ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.content, style: TextStyle(color: m.isUser ? scheme.onPrimary : scheme.onSurface)),
            if (m.changedPlan)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.edit_calendar, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('Plan change', style: Theme.of(context).textTheme.labelSmall),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                decoration: const InputDecoration(
                  hintText: 'Message your coach…',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : () => _send(_input.text),
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
