'use strict';

// Lightweight smoke tests — no test framework, runnable with `node test/smoke.test.js`.
// Exercises the stub generator + guardrails (the parts that run without an API key).

const assert = require('assert');
const { handleGenerate, handleChat } = require('../src/server');
const { generateStubPlan } = require('../src/stub');
const { validateShape, applyGuardrails } = require('../src/guardrails');

let passed = 0;
function test(name, fn) {
  return Promise.resolve()
    .then(fn)
    .then(() => {
      passed++;
      console.log(`  ok  ${name}`);
    })
    .catch((err) => {
      console.error(`FAIL  ${name}\n      ${err.message}`);
      process.exitCode = 1;
    });
}

const ctx = {
  profile: {
    level: 'Beginner',
    goals: ['build strength', 'general health'],
    trainingDays: ['Monday', 'Wednesday', 'Friday'],
    sessionMinutes: 45,
    injuries: ['bad knees'],
  },
  equipment: ['dumbbells', 'yoga mat'],
  weekStart: '2026-06-15',
};

async function run() {
  console.log('FitPlus backend smoke tests\n');

  await test('stub plan validates against schema shape', () => {
    const plan = generateStubPlan(ctx);
    validateShape(plan);
    assert.strictEqual(plan.sessions.length, 7);
  });

  await test('stub respects chosen training days (3 training, 4 rest)', () => {
    const plan = generateStubPlan(ctx);
    const training = plan.sessions.filter((s) => s.type === 'training');
    const rest = plan.sessions.filter((s) => s.type === 'rest');
    assert.strictEqual(training.length, 3);
    assert.strictEqual(rest.length, 4);
  });

  await test('every training session has a warmup and cooldown', () => {
    const plan = generateStubPlan(ctx);
    for (const s of plan.sessions.filter((x) => x.type === 'training')) {
      const kinds = s.blocks.map((b) => b.kind);
      assert.ok(kinds.includes('warmup'), `${s.day} missing warmup`);
      assert.ok(kinds.includes('cooldown'), `${s.day} missing cooldown`);
    }
  });

  await test('guardrails substitute equipment the user lacks', () => {
    const badPlan = {
      week_start: '2026-06-15',
      rationale: 'test',
      sessions: [
        {
          day: 'Monday',
          type: 'training',
          focus: 'test',
          rationale: 'test',
          estimated_minutes: 45,
          blocks: [
            {
              kind: 'main',
              exercises: [
                {
                  name: 'Barbell Squat',
                  equipment: 'barbell',
                  sets: 3,
                  reps: 5,
                  duration_sec: null,
                  target_load: '60kg',
                  target_rpe: 8,
                  rest_sec: 120,
                  timed: false,
                  notes: '',
                  how_to: '',
                  cues: '',
                },
              ],
            },
          ],
        },
      ],
    };
    const { plan, warnings } = applyGuardrails(badPlan, { equipment: ['dumbbells'] });
    const ex = plan.sessions[0].blocks.find((b) => b.kind === 'main').exercises[0];
    assert.strictEqual(ex.equipment, 'bodyweight');
    assert.ok(warnings.some((w) => /Barbell Squat/.test(w)));
    // And a warmup + cooldown were injected.
    const kinds = plan.sessions[0].blocks.map((b) => b.kind);
    assert.ok(kinds.includes('warmup') && kinds.includes('cooldown'));
  });

  await test('guardrails clamp RPE above 10', () => {
    const p = generateStubPlan(ctx);
    p.sessions.find((s) => s.type === 'training').blocks.find((b) => b.kind === 'main').exercises[0].target_rpe = 15;
    const { plan } = applyGuardrails(p, { equipment: ctx.equipment });
    const rpe = plan.sessions.find((s) => s.type === 'training').blocks.find((b) => b.kind === 'main').exercises[0].target_rpe;
    assert.ok(rpe <= 10);
  });

  await test('handleGenerate returns a guarded plan in offline mode', async () => {
    delete process.env.ANTHROPIC_API_KEY;
    const result = await handleGenerate(ctx);
    validateShape(result.plan);
    assert.strictEqual(result.source, 'stub');
    // No exercise should require unavailable equipment.
    const allowed = new Set(['bodyweight', 'dumbbells', 'yoga mat']);
    for (const s of result.plan.sessions) {
      for (const b of s.blocks) {
        for (const ex of b.exercises) {
          assert.ok(allowed.has(ex.equipment.toLowerCase()), `unexpected equipment ${ex.equipment}`);
        }
      }
    }
  });

  await test('chat is gated behind an API key in offline mode', async () => {
    delete process.env.ANTHROPIC_API_KEY;
    const result = await handleChat({ currentPlan: generateStubPlan(ctx), message: 'make it harder' });
    assert.strictEqual(result.updatedPlan, null);
    assert.ok(/offline/i.test(result.reply));
  });

  console.log(`\n${passed} passed`);
}

run();
