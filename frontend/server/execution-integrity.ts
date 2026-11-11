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
