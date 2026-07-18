/**
 * LLM Model Comparison Harness
 *
 * Measures accuracy, latency, and estimated cost for the three BioMate LLM
 * call sites under two model configurations: "current" and "proposed".
 *
 * Usage:
 *   npx tsx frontend/scripts/llm-model-harness.ts --config=current
 *   npx tsx frontend/scripts/llm-model-harness.ts --config=proposed
 */

import Anthropic from '@anthropic-ai/sdk';
import { GoogleGenerativeAI } from '@google/generative-ai';
import * as dotenv from 'dotenv';
import * as path from 'path';
import * as fs from 'fs';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.join(__dirname, '../.env') });
dotenv.config({ path: path.join(__dirname, '../.env.local') });

// ── Model configs ─────────────────────────────────────────────────────────────

const CONFIGS = {
  current: {
    extract: 'gemini-3.5-flash',
    intent: 'gemini-3.5-flash',
    response: 'gemini-3.5-flash',
  },
  proposed: {
    extract: 'gemini-2.5-flash-lite',
    intent: 'claude-haiku-4-5-20251001',
    response: 'gemini-2.5-flash',
  },
};

// ── Pricing ($/1M tokens, July 2026) ─────────────────────────────────────────

const PRICING: Record<string, { input: number; output: number }> = {
  'gemini-3.5-flash':      { input: 1.50, output: 9.00 },
  'gemini-2.5-flash':      { input: 0.30, output: 2.50 },
  'gemini-2.5-flash-lite': { input: 0.10, output: 0.40 },
  'claude-haiku-4-5-20251001': { input: 1.00, output: 5.00 },
  'claude-haiku-4-5':      { input: 1.00, output: 5.00 },
};

function estimateCost(model: string, inputTokens: number, outputTokens: number): number {
  const p = PRICING[model] ?? { input: 0, output: 0 };
  return (inputTokens / 1e6) * p.input + (outputTokens / 1e6) * p.output;
}

// ── API helpers ───────────────────────────────────────────────────────────────

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
const gemini = new GoogleGenerativeAI(process.env.GEMINI_API_KEY ?? process.env.GOOGLE_API_KEY ?? '');

async function callGemini(model: string, system: string, user: string, jsonMode = false): Promise<{
  text: string; latencyMs: number; inputTokens: number; outputTokens: number;
}> {
  const start = Date.now();
  const genModel = gemini.getGenerativeModel({
    model,
    ...(system ? { systemInstruction: system } : {}),
    generationConfig: {
      maxOutputTokens: 2048,
      temperature: 0,
      // @ts-expect-error thinkingConfig not in types
      thinkingConfig: { thinkingBudget: 0 },
      ...(jsonMode ? { responseMimeType: 'application/json' } : {}),
    },
  });
  const result = await genModel.generateContent(user);
  const latencyMs = Date.now() - start;
  const usage = result.response.usageMetadata;
  return {
    text: result.response.text(),
    latencyMs,
    inputTokens: usage?.promptTokenCount ?? 0,
    outputTokens: usage?.candidatesTokenCount ?? 0,
  };
}

async function callClaude(model: string, system: string, user: string, jsonMode = false): Promise<{
  text: string; latencyMs: number; inputTokens: number; outputTokens: number;
}> {
  const start = Date.now();
  const jsonSuffix = jsonMode ? '\n\nReturn ONLY valid JSON — no markdown, no code fences, no explanation.' : '';
  const msg = await anthropic.messages.create({
    model,
    max_tokens: 1024,
    temperature: 0,
    system: system + jsonSuffix,
    messages: [{ role: 'user', content: user }],
  });
  const latencyMs = Date.now() - start;
  const raw = msg.content[0].type === 'text' ? msg.content[0].text : '';
  // Strip markdown code fences Claude sometimes wraps around JSON
  const text = raw.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '').trim();
  return { text, latencyMs, inputTokens: msg.usage.input_tokens, outputTokens: msg.usage.output_tokens };
}

async function callModel(model: string, system: string, user: string, jsonMode = false) {
  if (model.startsWith('claude-')) return callClaude(model, system, user, jsonMode);
  return callGemini(model, system, user, jsonMode);
}

