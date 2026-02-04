/**
 * E2E Tests: Flexible Intent Architecture
 *
 * Tests the full user journey through the live system (frontend + backend).
 * Each test hits the real /api/chat endpoint with real LLM inference.
 *
 * Evaluation tiers:
 *   MUST  — failure = bug; blocks release
 *   SHOULD — failure = gap; logged as warning
 *   NICE  — informational; logged for visibility
 *
 * Prerequisites:
 *   - Frontend running on port 5000
 *   - Backend running on port 8081
 *   - PostgreSQL running with LTM tables
 *
 * Run: cd frontend && npx tsx server/test-e2e-flexible-intents.ts
 */

import { db, ltmSchema } from './db';
import { eq } from 'drizzle-orm';

const BASE_URL = process.env.TEST_BASE_URL || 'http://localhost:5000';
const TIMEOUT_MS = 120_000;

// ============================================================================
// Counters & reporting
// ============================================================================

interface TestResult {
  label: string;
  severity: 'MUST' | 'SHOULD' | 'NICE';
  passed: boolean;
  detail?: string;
  elapsedMs?: number;
}

const results: TestResult[] = [];

function record(severity: 'MUST' | 'SHOULD' | 'NICE', passed: boolean, label: string, detail?: string, elapsedMs?: number) {
  results.push({ severity, passed, label, detail, elapsedMs });
  const icon = passed ? '\u2713' : '\u2717';
  const tag = severity.padEnd(6);
  const time = elapsedMs !== undefined ? ` (${(elapsedMs / 1000).toFixed(1)}s)` : '';
  const extra = (!passed && detail) ? ` — ${detail}` : '';
  console.log(`  ${icon} ${tag} ${label}${time}${extra}`);
}

function header(title: string) {
  console.log('\n' + '='.repeat(72));
  console.log(`  ${title}`);
  console.log('='.repeat(72));
}

// ============================================================================
// Helpers
// ============================================================================

function generateSessionId(): string {
  // Must be a valid UUID for PostgreSQL
  const hex = () => Math.random().toString(16).slice(2, 6);
  return `e2e0${hex()}-${hex()}-4${hex().slice(1)}-8${hex().slice(1)}-${hex()}${hex()}${hex().slice(0,4)}`;
}

async function cleanupSession(sessionId: string) {
  try {
    await db.delete(ltmSchema.conversationStateFacts)
      .where(eq(ltmSchema.conversationStateFacts.sessionId, sessionId));
    await db.delete(ltmSchema.sessions)
      .where(eq(ltmSchema.sessions.id, sessionId));
  } catch {
    // Ignore cleanup errors
  }
}

async function createTestSession(sessionId: string, title: string): Promise<void> {
  await cleanupSession(sessionId);
  await db.insert(ltmSchema.sessions).values({ id: sessionId, title });
}

interface ChatResponse {
  response: string;
  suggestions?: string[];
  workflow?: any;
  metadata?: {
    intentType?: string;
    rawIntentType?: string;
    inlineParameters?: Record<string, string>;
    recommendedTools?: any[];
    sources?: {
      toolSearchUsed?: boolean;
      datasetRAGUsed?: boolean;
      researchAgentUsed?: boolean;
      benchmarkAgentUsed?: boolean;
    };
    researchResponse?: any;
    benchmarkEvidence?: any;
  };
  stateSnapshot?: {
    phase: string;
    factCount: number;
    readinessScore: number;
    missingRequired: string[];
    intentType: string;
    intentConfidence: number;
  };
  isMultiIntent?: boolean;
  subIntentResults?: any[];
  clarification?: any;
  _debug_timings?: any[];
}

async function sendChat(message: string, sessionId?: string): Promise<{ data: ChatResponse; status: number; elapsedMs: number }> {
  const body: any = { message };
  if (sessionId) body.context = { sessionId };

  const start = Date.now();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const res = await fetch(`${BASE_URL}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    clearTimeout(timeout);
    const elapsedMs = Date.now() - start;
    const text = await res.text();
    let data: ChatResponse;
    try {
      data = JSON.parse(text);
    } catch {
      data = { response: text } as any;
    }
    return { data, status: res.status, elapsedMs };
  } catch (err: any) {
    clearTimeout(timeout);
    const elapsedMs = Date.now() - start;
    if (err.name === 'AbortError') {
      throw new Error(`Request timed out after ${TIMEOUT_MS}ms`);
    }
    throw err;
  }
}

async function sendChatRaw(body: any): Promise<{ status: number; body: string; elapsedMs: number }> {
  const start = Date.now();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const res = await fetch(`${BASE_URL}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    clearTimeout(timeout);
    const elapsedMs = Date.now() - start;
    const text = await res.text();
    return { status: res.status, body: text, elapsedMs };
  } catch (err: any) {
    clearTimeout(timeout);
    throw err;
  }
}

