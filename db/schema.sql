-- FitPlus database schema (PostgreSQL / Supabase).
--
-- Maps the PRD §8 data model. Designed for Supabase: every table is owned by a
-- user (auth.users) and protected by Row-Level Security so a user can only ever
-- read/write their own rows. Run this once in the Supabase SQL editor (or via
-- `psql` against any Postgres ≥14).
--
-- Storage strategy: the generated weekly plan is stored as JSONB (it's produced
-- and rendered as a single document — see the workout schema in
-- backend/src/schema.js), while the things we query and chart — session logs,
-- set logs, surveys, body metrics — are normalised into their own tables.

-- gen_random_uuid() lives in pgcrypto. Supabase has this enabled; this is a no-op there.
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Profile (1 row per user)  — PRD §5.1, §8
-- ---------------------------------------------------------------------------
create table if not exists profiles (
  user_id          uuid primary key references auth.users (id) on delete cascade,
  age_range        text,
  sex              text,
  height_cm        integer,
  units            text    not null default 'metric',          -- metric | imperial
  level            text    not null default 'Beginner',        -- Beginner | Intermediate | Advanced
  goals            text[]  not null default '{}',               -- ranked goals
  training_days    text[]  not null default '{Monday,Wednesday,Friday}',
  session_minutes  integer not null default 45,
  time_pref        text,
  likes            text[]  not null default '{}',
  dislikes         text[]  not null default '{}',
  injuries         text[]  not null default '{}',               -- hard constraints
  experience_notes text    not null default '',
  version          integer not null default 1,                  -- bump when adaptation-relevant fields change
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Equipment (multiple locations per user — Home / Gym / Hotel)  — PRD §5.2, §8
-- For the MVP the app uses a single implicit location; this models the full shape.
-- ---------------------------------------------------------------------------
create table if not exists equipment_locations (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  name       text not null,                                    -- Home / Gym / Hotel
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists equipment_items (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  location_id uuid not null references equipment_locations (id) on delete cascade,
  type        text not null,                                   -- dumbbells, barbell, kettlebells, ...
  attributes  jsonb not null default '{}'::jsonb,              -- e.g. {"weights_kg":[5,10,15],"adjustable":true}
  available   boolean not null default true
);

-- ---------------------------------------------------------------------------
-- Plans (one document per generated/adapted week)  — PRD §5.3, §8
-- The full structured plan lives in `plan` (JSONB) matching the workout schema.
-- ---------------------------------------------------------------------------
create table if not exists plans (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  week_start  date not null,
  status      text not null default 'active',                  -- active | archived
  source      text,                                            -- ai | adapted | edited | stub
  model       text,                                            -- provider/model that produced it
  rationale   text,
  plan        jsonb not null,                                  -- the full week (sessions/blocks/exercises)
  created_at  timestamptz not null default now()
);
create index if not exists plans_user_week_idx on plans (user_id, week_start desc);

-- ---------------------------------------------------------------------------
-- Session logs + set logs  — the source of truth for charts & adaptation (PRD §5.4)
-- ---------------------------------------------------------------------------
create table if not exists session_logs (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  plan_id      uuid references plans (id) on delete set null,
  week_start   date,
  day          text,                                            -- Monday..Sunday
  focus        text,
  started_at   timestamptz not null default now(),
  completed_at timestamptz,
  status       text not null default 'partial'                 -- completed | partial | skipped
);
create index if not exists session_logs_user_idx on session_logs (user_id, started_at desc);

create table if not exists set_logs (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  session_log_id  uuid not null references session_logs (id) on delete cascade,
  exercise_name   text not null,
  set_index       integer not null,
  reps            integer,
  load            numeric,                                      -- kg or lb per profile units
  duration_sec    integer,
  rpe             integer,
  ts              timestamptz not null default now()
);
create index if not exists set_logs_session_idx on set_logs (session_log_id);
create index if not exists set_logs_user_exercise_idx on set_logs (user_id, exercise_name);

-- ---------------------------------------------------------------------------
-- Post-workout survey  — feeds the weekly adaptation engine (PRD §5.9)
-- ---------------------------------------------------------------------------
create table if not exists survey_responses (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  session_log_id uuid not null references session_logs (id) on delete cascade,
  difficulty     integer,                                       -- session RPE 1-10
  energy         integer,                                       -- 1-5
  enjoyment      integer,                                       -- 1-5
  pain_areas     text[] not null default '{}',
  note           text not null default '',
  skipped        boolean not null default false,
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Body metrics (optional, opt-in, hideable)  — PRD §5.7, §10 wellbeing guardrails
-- ---------------------------------------------------------------------------
create table if not exists body_metrics (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  type        text not null,                                   -- weight | measurement | resting_hr
  value       numeric not null,
  unit        text not null,
  recorded_at timestamptz not null default now()
);
create index if not exists body_metrics_user_idx on body_metrics (user_id, type, recorded_at);

-- ---------------------------------------------------------------------------
-- Chat messages  — conversation continuity (PRD §5.5)
-- ---------------------------------------------------------------------------
create table if not exists chat_messages (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  role            text not null,                               -- user | assistant
  content         text not null,
  related_plan_id uuid references plans (id) on delete set null,
  created_at      timestamptz not null default now()
);
create index if not exists chat_messages_user_idx on chat_messages (user_id, created_at);

-- ---------------------------------------------------------------------------
-- Personal records (detected from set logs)  — PRD §5.6
-- ---------------------------------------------------------------------------
create table if not exists personal_records (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  exercise_name text not null,
  metric        text not null,                                 -- est_1rm | max_reps | max_duration
  value         numeric not null,
  achieved_at   timestamptz not null default now(),
  unique (user_id, exercise_name, metric)
);

-- ---------------------------------------------------------------------------
-- updated_at trigger for profiles
-- ---------------------------------------------------------------------------
create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists profiles_updated_at on profiles;
create trigger profiles_updated_at before update on profiles
  for each row execute function set_updated_at();

-- ===========================================================================
-- Row-Level Security: a user can only touch their own rows.
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array[
    'profiles','equipment_locations','equipment_items','plans','session_logs',
    'set_logs','survey_responses','body_metrics','chat_messages','personal_records'
  ]
  loop
    execute format('alter table %I enable row level security;', t);
    execute format('drop policy if exists "own rows select" on %I;', t);
    execute format('drop policy if exists "own rows modify" on %I;', t);
    -- profiles keys on user_id (its PK); every other table also has user_id.
    execute format(
      'create policy "own rows select" on %I for select using (auth.uid() = user_id);', t);
    execute format(
      'create policy "own rows modify" on %I for all using (auth.uid() = user_id) with check (auth.uid() = user_id);', t);
  end loop;
end $$;
