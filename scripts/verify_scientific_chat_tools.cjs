#!/usr/bin/env node
// Live API journey only: one fixture login, one project, two chat turns, no mocks/Batch.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {randomUUID} = require('node:crypto');

function parseEvents(text) {
  return text.replace(/\r\n/g, '\n').split('\n\n').filter(s=>s.trim()).flatMap(block=>{
    const lines=block.split('\n'), event=lines.find(l=>l.startsWith('event:'))?.slice(6).trim();
    const body=lines.filter(l=>l.startsWith('data:')).map(l=>l.slice(5).trimStart()).join('\n');
    if (!body || !event) return [];
    return [{event,data:JSON.parse(body)}];
  });
}
function toolResult(events, name) {
  assert.ok(events.some(e=>e.event==='done' && e.data.ok===true), 'chat stream did not finish successfully');
  assert.ok(!events.some(e=>e.event==='error'), 'chat stream reported an error');
  const calls=events.filter(e=>e.event==='tool_event' && e.data.name===name);
  assert.ok(calls.some(e=>e.data.type==='tool_call'), `${name} was never called`);
  const results=calls.filter(e=>e.data.type==='tool_result');
  assert.ok(results.length, `${name} did not produce a result`);
  const result=results[results.length-1].data;
  assert.ok(!result.error, `${name} dispatch failed`);
  const out=typeof result.output==='string' ? JSON.parse(result.output) : result.output;
  assert.ok(out && !out.error, `${name} returned an error: ${out?.error || 'empty result'}`);
  return out;
}
async function main() {
  if (!process.env.E2E_FIXTURE_PASSWORD) throw Error('Set E2E_FIXTURE_PASSWORD for the existing shared fixture; no account will be created or reset.');
  const base=(process.env.BIOMATE_TEST_BASE_URL || 'https://dev-public.biomate.ai').replace(/\/$/,'');
  assert.equal(new URL(base).hostname,'dev-public.biomate.ai','live harness is restricted to dev');
  const report={startedAt:new Date().toISOString(),base,kind:'live API chat journey, not UI or scientific efficacy validation',turns:[],status:'failed'};
  const output=process.argv[2] || 'docs/qa/20261029-scientific-chat-live.json';
  let projectId, token;
  async function request(path, body, method='POST') {
    const r=await fetch(base+path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:body==null?undefined:JSON.stringify(body),signal:AbortSignal.timeout(180000)});
    if (!r.ok) throw Error(`${method} ${path} HTTP ${r.status}`);
    return r;
  }
  try {
    const login=await (await request('/api/auth/login',{email:'lifeifei163361@163.com',password:process.env.E2E_FIXTURE_PASSWORD})).json();
    token=login.token; assert.ok(typeof token==='string' && token.length,'login did not return a token');
    const project=await (await request('/api/projects',{name:`Scientific tools QA ${randomUUID()}`})).json();
    projectId=project.id; assert.ok(projectId,'project id missing');
    report.projectId=projectId;
    const sessionId=randomUUID();
    for (const [name,message] of [
      ['identify_targets','Use identify_targets to rank BRAF, NRAS and TP53 for melanoma, with verified disease ID MONDO_0005105 and top_k 3. Report evidence, failed channels and ranking limitations. Do not create or run a workflow.'],
      ['write_review','Use write_review to write a short evidence-backed overview of BRAF-targeted therapy in melanoma, including resistance, disagreements, real references and limitations. Do not create or run a workflow.'],
    ]) {
      const started=Date.now();
      const stream=await (await request('/api/chat/stream',{message,stream:true,context:{sessionId,projectId,previousMessages:[]}})).text();
      const events=parseEvents(stream), result=toolResult(events,name);
      if (name==='identify_targets') {
        assert.equal(result.status,'ok'); assert.ok(result.targets.length);
        assert.ok(result.targets.every(t=>['BRAF','NRAS','TP53'].includes(t.target)),'returned an unrequested gene');
        assert.ok(result.ranking?.mode,'ranking provenance missing');
        assert.ok(result.channel_provenance,'channel provenance missing');
      } else {
        assert.equal(result.status,'ok','review was uncited or unsuccessful');
        assert.ok(result.answer?.trim()); assert.ok(result.citations?.length);
        for (const match of result.answer.matchAll(/\[(\d+)\]/g)) assert.ok(+match[1]>0 && +match[1]<=result.citations.length,'dangling reference');
      }
      report.turns.push({name,durationMs:Date.now()-started,result,events:events.map(e=>e.event)});
    }
    report.status='passed';
  } catch(e) {
    report.error=e.message; process.exitCode=1;
  } finally {
    if (projectId) {
      try { await request(`/api/projects/${encodeURIComponent(projectId)}`,null,'DELETE'); report.cleanup='project deleted'; }
      catch(e) {report.cleanup=e.message;process.exitCode=1;report.status='failed';}
    }
    report.finishedAt=new Date().toISOString();
    fs.mkdirSync(require('node:path').dirname(output),{recursive:true});
    fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n');
    console.log(JSON.stringify({status:report.status,turns:report.turns.length,output,error:report.error,cleanup:report.cleanup}));
  }
}
if (require.main===module) main().catch(e=>{console.error(e.message);process.exitCode=2;});
module.exports={parseEvents,toolResult};
