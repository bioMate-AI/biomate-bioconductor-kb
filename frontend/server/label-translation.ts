/**
 * Catalog label translation — backend-sourced English labels (phase names, step
 * names, parameter labels from .nf annotations / nf schema) rendered in the zh UI.
 *
 * Founder 2026-11-11: no mixed English chrome in the zh UI. A per-workflow string
 * map in the frontend would be keyword overfitting (every new workflow needs an
 * entry), so the source is inference: one batched LLM call translates whatever
 * labels the panel shows, cached per unique string. Tool / method / file names stay
 * verbatim. Any failure returns the English source — rendering is never blocked and
 * nothing is invented.
 */
import { callGeminiFlash } from './gemini-flash';

/** Durable cache behind the in-memory one (migration 0023_label_translations), so a
 *  deploy/restart does not re-translate every label. Any store error degrades to
 *  memory-only — translation never fails because of the cache. */
export interface LabelStore {
  get(version: number, lang: string, srcs: string[]): Promise<Map<string, string>>;
  put(version: number, lang: string, entries: Array<[string, string]>): Promise<void>;
}

export const pgLabelStore: LabelStore = {
  async get(version, lang, srcs) {
    const { pool } = await import('./db');
    const { rows } = await pool.query(
      'SELECT src, translation FROM label_translations WHERE prompt_version = $1 AND lang = $2 AND src = ANY($3::text[])',
      [version, lang, srcs],
    );
    return new Map(rows.map((r: any) => [String(r.src), String(r.translation)]));
  },
  async put(version, lang, entries) {
    if (!entries.length) return;
    const { pool } = await import('./db');
    const vals: unknown[] = []; const ph: string[] = [];
    entries.forEach(([src, tr], i) => { ph.push(`($1, $2, $${i * 2 + 3}, $${i * 2 + 4})`); vals.push(src, tr); });
    await pool.query(
      `INSERT INTO label_translations (prompt_version, lang, src, translation) VALUES ${ph.join(', ')} ON CONFLICT DO NOTHING`,
      [version, lang, ...vals],
    );
  },
};

export type LabelLang = 'zh';

const CJK = /[\u3400-\u9fff]/;
/** Strings that are identifiers, not prose: snake_case/kebab ids, file names, versions, numbers. */
const IDENTIFIER = /^(?:[A-Za-z0-9]+(?:[_\-./][A-Za-z0-9]+)+|[0-9.%]+|[A-Z0-9_]+|[A-Za-z]*\d[A-Za-z0-9]*)$/;
export const MAX_LABELS = 200;
export const MAX_LABEL_LEN = 120;

/** Which inputs are worth translating at all (prose-like, not already Chinese). */
export function needsTranslation(s: string): boolean {
  const t = s.trim();
  if (!t || t.length > MAX_LABEL_LEN) return false;
  if (CJK.test(t)) return false;
  if (!/[A-Za-z]{2,}/.test(t)) return false;
  return !IDENTIFIER.test(t);
}

const cache = new Map<string, string>(); // `${lang}\u0000${src}` → translation
const key = (lang: LabelLang, s: string) => `${PROMPT_VERSION}\u0000${lang}\u0000${s}`;

/** Test hook. */
export function _resetLabelCache() { cache.clear(); }

/** Bump when the instruction changes so cached entries from an older prompt are not served. */
const PROMPT_VERSION = 3;

/** v3 — measured offline on 114 real catalog labels (phase names, step descriptions,
 *  param labels) with the production model: v1 left ordinary English inside 15/114
 *  ("Count 矩阵", "Peak Calling", "下载 samplesheet 与 count …"); v3 leaves none and
 *  keeps code identifiers (getAssociation, fetch(), pifit) exact. A regex "English
 *  leftover" check + repair pass was tried and REMOVED: it could not tell function
 *  names from English and made the model translate them ("pifit" → "π 拟合"). */
const SYSTEM = [
  'You translate short UI labels from a bioinformatics workflow panel into Simplified Chinese for scientists.',
  'Input: a JSON array of English labels. Output: a JSON object {"t": {"<exact input>": "<translation>"}} covering EVERY input.',
  'Translate the MEANING, idiomatically, the way a Chinese bioinformatics methods section would phrase it — never word by word.',
  'Translate generic nouns fully (samplesheet, count matrix, normalisation, contrast, report, …).',
  'Keep ONLY proper names verbatim: software/tool names, gene/protein symbols, file names, file-format acronyms (DESeq2, MultiQC, Seurat, TP53, counts_matrix.csv, BAM, FASTQ, HTML).',
  'Function and method names written in code style (camelCase or snake_case identifiers, names followed by "()", or the X in "using X" when X is a code identifier) are proper names: keep them exactly, never translate or explain them.',
  'Never leave an ordinary English word inside the Chinese. No explanations, quotes, or trailing punctuation.',
  'Style examples: "Input Download" → "获取输入文件"; "Download samplesheet and count matrix" → "获取样本表与计数矩阵";',
  '"Run DESeq2 per contrast" → "按对比组运行 DESeq2"; "Samplesheet" → "样本表".',
].join(' ');

/**
 * Translate labels to `lang`. Returns a map for every input string (untranslatable,
 * failed or skipped inputs map to themselves).
 */
export async function translateLabels(
  strings: string[],
  lang: LabelLang,
  llm: typeof callGeminiFlash = callGeminiFlash,
  store: LabelStore | null = pgLabelStore,
): Promise<Record<string, string>> {
  const uniq = [...new Set(strings.map(s => String(s ?? '')).filter(Boolean))].slice(0, MAX_LABELS);
  const out: Record<string, string> = {};
  let todo: string[] = [];
  for (const s of uniq) {
    const hit = cache.get(key(lang, s));
    if (hit !== undefined) out[s] = hit;
    else if (!needsTranslation(s)) out[s] = s;
    else todo.push(s);
  }
  if (todo.length && store) {
    try {
      const stored = await store.get(PROMPT_VERSION, lang, todo);
      for (const [src, tr] of stored) { out[src] = tr; cache.set(key(lang, src), tr); }
      todo = todo.filter(s => !stored.has(s));
    } catch { /* store unavailable — memory-only */ }
  }
  if (todo.length) {
    const fresh: Array<[string, string]> = [];
    let parsed: Record<string, unknown> = {};
    try {
      const raw = await llm({ system: SYSTEM, messages: [{ role: 'user', content: JSON.stringify(todo) }], maxTokens: 4096, temperature: 0, jsonMode: true });
      const obj = JSON.parse(String(raw).replace(/```json\n?|```/g, '').trim());
      parsed = obj && typeof obj === 'object' && obj.t && typeof obj.t === 'object' ? obj.t : {};
    } catch {
      parsed = {};
    }
    for (const s of todo) {
      const v = typeof parsed[s] === 'string' ? (parsed[s] as string).trim() : '';
      // A translation (contains CJK), or the model deliberately keeping a proper name
      // verbatim ("MultiQC"). A missing key / parse failure / other English string
      // falls back to the source and is NOT cached, so it is retried next time.
      const ok = !!v && v.length <= MAX_LABEL_LEN * 2 && (CJK.test(v) || v === s.trim());
      out[s] = ok ? v : s;
      if (ok) { cache.set(key(lang, s), v); fresh.push([s, v]); }
    }
    if (store && fresh.length) {
      try { await store.put(PROMPT_VERSION, lang, fresh); } catch { /* memory-only */ }
    }
  }
  return out;
}
