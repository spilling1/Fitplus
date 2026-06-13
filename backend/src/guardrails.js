'use strict';

// The guardrails layer. The model proposes; the backend disposes. After the LLM
// returns a plan we validate its shape and clamp/repair anything that violates a
// hard rule, so a single bad generation can't produce an unsafe or broken plan.

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

class PlanValidationError extends Error {}

// Shape validation. Throws PlanValidationError on anything structurally wrong so
// the caller can trigger a re-request. Returns the plan unchanged on success.
function validateShape(plan) {
  if (!plan || typeof plan !== 'object') throw new PlanValidationError('plan is not an object');
  if (typeof plan.week_start !== 'string') throw new PlanValidationError('week_start missing');
  if (typeof plan.rationale !== 'string') throw new PlanValidationError('rationale missing');
  if (!Array.isArray(plan.sessions) || plan.sessions.length === 0) {
    throw new PlanValidationError('sessions must be a non-empty array');
  }
  for (const s of plan.sessions) {
    if (!DAYS.includes(s.day)) throw new PlanValidationError(`invalid day: ${s.day}`);
    if (s.type !== 'training' && s.type !== 'rest') throw new PlanValidationError(`invalid session type: ${s.type}`);
    if (!Array.isArray(s.blocks)) throw new PlanValidationError('session.blocks must be an array');
    for (const b of s.blocks) {
      if (!['warmup', 'main', 'finisher', 'cooldown'].includes(b.kind)) {
        throw new PlanValidationError(`invalid block kind: ${b.kind}`);
      }
      if (!Array.isArray(b.exercises)) throw new PlanValidationError('block.exercises must be an array');
      for (const ex of b.exercises) {
        if (!ex || typeof ex.name !== 'string' || !ex.name.trim()) {
          throw new PlanValidationError('exercise missing name');
        }
      }
    }
  }
  return plan;
}

function normaliseEquip(s) {
  return String(s || '').trim().toLowerCase();
}

// Enforce hard constraints and clamp values. Mutates a deep copy and returns
// { plan, warnings } so the app can surface what was changed.
function applyGuardrails(rawPlan, { equipment = [] } = {}) {
  const plan = JSON.parse(JSON.stringify(rawPlan));
  const warnings = [];

  const allowed = new Set(['bodyweight', ...equipment.map(normaliseEquip)]);

  for (const session of plan.sessions) {
    if (session.type === 'rest') {
      session.blocks = [];
      continue;
    }

    // Equipment hard limit: any movement needing unavailable gear is downgraded
    // to bodyweight rather than silently prescribing something impossible.
    for (const block of session.blocks) {
      for (const ex of block.exercises) {
        const equip = normaliseEquip(ex.equipment);
        if (equip && !allowed.has(equip)) {
          warnings.push(
            `"${ex.name}" required ${ex.equipment}, which isn't available — substituted a bodyweight option.`,
          );
          ex.equipment = 'bodyweight';
          ex.target_load = 'bodyweight';
          ex.notes = (ex.notes ? ex.notes + ' ' : '') + '(Adjusted to bodyweight — equipment unavailable.)';
        }
        // Clamp RPE to a sane 1-10 range.
        if (typeof ex.target_rpe === 'number') {
          ex.target_rpe = Math.max(1, Math.min(10, Math.round(ex.target_rpe)));
        }
        // Never prescribe absurd set counts.
        if (typeof ex.sets === 'number') ex.sets = Math.max(1, Math.min(10, Math.round(ex.sets)));
      }
    }

    // Every training session must open with a warm-up and close with a cool-down.
    const kinds = session.blocks.map((b) => b.kind);
    if (!kinds.includes('warmup')) {
      warnings.push(`${session.day}: no warm-up provided — added a default mobility warm-up.`);
      session.blocks.unshift(defaultWarmup());
    }
    if (!kinds.includes('cooldown')) {
      warnings.push(`${session.day}: no cool-down provided — added a default stretch cool-down.`);
      session.blocks.push(defaultCooldown());
    }
  }

  return { plan, warnings };
}

// Cap week-over-week intensity jumps. Given the previous week's plan and a freshly
// generated one, clamp any per-exercise numeric load increase to <= maxPct.
function clampProgression(prevPlan, nextPlan, maxPct = 0.1) {
  if (!prevPlan) return { plan: nextPlan, warnings: [] };
  const warnings = [];
  const prevLoads = indexLoads(prevPlan);

  for (const session of nextPlan.sessions) {
    for (const block of session.blocks || []) {
      for (const ex of block.exercises || []) {
        const prev = prevLoads.get(ex.name.toLowerCase());
        const next = parseKg(ex.target_load);
        if (prev != null && next != null && next > prev * (1 + maxPct)) {
          const capped = Math.round(prev * (1 + maxPct) * 2) / 2; // round to 0.5kg
          warnings.push(
            `Capped "${ex.name}" from ${next}kg to ${capped}kg (max ${Math.round(maxPct * 100)}% week-over-week increase).`,
          );
          ex.target_load = `${capped}kg`;
        }
      }
    }
  }
  return { plan: nextPlan, warnings };
}

function indexLoads(plan) {
  const map = new Map();
  for (const s of plan.sessions || []) {
    for (const b of s.blocks || []) {
      for (const ex of b.exercises || []) {
        const kg = parseKg(ex.target_load);
        if (kg != null) map.set(ex.name.toLowerCase(), kg);
      }
    }
  }
  return map;
}

function parseKg(load) {
  if (typeof load !== 'string') return null;
  const m = load.match(/([\d.]+)\s*kg/i);
  return m ? parseFloat(m[1]) : null;
}

function defaultWarmup() {
  return {
    kind: 'warmup',
    exercises: [
      {
        name: 'Easy cardio + joint circles',
        equipment: 'bodyweight',
        sets: null,
        reps: null,
        duration_sec: 300,
        target_load: 'bodyweight',
        target_rpe: 3,
        rest_sec: 0,
        timed: true,
        notes: '',
        how_to: 'Five minutes of light movement (march, arm/leg circles) to raise your temperature and loosen joints.',
        cues: 'Build gradually — you should be warm, not tired.',
      },
    ],
  };
}

function defaultCooldown() {
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
        how_to: 'Gentle static stretches for the muscles you trained, ~30s each. Breathe slowly.',
        cues: 'Stretch to mild tension, never pain.',
      },
    ],
  };
}

module.exports = {
  PlanValidationError,
  validateShape,
  applyGuardrails,
  clampProgression,
  DAYS,
};
