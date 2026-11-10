const {test}=require('node:test');
const assert=require('node:assert/strict');
const {parseEvents,toolResult,createdProjectId,reviewResult,assertTargetReply,assertFinalReply}=require('./verify_scientific_chat_tools.cjs');
const targetFixture={targets:[
  {rank:1,target:'BRAF',score:0.8533,tier:'corroborated',conflict:false},
  {rank:2,target:'NRAS',score:0.7794,tier:'corroborated',conflict:false},
  {rank:3,target:'TP53',score:0.7178,tier:'nominated',conflict:true},
]};
const targetReply='Target identification completed successfully.\n\n'+
  '| Rank | Target | Score | Evidence tier | Channel conflict |\n'+
  '| --- | --- | --- | --- | --- |\n'+
  '| 1 | BRAF | 0.8533 | corroborated | No |\n'+
  '| 2 | NRAS | 0.7794 | corroborated | No |\n'+
  '| 3 | TP53 | 0.7178 | nominated | Yes |';
test('actual target scores must reach users; a successful tool event alone is insufficient',()=>{
  assert.doesNotThrow(()=>assertTargetReply(targetFixture,targetReply));
  assert.throws(()=>assertTargetReply(targetFixture,'BRAF and NRAS are associated with melanoma.'),/table/);
});
test('target rows bind rank, gene, score, tier and conflict rather than independent substrings',()=>{
  const wrongRows=[
    targetReply.replace('BRAF | 0.8533','BRAF | 0.7794').replace('NRAS | 0.7794','NRAS | 0.8533'),
    targetReply.replace('| 1 | BRAF','| 2 | BRAF'),
    targetReply.replace('TP53 | 0.7178 | nominated','TP53 | 0.7178 | corroborated'),
    targetReply.replace('nominated | Yes','nominated | No'),
    targetReply.replace('| 3 | TP53 | 0.7178 | nominated | Yes |',''),
    targetReply+'\n| 3 | TP53 | 0.7178 | nominated | Yes |',
  ];
  for(const text of wrongRows) assert.throws(()=>assertTargetReply(targetFixture,text));
});
test('known three-target fixture rejects missing, extra and duplicate backend genes',()=>{
  for(const targets of [targetFixture.targets.slice(0,1),
    [...targetFixture.targets,{rank:4,target:'EGFR',score:0.5,tier:'nominated'}],
    [targetFixture.targets[0],targetFixture.targets[0],targetFixture.targets[2]]]) {
    assert.throws(()=>assertTargetReply({targets},targetReply),/exactly BRAF/);
  }
});
test('successful tables do not conceal execution-denial variants',()=>{
  for(const denial of [
    'Target identification was not executed.',
    'Target identification could not be executed.',
    'I did not actually execute target identification.',
    'I could not run target identification.',
    "I couldn't execute target identification.",
    'Target identification has never been performed.',
    'I am unable to execute target identification.',
    'This answer was written without running the live target channels.',
  ]) assert.throws(()=>assertTargetReply(targetFixture,targetReply+'\n'+denial),/denied/);
});
test('streamed reply must match the actual final.response and any final.message',()=>{
  assert.doesNotThrow(()=>assertFinalReply([{event:'final',data:{response:targetReply}}],targetReply));
  assert.doesNotThrow(()=>assertFinalReply([{event:'final',data:{message:targetReply}}],targetReply));
  assert.doesNotThrow(()=>assertFinalReply([{event:'final',data:{researchResponse:{}}}],targetReply));
  for(const field of ['response','message']) {
    assert.throws(()=>assertFinalReply([{event:'final',data:{[field]:targetReply}}],'Leaked preamble\n'+targetReply),/differs/);
    assert.throws(()=>assertFinalReply([{event:'final',data:{[field]:{text:targetReply}}}],targetReply),/must be reply text/);
  }
  assert.throws(()=>assertFinalReply([{event:'final',data:{response:targetReply,message:'different'}}],targetReply),/final.message/);
});
test('automatic research needs a real successful cited artifact, not just fluent final prose',()=>{
  const end={event:'done',data:{ok:true}};
  assert.throws(()=>reviewResult([{event:'final',data:{message:'A convincing overview'}},end]),/no successful/);
  const result=reviewResult([{event:'final',data:{researchResponse:{success:true,source:'research_agent',answer:'Evidence [1]',citations:[{title:'Paper'}]}}},end]);
  assert.equal(result.executionPath,'automatic_research_agent');
});
test('a failed explicit review tool is never hidden behind a successful automatic artifact',()=>{
  assert.throws(()=>reviewResult([{event:'tool_event',data:{name:'write_review',type:'tool_call'}},{event:'tool_event',data:{name:'write_review',type:'tool_result',output:'{"error":"failed"}'}},{event:'done',data:{ok:true}}]),/returned an error/);
});
test('project setup uses the real wrapped API contract and refuses a guessed root id',()=>{
  assert.equal(createdProjectId({project:{id:'qa-project'}}),'qa-project');
  assert.throws(()=>createdProjectId({id:'qa-project'}),/project wrapper/);
});
test('SSE parser handles CRLF and multiline data, not just matching tool names in prose',()=>{
  const events=parseEvents('event: tool_event\r\ndata: {"name":"write_review",\r\ndata: "type":"tool_call"}\r\n\r\nevent: done\r\ndata: {"ok":true}\r\n\r\n');
  assert.equal(events[0].data.name,'write_review');
  assert.throws(()=>toolResult(events,'write_review'),/did not produce/);
});
test('successful-looking prose, empty streams and backend tool errors never pass',()=>{
  for(const events of [[],[{event:'done',data:{ok:true}}],[{event:'done',data:{ok:false}}]]) assert.throws(()=>toolResult(events,'identify_targets'));
  const events=[{event:'tool_event',data:{type:'tool_call',name:'identify_targets'}},{event:'tool_event',data:{type:'tool_result',name:'identify_targets',output:'{"error":"401"}'}},{event:'done',data:{ok:true}}];
  assert.throws(()=>toolResult(events,'identify_targets'),/returned an error/);
});
test('completed tool call and actual JSON result are both required',()=>{
  const events=[{event:'tool_event',data:{type:'tool_call',name:'write_review'}},{event:'tool_event',data:{type:'tool_result',name:'write_review',output:'{"status":"ok","answer":"grounded"}'}},{event:'done',data:{ok:true}}];
  assert.equal(toolResult(events,'write_review').answer,'grounded');
});
