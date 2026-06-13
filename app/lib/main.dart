import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/data/local_store.dart';
import 'src/state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalStore.create();

  runApp(
    ProviderScope(
      // Inject the loaded SharedPreferences-backed store so notifiers can read
      // it synchronously in their build().
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const FitPlusApp(),
    ),
  );
}