// ── Test suites ───────────────────────────────────────────────────────────────

// --- Suite 1: extractInlineDataWithLLM ---

const EXTRACT_SYSTEM = `You are a parameter extractor. Given a user message, identify inline scientific data values.

Parameter type names to detect:
- vcf_variants: a VCF-format variant table with #CHROM/POS/ID/REF/ALT columns, chromosome positions, and rs-IDs
- gwas_summary_stats: GWAS summary statistics table with SNP/CHR/POS/BETA/SE/P columns
- genomic_intervals: a BED-format table of genomic regions with chr, start, end columns
- count_matrix: a comma/tab-separated gene expression count matrix
- smiles: SMILES molecular structure strings
- fasta_sequence: nucleotide or protein sequence in FASTA format
- coordinates: genomic coordinates in chr:start-end format

Return JSON: {"paramName": "value"} or {} if nothing detected.`;

const EXTRACT_CASES: Array<{ name: string; input: string; expected: string }> = [
  {
    name: 'VCF variants',
    input: 'Annotate these germline variants:\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\n1\t752566\trs3094315\tG\tA\t60\n1\t776546\trs12124819\tA\tG\t55',
    expected: 'vcf_variants',
  },
  {
    name: 'GWAS summary stats',
    input: 'Run clumping on this GWAS:\nrsid\tchr\tbp\tbeta\tse\tp\nrs3094315\t1\t752566\t0.0123\t0.0041\t2.8e-3\nrs2905035\t1\t759036\t-0.0087\t0.0039\t2.6e-2',
    expected: 'gwas_summary_stats',
  },
  {
    name: 'BED intervals',
    input: 'Find motifs in these peaks:\nchr1\t1000\t2000\tpeak1\nchr2\t5000\t6000\tpeak2\nchrX\t10000\t11000\tpeak3',
    expected: 'genomic_intervals',
  },
  {
    name: 'Count matrix',
    input: 'Run DESeq2 on this:\ngene\tctrl1\tctrl2\ttreat1\ttreat2\nBRCA1\t100\t120\t450\t480\nTP53\t50\t60\t200\t210',
    expected: 'count_matrix',
  },
  {
    name: 'SMILES',
    input: 'Run ADMET on these:\nCC(=O)Oc1ccccc1C(=O)O\nCN1CCC[C@H]1c2cccnc2',
    expected: 'smiles',
  },
  {
    name: 'FASTA sequence',
    input: 'Align this sequence:\n>gene1\nATGCATGCATGCATGCATGC\nATGCATGCATGCATGCATGC',
    expected: 'fasta_sequence',
  },
  {
    name: 'Genomic coordinates',
    input: 'Show coverage at chr17:43044295-43125483',
    expected: 'coordinates',
  },
  {
    name: 'Plain text (no data)',
    input: 'What is the difference between DESeq2 and edgeR?',
    expected: 'none',
  },
];

async function runExtractSuite(model: string): Promise<SuiteResult> {
  const results: CaseResult[] = [];
  for (const tc of EXTRACT_CASES) {
    const { text, latencyMs, inputTokens, outputTokens } = await callModel(model, EXTRACT_SYSTEM, tc.input, true);
    let parsed: Record<string, string> = {};
    try { parsed = JSON.parse(text); } catch { /* fallback */ }
    const detectedKey = Object.keys(parsed)[0] ?? 'none';
    const correct = tc.expected === 'none' ? Object.keys(parsed).length === 0 : detectedKey === tc.expected;
    results.push({ name: tc.name, correct, latencyMs, inputTokens, outputTokens,
      cost: estimateCost(model, inputTokens, outputTokens),
      detail: correct ? '' : `expected ${tc.expected}, got ${detectedKey}` });
  }
  return { suite: 'extractInlineDataWithLLM', model, results };
}

// --- Suite 2: intentModel (parseActions) ---

const INTENT_SYSTEM = `Classify the user's message intent. Return JSON with:
{
  "type": "workflow_generation" | "research_question" | "troubleshooting" | "data_interpretation" | "general_question",
  "needsWorkflowGeneration": boolean,
  "confidence": number (0-1)
}

Rules:
- "workflow_generation" + needsWorkflowGeneration=true: user wants to run a computational pipeline
- "research_question": user wants scientific knowledge, not to run a pipeline
- "troubleshooting": debugging an existing run
- "data_interpretation": user has results and wants to understand them
- needsWorkflowGeneration must be true when type=workflow_generation`;

