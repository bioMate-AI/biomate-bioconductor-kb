import { redactInternalBackend, redactUserFacingReply } from '../shared/tool-call-display';
/**
 * Structural fabrication guard (docs/20261110_ROUTING_CLASSIFIER_AUTHORITY.md §5).
 *
 * Primary mechanism = STRUCTURE, not prose regex:
 *  1. When the intent classifier decided execution=direct_compute and run_code was offered but did
 *     not run in this turn, the reply cannot contain real results — re-prompt ONCE to execute.
 *  2. Output files presented to the user as produced must be run_code $OUTPUT_DIR artifacts of
 *     this turn; any other "saved/generated X.csv" claim is flagged as not produced.
 * The prose regex (presentsUnexecutedCode / claimsProducedOutputFile) is only a secondary signal
 * for turns the classifier did not mark direct_compute.
 */

export const EXECUTE_NOW_NUDGE = 'You presented analysis code or results, or said you produced an output file, but run_code '
  + 'did not run in this turn, so no result or file exists. The user\'s data is already staged (see the run_code inputs). '
  + 'Call run_code now (write files to $OUTPUT_DIR), then report only the actual output. Do not state results '
  + 'or files that were not produced.';

export function shouldRequireExecution(s: {
  directCompute: boolean;      // classifier execution === 'direct_compute'
  runCodeOffered: boolean;
  ranRunCode: boolean;
  alreadyNudged: boolean;
  proseSignal: boolean;        // secondary: presentsUnexecutedCode(text) && data in conversation && !wantsCodeItself
}): boolean {
  if (!s.runCodeOffered || s.ranRunCode || s.alreadyNudged) return false;
  return s.directCompute || s.proseSignal;
}

const FILE_RE = /\b([\w.-]+\.(?:csv|tsv|xlsx?|json|jsonl|png|pdf|svg|parquet|txt|html|zip))\b/gi;
const PRODUCED_VERB_RE = /(?:已生成|已保存|已导出|已创建|生成了|保存为|导出为|下载|\b(?:saved|generated|created|wrote|written|exported|produced|download)\b)/i;

/** File names the reply presents as produced in this turn (a production verb within 80 chars before
 *  the name, or a markdown link to the file). */
export function claimedOutputFiles(text: string): string[] {
  const out = new Set<string>();
  const t = text || '';
  for (const m of t.matchAll(FILE_RE)) {
    const before = t.slice(Math.max(0, (m.index ?? 0) - 80), m.index ?? 0);
    const inLink = /\]\([^)]*$/.test(before) || /\[[^\]]*$/.test(before);
    if (PRODUCED_VERB_RE.test(before) || inLink) out.add(m[1]);
  }
  return [...out];
}

/** Claimed files that no run_code call produced in this turn. Input files the user attached are
 *  not claims of production, so they are excluded via `knownInputs`. */
export function unbackedOutputFileClaims(text: string, produced: string[], knownInputs: string[] = []): string[] {
  const have = new Set(produced.map(n => n.split('/').pop()!.toLowerCase()));
  const inputs = new Set(knownInputs.map(n => n.split('/').pop()!.toLowerCase()));
  return claimedOutputFiles(text).filter(n => !have.has(n.toLowerCase()) && !inputs.has(n.toLowerCase()));
}

/** Names of input files attached in the conversation ("[Attached files: a.csv, b.tsv]"). */
export function attachedInputNames(...texts: string[]): string[] {
  const names: string[] = [];
  for (const t of texts) for (const m of (t || '').matchAll(/\[(?:Attached files?|Uploaded datasets?):\s*([^\]]+)\]/gi)) {
    for (const part of m[1].split(/[;,]\s*/)) {
      const n = part.split(':')[0].trim();
      if (/\.\w{2,6}$/.test(n)) names.push(n);
    }
  }
  return names;
}

/** run_code that had NO staged inputs and generated its own values (random draws / an explicit
 *  simulation). Its "results" describe numbers the code made up, not the user's data or a
 *  workflow's real built-in data (dev 2026-11-11: "Run analyze_ebv_antibody_titers on its built-in
 *  data" → run_code simulated OD readings "from literature-based distributions" and reported
 *  group titers as results). Structural: zero staged inputs + a generation call. */
