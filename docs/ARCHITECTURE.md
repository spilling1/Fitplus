# FitPlus Architecture

A thin-but-real implementation of the PRD's MVP, built end-to-end so the core
loop works before widening features.

## Shape

```
┌─────────────────────────┐        HTTPS/JSON         ┌───────────────────────────┐
│  Flutter app (client)   │  ───────────────────────▶ │  Backend AI proxy (Node)  │
│                         │                            │                           │
│  • Onboarding/profile   │   POST /api/plan/generate  │  • holds ANTHROPIC_API_KEY │
│  • Equipment            │   POST /api/plan/adapt     │  • assembles prompts       │
│  • Plan view            │   POST /api/chat           │  • validates structured    │
│  • Workout player       │   GET  /health             │    output (re-request)     │
│    + timers + logging   │ ◀───────────────────────   │  • guardrails (clamp/repair)│
│  • Coach chat           │                            │  • stub fallback           │
│  • Progress charts      │                            │           │                │
│                         │                            │           ▼                │
│  Local store (offline)  │                            │   Anthropic Claude API     │
└─────────────────────────┘                            └───────────────────────────┘
```

The mobile client is **offline-first**: profile, current plan and logs persist
locally, so an already-generated workout runs and logs with no connectivity. Only
AI generation and chat need the network.

## Backend (`backend/`)

Zero npm dependencies — Node's built-in `http` server and global `fetch`. Files:

- **`schema.js`** — the workout JSON schema the model must satisfy (Appendix A of
  the PRD). Optional numeric fields use `["integer","null"]` unions so the model
  can omit them while still passing strict structured-output validation.
- **`prompts.js`** — the coach system prompt (hard rules: equipment, injuries,
  warm-up/cool-down, progressive overload, no medical advice, health-framed) and
  the prompt builder that turns the app's context bundle into a request.
- **`anthropic.js`** — the *only* file that knows about the LLM vendor. Calls the
  Messages API with `claude-opus-4-8`, adaptive thinking, `output_config.format`
  for generation, and an `update_plan` tool for chat edits. Swap this file to
  change providers.
- **`guardrails.js`** — the "model proposes, backend disposes" layer. Validates
  shape; substitutes movements needing unavailable equipment; injects a missing
  warm-up/cool-down; clamps RPE and set counts; caps week-over-week load increases
  to ≤10%.
- **`stub.js`** — deterministic, equipment-aware plan generator. Powers offline
  dev/demo mode *and* is the graceful fallback when an AI call fails (PRD: AI
  failures never break the workout flow).
- **`server.js`** — routing + the orchestration: AI generate → validate → (one
  silent re-request on malformed output) → guardrails → progression clamp → return,
  falling back to the stub on any failure.

### Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET  | `/health` | liveness + whether AI is enabled |
| POST | `/api/plan/generate` | first/weekly plan from profile + equipment |
| POST | `/api/plan/adapt` | same, with a history summary + previous plan for adaptation |
| POST | `/api/chat` | conversational Q&A and structured plan edits |

## App (`app/`)

Flutter + Riverpod, deliberately **codegen-free** (hand-written JSON models, no
`build_runner`) so it compiles without a generation step.

- **`models/`** — `plan`, `profile`, `logs`, `chat`. Mirror the backend schema.
- **`data/`** — `api_client` (HTTP) and `local_store` (`shared_preferences`-backed
  persistence + export/wipe for data ownership).
- **`state/providers.dart`** — Riverpod `Notifier`s for profile, plan, logs, chat,
  and a `PlanController` that orchestrates generation/adaptation (including building
  the history summary the adaptation engine consumes).
- **`screens/`** — onboarding, home shell (bottom nav), plan, session player,
  survey, chat, progress, settings.
- **`widgets/`** — countdown timer (timed holds + rest, haptic/audio cues),
  rationale card ("why this"), multi-select chips.

## Adaptation loop (PRD §5.9)

1. Player logs every set → `SessionLog` (source of truth).
2. Post-workout survey captures session RPE, energy, enjoyment, pain flags.
3. "Next week" aggregates adherence + average RPE + pain flags into a compact
   summary and sends it with the previous plan to `/api/plan/adapt`.
4. The model applies sound programming; the backend enforces the overload cap and
   equipment/injury constraints in code regardless of what the model returns.

## Deliberate MVP cuts / next steps

- **Auth & cloud sync** — local-only today. Add Supabase/Firebase auth + a sync
  queue (last-write-wins) behind `local_store`.
- **Background/locked-screen timers** — current timers run foregrounded; true
  background needs `flutter_local_notifications` + a background isolate.
- **Exercise media** — text cues only; images/animation are a V1.x add.
- **Body-weight tracking, theory library, multiple equipment locations, readiness
  autoregulation** — scoped out of MVP per the PRD roadmap.
- **Prompt caching / model tiering / streaming chat** — cost/latency levers to add
  once usage justifies them.
