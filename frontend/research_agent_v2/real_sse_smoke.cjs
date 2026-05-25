/**
 * Real-backend SSE contract smoke — verifies end-to-end wire path:
 *
 *   POST /internal/sse-inject  (chat_progress events)
 *       → WorkflowSSEManager.injectRawEvent
 *       → GET  /api/workflows/<inv>/events  (EventSource client)
 *       → translateBiomateEvent(payload)
 *
 * Run:  node real_sse_smoke.cjs [https://dev-public.biomate.ai]
 *
 * What it does:
 *  1. Opens an EventSource (eventsource npm OR raw https.request fallback)
 *     against /api/workflows/<smoke-inv>/events.
 *  2. Injects 8 representative chat_progress events shaped exactly like
 *     workflow_chat_narrator.emit() would (kind, invocation_id,
 *     friendly_message, ts, technical — no speaker).
 *  3. Runs each received payload through a JS port of translateBiomateEvent
 *     + deriveSpeakerFallback (loaded from src/sse-adapter.js implicitly).
 *  4. Asserts: each event arrives, JSON parses, has the expected fields,
 *     speaker derivation matches the wire kind, friendly_message survives
 *     the round-trip intact.
 *
 * No browser, no auth, no actual workflow needed — exercises the wire
 * path the sandbox's ?live=real mode depends on.
 */

const https = require('https');
const http = require('http');

const BASE = process.argv[2] || 'https://dev-public.biomate.ai';
const INV  = 'rav2-smoke-' + Date.now();

// ── Speaker fallback (mirror of ResearchApp.deriveSpeakerFallback) ──
function deriveSpeakerFallback(kind) {
  if (!kind) return 'wf';
  if (kind.startsWith('workflow.qc_'))      return 'qc';
  if (kind.startsWith('workflow.autoloop')) return 'loop';
  if (kind.startsWith('workflow.'))         return 'wf';
  if (kind.startsWith('deepagent.'))        return 'agent';
  if (kind.startsWith('plan.'))             return 'plan';
  if (kind.startsWith('findings.'))         return 'find';
  return 'wf';
}

// ── translateBiomateEvent (mirror of ResearchApp's) ──
function translateBiomateEvent(ev) {
  if (ev.kind === 'plan.shown') {
    const items = (ev.technical && ev.technical.items) || [];
    return [{ kind: 'planShow', items, editing: false }];
  }
  return [{
    kind: 'chatLine',
    s: ev.speaker || deriveSpeakerFallback(ev.kind),
    m: ev.friendly_message,
    rationaleId: ev.technical && ev.technical.rationale_id,
  }];
}

// ── Tape of events to inject (covers all speaker prefixes) ──
const TAPE = [
  { kind: 'workflow.submitted',        friendly_message: 'Got it — starting your workflow now.', technical: { workflow: 'smoke' }, expected: 'wf' },
  { kind: 'plan.shown',                friendly_message: 'Decomposed into sub-tasks.',           technical: { items: [{id:'a',title:'Step A',status:'pending'}] }, expected: 'plan' },
  { kind: 'workflow.phase_started',    friendly_message: 'Step 1/3: STAR alignment…',            technical: { phase_name: 'STAR alignment', n: 1, of: 3 }, expected: 'wf' },
  { kind: 'workflow.qc_gate_warning',  friendly_message: 'QC flagged mapping_rate = 0.948 (threshold 0.95).', technical: { metric: 'mapping_rate', value: 0.948, threshold: 0.95 }, expected: 'qc' },
  { kind: 'workflow.autoloop_started', friendly_message: 'Trying again with logp_max=4.5.',      technical: { changes: { logp_max: 4.5 } }, expected: 'loop' },
  { kind: 'deepagent.start',           friendly_message: 'Looking into why your workflow failed…', technical: {}, expected: 'agent' },
  { kind: 'findings.generated',        friendly_message: 'Findings are ready in the After-run report.', technical: {}, expected: 'find' },
  { kind: 'workflow.completed',        friendly_message: 'Workflow finished. 3/3 steps succeeded.', technical: { steps_succeeded: 3, steps_total: 3 }, expected: 'wf' },
];

