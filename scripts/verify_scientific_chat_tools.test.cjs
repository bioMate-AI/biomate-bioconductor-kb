const {test}=require('node:test');
const assert=require('node:assert/strict');
const {parseEvents,toolResult}=require('./verify_scientific_chat_tools.cjs');
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