// ============================================================================
// E2E-1: Intent Classification Accuracy
// ============================================================================

async function e2e1_intentClassification() {
  header('E2E-1: Intent Classification Accuracy');

  const cases: { query: string; expected: string[]; label: string }[] = [
    { query: 'Get the reverse complement of ATGCGATCG', expected: ['workflow_generation', 'data_format_conversion'], label: 'workflow_generation' },
    { query: 'What papers discuss CRISPR delivery methods in vivo?', expected: ['research_question'], label: 'research_question' },
    { query: 'Compare BWA vs Bowtie2 for short reads', expected: ['result_comparison', 'comparative_methodology', 'benchmark_query'], label: 'result_comparison' },
    { query: 'What tools can do peak calling in ChIP-seq?', expected: ['tool_search'], label: 'tool_search' },
    { query: 'Show me benchmarks for variant callers', expected: ['benchmark_query', 'result_comparison'], label: 'benchmark_query' },
    { query: 'What datasets do you have for mouse RNA-seq?', expected: ['dataset_inquiry'], label: 'dataset_inquiry' },
    { query: 'Hello, what can you do?', expected: ['general_question', 'teaching_explanation'], label: 'general_question' },
    { query: 'My alignment rate is only 30%, what could be wrong?', expected: ['troubleshooting', 'workflow_generation', 'general_question'], label: 'troubleshooting' },
  ];

  let correct = 0;
  for (const tc of cases) {
    try {
      const { data, status, elapsedMs } = await sendChat(tc.query);

      record('MUST', status === 200, `${tc.label}: HTTP 200`, `got ${status}`, elapsedMs);
      record('MUST', typeof data.response === 'string' && data.response.length > 0,
        `${tc.label}: non-empty response`, data.response?.slice(0, 80));
      record('MUST', elapsedMs < TIMEOUT_MS,
        `${tc.label}: within timeout`, `${(elapsedMs / 1000).toFixed(1)}s`);

      const intentType = data.metadata?.intentType || data.stateSnapshot?.intentType || '';
      const matched = tc.expected.includes(intentType);
      record('SHOULD', matched,
        `${tc.label}: intent = "${intentType}" (expected one of [${tc.expected.join(', ')}])`,
        matched ? undefined : `got "${intentType}"`);
      if (matched) correct++;
    } catch (err: any) {
      record('MUST', false, `${tc.label}: request failed`, err.message);
    }
  }

  console.log(`\n  Classification accuracy: ${correct}/${cases.length} (${((correct / cases.length) * 100).toFixed(0)}%)`);
}

// ============================================================================
// E2E-2: Fact Extraction & State Persistence (Multi-turn)
// ============================================================================

async function e2e2_factExtractionMultiTurn() {
  header('E2E-2: Fact Extraction & State Persistence');

  const sessionId = generateSessionId();
  await createTestSession(sessionId, 'E2E-2 Fact Extraction');

  const turns = [
    { msg: 'Align human WGS paired-end reads with BWA-MEM against hg38', label: 'Turn 1: initial' },
    { msg: 'Actually, use mouse genome mm10 instead', label: 'Turn 2: supersede' },
    { msg: 'Also filter for mapping quality > 30', label: 'Turn 3: new fact' },
  ];

  const snapshots: (ChatResponse['stateSnapshot'] | undefined)[] = [];

  for (const turn of turns) {
    try {
      const { data, elapsedMs } = await sendChat(turn.msg, sessionId);

      record('MUST', typeof data.response === 'string' && data.response.length > 0,
        `${turn.label}: non-empty response`, undefined, elapsedMs);

      const snap = data.stateSnapshot;
      snapshots.push(snap);

      if (snap) {
        record('MUST', typeof snap.phase === 'string' && snap.phase.length > 0,
          `${turn.label}: phase = "${snap.phase}"`);
        record('MUST', typeof snap.factCount === 'number',
          `${turn.label}: factCount = ${snap.factCount}`);
        record('MUST', snap.intentConfidence > 0,
          `${turn.label}: intentConfidence = ${snap.intentConfidence}`);
      } else {
        record('SHOULD', false, `${turn.label}: stateSnapshot missing`);
      }
    } catch (err: any) {
      record('MUST', false, `${turn.label}: request failed`, err.message);
      snapshots.push(undefined);
    }
  }

  // Cross-turn checks
  const s1 = snapshots[0];
  const s2 = snapshots[1];
  const s3 = snapshots[2];

  if (s1 && s2) {
    record('SHOULD', (s2.factCount ?? 0) >= (s1.factCount ?? 0),
      `Turn 2 factCount (${s2.factCount}) >= Turn 1 (${s1.factCount})`);
  }
  if (s1 && s3) {
    record('SHOULD', (s3.factCount ?? 0) >= (s1.factCount ?? 0),
      `Turn 3 factCount (${s3.factCount}) >= Turn 1 (${s1.factCount})`);
  }

  // Intent stability
  const intents = snapshots.map(s => s?.intentType).filter(Boolean);
  if (intents.length >= 2) {
    const stable = intents.every(i => i === intents[0]);
    record('SHOULD', stable,
      `Intent stable across turns: [${intents.join(', ')}]`);
  }

  await cleanupSession(sessionId);
}