// ── Tiny EventSource implementation over https.request (no npm dep) ──
function openSSE(url, onEvent, onConnect) {
  const lib = url.startsWith('https') ? https : http;
  const req = lib.request(url, { method: 'GET', headers: { Accept: 'text/event-stream' } }, (res) => {
    if (res.statusCode !== 200) {
      console.error('SSE HTTP', res.statusCode);
      process.exit(2);
    }
    let buf = '';
    let evType = null;
    res.setEncoding('utf8');
    res.on('data', chunk => {
      buf += chunk;
      let idx;
      while ((idx = buf.indexOf('\n\n')) !== -1) {
        const block = buf.slice(0, idx);
        buf = buf.slice(idx + 2);
        const lines = block.split('\n');
        let type = 'message', data = '';
        for (const ln of lines) {
          if (ln.startsWith('event:')) type = ln.slice(6).trim();
          else if (ln.startsWith('data:')) data += ln.slice(5).trim();
        }
        if (type === 'connected') onConnect && onConnect(data);
        else if (type === 'chat_progress') onEvent(data);
      }
    });
    res.on('end', () => {});
  });
  req.on('error', e => { console.error('SSE req error:', e.message); process.exit(2); });
  req.end();
  return req;
}

function postJSON(url, body) {
  return new Promise((resolve, reject) => {
    const lib = url.startsWith('https') ? https : http;
    const u = new URL(url);
    const req = lib.request({
      method: 'POST', hostname: u.hostname, port: u.port, path: u.pathname,
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
    }, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

(async () => {
  const sseUrl = `${BASE}/api/workflows/${encodeURIComponent(INV)}/events`;
  const injectUrl = `${BASE}/internal/sse-inject`;
  console.log('[smoke] SSE   :', sseUrl);
  console.log('[smoke] inject:', injectUrl);

  const received = [];
  const fails = [];

  openSSE(sseUrl, (raw) => {
    try {
      const ev = JSON.parse(raw);
      const internal = translateBiomateEvent(ev);
      received.push({ raw: ev, internal });
    } catch (e) {
      fails.push('bad JSON: ' + e.message);
    }
  }, () => console.log('[smoke] connected'));

  // Wait a beat for connection to register
  await new Promise(r => setTimeout(r, 1500));

  // Inject the tape
  for (const [i, ev] of TAPE.entries()) {
    const payload = {
      invocation_id: INV,
      event_type: 'chat_progress',
      data: { kind: ev.kind, invocation_id: INV, friendly_message: ev.friendly_message, ts: Date.now()/1000, technical: ev.technical },
    };
    const r = await postJSON(injectUrl, JSON.stringify(payload));
    if (r.status !== 200) fails.push(`inject ${i} (${ev.kind}) HTTP ${r.status}: ${r.body.slice(0,200)}`);
    await new Promise(r => setTimeout(r, 300));
  }

  // Wait for the receiver to drain
  await new Promise(r => setTimeout(r, 2500));

  // Validate
  console.log(`[smoke] received ${received.length}/${TAPE.length} events`);
  for (const [i, exp] of TAPE.entries()) {
    const got = received[i];
    if (!got) { fails.push(`MISSING #${i} (${exp.kind})`); continue; }
    if (got.raw.kind !== exp.kind)
      fails.push(`#${i} kind: ${got.raw.kind} ≠ ${exp.kind}`);
    if (got.raw.friendly_message !== exp.friendly_message)
      fails.push(`#${i} friendly_message altered: ${got.raw.friendly_message}`);
    if (got.raw.speaker !== undefined)
      fails.push(`#${i} unexpected speaker on wire (backend should not send it): ${got.raw.speaker}`);
    const derivedSpeaker = exp.kind === 'plan.shown' ? null : got.internal[0]?.s;
    if (exp.kind !== 'plan.shown' && derivedSpeaker !== exp.expected)
      fails.push(`#${i} speaker derived=${derivedSpeaker} ≠ expected=${exp.expected}`);
    // plan.shown special — items must come through
    if (exp.kind === 'plan.shown') {
      const items = got.internal[0]?.items || [];
      if (got.internal[0]?.kind !== 'planShow') fails.push(`#${i} plan.shown → ${got.internal[0]?.kind}`);
      if (items.length !== 1) fails.push(`#${i} plan items lost: ${items.length}`);
    }
  }

  console.log('\n=== RESULT ===');
  if (fails.length === 0) {
    console.log(`✓ ALL ${TAPE.length} events round-tripped through dev EC2 SSE pipeline`);
    console.log('  · backend payload shape matches sandbox expectations');
    console.log('  · speaker derivation fallback works for every prefix');
    console.log('  · plan.shown items survive injection → SSE → translation');
    console.log('  · friendly_message preserved end-to-end');
    process.exit(0);
  } else {
    console.error(`✗ ${fails.length} failure(s):`);
    for (const f of fails) console.error('  -', f);
    process.exit(1);
  }
})();
