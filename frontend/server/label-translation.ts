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
const key = (lang: LabelLang, s: string) => `${lang}\u0000${s}`;

/** Test hook. */
export function _resetLabelCache() { cache.clear(); }

const SYSTEM = [
  'You translate short UI labels from a bioinformatics workflow panel into Simplified Chinese for scientists.',
  'Input: a JSON array of English labels. Output: a JSON object {"t": {"<exact input>": "<translation>"}} covering EVERY input.',
  'Rules: concise, idiomatic professional Chinese (as a Chinese bioinformatics paper would write it);',
  'keep tool, software, method, file-format and gene names verbatim (DESeq2, MACS2, PCA, BAM, FASTQ, HTML, nf-core, …);',
  'keep any file name verbatim; do not add explanations, punctuation at the end, or quotes.',
].join(' ');

/**
 * Translate labels to `lang`. Returns a map for every input string (untranslatable,
 * failed or skipped inputs map to themselves).
 */
export async function translateLabels(
  strings: string[],
  lang: LabelLang,
  llm: typeof callGeminiFlash = callGeminiFlash,
): Promise<Record<string, string>> {
  const uniq = [...new Set(strings.map(s => String(s ?? '')).filter(Boolean))].slice(0, MAX_LABELS);
  const out: Record<string, string> = {};
  const todo: string[] = [];
  for (const s of uniq) {
    const hit = cache.get(key(lang, s));
    if (hit !== undefined) out[s] = hit;
    else if (!needsTranslation(s)) out[s] = s;
    else todo.push(s);
  }
  if (todo.length) {
    let parsed: Record<string, unknown> = {};
    try {
      const raw = await llm({
        system: SYSTEM,
        messages: [{ role: 'user', content: JSON.stringify(todo) }],
        maxTokens: 4096,
        temperature: 0,
        jsonMode: true,
      });
      const obj = JSON.parse(String(raw).replace(/```json\n?|```/g, '').trim());
      parsed = obj && typeof obj === 'object' && obj.t && typeof obj.t === 'object' ? obj.t : {};
    } catch {
      parsed = {};
    }
    for (const s of todo) {
      const v = typeof parsed[s] === 'string' ? (parsed[s] as string).trim() : '';
      // A translation (contains CJK), or the model deliberately keeping a name
      // verbatim (e.g. "MultiQC"). Anything else — missing key, parse failure, some
      // other English string — falls back to the source and is NOT cached, so a
      // transient failure is retried next time.
      const ok = !!v && v.length <= MAX_LABEL_LEN * 2 && (CJK.test(v) || v === s.trim());
      out[s] = ok ? v : s;
      if (ok) cache.set(key(lang, s), v);
    }
  }
  return out;
}