// ============================================================================
// E2E-3: Tool Search After Fix
// ============================================================================

async function e2e3_toolSearch() {
  header('E2E-3: Tool Search (Post-Fix)');

  const cases = [
    { query: 'What tools can do variant calling?', label: 'variant calling tools' },
    { query: 'Run differential expression with DESeq2', label: 'DE with DESeq2' },
    { query: 'Find tools for peak calling in ChIP-seq', label: 'peak calling tools' },
  ];

  for (const tc of cases) {
    try {
      const { data, status, elapsedMs } = await sendChat(tc.query);

      record('MUST', status === 200, `${tc.label}: HTTP 200`, `got ${status}`, elapsedMs);

      const toolSearchUsed = data.metadata?.sources?.toolSearchUsed;
      record('MUST', toolSearchUsed === true,
        `${tc.label}: toolSearchUsed = ${toolSearchUsed}`,
        toolSearchUsed === true ? undefined : `got ${toolSearchUsed}`);

      const tools = data.metadata?.recommendedTools || [];
      record('SHOULD', tools.length > 0,
        `${tc.label}: ${tools.length} tools returned`);

      if (tools.length > 0) {
        const first = tools[0];
        record('SHOULD', typeof first.tool?.tool_id === 'string',
          `${tc.label}: first tool has tool_id`, JSON.stringify(first.tool?.tool_id)?.slice(0, 80));
        record('NICE', !String(first.tool?.tool_id || '').includes('Repository_Actions_'),
          `${tc.label}: tool_id clean (no Repository_Actions_ prefix)`);
      }
    } catch (err: any) {
      record('MUST', false, `${tc.label}: request failed`, err.message);
    }
  }
}

// ============================================================================
// E2E-4: Workflow Generation
// ============================================================================

async function e2e4_workflowGeneration() {
  header('E2E-4: Workflow Generation');

  const cases = [
    { query: 'Get the reverse complement of ATGCGATCG', label: 'reverse complement' },
    { query: 'Convert FASTQ to FASTA format', label: 'format conversion' },
  ];

  for (const tc of cases) {
    try {
      const { data, status, elapsedMs } = await sendChat(tc.query);

      record('MUST', status === 200, `${tc.label}: HTTP 200`, `got ${status}`, elapsedMs);
      record('MUST', typeof data.response === 'string' && data.response.length > 0,
        `${tc.label}: non-empty response`);

      const wf = data.workflow;
      record('SHOULD', wf !== null && wf !== undefined,
        `${tc.label}: workflow present`, wf ? 'yes' : 'null');

      if (wf) {
        record('SHOULD', wf.success === true,
          `${tc.label}: workflow.success = ${wf.success}`);

        const steps = wf.workflow_ga?.steps;
        const hasSteps = steps && typeof steps === 'object' && Object.keys(steps).length > 0;
        record('SHOULD', hasSteps,
          `${tc.label}: workflow has ${hasSteps ? Object.keys(steps).length : 0} steps`);

        if (hasSteps) {
          const firstStep = Object.values(steps)[0] as any;
          record('NICE', typeof firstStep?.tool_id === 'string',
            `${tc.label}: step tool_id = ${firstStep?.tool_id?.slice(0, 60)}`);
        }
      }
    } catch (err: any) {
      record('MUST', false, `${tc.label}: request failed`, err.message);
    }
  }
}

// ============================================================================
// E2E-5: Readiness Score Evolution
// ============================================================================

