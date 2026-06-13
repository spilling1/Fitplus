'use strict';

// Deterministic, offline plan generator. Two jobs:
//  1. Let the whole app run with no ANTHROPIC_API_KEY set (great for dev/demo).
//  2. Be the graceful fallback when a real AI generation fails (the PRD requires
//     that AI failures never break the workout flow).
//
// It is intentionally simple: a small equipment-aware exercise bank, assembled
// into warm-up / main / cool-down blocks honouring the user's training days. It
// is not "smart", but it is always valid and always safe.

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

// name, equipment, muscle focus tag
const BANK = [
  { name: 'Goblet Squat', equipment: 'dumbbells', focus: 'lower', reps: 10, rpe: 7 },
  { name: 'Dumbbell Romanian Deadlift', equipment: 'dumbbells', focus: 'lower', reps: 10, rpe: 7 },
  { name: 'Dumbbell Bench Press', equipment: 'dumbbells', focus: 'push', reps: 10, rpe: 7 },
  { name: 'One-Arm Dumbbell Row', equipment: 'dumbbells', focus: 'pull', reps: 10, rpe: 7 },
  { name: 'Dumbbell Shoulder Press', equipment: 'dumbbells', focus: 'push', reps: 10, rpe: 7 },
  { name: 'Kettlebell Swing', equipment: 'kettlebells', focus: 'lower', reps: 15, rpe: 7 },
  { name: 'Kettlebell Goblet Squat', equipment: 'kettlebells', focus: 'lower', reps: 12, rpe: 7 },
  { name: 'Barbell Back Squat', equipment: 'barbell', focus: 'lower', reps: 5, rpe: 8 },
  { name: 'Barbell Deadlift', equipment: 'barbell', focus: 'lower', reps: 5, rpe: 8 },
  { name: 'Barbell Bench Press', equipment: 'barbell', focus: 'push', reps: 5, rpe: 8 },
  { name: 'Pull-up', equipment: 'pull-up bar', focus: 'pull', reps: 6, rpe: 8 },
  { name: 'Band Row', equipment: 'resistance bands', focus: 'pull', reps: 15, rpe: 6 },
  { name: 'Band Pull-Apart', equipment: 'resistance bands', focus: 'pull', reps: 15, rpe: 5 },
  // Always-available bodyweight movements.
  { name: 'Push-up', equipment: 'bodyweight', focus: 'push', reps: 10, rpe: 6 },
  { name: 'Bodyweight Squat', equipment: 'bodyweight', focus: 'lower', reps: 15, rpe: 6 },
  { name: 'Reverse Lunge', equipment: 'bodyweight', focus: 'lower', reps: 10, rpe: 6 },
  { name: 'Glute Bridge', equipment: 'bodyweight', focus: 'lower', reps: 15, rpe: 5 },
  { name: 'Incline Push-up', equipment: 'bodyweight', focus: 'push', reps: 12, rpe: 5 },
  { name: 'Superman', equipment: 'bodyweight', focus: 'pull', reps: 12, rpe: 5 },
];

const HOWTO = {
  push: 'Brace your core, lower under control, then press back to the start without flaring the elbows.',
  pull: 'Lead with the elbow and squeeze the back at the top; lower slowly without shrugging.',
  lower: 'Keep a neutral spine, drive through mid-foot and control the descent.',
};

function pickMain(allowed, level, count) {
  const valid = BANK.filter((e) => allowed.has(e.equipment));
  // Prefer a balanced spread across focuses, fall back to bodyweight bank.
  const order = ['lower', 'push', 'pull', 'lower'];
  const chosen = [];
  const used = new Set();
  for (let i = 0; i < count; i++) {
    const want = order[i % order.length];
    const cand = valid.find((e) => e.focus === want && !used.has(e.name)) || valid.find((e) => !used.has(e.name));
    if (!cand) break;
    used.add(cand.name);
    chosen.push(toPrescription(cand, level));
  }
  return chosen;
}

