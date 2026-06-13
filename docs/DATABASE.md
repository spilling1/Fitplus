# FitPlus — Database setup

Today the app stores everything **on the device** (great for offline-first, but it
doesn't survive a reinstall or move between phones). This sets up the **cloud
database** so users get accounts, sync, and durable history — the PRD §7 backend.

We use **Supabase** (managed Postgres + auth + row-level security). It's the
fastest path for a solo build and the schema is plain Postgres, so it also runs on
any Postgres if you outgrow Supabase.

## 1. Create the project (5 minutes)

1. Sign up at supabase.com and create a new project. Pick a region near your users
   and save the database password.
2. In the dashboard go to **SQL Editor → New query**, paste the entire contents of
   [`db/schema.sql`](../db/schema.sql), and **Run**. This creates every table and
   turns on Row-Level Security.
3. Go to **Project Settings → API** and copy three values:
   - **Project URL** (e.g. `https://abcd.supabase.co`)
   - **anon public key** — safe to ship in the mobile app
   - **service_role key** — secret, **backend only**, never in the app

## 2. What you just created

The schema maps the PRD §8 data model:

| Table | Holds |
|-------|-------|
| `profiles` | one row per user — level, goals, training days, injuries, units |
| `equipment_locations` / `equipment_items` | gear per location (Home/Gym/Hotel) |
| `plans` | each generated/adapted week, full plan stored as JSONB |
| `session_logs` / `set_logs` | what was actually done — the source of truth |
| `survey_responses` | post-workout feedback that drives adaptation |
| `body_metrics` | optional, opt-in weight/measurements (PRD §5.7) |
| `chat_messages` | coach conversation history |
| `personal_records` | detected PRs for the progress screen |

**Row-Level Security is on for every table**, so even with the anon key a user can
only ever read or write rows where `user_id = auth.uid()`. There is no way for one
user to see another's data.

## 3. Wiring it up (the integration, in order)

This is the next build chunk. Nothing here is wired yet — the schema is the
foundation.

1. **Auth in the app.** Add `supabase_flutter` to the Flutter app; add email/magic-
   link sign-in. On sign-in you get a JWT. Store the Supabase URL + anon key via
   `--dart-define` (not hardcoded).
2. **Sync the local store to Postgres.** Keep the offline-first local store as the
   write path; add a sync queue that upserts `profiles`, `plans`, `session_logs`,
   `set_logs`, `survey_responses` to Supabase when online (last-write-wins on
   `updated_at` is fine for v1 — single user per account, low conflict). The Dart
   client talks to Supabase directly under RLS for these CRUD rows.
3. **Backend reads history from Postgres.** Give the backend the `service_role` key
   so the AI proxy can pull a user's recent logs to build the adaptation summary
   server-side, instead of the app sending it. Set:
   ```
   SUPABASE_URL=https://abcd.supabase.co
   SUPABASE_SERVICE_ROLE_KEY=...   # secret, backend env only
   ```
   The proxy verifies the user's JWT (passed from the app as a Bearer token),
   loads their profile + log summary, calls the model, and writes the new plan to
   `plans`.
4. **Export / delete (PRD §9/§10).** "Export my data" = select the user's rows to
   JSON; "Delete everything" = `delete from profiles where user_id = auth.uid()` —
   the `on delete cascade` foreign keys wipe all child rows automatically.

## 4. Local Postgres alternative (no Supabase account)

The schema is standard Postgres, but it references `auth.users` and `auth.uid()`
(Supabase-provided). To run it on a bare Postgres for local testing, create a
stand-in `auth` schema first:

```sql
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key default gen_random_uuid());
create or replace function auth.uid() returns uuid
  language sql stable as $$ select current_setting('app.user_id', true)::uuid $$;
```

Then run `db/schema.sql`. Set the current user per session with
`select set_config('app.user_id', '<some-uuid>', false);` to exercise RLS.

> The AI prompts that drive plan generation and the coach chat live in
> [`backend/src/prompts.js`](../backend/src/prompts.js) — that's the "brain", this
> is the "memory".