async function e2e5_readinessEvolution() {
  header('E2E-5: Readiness Score Evolution');

  const sessionId = generateSessionId();
  await createTestSession(sessionId, 'E2E-5 Readiness');

  const turns = [
    { msg: 'I want to analyze some data', label: 'Turn 1: vague' },
    { msg: "It's RNA-seq data from human samples", label: 'Turn 2: more detail' },
    { msg: 'Use STAR for alignment, then DESeq2 for DE, p-value cutoff 0.05', label: 'Turn 3: specific' },
  ];

  const scores: number[] = [];

  for (const turn of turns) {
    try {
      const { data, elapsedMs } = await sendChat(turn.msg, sessionId);
      const score = data.stateSnapshot?.readinessScore;

      record('MUST', typeof score === 'number',
        `${turn.label}: readinessScore = ${score}`, undefined, elapsedMs);

      if (typeof score === 'number') {
        record('MUST', score >= 0 && score <= 1,
          `${turn.label}: readinessScore in [0,1]`, `got ${score}`);
        scores.push(score);
      }
    } catch (err: any) {
      record('MUST', false, `${turn.label}: request failed`, err.message);
    }
  }

  // Trend check
  if (scores.length >= 3) {
    record('SHOULD', scores[2] > scores[0],
      `Readiness increased: ${scores[0].toFixed(2)} → ${scores[1].toFixed(2)} → ${scores[2].toFixed(2)}`);
  }

  await cleanupSession(sessionId);
}

// ============================================================================
// E2E-6: Doom Loop Detection
// ============================================================================

async function e2e6_doomLoopDetection() {
  header('E2E-6: Doom Loop Detection');

  const sessionId = generateSessionId();
  await createTestSession(sessionId, 'E2E-6 Doom Loop');

  const repeatedMsg = 'Run alignment';
  const responses: ChatResponse[] = [];

  for (let i = 1; i <= 4; i++) {
    try {
      const { data, elapsedMs } = await sendChat(repeatedMsg, sessionId);
      responses.push(data);
      record('MUST', typeof data.response === 'string' && data.response.length > 0,
        `Turn ${i}: valid response`, undefined, elapsedMs);
    } catch (err: any) {
      record('MUST', false, `Turn ${i}: request failed`, err.message);
    }
  }

  // Check for doom loop indicators in later turns
  if (responses.length >= 4) {
    const last = responses[3];
    const hasClarification = !!last.clarification;
    const hasReprobeHint = (last.response || '').toLowerCase().includes('specify') ||
                           (last.response || '').toLowerCase().includes('clarif') ||
                           (last.response || '').toLowerCase().includes('which') ||
                           (last.response || '').toLowerCase().includes('more detail');
    const hasSuggestions = (last.suggestions || []).length > 0;

    record('SHOULD', hasClarification || hasReprobeHint || hasSuggestions,
      'Turn 4: doom loop indication present',
      `clarification=${hasClarification}, reprobe=${hasReprobeHint}, suggestions=${hasSuggestions}`);
  }

  await cleanupSession(sessionId);
}

// ============================================================================
// E2E-7: Research & Benchmark Agents
// ============================================================================

async function e2e7_researchBenchmarkAgents() {
  header('E2E-7: Research & Benchmark Agents');

  // Research query
  try {
    const { data, status, elapsedMs } = await sendChat('What papers discuss CRISPR delivery methods for in vivo gene therapy?');
    record('MUST', status === 200, 'Research: HTTP 200', `got ${status}`, elapsedMs);
    record('MUST', typeof data.response === 'string' && data.response.length > 0,
      'Research: non-empty response');

    const hasResearch = !!(data as any).researchResponse;
    const researchUsed = data.metadata?.sources?.researchAgentUsed;
    record('SHOULD', hasResearch || researchUsed === true,
      'Research: researchResponse or researchAgentUsed present',
      `researchResponse=${hasResearch}, researchAgentUsed=${researchUsed}`);

    if (!hasResearch && researchUsed !== true) {
      console.log('    WARNING: Research agent may not be running or returning structured data');
    }
  } catch (err: any) {
    record('MUST', false, 'Research: request failed', err.message);
  }

  // Benchmark query
  try {
    const { data, status, elapsedMs } = await sendChat('Show me benchmarks for variant callers on whole genome sequencing data');
    record('MUST', status === 200, 'Benchmark: HTTP 200', `got ${status}`, elapsedMs);
    record('MUST', typeof data.response === 'string' && data.response.length > 0,
      'Benchmark: non-empty response');

    const hasBenchmark = !!(data as any).benchmarkEvidence;
    const benchmarkUsed = data.metadata?.sources?.benchmarkAgentUsed;
    record('SHOULD', hasBenchmark || benchmarkUsed === true,
      'Benchmark: benchmarkEvidence or benchmarkAgentUsed present',
      `benchmarkEvidence=${hasBenchmark}, benchmarkAgentUsed=${benchmarkUsed}`);

    if (!hasBenchmark && benchmarkUsed !== true) {
      console.log('    WARNING: Benchmark agent may not be running or returning structured data');
    }
  } catch (err: any) {
    record('MUST', false, 'Benchmark: request failed', err.message);
  }
}

