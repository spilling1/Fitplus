'use strict';

// Provider selector. The rest of the backend requires this module and never
// touches a vendor directly (PRD: keep the LLM provider swappable behind an
// interface). Each provider exposes the same surface:
//   { NAME, hasApiKey(), generatePlan(), chat(), MODEL }
//
// Selection order:
//   1. FITPLUS_PROVIDER=openai|anthropic forces a choice.
//   2. Otherwise use whichever key is present (OpenAI preferred if both).
//   3. Otherwise default to OpenAI (runs in offline stub mode until a key is set).

const anthropic = require('./anthropic');
const openai = require('./openai');

function select() {
  const forced = (process.env.FITPLUS_PROVIDER || '').toLowerCase();
  if (forced === 'openai') return openai;
  if (forced === 'anthropic') return anthropic;
  if (openai.hasApiKey()) return openai;
  if (anthropic.hasApiKey()) return anthropic;
  return openai;
}

module.exports = select();
