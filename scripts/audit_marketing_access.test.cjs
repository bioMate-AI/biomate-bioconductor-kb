const {test} = require('node:test');
const assert = require('node:assert/strict');
const {summarizeAudit} = require('./audit_marketing_access.cjs');
test('public audit treats failed requests and HTTP-200 challenges as failures, not crawl success', () => {
  const result = summarizeAudit({pages:[{status:200,canonical:'https://biomate.ai/'},{error:'timeout'}],syntheticAgents:[{status:200,challenge:false},{status:200,challenge:true},{status:403,challenge:false}]});
  assert.deepEqual(result,{pagesChecked:2,non200:1,noindex:0,missingCanonical:1,syntheticAgentRequests:3,syntheticAgentBlocked:2});
});
test('noindex audit includes header restrictions and robots none, without treating nofollow as noindex', () => {
  const pages = [
    {robots:'NOINDEX, FOLLOW'}, {xRobotsTag:'googlebot: noindex'},
    {robots:'none'}, {robots:'index, nofollow'}, {robots:'index, follow'}
  ].map(p=>({status:200,canonical:'https://biomate.ai/',...p}));
  assert.equal(summarizeAudit({pages,syntheticAgents:[]}).noindex,3);
});
