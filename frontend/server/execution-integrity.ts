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

export function unbackedFilesNote(files: string[], zh = false): string {
  if (files.length === 0) return '';
  const list = files.map(f => `\`${f}\``).join(', ');
  return zh
    ? `\n\n> ⚠️ ${list} 并未由本轮执行的代码生成，因此不存在可下载的文件。只有 run_code 实际输出到 $OUTPUT_DIR 的文件才会显示为附件。`
    : `\n\n> ⚠️ ${list} ${files.length === 1 ? 'was' : 'were'} not produced by any code executed in this turn, so no such downloadable file exists. Only files run_code actually wrote to $OUTPUT_DIR are attached.`;
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
const SYNTHETIC_DATA_RE = /\bnp\.random\b|\bdefault_rng\b|\brandom\.(?:normal|uniform|randint|choice|gauss|seed|random)\b|\b(?:rnorm|runif|rbinom|rpois|rexp|rgamma|rbeta)\s*\(|\bset\.seed\s*\(|\bsimulat\w*/i;
export function generatesSyntheticData(code: string, stagedInputCount: number): boolean {
  return stagedInputCount === 0 && SYNTHETIC_DATA_RE.test(code || '');
}

export function simulatedDataNote(zh = false): string {
  return zh
    ? '\n\n> ⚠️ **以上数值来自代码生成的模拟数据**：本轮没有提供任何输入数据，计算所用的数据是代码随机或按假设生成的，并非真实分析结果。若要分析真实数据，请上传文件，或运行对应工作流（使用其内置示例数据）。'
    : '\n\n> ⚠️ **These numbers come from data the code simulated.** No input data was available in this turn, so the values were generated by the code (random draws or assumed distributions) — they are not results of a real analysis. Upload your data, or run the matching workflow on its built-in sample data, for real results.';
}

/** Storage URIs never reach the user (founder directive 2026-11-10: no S3 anywhere in user-facing
 *  text). Prompt rules are not enforcement — the model still echoed a staged prefix from an
 *  example's notes (cryo-EM, dev 2026-11-11). A file URI becomes its file name; a folder prefix
 *  becomes "the staged dataset" / "已准备好的数据集". Code blocks are left alone (tool code, not prose). */
export function redactStoragePaths(text: string, zh = false): string {
  const parts = String(text || '').split(/(```[\s\S]*?```)/g);
  return parts.map((part, i) => i % 2 === 1 ? part : part.replace(/`?s3:\/\/[^\s`)\]>"']+`?/gi, (m) => {
    const uri = m.replace(/`/g, '');
    const last = uri.replace(/\/+$/, '').split('/').pop() || '';
    const isFolder = uri.endsWith('/') || !/\.[A-Za-z0-9]{1,8}(?:\.gz)?$/.test(last);
    return isFolder ? (zh ? '已准备好的数据集' : 'the staged dataset') : last;
  })).join('');
}
