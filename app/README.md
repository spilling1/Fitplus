# FitPlus — Flutter app

This folder contains the FitPlus mobile app's **source** (`lib/`). To turn it into
a runnable iOS/Android/web app you generate the platform projects once with
Flutter — they aren't committed because Flutter regenerates them per machine.

## First-time setup

```bash
# 1. Install Flutter: https://docs.flutter.dev/get-started/install
flutter doctor                 # resolve any red items (Xcode, Android toolchain)

# 2. From this app/ folder, generate ios/, android/, web/ around the existing lib/.
#    This does NOT overwrite your code in lib/.
flutter create .

# 3. Fetch packages and run.
flutter pub get
flutter run                    # choose a simulator / device
```

Point the app at the backend in the in-app **You** tab, or at launch:

```bash
# iOS simulator / web:
flutter run --dart-define=FITPLUS_API=http://localhost:8080
# Android emulator (host loopback is 10.0.2.2 — this is the default):
flutter run --dart-define=FITPLUS_API=http://10.0.2.2:8080
```

Make sure the backend is running (`cd ../backend && npm start`).

## Making it feel like a finished app (after `flutter create .`)

| Polish | Where |
|--------|-------|
| App display name "FitPlus" | iOS: `ios/Runner/Info.plist` → `CFBundleDisplayName`; Android: `android/app/src/main/AndroidManifest.xml` → `android:label` |
| Bundle / application ID | `flutter create . --org com.yourname` (set once), or edit the project files |
| App icon | add `flutter_launcher_icons` to `pubspec.yaml` and run it |
| Splash screen | add `flutter_native_splash` |

## What's in `lib/`

```
main.dart                 app entry (loads local store, runs the app)
src/app.dart              routes to onboarding vs. home based on profile
src/theme.dart            calm, health-forward Material 3 theme
src/models/               plan, profile, logs, chat (hand-written JSON, no codegen)
src/data/                 api_client (backend), local_store (offline persistence)
src/state/providers.dart  Riverpod state + plan generation/adaptation
src/screens/              onboarding, plan, session player, survey, chat, progress, settings
src/widgets/              countdown timer, rationale card, multi-select chips
```

Run the unit tests with `flutter test`.
