// Test the SSE stream directly to see what the final event contains
const BASE_URL = 'http://localhost:5000';

// First register and get a session
const ts = Date.now();
const email = `sse_debug_${ts}@biomate.test`;
const password = 'TestPass123!';

const regRes = await fetch(`${BASE_URL}/api/register`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name: 'SSE Debug', email, password })
});
const regData = await regRes.json();
const token = regData.token;
console.log('[SSE] Register status:', regRes.status, 'token:', !!token);

// Send chat message via stream
const streamRes = await fetch(`${BASE_URL}/api/chat/stream`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    ...(token ? { 'Authorization': `Bearer ${token}` } : {})
  },
  body: JSON.stringify({
    message: 'Perform variant calling on whole genome sequencing data using GATK',
    stream: true,
    context: {}
  })
});

console.log('[SSE] Stream status:', streamRes.status);

const reader = streamRes.body.getReader();
const decoder = new TextDecoder();
let buffer = '';
let eventCount = 0;

while (true) {
  const { done, value } = await reader.read();
  if (done) break;
  buffer += decoder.decode(value, { stream: true });
  
  while (true) {
    const boundary = buffer.indexOf('\n\n');
    if (boundary === -1) break;
    const rawEvent = buffer.slice(0, boundary);
    buffer = buffer.slice(boundary + 2);
    
    const lines = rawEvent.split('\n');
    let eventName = 'message';
    const dataLines = [];
    for (const line of lines) {
      if (line.startsWith('event:')) eventName = line.slice(6).trim();
      if (line.startsWith('data:')) dataLines.push(line.slice(5).trim());
    }
    const payloadText = dataLines.join('\n');
    if (!payloadText) continue;
    
    eventCount++;
    if (eventName === 'final') {
      try {
        const payload = JSON.parse(payloadText);
        console.log('[SSE] FINAL event received!');
        console.log('[SSE] workflow:', JSON.stringify(payload.workflow)?.slice(0, 500));
        console.log('[SSE] workflow.success:', payload.workflow?.success);
        console.log('[SSE] workflow.nextflow_path:', payload.workflow?.nextflow_path);
        console.log('[SSE] workflow.workflow_name:', payload.workflow?.workflow_name);
        console.log('[SSE] workflow.workflow_ga:', JSON.stringify(payload.workflow?.workflow_ga)?.slice(0, 300));
        console.log('[SSE] response (first 200):', payload.response?.slice(0, 200));
      } catch (e) {
        console.log('[SSE] FINAL parse error:', e.message);
        console.log('[SSE] FINAL raw:', payloadText.slice(0, 500));
      }
    } else if (eventName === 'done') {
      console.log('[SSE] DONE event');
    }
  }
}
console.log('[SSE] Total events:', eventCount);