function toPrescription(e, level) {
  const sets = level === 'Beginner' ? 3 : level === 'Advanced' ? 4 : 3;
  return {
    name: e.name,
    equipment: e.equipment,
    sets,
    reps: e.reps,
    duration_sec: null,
    target_load: e.equipment === 'bodyweight' ? 'bodyweight' : `RPE ${e.rpe}`,
    target_rpe: e.rpe,
    rest_sec: e.rpe >= 8 ? 120 : 75,
    timed: false,
    notes: '',
    how_to: HOWTO[e.focus] || 'Perform with controlled tempo and full range of motion.',
    cues: level === 'Beginner' ? 'Start light and prioritise good form over load.' : 'Leave 2-3 reps in reserve.',
  };
}

function warmupBlock() {
  return {
    kind: 'warmup',
    exercises: [
      {
        name: 'Easy cardio + dynamic mobility',
        equipment: 'bodyweight',
        sets: null,
        reps: null,
        duration_sec: 300,
        target_load: 'bodyweight',
        target_rpe: 3,
        rest_sec: 0,
        timed: true,
        notes: '',
        how_to: 'Five minutes of light cardio and joint circles to raise your temperature and prep the joints.',
        cues: 'Build gradually — warm, not tired.',
      },
    ],
  };
}

function coreFinisher() {
  return {
    kind: 'finisher',
    exercises: [
      {
        name: 'Plank',
        equipment: 'bodyweight',
        sets: 3,
        reps: null,
        duration_sec: 40,
        target_load: 'bodyweight',
        target_rpe: 6,
        rest_sec: 45,
        timed: true,
        notes: '',
        how_to: 'Hold a straight line from head to heels; squeeze glutes and brace the core.',
        cues: "Don't let the hips sag.",
      },
    ],
  };
}

function cooldownBlock() {
  return {
    kind: 'cooldown',
    exercises: [
      {
        name: 'Full-body stretch',
        equipment: 'bodyweight',
        sets: null,
        reps: null,
        duration_sec: 300,
        target_load: 'bodyweight',
        target_rpe: 2,
        rest_sec: 0,
        timed: true,
        notes: '',
        how_to: 'Gentle static stretches for the muscles you trained, ~30s each.',
        cues: 'Stretch to mild tension, never pain.',
      },
    ],
  };
}

function generateStubPlan(ctx = {}) {
  const profile = ctx.profile || {};
  const equipment = ctx.equipment || [];
  const weekStart = ctx.weekStart || isoMonday(new Date());
  const level = profile.level || 'Beginner';
  const trainingDays = (profile.trainingDays && profile.trainingDays.length ? profile.trainingDays : ['Monday', 'Wednesday', 'Friday']);
  const allowed = new Set(['bodyweight', ...equipment.map((e) => String(e).toLowerCase())]);
  const sessionMinutes = profile.sessionMinutes || 45;
  const mainCount = sessionMinutes >= 50 ? 4 : 3;

  const injuries = (profile.injuries || []).join(', ');
  const injuryNote = injuries ? ` Movements were chosen to accommodate: ${injuries}.` : '';

  const sessions = DAYS.map((day) => {
    if (!trainingDays.includes(day)) {
      return {
        day,
        type: 'rest',
        focus: '',
        rationale: 'Recovery day — adaptation happens when you rest.',
        estimated_minutes: null,
        blocks: [],
      };
    }
    const blocks = [warmupBlock(), { kind: 'main', exercises: pickMain(allowed, level, mainCount) }];
    if (sessionMinutes >= 40) blocks.push(coreFinisher());
    blocks.push(cooldownBlock());
    return {
      day,
      type: 'training',
      focus: 'Full body',
      rationale: 'A balanced full-body session hitting lower body, push and pull patterns.',
      estimated_minutes: sessionMinutes,
      blocks,
    };
  });

  return {
    week_start: weekStart,
    rationale:
      `Week 1 of a ${level.toLowerCase()} full-body programme across ${trainingDays.length} days. ` +
      `Loads start conservative so we can learn how you respond, then progress next week.${injuryNote} ` +
      '(Generated offline by FitPlus — connect AI for fully personalised, adaptive plans.)',
    sessions,
  };
}

function isoMonday(d) {
  const date = new Date(d);
  const day = (date.getDay() + 6) % 7; // 0 = Monday
  date.setDate(date.getDate() - day);
  return date.toISOString().slice(0, 10);
}

module.exports = { generateStubPlan, isoMonday };
