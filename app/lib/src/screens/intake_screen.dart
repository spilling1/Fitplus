import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../state/providers.dart';
import 'home_shell.dart';
import 'onboarding_screen.dart';

/// Conversational onboarding (the "tell me what you want" flow). The coach
/// interviews the user in plain language and extracts a structured profile —
/// schedule, goals, level, injuries, and equipment-by-day — then builds the
/// first plan. Falls back to the form-based [OnboardingScreen] when AI is off.
class IntakeScreen extends ConsumerStatefulWidget {
  const IntakeScreen({super.key});

  @override
  ConsumerState<IntakeScreen> createState() => _IntakeScreenState();
}

class _Msg {
  final String role; // user | assistant
  final String content;
  _Msg(this.role, this.content);
  bool get isUser => role == 'user';
  Map<String, String> get wire => {'role': role, 'content': content};
}

class _IntakeScreenState extends ConsumerState<IntakeScreen> {
  static const _greeting =
      "Hi! I'm your FitPlus coach. Tell me what you're after and I'll build your "
      "plan — your goals, how many days a week you can train, and what you have "
      "access to where (a gym? gear at home? a pool or Peloton?).";

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [_Msg('assistant', _greeting)];
  Map<String, dynamic> _profile = {};
  bool _sending = false;
  bool _complete = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _messages.add(_Msg('user', text));
      _sending = true;
    });
    _input.clear();
    _scrollToEnd();

    try {
      final result = await ref.read(apiClientProvider).intake(
            messages: _messages.map((m) => m.wire).toList(),
            profile: _profile,
          );
      setState(() {
        _messages.add(_Msg('assistant', result.reply));
        if (result.profile != null) _profile = result.profile!;
        _complete = result.complete;
      });
    } catch (e) {
      setState(() => _messages.add(_Msg('assistant', 'Sorry — I had trouble reaching the coach. $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  void _buildPlan() {
    final profile = Profile.fromIntake(_profile);
    ref.read(profileProvider.notifier).update(profile);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeShell()),
    );
    // Kick off generation; the Plan tab shows the loading state.
    ref.read(planControllerProvider.notifier).generate();
  }

  void _useForm() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
    );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up with your coach'),
        actions: [
          TextButton(onPressed: _useForm, child: const Text('Use a form')),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _bubble(_messages[i]),
            ),
          ),
          if (_sending) const LinearProgressIndicator(),
          if (_complete) _buildPlanBar() else _composer(),
        ],
      ),
    );
  }

  Widget _bubble(_Msg m) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: m.isUser ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(m.content,
            style: TextStyle(color: m.isUser ? scheme.onPrimary : scheme.onSurface)),
      ),
    );
  }

  Widget _buildPlanBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Got everything I need 🎉', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _complete = false),
                    child: const Text('Keep chatting'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _buildPlan,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Build my plan'),
                  ),
                ),
              ],
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
                minLines: 1,
                maxLines: 4,
                onSubmitted: _send,
                decoration: const InputDecoration(
                  hintText: 'Tell your coach…',
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