// ============================================================================
// E2E-8: Multi-Intent Decomposition
// ============================================================================

async function e2e8_multiIntentDecomposition() {
  header('E2E-8: Multi-Intent Decomposition');

  const query = 'Run DE analysis on my RNA-seq data AND compare DESeq2 vs edgeR AND find papers on batch correction methods';

  try {
    const { data, status, elapsedMs } = await sendChat(query);
    record('MUST', status === 200, 'Multi-intent: HTTP 200', `got ${status}`, elapsedMs);
    record('MUST', typeof data.response === 'string' && data.response.length > 0,
      'Multi-intent: non-empty response');

    const isMulti = data.isMultiIntent === true;
    record('SHOULD', isMulti,
      `Multi-intent: isMultiIntent = ${data.isMultiIntent}`);

    const subs = data.subIntentResults;
    if (Array.isArray(subs) && subs.length > 0) {
      record('SHOULD', subs.length >= 2,
        `Multi-intent: ${subs.length} sub-results`);

      for (const sub of subs) {
        record('SHOULD', typeof sub.intentType === 'string' && sub.intentType.length > 0,
          `Sub-intent: type = "${sub.intentType}"`);
        record('SHOULD', typeof sub.subQuery === 'string' && sub.subQuery.length > 0,
          `Sub-intent: subQuery present`);
        record('SHOULD', sub.status === 'success' || sub.status === 'error',
          `Sub-intent: status = "${sub.status}"`);
      }
    } else if (!isMulti) {
      console.log('    WARNING: LLM did not decompose compound request — fell back to single intent');
      record('NICE', false, 'Multi-intent: decomposition not triggered');
    }
  } catch (err: any) {
    record('MUST', false, 'Multi-intent: request failed', err.message);
  }
}

// ============================================================================
// E2E-9: Error Handling & Edge Cases
// ============================================================================

async function e2e9_errorHandling() {
  header('E2E-9: Error Handling & Edge Cases');

  // Empty message
  try {
    const { status, body } = await sendChatRaw({ message: '' });
    record('MUST', status === 400, `Empty message: HTTP ${status} (expect 400)`, `body: ${body.slice(0, 120)}`);
  } catch (err: any) {
    record('MUST', false, 'Empty message: request failed', err.message);
  }

  // Very long message
  try {
    const longMsg = 'A'.repeat(5000);
    const { status, elapsedMs } = await sendChatRaw({ message: longMsg });
    record('MUST', status !== 500, `Long message: HTTP ${status} (not 500)`, undefined, elapsedMs);
  } catch (err: any) {
    record('MUST', false, 'Long message: request failed', err.message);
  }

  // Special characters / XSS attempt
  try {
    const xss = "<script>alert('xss')</script>";
    const { status, elapsedMs } = await sendChatRaw({ message: xss });
    record('MUST', status !== 500, `Special chars: HTTP ${status} (not 500)`, undefined, elapsedMs);
  } catch (err: any) {
    record('MUST', false, 'Special chars: request failed', err.message);
  }

  // No context (no sessionId)
  try {
    const { data, status, elapsedMs } = await sendChat('Hello, this is a test');
    record('MUST', status === 200, `No context: HTTP ${status}`, undefined, elapsedMs);
    record('MUST', typeof data.response === 'string' && data.response.length > 0,
      'No context: has response');
  } catch (err: any) {
    record('MUST', false, 'No context: request failed', err.message);
  }
}

// ============================================================================
// E2E-10: Response Timing & Quality
// ============================================================================

