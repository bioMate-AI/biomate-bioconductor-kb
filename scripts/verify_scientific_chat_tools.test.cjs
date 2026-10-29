const {test}=require('node:test');
const assert=require('node:assert/strict');
const {parseEvents,toolResult,createdProjectId,reviewResult}=require('./verify_scientific_chat_tools.cjs');
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
