const { test } = require('node:test');
const assert = require('node:assert/strict');
const { prompts, validate, summarize } = require('./ai_search_baseline.cjs');
const record = overrides => ({ provider:'ChatGPT', interface:'consumer', promptId:1, repeat:1, status:'completed', model:'record displayed model', mode:'web', language:'en', region:'US', accountContext:'fresh chat; account tier recorded', capturedAt:'2026-10-09T23:00:00Z', answerPath:__filename, searchRan:true, citations:[], ...overrides });
test('24 prompts retain separate categories and non-branded task queries', () => {
  const p = prompts(); assert.equal(p.length, 24);
  assert.equal(p.filter(x => x.category === 'task').length, 8);
  assert.ok(p.filter(x => x.category === 'task').every(x => !/biomate/i.test(x.text)));
});
test('missing, unknown-search and failed answers never become measured zeros', () => {
  assert.deepEqual(summarize([]).groups, {});
  const g = summarize([record({searchRan:null}), record({repeat:2,status:'error',reason:'unavailable'})]).groups['ChatGPT/consumer/branded'];
  assert.equal(g.searched,0); assert.equal(g.mentionReviewed,0); assert.equal(g.errors,1); assert.equal(g.searchUnknown,1);
});
test('rejects duplicates, missing archives, malformed reviews and fabricated results on unrun cells', () => {
  assert.throws(() => validate([record(),record()]), /duplicate/);
  assert.throws(() => validate([record({answerPath:'/nonexistent/answer.txt'})]), /archived answer/);
  assert.throws(() => validate([record({review:{reviewer:'tester',mentionsBioMate:'yes'}})]), /must be true/);
  assert.throws(() => validate([record({status:'not_run',reason:'no access',review:{}})]), /cannot contain/);
});
test('API, consumer and prompt categories stay separate; unreviewed answers are excluded', () => {
  const g = summarize([record(),record({interface:'api'}),record({promptId:5})]).groups;
  assert.equal(Object.keys(g).length,3); assert.equal(g['ChatGPT/consumer/branded'].mentionReviewed,0);
});
test('citation host matching rejects spoofed brand domains and counts exact/subdomain URLs', () => {
  const g = summarize([record({citations:['https://biomate.ai.evil.example/']}),record({repeat:2,citations:['https://biomate.ai/benchmarks.html']}),record({repeat:3,citations:['https://docs.biomate.ai/']})]).groups['ChatGPT/consumer/branded'];
  assert.equal(g.ownCitations,2); assert.equal(g.searched,3);
});
test('no-search answers remain separate even when reviewed positively', () => {
  const g = summarize([record({searchRan:false,review:{reviewer:'human',mentionsBioMate:true,capabilityAccurate:true,citationsSupportClaims:null}})]).groups['ChatGPT/consumer/branded'];
  assert.equal(g.noSearch,1); assert.equal(g.mentions,0);
});
