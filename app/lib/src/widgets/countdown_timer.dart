import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A countdown timer for timed holds (planks, dead hangs) and rest periods
/// (PRD §5.4). Gives audible + haptic cues on completion for eyes-free use
/// mid-set.
///
/// Note: this runs while the app is foregrounded. True background / locked-screen
/// timing needs a platform plugin (e.g. flutter_local_notifications + a
/// background isolate) and is tracked as a V1.x enhancement.
class CountdownTimer extends StatefulWidget {
  final int seconds;
  final bool autoStart;
  final String label;
  final VoidCallback? onComplete;

  const CountdownTimer({
    super.key,
    required this.seconds,
    this.autoStart = false,
    this.label = '',
    this.onComplete,
  });

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  late int _remaining;
  Timer? _timer;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.seconds;
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_running || _remaining <= 0) return;
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining <= 1) {
        t.cancel();
        setState(() {
          _remaining = 0;
          _running = false;
        });
        _cue();
        widget.onComplete?.call();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _running = false);
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _remaining = widget.seconds;
      _running = false;
    });
  }

  void _cue() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  }

  String get _formatted {
    final m = _remaining ~/ 60;
    final s = _remaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = widget.seconds == 0 ? 0.0 : _remaining / widget.seconds;
    return Column(
      children: [
        if (widget.label.isNotEmpty)
          Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 8,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              Text(_formatted, style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              onPressed: _running ? _pause : _start,
              icon: Icon(_running ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: 12),
            IconButton.outlined(onPressed: _reset, icon: const Icon(Icons.replay)),
          ],
        ),
      ],
    );
  }
}
