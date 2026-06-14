import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'theme.dart';
import 'screens/intake_screen.dart';
import 'screens/home_shell.dart';

class FitPlusApp extends ConsumerWidget {
  const FitPlusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(profileProvider.select((p) => p.onboarded));
    return MaterialApp(
      title: 'FitPlus',
      debugShowCheckedModeBanner: false,
      theme: FitTheme.light(),
      darkTheme: FitTheme.dark(),
      home: onboarded ? const HomeShell() : const IntakeScreen(),
    );
  }
}
