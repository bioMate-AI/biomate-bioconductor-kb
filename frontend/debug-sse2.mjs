// Test the SSE stream directly
const BASE_URL = 'http://localhost:5000';

// Register
const ts = Date.now();
const regRes = await fetch(`${BASE_URL}/api/auth/register`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name: 'SSE Debug', email: `sse2_${ts}@biomate.test`, password: 'TestPass123!', confirmPassword: 'TestPass123!', agreeToTerms: true })
});
const regData = await regRes.json();
const token = regData.token;
console.log('[SSE2] Register status:', regRes.status, 'has_token:', !!token);

// Stream chat
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

console.log('[SSE2] Stream status:', streamRes.status);

const reader = streamRes.body.getReader();
const decoder = new TextDecoder();
let buffer = '';

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
    
    if (eventName === 'final') {
      const payload = JSON.parse(payloadText);
      console.log('\n[SSE2] === FINAL EVENT ===');
      console.log('workflow.success:', payload.workflow?.success);
      console.log('workflow.nextflow_path:', payload.workflow?.nextflow_path);
      console.log('workflow.workflow_name:', payload.workflow?.workflow_name);
      console.log('workflow.workflow_ga.name:', payload.workflow?.workflow_ga?.name);
      console.log('workflow.workflow_ga.nextflow_path:', payload.workflow?.workflow_ga?.nextflow_path);
      console.log('workflow.workflow_type:', payload.workflow?.workflow_type);
    }
  }
}
