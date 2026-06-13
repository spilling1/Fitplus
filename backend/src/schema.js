'use strict';

// JSON Schema for a generated weekly plan. This is the contract the LLM must
// satisfy (Appendix A of the PRD) and what the app validates before rendering.
//
// Notes on shape:
// - Optional numeric fields use a ["integer","null"] union so the model can
//   omit them (e.g. a timed plank has duration_sec but no reps) while still
//   satisfying strict structured-output validation, which requires every
//   property to appear in `required` and `additionalProperties: false`.
// - We deliberately avoid numeric min/max and string length constraints —
//   the structured-output engine does not enforce them. Those bounds are
//   applied in code by the guardrails layer instead.

const exerciseSchema = {
  type: 'object',
  additionalProperties: false,
  properties: {
    name: { type: 'string', description: 'Human-readable exercise name, e.g. "Goblet Squat".' },
    equipment: {
      type: 'string',
      description:
        'The single primary equipment type this movement needs. Use "bodyweight" when none is required. Must be one of the equipment types available to the user.',
    },
    sets: { type: ['integer', 'null'], description: 'Number of working sets. Null for warmup/cooldown holds.' },
    reps: { type: ['integer', 'null'], description: 'Reps per set. Null when the movement is timed.' },
    duration_sec: { type: ['integer', 'null'], description: 'Hold/work duration in seconds for timed movements.' },
    target_load: {
      type: ['string', 'null'],
      description: 'Target load or intensity, e.g. "24kg", "bodyweight", "RPE 7", "60% 1RM". Null if not applicable.',
    },
    target_rpe: { type: ['integer', 'null'], description: 'Target rate of perceived exertion, 1-10.' },
    rest_sec: { type: ['integer', 'null'], description: 'Rest after the movement, in seconds.' },
    timed: { type: 'boolean', description: 'True if this is a timed hold/interval rather than counted reps.' },
    notes: { type: 'string', description: 'Short per-exercise note. Empty string if none.' },
    how_to: { type: 'string', description: 'One or two sentences on how to perform the movement safely.' },
    cues: { type: 'string', description: 'A coaching cue or common mistake to avoid. Empty string if none.' },
  },
  required: [
    'name',
    'equipment',
    'sets',
    'reps',
    'duration_sec',
    'target_load',
    'target_rpe',
    'rest_sec',
    'timed',
    'notes',
    'how_to',
    'cues',
  ],
};

const blockSchema = {
  type: 'object',
  additionalProperties: false,
  properties: {
    kind: { type: 'string', enum: ['warmup', 'main', 'finisher', 'cooldown'] },
    exercises: { type: 'array', items: exerciseSchema },
  },
  required: ['kind', 'exercises'],
};

const sessionSchema = {
  type: 'object',
  additionalProperties: false,
  properties: {
    day: {
      type: 'string',
      enum: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
    },
    type: { type: 'string', enum: ['training', 'rest'] },
    focus: { type: 'string', description: 'Short focus label, e.g. "Lower body strength". Empty for rest days.' },
    rationale: { type: 'string', description: 'One sentence on why this session looks the way it does.' },
    estimated_minutes: { type: ['integer', 'null'], description: 'Estimated session length. Null for rest days.' },
    blocks: { type: 'array', items: blockSchema, description: 'Empty array for rest days.' },
  },
  required: ['day', 'type', 'focus', 'rationale', 'estimated_minutes', 'blocks'],
};

const planSchema = {
  type: 'object',
  additionalProperties: false,
  properties: {
    week_start: { type: 'string', description: 'ISO date (YYYY-MM-DD) of the Monday the week begins.' },
    rationale: { type: 'string', description: 'A few sentences explaining the week as a whole — the "why".' },
    sessions: { type: 'array', items: sessionSchema },
  },
  required: ['week_start', 'rationale', 'sessions'],
};

module.exports = { planSchema, sessionSchema, blockSchema, exerciseSchema };
