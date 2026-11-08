#!/usr/bin/env node
// Offline measurement only: no model calls, credentials, or fabricated answers.
const fs = require('node:fs');
const path = require('node:path');
const providers = ['ChatGPT', 'Claude', 'Gemini', 'Grok', 'Perplexity'];
const strategy = path.resolve(__dirname, '../docs/20261009_AI_SEARCH_VISIBILITY_STRATEGY.md');
function prompts() {
  const section = fs.readFileSync(strategy, 'utf8').split('## Fixed evaluation prompts')[1].split('## Measurement and decisions')[0];
  const result = [...section.matchAll(/^(\d+)\. (.+)$/gm)].map(([, id, text]) => ({
    id: Number(id), text,
    category: Number(id) <= 4 ? 'branded' : Number(id) <= 12 ? 'task' : Number(id) <= 16 ? 'comparison' : Number(id) <= 20 ? 'evidence' : 'chinese',
  }));
  if (result.length !== 24 || result.some((p, i) => p.id !== i + 1)) throw Error('Expected the fixed 24 sequential prompts');
  return result;
}
function validate(records) {
  const seen = new Set();
  for (const r of records) {
    const fail = message => { throw Error(`${r.provider || '?'} / prompt ${r.promptId || '?'}: ${message}`); };
    if (!providers.includes(r.provider)) fail('unknown provider');
    if (!['consumer', 'api'].includes(r.interface)) fail('interface must be consumer or api');
    if (!Number.isInteger(r.promptId) || r.promptId < 1 || r.promptId > 24) fail('invalid promptId');
    if (!Number.isInteger(r.repeat) || r.repeat < 1 || r.repeat > 3) fail('repeat must be 1–3');
    if (!['completed', 'not_run', 'error'].includes(r.status)) fail('invalid status');
    const key = [r.provider, r.interface, r.promptId, r.repeat].join(':');
    if (seen.has(key)) fail('duplicate observation');
    seen.add(key);
    if (r.status !== 'completed') {
      if (!r.reason?.trim()) fail('unrun/error records require a reason');
      if (r.review != null) fail('unrun/error records cannot contain scored reviews');
      continue;
    }
    for (const k of ['model', 'mode', 'language', 'region', 'accountContext', 'answerPath']) {
      if (typeof r[k] !== 'string' || !r[k].trim()) fail(`missing ${k}`);
    }
    if (!/^\d{4}-\d{2}-\d{2}T/.test(r.capturedAt || '') || !Number.isFinite(Date.parse(r.capturedAt))) fail('invalid capturedAt');
    if (![true, false, null].includes(r.searchRan)) fail('searchRan must be true, false, or null (unknown)');
    if (!Array.isArray(r.citations)) fail('citations must be an array of public URLs');
    for (const url of r.citations) {
      try { if (!['https:', 'http:'].includes(new URL(url).protocol)) fail('invalid citation URL'); }
      catch { fail('invalid citation URL'); }
    }
    if (!path.isAbsolute(r.answerPath) || !fs.existsSync(r.answerPath) || !fs.statSync(r.answerPath).isFile() || !fs.readFileSync(r.answerPath, 'utf8').trim()) fail('answerPath must reference an existing nonempty archived answer');
    if (r.review != null) {
      if (typeof r.review.reviewer !== 'string' || !r.review.reviewer.trim()) fail('review requires reviewer');
      for (const k of ['mentionsBioMate', 'capabilityAccurate', 'citationsSupportClaims']) {
        if (![true, false, null].includes(r.review[k])) fail(`review.${k} must be true, false, or null`);
      }
    }
  }
  return records;
}
function summarize(records) {
  validate(records);
  const groups = {};
  for (const r of records) {
    const category = prompts()[r.promptId - 1].category;
    const key = `${r.provider}/${r.interface}/${category}`;
    const g = groups[key] ||= { observations: 0, completed: 0, searched: 0, noSearch: 0, searchUnknown: 0, notRun: 0, errors: 0, mentions: 0, mentionReviewed: 0, ownCitations: 0, accurate: 0, accuracyReviewed: 0, supported: 0, citationReviewed: 0 };
    g.observations++;
    if (r.status === 'not_run') { g.notRun++; continue; }
    if (r.status === 'error') { g.errors++; continue; }
    g.completed++;
    if (r.searchRan !== true) { g[r.searchRan === false ? 'noSearch' : 'searchUnknown']++; continue; }
    g.searched++;
    if (r.citations.some(u => { const h = new URL(u).hostname; return h === 'biomate.ai' || h.endsWith('.biomate.ai'); })) g.ownCitations++;
    for (const [field, numerator, denominator] of [['mentionsBioMate', 'mentions', 'mentionReviewed'], ['capabilityAccurate', 'accurate', 'accuracyReviewed'], ['citationsSupportClaims', 'supported', 'citationReviewed']]) {
      if (typeof r.review?.[field] === 'boolean') { g[denominator]++; if (r.review[field]) g[numerator]++; }
    }
  }
  return { note: 'Offline observations only. Missing cells are unmeasured; API and consumer results are separate. Review rates are answer-level judgments, not per-claim scientific accuracy.', groups };
}
if (require.main === module) {
  try {
    const [command, file] = process.argv.slice(2);
    if (command === 'plan') console.log(JSON.stringify({ providers, repeats: 3, expectedConsumerAnswers: 360, prompts: prompts() }, null, 2));
    else if (command === 'summarize' && file) {
      const records = fs.readFileSync(file, 'utf8').split(/\r?\n/).filter(s => s.trim()).map(s => JSON.parse(s));
      console.log(JSON.stringify(summarize(records), null, 2));
    } else throw Error('Usage: node scripts/ai_search_baseline.cjs plan | summarize <observations.jsonl>');
  } catch (e) { console.error(e.message); process.exitCode = 1; }
}
module.exports = { prompts, validate, summarize };
