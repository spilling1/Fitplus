'use strict';

// FitPlus backend AI proxy.
//
// Responsibilities (PRD §7):
//  - Hold the Anthropic API key; the mobile client never sees it.
//  - Assemble prompts from the profile/equipment/history bundle the app sends.
//  - Validate + repair structured output and apply programming guardrails.
//  - Always return a usable plan: if AI is unavailable or fails, fall back to a
//    deterministic stub so the workout flow never breaks.
//
// Zero npm dependencies — built-in http + global fetch.

const http = require('http');
const fs = require('fs');
const path = require('path');
const provider = require('./provider');
const {
  COACH_SYSTEM,
  CHAT_SYSTEM,
  INTAKE_SYSTEM,
  buildPlanGenerationMessage,
  buildIntakeContext,
} = require('./prompts');
const { validateShape, applyGuardrails, clampProgression, PlanValidationError } = require('./guardrails');
const { generateStubPlan, isoMonday } = require('./stub');

const PORT = process.env.PORT || 8080;

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'content-type': 'application/json',
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'content-type',
    'access-control-allow-methods': 'GET,POST,OPTIONS',
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > 1_000_000) reject(new Error('payload too large'));
      data += chunk;
    });
    req.on('end', () => {
      if (!data) return resolve({});
      try {
        resolve(JSON.parse(data));
      } catch (e) {
        reject(new Error('invalid JSON body'));
      }
    });
    req.on('error', reject);
  });
}

// Run a generation through validate -> guardrails, retrying the model once on a
// shape failure before falling back to the stub.
async function generateValidated(ctx, { system, userMessage }) {
  let raw;
  let source = 'ai';
  try {
    raw = await provider.generatePlan({ system, userMessage });
    validateShape(raw);
  } catch (err) {
    if (err instanceof PlanValidationError) {
      // One silent re-request, per AC §5.3.
      try {
        raw = await provider.generatePlan({ system, userMessage });
        validateShape(raw);
      } catch (_) {
        raw = generateStubPlan(ctx);
        source = 'stub-fallback';
      }
    } else {
      // API/network/refusal failure — degrade gracefully.
      raw = generateStubPlan(ctx);
      source = 'stub-fallback';
    }
  }
  return { raw, source };
}

async function handleGenerate(ctx) {
  const weekStart = ctx.weekStart || isoMonday(new Date());
  const fullCtx = { ...ctx, weekStart };

  let raw;
  let source;
  if (provider.hasApiKey()) {
    const userMessage = buildPlanGenerationMessage(fullCtx);
    ({ raw, source } = await generateValidated(fullCtx, { system: COACH_SYSTEM, userMessage }));
  } else {
    raw = generateStubPlan(fullCtx);
    source = 'stub';
  }

  let { plan, warnings } = applyGuardrails(raw, {
    equipment: ctx.equipment || [],
    equipmentByDay: ctx.equipmentByDay || null,
  });

  // Cap week-over-week progression against the previous plan if one was sent.
  if (ctx.previousPlan) {
    const clamped = clampProgression(ctx.previousPlan, plan, 0.1);
    plan = clamped.plan;
    warnings = warnings.concat(clamped.warnings);
  }

  return { plan, warnings, source, model: provider.MODEL };
}

async function handleChat(body) {
  const { currentPlan, history = [], message = '', equipment = [] } = body;
  if (!currentPlan) return { error: 'currentPlan is required' };
  if (!message.trim()) return { error: 'message is required' };

  if (!provider.hasApiKey()) {
    return {
      reply:
        "I'm running in offline demo mode, so I can't chat or rewrite your plan right now. Set ANTHROPIC_API_KEY on the FitPlus backend to enable the coach.",
      updatedPlan: null,
      warnings: [],
    };
  }

  let result;
  try {
    result = await provider.chat({
      system: CHAT_SYSTEM,
      history,
      currentPlan,
      userText: message,
    });
  } catch (err) {
    return { reply: 'Sorry — I had trouble reaching the coach just now. Please try again.', updatedPlan: null, warnings: [] };
  }

  // Any AI-edited plan still goes through validation + guardrails.
  let warnings = [];
  if (result.updatedPlan) {
    try {
      validateShape(result.updatedPlan);
      const guarded = applyGuardrails(result.updatedPlan, { equipment });
      result.updatedPlan = guarded.plan;
      warnings = guarded.warnings;
      const clamped = clampProgression(currentPlan, result.updatedPlan, 0.1);
      result.updatedPlan = clamped.plan;
      warnings = warnings.concat(clamped.warnings);
    } catch (_) {
      // If the edit is malformed, keep the chat reply but drop the bad plan.
      result.updatedPlan = null;
    }
  }
  return { ...result, warnings };
}

// Conversational onboarding. The model interviews the user and returns an
// updated structured profile each turn, with a `complete` flag.
async function handleIntake(body) {
  const { messages = [], profile = {} } = body;

  if (!provider.intake || !provider.hasApiKey()) {
    return {
      reply:
        "I'm in offline mode, so I can't do the guided chat right now. Tap “Use a quick form instead” to set up — or set a provider API key on the backend to chat with me.",
      complete: false,
      profile: null,
    };
  }

  // Carry the profile-so-far forward as context, then the conversation.
  const wire = [{ role: 'user', content: buildIntakeContext(profile) }, ...messages];
  try {
    const result = await provider.intake({ system: INTAKE_SYSTEM, messages: wire });
    return result;
  } catch (e) {
    return { reply: 'Sorry — I had trouble just then. Could you say that again?', complete: false, profile: null };
  }
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') return sendJson(res, 204, {});

  const url = new URL(req.url, `http://localhost:${PORT}`);

  try {
    // Serve the click-through web tester so you can drive the whole loop in a
    // browser with no app/Flutter setup — just open http://localhost:8080/.
    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/tester')) {
      const file = path.join(__dirname, '..', 'public', 'tester.html');
      const html = fs.readFileSync(file);
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      return res.end(html);
    }

    if (req.method === 'GET' && url.pathname === '/health') {
      return sendJson(res, 200, {
        ok: true,
        ai: provider.hasApiKey(),
        provider: provider.NAME,
        model: provider.MODEL,
      });
    }

    if (req.method === 'POST' && (url.pathname === '/api/plan/generate' || url.pathname === '/api/plan/adapt')) {
      const body = await readBody(req);
      const result = await handleGenerate(body);
      return sendJson(res, 200, result);
    }

    if (req.method === 'POST' && url.pathname === '/api/intake') {
      const body = await readBody(req);
      const result = await handleIntake(body);
      return sendJson(res, 200, result);
    }

    if (req.method === 'POST' && url.pathname === '/api/chat') {
      const body = await readBody(req);
      const result = await handleChat(body);
      return sendJson(res, result.error ? 400 : 200, result);
    }

    return sendJson(res, 404, { error: 'not found' });
  } catch (err) {
    return sendJson(res, 400, { error: err.message || 'bad request' });
  }
});

if (require.main === module) {
  server.listen(PORT, () => {
    // eslint-disable-next-line no-console
    console.log(`FitPlus backend listening on :${PORT} (AI ${provider.hasApiKey() ? 'enabled' : 'OFFLINE — stub mode'})`);
  });
}

module.exports = { server, handleGenerate, handleChat, handleIntake };