async function e2e10_responseTimingQuality() {
  header('E2E-10: Response Timing & Quality');

  // Use a varied set of queries to test timing
  const queries = [
    'What is RNA-seq?',
    'Run FASTQC on my reads',
    'How does CRISPR-Cas9 work?',
  ];

  const timings: number[] = [];

  for (const query of queries) {
    try {
      const { data, status, elapsedMs } = await sendChat(query);
      timings.push(elapsedMs);

      record('MUST', status === 200, `"${query.slice(0, 40)}": HTTP 200`, undefined, elapsedMs);
      record('MUST', typeof data.response === 'string' && data.response.length > 0,
        `"${query.slice(0, 40)}": non-empty response`);
      record('SHOULD', elapsedMs < 60_000,
        `"${query.slice(0, 40)}": under 60s`, `${(elapsedMs / 1000).toFixed(1)}s`);
      record('SHOULD', Array.isArray(data.suggestions) && data.suggestions.length > 0,
        `"${query.slice(0, 40)}": ${data.suggestions?.length || 0} suggestions`);
      record('NICE', Array.isArray(data._debug_timings) && data._debug_timings.length > 0,
        `"${query.slice(0, 40)}": debug timings present (${data._debug_timings?.length || 0} entries)`);
    } catch (err: any) {
      record('MUST', false, `"${query.slice(0, 40)}": failed`, err.message);
    }
  }

  if (timings.length > 0) {
    const avg = timings.reduce((a, b) => a + b, 0) / timings.length;
    const max = Math.max(...timings);
    const min = Math.min(...timings);
    console.log(`\n  Timing: avg=${(avg / 1000).toFixed(1)}s, min=${(min / 1000).toFixed(1)}s, max=${(max / 1000).toFixed(1)}s`);
  }
}

// ============================================================================
// Runner
// ============================================================================

async function runAll() {
  console.log('\n\u2554' + '\u2550'.repeat(70) + '\u2557');
  console.log('\u2551     E2E Flexible Intent Architecture Test Suite                      \u2551');
  console.log('\u255A' + '\u2550'.repeat(70) + '\u255D');

  // Quick health check
  try {
    const res = await fetch(`${BASE_URL}/`);
    if (!res.ok) throw new Error(`Frontend HTTP ${res.status}`);
    const res2 = await fetch('http://localhost:8081/api/version');
    if (!res2.ok) throw new Error(`Backend HTTP ${res2.status}`);
    console.log('\n  System health: Frontend (5000) + Backend (8081) reachable');
  } catch (err: any) {
    console.log(`\n  FATAL: Health check failed — ${err.message}`);
    console.log('  Make sure both frontend (port 5000) and backend (port 8081) are running.');
    process.exit(1);
  }

  await e2e1_intentClassification();
  await e2e2_factExtractionMultiTurn();
  await e2e3_toolSearch();
  await e2e4_workflowGeneration();
  await e2e5_readinessEvolution();
  await e2e6_doomLoopDetection();
  await e2e7_researchBenchmarkAgents();
  await e2e8_multiIntentDecomposition();
  await e2e9_errorHandling();
  await e2e10_responseTimingQuality();

  // ========== Summary ==========
  console.log('\n' + '='.repeat(72));
  console.log('  SUMMARY');
  console.log('='.repeat(72));

  const bySeverity = (s: 'MUST' | 'SHOULD' | 'NICE') => results.filter(r => r.severity === s);
  for (const sev of ['MUST', 'SHOULD', 'NICE'] as const) {
    const group = bySeverity(sev);
    const passed = group.filter(r => r.passed).length;
    console.log(`  ${sev.padEnd(6)}: ${passed}/${group.length} passed`);
  }

  const mustFails = bySeverity('MUST').filter(r => !r.passed);
  const shouldFails = bySeverity('SHOULD').filter(r => !r.passed);

  if (mustFails.length > 0) {
    console.log(`\n  CRITICAL FAILURES (MUST):`);
    for (const f of mustFails) {
      console.log(`    \u2717 ${f.label}${f.detail ? ` — ${f.detail}` : ''}`);
    }
  }

  if (shouldFails.length > 0) {
    console.log(`\n  GAPS (SHOULD):`);
    for (const f of shouldFails) {
      console.log(`    \u2717 ${f.label}${f.detail ? ` — ${f.detail}` : ''}`);
    }
  }

  const total = results.length;
  const totalPassed = results.filter(r => r.passed).length;
  console.log(`\n  Total: ${totalPassed}/${total} passed`);
  console.log('='.repeat(72));

  // Exit code based on MUST failures
  if (mustFails.length > 0) {
    process.exit(1);
  }
}

runAll().catch(err => {
  console.error('Fatal error:', err);
  process.exit(2);
});
