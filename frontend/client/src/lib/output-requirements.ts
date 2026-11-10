// Output requirements (project Instructions → "Output formats"). The store is a JSON array of
// OutputFormat (or legacy free text). This is the ONE place that parses the store and renders the
// prompt text, so the editor panel (project-guidance-cards) and the composer send path (chat-input)
// can never disagree — in particular so a format the user switched OFF is never sent to the model.

export type OutputFormatKind = 'report' | 'figure' | 'table' | 'naming';
export type OutputFormat = { kind: OutputFormatKind; name: string; detail: string; on: boolean };

const KINDS: OutputFormatKind[] = ['report', 'figure', 'table', 'naming'];

/** Parse the stored `outputRequirements` string into structured formats. Pre-structured free text
 *  becomes a single enabled 'report' entry so nothing a user previously wrote is lost. */
export function parseOutputFormats(raw: string | null | undefined): OutputFormat[] {
  if (!raw || !raw.trim()) return [];
  try {
    const j = JSON.parse(raw);
    if (Array.isArray(j)) {
      return j
        .filter((f: any) => f && f.name)
        .map((f: any) => ({
          kind: (KINDS.includes(f.kind) ? f.kind : 'report') as OutputFormatKind,
          name: String(f.name),
          detail: String(f.detail || ''),
          on: f.on !== false,
        }));
    }
  } catch { /* legacy free text handled below */ }
  return [{ kind: 'report', name: 'Output requirements', detail: String(raw), on: true }];
}

const KIND_LABEL: Record<OutputFormatKind, string> = {
  report: 'Report', figure: 'Figure', table: 'Table', naming: 'File naming',
};

/** Render ONLY the enabled formats as prose for the model prompt. Disabled (on:false) formats are
 *  the ones the user switched OFF and must never reach the model. Returns '' when none are enabled
 *  (honest-empty — adds nothing to the context). */
export function outputRequirementsToPrompt(raw: string | null | undefined): string {
  const active = parseOutputFormats(raw).filter(f => f.on);
  if (active.length === 0) return '';
  const lines = active.map(f => {
    const head = `- ${KIND_LABEL[f.kind]} — ${f.name}`;
    return f.detail.trim() ? `${head}: ${f.detail.trim()}` : head;
  });
  return `Output requirements (write deliverables to these):\n${lines.join('\n')}`;
}

// ── Structured parameterization ──────────────────────────────────────────────
// Some deliverable generators are NOT LLM calls (e.g. the QC HTML template) or
// run server-side where an appended prose block cannot steer them. For those we
// parse the SAME store into a small structured object so a generator can honor
// what it CAN deterministically (section palette, a length/dpi note) and a
// cheap rule-based validator can flag deviations after an LLM deliverable is
// produced. The structured object is derived ONLY from enabled formats, so a
// switched-off format never takes effect here either.

export interface OutputRequirements {
  /** Enabled formats only (same filter as outputRequirementsToPrompt). */
  formats: OutputFormat[];
  /** The most restrictive "≤N words" / "N words" hint parsed from any detail, if any. */
  lengthCapWords?: number;
  /** A detail asked for findings/results before methods. */
  findingsFirst?: boolean;
  /** Figure DPI hint parsed from a detail (e.g. "300 dpi"). */
  figureDpi?: number;
  /** A detail asked for a greyscale-safe / grayscale palette. */
  grayscaleSafe?: boolean;
}

const WORDS_CAP_RE =
  /(?:≤|<=?|under|below|no more than|at most|max(?:imum)?|up to)\s*(\d{2,5})\s*(?:word|字)/i;
const WORDS_PLAIN_RE = /(\d{2,5})\s*(?:word|字)/i;
const DPI_RE = /(\d{2,4})\s*dpi/i;
const FINDINGS_FIRST_RE = /findings[-\s]?first|findings\s+first|先列(?:研究)?发现/i;
const GRAYSCALE_RE = /gr[ae]yscale|灰度/i;

/** Parse the store into a structured object. Only enabled formats contribute hints.
 *  Pure + dependency-free, so both the server generators and tests use it. */
export function parseOutputRequirements(raw: string | null | undefined): OutputRequirements {
  const formats = parseOutputFormats(raw).filter(f => f.on);
  const out: OutputRequirements = { formats };
  for (const f of formats) {
    const detail = f.detail || '';
    const cap = detail.match(WORDS_CAP_RE) ?? detail.match(WORDS_PLAIN_RE);
    if (cap) {
      const n = parseInt(cap[1], 10);
      // Keep the MOST restrictive cap seen across enabled formats.
      if (Number.isFinite(n) && (out.lengthCapWords === undefined || n < out.lengthCapWords)) {
        out.lengthCapWords = n;
      }
    }
    const dpi = detail.match(DPI_RE);
    if (dpi) {
      const n = parseInt(dpi[1], 10);
      if (Number.isFinite(n) && (out.figureDpi === undefined || n > out.figureDpi)) out.figureDpi = n;
    }
    if (FINDINGS_FIRST_RE.test(detail)) out.findingsFirst = true;
    if (GRAYSCALE_RE.test(detail)) out.grayscaleSafe = true;
  }
  return out;
}

