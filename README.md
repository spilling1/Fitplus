# FitPlus 🏋️

An adaptive AI personal trainer in your pocket — for anyone. You tell FitPlus your
equipment, level, schedule and goals; it generates a personalised weekly plan,
explains *why*, runs the workout with timers and logging, and **adapts next week**
based on what you actually did and how it felt.

This repo implements the **MVP core loop** from the PRD:

> **plan → do → measure → reflect → re-plan**, with an AI coach you can argue with.

## What's here

```
backend/   Node.js AI proxy — holds the Anthropic key, generates & adapts
           structured plans, enforces programming guardrails. Zero npm deps.
app/        Flutter (Dart) mobile client — onboarding, plan, workout player
           with timers + logging, coach chat, progress charts. Codegen-free.
docs/       Architecture notes.
```

The original product spec lives in the PRD you started from; `docs/ARCHITECTURE.md`
maps each PRD section to where it's implemented.

## Why a backend?

**The Anthropic API key must never live in the mobile app** — anyone can decompile
a binary and extract embedded secrets (PRD §6). All LLM calls go through the
backend, which holds the key, assembles prompts, validates the model's structured
output, and clamps anything that violates a hard rule (equipment, injuries,
progression caps).

## Quick start

### 1. Backend

```bash
cd backend
cp .env.example .env        # then put OPENAI_API_KEY=sk-... in .env (auto-loaded)
npm start                   # listens on :8080
npm test                    # runs the smoke tests (no key needed)
```

**Where the API key goes:** in `backend/.env` (e.g. `OPENAI_API_KEY=sk-...`), which
the backend loads automatically on `npm start`. It lives only on the server — never
in the app. You can also `export OPENAI_API_KEY=...` instead of using `.env`.

**No API key?** The backend runs in **offline stub mode**: it still generates
valid, safe, equipment-aware plans deterministically so the whole app works for
development and demos. AI chat and adaptive personalisation switch on the moment
you set a provider key.

**Provider is swappable** (PRD §6). Set `OPENAI_API_KEY` to use OpenAI (default,
`gpt-4o`, JSON-schema structured outputs) or `ANTHROPIC_API_KEY` to use Claude
(`claude-opus-4-8`). If both are set, OpenAI wins; force a choice with
`FITPLUS_PROVIDER=openai|anthropic`. Each provider is one isolated file
(`backend/src/{openai,anthropic}.js`) behind a common interface, selected in
`backend/src/provider.js`.

### 2. App

```bash
cd app
flutter pub get
flutter run                 # on a simulator/emulator or device
```

Point the app at your backend in the **You** tab, or at launch:

```bash
# Android emulator reaches the host at 10.0.2.2 (this is the default)
flutter run --dart-define=FITPLUS_API=http://10.0.2.2:8080
# iOS simulator / web:
flutter run --dart-define=FITPLUS_API=http://localhost:8080
```

> Flutter isn't required to evaluate the backend — `cd backend && npm test` runs
> the riskiest core (schema + guardrails + offline generation) on its own.

## The core loop, feature by feature

| PRD | Feature | Where |
|----|---------|-------|
| §5.1 | Onboarding & profile | `app/lib/src/screens/onboarding_screen.dart` |
| §5.2 | Equipment checklist (hard constraint) | profile + `backend/src/guardrails.js` |
| §5.3 | AI plan generation (structured JSON) | `backend/src/{anthropic,schema,prompts}.js` |
| §5.4 | Workout player, timers, logging (offline) | `app/lib/src/screens/session_player_screen.dart` |
| §5.5 | AI chat & plan edits (confirmable, undoable) | `app/lib/src/screens/chat_screen.dart` + `/api/chat` |
| §5.6 | Progress charts + PRs | `app/lib/src/screens/progress_screen.dart` |
| §5.9 | Post-workout survey + weekly adaptation | `survey_screen.dart` + adaptation in `providers.dart` / backend |
| §6   | Guardrails (equipment, injuries, overload caps) | `backend/src/guardrails.js` |
| §9/§10 | Export, delete, safety disclaimers | `settings_screen.dart`, system prompts |

## Safety & wellbeing

FitPlus is a coach, not a doctor (PRD §10). Declared injuries are hard constraints;
the chat model declines medical/physio advice and redirects to professionals; goals
are framed around health and capability, never extreme weight loss. Body-weight
tracking is intentionally **not** in the MVP.

## Status

This is an MVP that proves the loop end-to-end. Not yet built (PRD roadmap): real
auth + cloud sync, background/locked-screen timers (needs a platform plugin),
body-weight tracking, the full theory library, multiple equipment locations,
and store packaging. See `docs/ARCHITECTURE.md` for the next steps.