// Match genuine input-FABRICATION calls (draws that CREATE the analysed matrix),
// not reproducibility boilerplate or resampling of real data. `set.seed(...)`,
// `np.random.seed`, `np.random.permutation/shuffle/choice`, `random.seed`, and a
// bare `simulat…` substring (which also hit `simulated_annealing` and prose
// comments) were false positives that wrongly refused real-data run_code — see
// the 2026-11-11 correctness review. torch / scipy.rvs / sklearn make_* were
// evading — now covered. requestAsksForSimulation() still lets explicit
// simulations through regardless.
const SYNTHETIC_DATA_RE = /\bnp\.random\.(?:rand|randn|standard_normal|normal|uniform|poisson|binomial|exponential|gamma|beta|lognormal|multivariate_normal|standard_t|chisquare|standard_cauchy|dirichlet)\b|\bdefault_rng\b|\brandom\.(?:gauss|normalvariate|lognormvariate|uniform|expovariate|gammavariate|betavariate)\b|\b(?:rnorm|runif|rbinom|rpois|rexp|rgamma|rbeta|rlnorm|rt|rchisq)\s*\(|\btorch\.(?:randn|rand|randint|normal)\b|\.rvs\s*\(|\bmake_(?:classification|regression|blobs|moons|circles|gaussian_quantiles)\b/i;
export function generatesSyntheticData(code: string, stagedInputCount: number): boolean {
  return stagedInputCount === 0 && SYNTHETIC_DATA_RE.test(code || '');
}

/** May run_code generate its own input values this turn? The INTENT decides: the classifier reads
 *  the request in any language and reports `user_requested_synthetic_data` (the user asked to
 *  generate / simulate / use example, demo, toy or test data, or the task is a simulation). A
 *  keyword list cannot do that — it refused a zh request for 示例数据 (audit round 9, 2026-11-12).
 *  Only when no intent is available (classifier failure / degraded keyword decomposition →
 *  undefined) does the narrow keyword fallback below decide. */
export function syntheticDataAllowed(intentRequestedSynthetic: boolean | undefined, userMessage: string): boolean {
  if (typeof intentRequestedSynthetic === 'boolean') return intentRequestedSynthetic;
  return requestAsksForSimulation(userMessage);
}

/** FALLBACK ONLY (see syntheticDataAllowed): the user explicitly asked for a simulation (power
 *  analysis, Monte Carlo, bootstrap, simulated PK/curves, synthetic data …). */
const SIMULATION_REQUEST_RE = /simulat|synthetic|monte\s*carlo|bootstrap|permutation|power\s+(?:analysis|calculation)|sample\s+size|random(?:ly)?\s+(?:generat|sampl|draw)|toy\s+(?:data|example)|模拟|仿真|合成数据|蒙特卡[洛罗]|自助法|功效分析|样本量|随机生成/i;
export function requestAsksForSimulation(userMessage: string): boolean {
  return SIMULATION_REQUEST_RE.test(userMessage || '');
}

/** run_code is refused (not executed) when it would invent its own input data and the user did not
 *  ask for a simulation — made-up numbers must never become a reply (founder 2026-11-11: disclosing
 *  a simulation still lowers confidence; prevent it). The model gets this instead of a result. */
export const SYNTHETIC_DATA_REFUSAL = 'NOT EXECUTED: this code generates its own input values (random draws / '
  + 'assumed distributions) but no input data was provided, and the user did not ask for a simulation. Do not '
  + 'simulate or invent data. Use real data only: the dataset the user attached, or — when the request names a '
  + 'workflow or its built-in sample data — that workflow (it runs on its real built-in data). If neither is '
  + 'available, ask the user for the data. Do not report any numbers from this attempt.';

/** Storage URIs never reach the user (founder directive 2026-11-10: no S3 anywhere in user-facing
 *  text). Prompt rules are not enforcement — the model still echoed a staged prefix from an
 *  example's notes (cryo-EM, dev 2026-11-11). A file URI becomes its file name; a folder prefix
 *  becomes "the staged dataset" / "已准备好的数据集". Code blocks are left alone (tool code, not prose). */
export { redactInternalBackend, redactUserFacingReply };
export function redactStoragePaths(text: string, zh = false): string {
  const parts = String(text || '').split(/(```[\s\S]*?```)/g);
  return parts.map((part, i) => i % 2 === 1 ? part : part.replace(/`?s3:\/\/[^\s`)\]>"']+`?/gi, (m) => {
    const uri = m.replace(/`/g, '');
    const last = uri.replace(/\/+$/, '').split('/').pop() || '';
    const isFolder = uri.endsWith('/') || !/\.[A-Za-z0-9]{1,8}(?:\.gz)?$/.test(last);
    return isFolder ? (zh ? '已准备好的数据集' : 'the staged dataset') : last;
  })).join('');
}
