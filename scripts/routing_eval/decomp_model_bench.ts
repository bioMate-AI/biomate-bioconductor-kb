// Decomposition model benchmark: BioMate's real analyzeIntent (the production classifier prompt)
// with the intent model pointed at each candidate via OpenRouter (the same Anthropic<->OpenAI
// function-calling shim the product uses), over the workflow-level rows of the held-out
// decomposition_real set (sources real_workflow_chain + real_nfcore_subworkflow; the GTN tutorial
// rows are tool-level steps with some inverted gold edges — excluded, see the doc).
//
// Output JSONL rows: {model, id, secs, error, nodes:[{text, order, depends_on}], usage}.
// Score with scripts/routing_eval/decomp_judge.py.
//
// Usage: npx tsx scripts/routing_eval/decomp_model_bench.ts <out.jsonl> [model,model,...]
// Needs ~/.config/biomate/openrouter.key. Run from frontend/ (module resolution).
import fs from 'fs';
import path from 'path';
import { GalaxyAssistant } from '../../frontend/server/galaxy-assistant';
import { openaiCompatMessagesClient } from '../../frontend/server/local-llm';

const KEY = fs.readFileSync(`${process.env.HOME}/.config/biomate/openrouter.key`, 'utf8').trim();
const DEFAULT_MODELS = [
  'google/gemini-3.8-flash', 'google/gemini-3.1-pro-preview', 'anthropic/claude-haiku-4.5',
  'anthropic/claude-sonnet-5.5', 'anthropic/claude-opus-5.5', 'openai/gpt-5.6-luna', 'openai/gpt-5.6-terra',
  'z-ai/glm-5.2', 'z-ai/glm-5.3-prime', 'deepseek/deepseek-v4-pro', 'qwen/qwen3.8-27b', 'moonshotai/kimi-k3',
];
const GOLD = path.resolve(__dirname, '../../evaluation/datasets/decomposition_real/decomposition_real.jsonl');
const rows = fs.readFileSync(GOLD, 'utf8').split('\n').filter(Boolean).map(l => JSON.parse(l))
  .filter(r => r.source === 'real_workflow_chain' || r.source === 'real_nfcore_subworkflow');

async function decompose(model: string, query: string) {
  const a = Object.create(GalaxyAssistant.prototype) as any;
  a.modelConfig = { intentModel: model, responseModel: model, toolRankingModel: model };
  a.gemini = null;
  a._chainHintNamesCache = { names: [], fetchedAt: Date.now() };
  let usage: any = null;
  const shim = openaiCompatMessagesClient({ url: 'https://openrouter.ai/api/v1', model, key: KEY }) as any;
  const create = shim.messages.create.bind(shim.messages);
  let lastErr = '';
  // Providers throttle several large (≈21k-token) requests per key; analyzeIntent swallows the error
  // and falls back, so retry here with back-off and record the last error.
  shim.messages.create = async (req: any) => {
    for (let attempt = 0; attempt < 5; attempt++) {
      try { const r = await create(req); usage = r?.usage ?? null; return r; }
      catch (e: any) { lastErr = String(e?.message || e).slice(0, 200); await new Promise(res => setTimeout(res, 2000 * 2 ** attempt)); }
    }
    throw new Error(lastErr || 'model call failed');
  };
  a._getClaude = () => shim;
  const t0 = Date.now();
  const dec = await a.analyzeIntent(query, { previousMessages: [] }, '');
  const intents = (dec?.intents || []) as any[];
  const wf = intents.filter(i => i.type === 'workflow_generation' || i.actions?.needsWorkflowGeneration);
  const order = new Map(wf.map((i, k) => [i.id, k + 1]));
  const nodes = wf.map((i, k) => ({
    text: [i.subQuery, i.taskSpec].filter(Boolean).join(' | '),
    order: k + 1,
    depends_on: (i.dependsOn || []).map((d: string) => order.get(d)).filter((n: any) => typeof n === 'number' && n !== k + 1),
  }));
  return { secs: (Date.now() - t0) / 1000, nodes, usage, sequential: !!dec?.isSequential, last_error: lastErr };
}

async function pool<T>(items: T[], n: number, fn: (x: T) => Promise<void>) {
  const q = [...items];
  await Promise.all(Array.from({ length: n }, async () => { while (q.length) await fn(q.shift() as T); }));
}

(async () => {
  const out = process.argv[2];
  const models = process.argv[3] ? process.argv[3].split(',') : DEFAULT_MODELS;
  const done = new Set<string>();
  if (fs.existsSync(out)) for (const l of fs.readFileSync(out, 'utf8').split('\n').filter(Boolean)) {
    const j = JSON.parse(l); if (!j.error && j.usage) done.add(`${j.model}|${j.id}`);
  }
  // Round-robin across models so no single provider gets several concurrent large requests.
  const jobs = rows.flatMap(r => models.map(m => ({ m, r }))).filter(j => !done.has(`${j.m}|${j.r.id}`));
  console.log(`${rows.length} rows × ${models.length} models; ${jobs.length} to run`);
  await pool(jobs, Number(process.env.DECOMP_CONCURRENCY || 4), async ({ m, r }) => {
    let rec: any;
    try {
      const d = await decompose(m, r.query);
      // analyzeIntent catches a failed model call and falls back to a non-LLM heuristic; without real
      // usage the result is not this model's answer (240 such calls on the first run, 0.2 s each).
      rec = { model: m, id: r.id, ...d, error: d.usage ? '' : `no model response (analyzeIntent fallback)${d.last_error ? ': ' + d.last_error : ''}` };
    }
    catch (e: any) { rec = { model: m, id: r.id, secs: 0, nodes: [], usage: null, error: String(e?.message || e).slice(0, 300) }; }
    fs.appendFileSync(out, JSON.stringify(rec) + '\n');
    console.log(`${m.padEnd(30)} ${r.id.padEnd(28)} ${rec.secs.toFixed(1)}s nodes=${rec.nodes.length} ${rec.error.slice(0, 80)}`);
  });
})();