/** Lightweight, non-blocking conformance check. Returns a list of human-readable
 *  deviation strings for the requirements it CAN verify (length cap, findings-first
 *  ordering). It NEVER throws, never rewrites the deliverable, and never fabricates —
 *  callers log/annotate the deviations. `[]` means "nothing checkable deviated". */
export function checkOutputConformance(
  text: string | null | undefined,
  reqs: OutputRequirements | null | undefined,
): string[] {
  const deviations: string[] = [];
  if (!text || !reqs) return deviations;
  const body = String(text);

  if (reqs.lengthCapWords !== undefined) {
    const words = body.trim().split(/\s+/).filter(Boolean).length;
    // 10% tolerance — a prose cap is a target, not a hard token budget.
    if (words > Math.round(reqs.lengthCapWords * 1.1)) {
      deviations.push(`length cap: ${words} words > requested ≤${reqs.lengthCapWords}`);
    }
  }

  if (reqs.findingsFirst) {
    const methodIdx = body.search(/\bmethod/i);
    const resultIdx = body.search(/\b(finding|result|conclusion)/i);
    // Only a deviation when methods are clearly introduced BEFORE any finding/result.
    if (methodIdx >= 0 && (resultIdx < 0 || methodIdx < resultIdx)) {
      deviations.push('findings-first ordering: methods appear before findings/results');
    }
  }

  return deviations;
}

/** Concrete, design-accurate examples (data_centroid_design_v2 ProjectSetup `outputs`) shown in the
 *  Instructions panel so a user understands what an output format IS — the field is hard to fill
 *  from a blank input. Seeded as `on:false` so adding an example never silently takes effect until
 *  the user switches it on. */
export const EXAMPLE_OUTPUT_FORMATS: OutputFormat[] = [
  { kind: 'report',  name: 'Internal memo',           detail: 'Findings first (≤200 words), then methods, then the QC audit. Figures 300 dpi, greyscale-safe palette.', on: false },
  { kind: 'figure',  name: 'Manuscript figure spec',  detail: 'Vector SVG, Arial 8 pt axis labels, no chart junk, panel letters bottom-left.', on: false },
  { kind: 'table',   name: 'Supplementary table',     detail: 'One sheet per contrast, gene id in column A, effect size before p-value.', on: false },
  { kind: 'naming',  name: 'File naming convention',   detail: '<project>_<assay>_<contrast>_<yyyymmdd> — applied at ingest and to every output.', on: false },
];

const CHINESE_EXAMPLE_OUTPUT_FORMATS: OutputFormat[] = [
  { kind: 'report', name: '内部备忘录', detail: '先列研究发现（不超过 200 字），再写方法和质量控制审计。图像为 300 dpi，配色适合灰度打印。', on: false },
  { kind: 'figure', name: '论文图表规范', detail: '使用矢量 SVG；坐标轴标签为 Arial 8 pt；去除多余装饰；分图字母放在左下角。', on: false },
  { kind: 'table', name: '补充表格', detail: '每个比较使用单独的工作表；A 列为基因 ID；先列效应量，再列 p 值。', on: false },
  { kind: 'naming', name: '文件命名约定', detail: '<project>_<assay>_<contrast>_<yyyymmdd> — 用于导入文件和所有输出文件。', on: false },
];

/** Locale affects new examples, never rewrites saved user requirements. */
export function exampleOutputFormats(language: string): OutputFormat[] {
  return (language === 'zh' ? CHINESE_EXAMPLE_OUTPUT_FORMATS : EXAMPLE_OUTPUT_FORMATS).map(format => ({ ...format }));
}

/** Insert missing templates by semantic content, preserving user variants and enabled states.
 * Existing duplicates are deliberately retained: removing persisted entries requires user intent. */
export function appendMissingOutputFormats(existing: OutputFormat[], additions: OutputFormat[]): OutputFormat[] {
  const contentKey = (f: OutputFormat) => JSON.stringify([f.kind, f.name.trim(), f.detail.trim()]);
  const key = (f: OutputFormat) => {
    const raw = contentKey(f);
    // Translated built-ins are the same template. Keep user-edited variants.
    const index = EXAMPLE_OUTPUT_FORMATS.findIndex((example, i) => contentKey(example) === raw || contentKey(CHINESE_EXAMPLE_OUTPUT_FORMATS[i]) === raw);
    return index < 0 ? raw : `builtin:${index}`;
  };
  const seen = new Set(existing.map(key));
  const next = [...existing];
  for (const format of additions) {
    if (!seen.has(key(format))) { next.push({ ...format }); seen.add(key(format)); }
  }
  return next;
}
