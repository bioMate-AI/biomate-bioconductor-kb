/**
 * Routing replay harness — runs the REAL intent classifier (the production analyzeIntent prompt,
 * via OpenRouter google/gemini-3.8-flash = the deployed intent model) over a held-out case set,
 * then applies the post-classifier routing policy exactly as _generateResponse does, and reports
 * the final workflow / direct_compute / no_exec decision per case.
 *
 * Usage (from frontend/):
 *   BIOMATE_DECOMP_OPENROUTER_KEY=$(cat ~/.config/biomate/openrouter.key) \
 *   npx tsx ../scripts/routing_replay/run.ts --label after --reps 1 [--only F1,F2]
 * Output: ../scripts/routing_replay/out/<label>.jsonl + a per-group summary on stdout.
 * See docs/20261110_ROUTING_CLASSIFIER_AUTHORITY.md.
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { GalaxyAssistant } from '../../frontend/server/galaxy-assistant';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const arg = (k: string, d?: string) => { const i = args.indexOf(`--${k}`); return i >= 0 ? args[i + 1] : d; };
const label = arg('label', 'run')!;
const reps = parseInt(arg('reps', '1')!, 10);
const only = arg('only')?.split(',');
const model = arg('model', 'google/gemini-3.8-flash')!;
const conc = parseInt(arg('concurrency', '6')!, 10);

type Case = { id: string; group: string; text: string; history?: string[]; attach?: string; paper?: boolean; expect: string[] };
const cases: Case[] = JSON.parse(readFileSync(path.join(HERE, 'cases.json'), 'utf8')).cases
  .filter((c: Case) => !only || only.includes(c.id));

const attachBlock = (name: string) =>
  `\n\n[Attached files: ${name}]\n[Uploaded datasets: ${name}: dataset_id=6f1c2a9e-3b7d-4c55-9a0e-1d2e3f4a5b6c, galaxy_dataset_id=f2db41e8fa331b3e, s3_uri=s3://biomate-uploads/u1/${name}]`;

if (!process.env.BIOMATE_DECOMP_OPENROUTER_KEY) throw new Error('BIOMATE_DECOMP_OPENROUTER_KEY unset');
process.env.ML_TRAINING_ROUTING = process.env.ML_TRAINING_ROUTING ?? '1';
const ga: any = new GalaxyAssistant({ galaxyAPIProxy: {} as any, modelConfig: { intentModel: `openrouter:${model}` } as any } as any);

function outcome(intents: any[]): string {
  if (intents.some(i => i.actions?.needsWorkflowGeneration || i.actions?.needsWorkflowModification)) return 'workflow';
  if (intents.some(i => i.execution === 'direct_compute' || i.type === 'workflow_generation')) return 'direct_compute';
  return 'no_exec';
}

async function runCase(c: Case, rep: number) {
  const message = c.text + (c.attach ? attachBlock(c.attach) : '');
  const context: any = { previousMessages: (c.history || []).map(content => ({ role: 'user', content })) };
  const t0 = Date.now();
  const decomposition = await ga.analyzeIntent(message, context, '');
  const raw = decomposition.intents.map((i: any) => ({ type: i.type, execution: i.execution ?? null, nwg: !!i.actions?.needsWorkflowGeneration }));
  const rawOutcome = outcome(decomposition.intents);
  // Same order as _generateResponse.
  ga._maybeCollapseNamedWorkflowCardRequest?.(decomposition, message);
  ga._applyNamedWorkflowOverridesToDecomposition?.(decomposition, message);
  let boin = false;
  if (decomposition.isMultiIntent) {
    for (const i of decomposition.intents) ga._applySubIntentRouting(i, message);
  } else {
    const r = ga._applyPostClassifierRouting(decomposition.primaryIntent, decomposition, message,
      { paperContentResult: c.paper ? { ref: 'paper', content: 'Methods: RNA-seq reads were aligned with STAR; pipeline ...' } : undefined, originalUserQuery: message });
    boin = !!r?.boinDoseLevelsMissing;
  }
  const final = boin ? 'workflow' /* classifier said workflow; prereq clarification asked */ : outcome(decomposition.intents);
  return {
    id: c.id, group: c.group, rep, expect: c.expect, raw, rawOutcome, final, boinClarify: boin,
    ok: c.expect.includes(final), degraded: !!decomposition.degraded, ms: Date.now() - t0,
    rationale: decomposition.rationale?.slice(0, 200),
    // what the backend catalog search receives (for relevance-floor calibration)
    search: decomposition.intents.filter((i: any) => i.actions?.needsWorkflowGeneration).map((i: any) => ({
      subQuery: i.subQuery, taskSpec: i.taskSpec, inputKinds: i.inputKinds ?? decomposition.inputKinds ?? null,
    })),
    keyTerms: decomposition.keyTerms, preferredDomains: decomposition.preferredDomains, penalizedDomains: decomposition.penalizedDomains,
  };
}

async function main() {
  const jobs: Array<() => Promise<any>> = [];
  for (let r = 0; r < reps; r++) for (const c of cases) jobs.push(() => runCase(c, r).catch(e => ({ id: c.id, group: c.group, rep: r, error: String(e?.message || e), ok: false, expect: c.expect })));
  const results: any[] = [];
  let next = 0;
  await Promise.all(Array.from({ length: conc }, async () => {
    while (next < jobs.length) { const j = jobs[next++]; const res = await j(); results.push(res); process.stderr.write(`${res.ok ? '.' : 'x'}`); }
  }));
  process.stderr.write('\n');
  results.sort((a, b) => a.id.localeCompare(b.id) || a.rep - b.rep);
  mkdirSync(path.join(HERE, 'out'), { recursive: true });
  writeFileSync(path.join(HERE, 'out', `${label}.jsonl`), results.map(r => JSON.stringify(r)).join('\n') + '\n');
  const groups = [...new Set(results.map(r => r.group))];
  let tot = 0, ok = 0;
  console.log(`label=${label} model=${model} reps=${reps}`);
  for (const g of groups) {
    const rs = results.filter(r => r.group === g);
    const k = rs.filter(r => r.ok).length; tot += rs.length; ok += k;
    const bad = rs.filter(r => !r.ok).map(r => `${r.id}:${r.final ?? 'ERR'}${r.error ? '(' + r.error.slice(0, 60) + ')' : ''}`);
    console.log(`${g.padEnd(24)} ${k}/${rs.length}${bad.length ? '  miss: ' + bad.join(' ') : ''}`);
  }
  console.log(`TOTAL ${ok}/${tot}`);
  const labels = ['workflow', 'direct_compute', 'no_exec'];
  console.log('confusion (row=expected primary label, col=final):');
  console.log('expected\\final'.padEnd(18) + labels.map(l => l.padEnd(16)).join(''));
  for (const e of labels) {
    const rs = results.filter(r => r.expect?.[0] === e);
    console.log(e.padEnd(18) + labels.map(l => String(rs.filter(r => r.final === l).length).padEnd(16)).join(''));
  }
}
main().then(() => process.exit(0), e => { console.error(e); process.exit(1); });
