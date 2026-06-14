'use strict';

// Thin OpenAI provider — same interface as anthropic.js, so the rest of the
// backend is unchanged. The API key lives here on the server and is never
// shipped to the Flutter client. Zero npm deps: we call the Chat Completions
// REST API directly with the built-in fetch.
//
// Structured output: OpenAI's strict json_schema mode requires every object to
// have additionalProperties:false and list all properties in `required` — our
// planSchema already satisfies that.

const { planSchema, intakeSchema } = require('./schema');

const NAME = 'openai';
const API_URL = 'https://api.openai.com/v1/chat/completions';
const MODEL = process.env.OPENAI_MODEL || 'gpt-4o';

function hasApiKey() {
  return !!process.env.OPENAI_API_KEY;
}

async function callChat(body) {
  const res = await fetch(API_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    const err = new Error(`OpenAI API error ${res.status}: ${text}`);
    err.status = res.status;
    throw err;
  }
  return res.json();
}

function jsonSchemaFormat(name, schema) {
  return { type: 'json_schema', json_schema: { name, strict: true, schema } };
}

// A chat-edit response carries both a human-readable reply and an optional full
// revised plan in one structured object. This avoids the "content is null when a
// function is called" pitfall of tool-calling and keeps the edit deterministic.
function chatResponseSchema() {
  return {
    type: 'object',
    additionalProperties: false,
    properties: {
      reply: { type: 'string', description: 'A short, warm, human-readable reply to the user.' },
      updated_plan: {
        anyOf: [planSchema, { type: 'null' }],
        description: 'The COMPLETE revised plan if the user asked for a change, otherwise null.',
      },
    },
    required: ['reply', 'updated_plan'],
  };
}

// Generate a structured weekly plan. Throws on API/parse/refusal so the caller
// can fall back to the stub.
async function generatePlan({ system, userMessage }) {
  const data = await callChat({
    model: MODEL,
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: userMessage },
    ],
    response_format: jsonSchemaFormat('weekly_plan', planSchema),
  });

  const msg = data.choices && data.choices[0] && data.choices[0].message;
  if (!msg) throw new Error('OpenAI returned no message');
  if (msg.refusal) {
    const err = new Error('Model refused the request.');
    err.refusal = msg.refusal;
    throw err;
  }
  return JSON.parse(msg.content);
}

// Conversational plan editing. Returns { reply, updatedPlan|null }.
async function chat({ system, history, currentPlan, userText }) {
  const planContext = `The user's current plan (JSON):\n${JSON.stringify(currentPlan)}`;
  const messages = [
    { role: 'system', content: system },
    { role: 'user', content: planContext },
    ...history.map((m) => ({ role: m.role, content: m.content })),
    { role: 'user', content: userText },
  ];

  const data = await callChat({
    model: MODEL,
    messages,
    response_format: jsonSchemaFormat('chat_response', chatResponseSchema()),
  });

  const msg = data.choices && data.choices[0] && data.choices[0].message;
  if (!msg) throw new Error('OpenAI returned no message');
  if (msg.refusal) {
    return {
      reply:
        "I can't help with that one. If you're dealing with pain or a medical issue, please check in with a professional — I can adjust your training around it once you have guidance.",
      updatedPlan: null,
    };
  }

  const parsed = JSON.parse(msg.content);
  return {
    reply: parsed.reply || 'Done.',
    updatedPlan: parsed.updated_plan || null,
  };
}

// Conversational intake. messages = full user/assistant history. Returns the
// structured { reply, complete, profile }.
async function intake({ system, messages }) {
  const data = await callChat({
    model: MODEL,
    messages: [{ role: 'system', content: system }, ...messages],
    response_format: jsonSchemaFormat('intake', intakeSchema),
  });
  const msg = data.choices && data.choices[0] && data.choices[0].message;
  if (!msg) throw new Error('OpenAI returned no message');
  if (msg.refusal) {
    return { reply: "Let's keep this about your training — tell me your goals and schedule.", complete: false, profile: null };
  }
  return JSON.parse(msg.content);
}

module.exports = { NAME, hasApiKey, generatePlan, chat, intake, MODEL };