const INTENT_CASES: Array<{ name: string; input: string; expectedType: string; expectedNWG: boolean }> = [
  {
    name: 'VCF annotation request (workflow)',
    input: 'Annotate and filter these germline variants for a population genetics study:\n#CHROM\tPOS\tREF\tALT\n1\t752566\tG\tA',
    expectedType: 'workflow_generation',
    expectedNWG: true,
  },
  {
    name: 'RNA-seq DESeq2 request (workflow)',
    input: 'Run differential expression on my RNA-seq count matrix comparing treated vs control.',
    expectedType: 'workflow_generation',
    expectedNWG: true,
  },
  {
    name: 'SMILES ADMET (workflow)',
    input: 'Run ADMET profiling on CC(=O)Oc1ccccc1C(=O)O and flag hERG liabilities.',
    expectedType: 'workflow_generation',
    expectedNWG: true,
  },
  {
    name: 'Research question (not workflow)',
    input: 'What is the difference between DESeq2 and edgeR for differential expression?',
    expectedType: 'research_question',
    expectedNWG: false,
  },
  {
    name: 'Data interpretation (not workflow)',
    input: 'My DESeq2 results show 500 genes with padj < 0.05. Is that a lot?',
    expectedType: 'data_interpretation',
    expectedNWG: false,
  },
  {
    name: 'Troubleshooting (not workflow)',
    input: 'My nf-core/rnaseq run failed with: ERROR ~ Process terminated with an error exit status (137).',
    expectedType: 'troubleshooting',
    expectedNWG: false,
  },
];

async function runIntentSuite(model: string): Promise<SuiteResult> {
  const results: CaseResult[] = [];
  for (const tc of INTENT_CASES) {
    const { text, latencyMs, inputTokens, outputTokens } = await callModel(model, INTENT_SYSTEM, tc.input, true);
    let parsed: { type?: string; needsWorkflowGeneration?: boolean } = {};
    try { parsed = JSON.parse(text); } catch { /* fallback */ }
    const typeOk = parsed.type === tc.expectedType;
    const nwgOk = parsed.needsWorkflowGeneration === tc.expectedNWG;
    const correct = typeOk && nwgOk;
    results.push({ name: tc.name, correct, latencyMs, inputTokens, outputTokens,
      cost: estimateCost(model, inputTokens, outputTokens),
      detail: correct ? '' : `type: ${parsed.type}(exp:${tc.expectedType}) nwg: ${parsed.needsWorkflowGeneration}(exp:${tc.expectedNWG})` });
  }
  return { suite: 'intentModel (parseActions)', model, results };
}

// --- Suite 3: responseModel format adherence ---

const RESPONSE_SYSTEM = `You are BioMate, an expert bioinformatics AI assistant.

RESPONSE FORMAT:
When a workflow was generated successfully:
  **[Workflow name]** — [one-sentence description]
  - **Input:** [list the actual inputs used]
  - **Key steps:** [2-3 bullets, tool → output]
  - **Expected output:** [what files the user will get]

When no workflow was generated AND inline data IS present:
  **Could not generate workflow** — [specific reason]
  **Closest available option:** [name + brief description]`;

const RESPONSE_CASES: Array<{ name: string; input: string; checkFn: (t: string) => boolean; checkDesc: string }> = [
  {
    name: 'Workflow success format',
    input: 'I generated the nf-core/rnaseq workflow for paired-end reads. Confirm format.',
    checkFn: (t) => /\*\*.*\*\*\s*—/.test(t) && /\*\*Input:\*\*/.test(t),
    checkDesc: 'has **Name** — pattern and **Input:** section',
  },
  {
    name: 'Workflow failure format',
    input: 'Workflow generation failed. Inline data present: vcf_variants. Error: connect ECONNREFUSED 127.0.0.1:8081. Closest available: wgs_germline_gatk.',
    checkFn: (t) => /\*\*Could not generate workflow\*\*/.test(t),
    checkDesc: 'has **Could not generate workflow** header',
  },
  {
    name: 'Research question — no format enforcement',
    input: 'What is the difference between BWA-MEM and BWA-MEM2?',
    checkFn: (t) => t.length > 100,
    checkDesc: 'returns a substantive answer (>100 chars)',
  },
];

