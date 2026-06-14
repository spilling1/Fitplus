'use strict';

// Thin Anthropic (Claude) provider. This is the ONLY place that knows about the
// LLM vendor — everything else talks to this interface, so the provider stays
// swappable (a PRD requirement). The API key lives here on the server and is
// never shipped to the Flutter client.
//
// We call the Messages REST API directly with the built-in fetch so the backend
// has zero npm dependencies and runs anywhere Node 18+ is installed. To move to
// the official @anthropic-ai/sdk later, only this file changes.

const { planSchema, intakeSchema } = require('./schema');

const NAME = 'anthropic';
const API_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = process.env.ANTHROPIC_MODEL || process.env.FITPLUS_MODEL || 'claude-opus-4-8';
const ANTHROPIC_VERSION = '2023-06-01';

function hasApiKey() {
  return !!process.env.ANTHROPIC_API_KEY;
}

async function callMessages(body) {
  const res = await fetch(API_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': process.env.ANTHROPIC_API_KEY,
      'anthropic-version': ANTHROPIC_VERSION,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    const err = new Error(`Anthropic API error ${res.status}: ${text}`);
    err.status = res.status;
    throw err;
  }
  return res.json();
}

function firstTextBlock(message) {
  const block = (message.content || []).find((b) => b.type === 'text');
  return block ? block.text : '';
}

function firstToolUse(message, name) {
  return (message.content || []).find((b) => b.type === 'tool_use' && b.name === name) || null;
}

// Generate a structured weekly plan. Returns the raw parsed plan object (caller
// runs it through guardrails). Throws on API or parse failure so the caller can
// fall back to the stub.
async function generatePlan({ system, userMessage }) {
  const message = await callMessages({
    model: MODEL,
    max_tokens: 8000,
    thinking: { type: 'adaptive' },
    system,
    output_config: { format: { type: 'json_schema', schema: planSchema } },
    messages: [{ role: 'user', content: userMessage }],
  });

  if (message.stop_reason === 'refusal') {
    const err = new Error('Model refused the request.');
    err.refusal = message.stop_details || null;
    throw err;
  }

  const text = firstTextBlock(message);
  // With output_config.format the first text block is guaranteed valid JSON.
  return JSON.parse(text);
}

// Conversational plan editing. The model replies in text and, when the user
// requests a change, calls the update_plan tool with the full revised plan.
// Returns { reply, updatedPlan|null }.
async function chat({ system, history, currentPlan, userText }) {
  const tools = [
    {
      name: 'update_plan',
      description:
        'Apply a change to the user\'s current weekly plan. Provide the COMPLETE revised plan that conforms to the schema. Only call this when the user asks for a change, not for questions.',
      input_schema: planSchema,
    },
  ];

  const planContext = `The user's current plan (JSON):\n${JSON.stringify(currentPlan)}`;

  const messages = [
    { role: 'user', content: planContext },
    ...history.map((m) => ({ role: m.role, content: m.content })),
    { role: 'user', content: userText },
  ];

  const message = await callMessages({
    model: MODEL,
    max_tokens: 8000,
    thinking: { type: 'adaptive' },
    system,
    tools,
    messages,
  });

  if (message.stop_reason === 'refusal') {
    return {
      reply:
        "I can't help with that one. If you're dealing with pain or a medical issue, please check in with a professional — I can adjust your training around it once you have guidance.",
      updatedPlan: null,
    };
  }

  const reply = firstTextBlock(message) || 'Done.';
  const toolUse = firstToolUse(message, 'update_plan');
  return { reply, updatedPlan: toolUse ? toolUse.input : null };
}

// Conversational intake. Returns structured { reply, complete, profile }.
async function intake({ system, messages }) {
  const message = await callMessages({
    model: MODEL,
    max_tokens: 4000,
    thinking: { type: 'adaptive' },
    system,
    output_config: { format: { type: 'json_schema', schema: intakeSchema } },
    messages,
  });
  if (message.stop_reason === 'refusal') {
    return { reply: "Let's keep this about your training — tell me your goals and schedule.", complete: false, profile: null };
  }
  return JSON.parse(firstTextBlock(message));
}

module.exports = { NAME, hasApiKey, generatePlan, chat, intake, MODEL };