async function runResponseSuite(model: string): Promise<SuiteResult> {
  const results: CaseResult[] = [];
  for (const tc of RESPONSE_CASES) {
    const { text, latencyMs, inputTokens, outputTokens } = await callModel(model, RESPONSE_SYSTEM, tc.input);
    const correct = tc.checkFn(text);
    results.push({ name: tc.name, correct, latencyMs, inputTokens, outputTokens,
      cost: estimateCost(model, inputTokens, outputTokens),
      detail: correct ? '' : `format check failed: ${tc.checkDesc}\n    got: ${text.slice(0, 150)}` });
  }
  return { suite: 'responseModel', model, results };
}

// ── Types + runner ────────────────────────────────────────────────────────────

interface CaseResult {
  name: string; correct: boolean; latencyMs: number;
  inputTokens: number; outputTokens: number; cost: number; detail: string;
}
interface SuiteResult { suite: string; model: string; results: CaseResult[]; }

function printSuite(sr: SuiteResult) {
  const pass = sr.results.filter(r => r.correct).length;
  const total = sr.results.length;
  const avgLatency = Math.round(sr.results.reduce((s, r) => s + r.latencyMs, 0) / total);
  const totalCost = sr.results.reduce((s, r) => s + r.cost, 0);
  console.log(`\n── ${sr.suite} [${sr.model}] ──────────────`);
  console.log(`Accuracy: ${pass}/${total}  Avg latency: ${avgLatency}ms  Total cost: $${totalCost.toFixed(5)}`);
  for (const r of sr.results) {
    const mark = r.correct ? '✓' : '✗';
    const detail = r.detail ? `  (${r.detail})` : '';
    console.log(`  ${mark} ${r.name} [${r.latencyMs}ms, $${r.cost.toFixed(5)}]${detail}`);
  }
}

async function main() {
  const configName = (process.argv.find(a => a.startsWith('--config='))?.split('=')[1] ?? 'current') as 'current' | 'proposed';
  const cfg = CONFIGS[configName];
  if (!cfg) { console.error('Unknown config:', configName); process.exit(1); }

  console.log(`\n=== LLM Model Harness — config: ${configName} ===`);
  console.log(`  extract:  ${cfg.extract}`);
  console.log(`  intent:   ${cfg.intent}`);
  console.log(`  response: ${cfg.response}`);
  console.log(`  started:  ${new Date().toISOString()}`);

  const [extractResult, intentResult, responseResult] = await Promise.all([
    runExtractSuite(cfg.extract),
    runIntentSuite(cfg.intent),
    runResponseSuite(cfg.response),
  ]);

  printSuite(extractResult);
  printSuite(intentResult);
  printSuite(responseResult);

  // Summary row
  const allResults = [...extractResult.results, ...intentResult.results, ...responseResult.results];
  const totalPass = allResults.filter(r => r.correct).length;
  const totalTests = allResults.length;
  const totalCost = allResults.reduce((s, r) => s + r.cost, 0);
  const avgLat = Math.round(allResults.reduce((s, r) => s + r.latencyMs, 0) / totalTests);
  console.log(`\n=== Summary: ${totalPass}/${totalTests} passed  avg ${avgLat}ms  total $${totalCost.toFixed(5)} ===`);

  // Write JSON results for comparison
  const outPath = path.join(__dirname, `../scripts/harness-results-${configName}.json`);
  fs.writeFileSync(outPath, JSON.stringify({
    config: configName, models: cfg, timestamp: new Date().toISOString(),
    suites: [extractResult, intentResult, responseResult],
    summary: { passed: totalPass, total: totalTests, avgLatencyMs: avgLat, totalCostUsd: totalCost },
  }, null, 2));
  console.log(`\nResults written to ${outPath}`);
}

main().catch(e => { console.error(e); process.exit(1); });
