/**
 * User-facing one-line summary of an agent tool call's arguments.
 *
 * Tool inputs are written for the model — `{"galaxy_dataset_id": "<uuid>"}` —
 * and must never be shown raw: identifiers mean nothing to the user and name
 * internal systems. This keeps what a person recognises (a dataset's name, a
 * search query, a file name) and drops the rest.
 *
 *  - an id-like value (key `id` / `*_id` / `*_ids`, or a UUID / long hex value)
 *    is replaced by its display name when `resolveName` knows it, else dropped;
 *  - a storage URI or absolute path is reduced to its file name;
 *  - `code` is skipped (the card shows code separately);
 *  - other strings are kept, trimmed; non-string values are skipped.
 */

const UUID_RE = /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i;
const HEX_ID_RE = /^[0-9a-f]{16,}$/i;
const ID_KEY_RE = /(?:^|_)ids?$/i;
const STORAGE_RE = /^(?:s3|gs|file):\/\/|^\/[^\s]+\/[^\s]+$/i;
const MAX_PART = 80;

function baseName(v: string): string {
  const clean = v.replace(/[?#].*$/, '').replace(/\/+$/, '');
  return clean.slice(clean.lastIndexOf('/') + 1);
}

export function toolCallDisplay(
  input: Record<string, unknown> | undefined | null,
  resolveName?: (id: string) => string | undefined,
): string {
  const parts: string[] = [];
  for (const [key, value] of Object.entries(input || {})) {
    if (key === 'code') continue;
    const values = Array.isArray(value) ? value : [value];
    for (const v of values) {
      if (typeof v !== 'string' || !v.trim()) continue;
      const s = v.trim();
      if (ID_KEY_RE.test(key) || UUID_RE.test(s) || HEX_ID_RE.test(s)) {
        const name = resolveName?.(s);
        if (name) parts.push(name);
        continue;
      }
      if (STORAGE_RE.test(s)) {
        const name = baseName(s);
        if (name) parts.push(name);
        continue;
      }
      const shown = redactInternalBackend(s);
      parts.push(shown.length > MAX_PART ? `${shown.slice(0, MAX_PART)}…` : shown);
    }
  }
  return Array.from(new Set(parts)).join(' · ');
}

/** The internal execution backend's identifiers never reach the user (founder 2026-11-12: "there
 *  should not have galaxy in output"). Narrow on purpose (committee review 2026-11-12: a broad
 *  "Galaxy X" → neutral rewrite turned correct answers about the Galaxy platform — "the Galaxy API",
 *  usegalaxy.org — into false ones):
 *   - backend id fields: `galaxy_dataset_id=<v>` / `galaxy_history_id: <v>` removed; a bare
 *     `galaxy_*_id` name → "dataset ID";
 *   - the user's OWN data called by the backend's name: "your Galaxy history/dataset" → "your data /
 *     your dataset" (zh: 你的/您的 Galaxy 历史/数据集).
 *  Prose only: callers pass prose segments (see redactUserFacingReply). */
export function redactInternalBackend(text: string, zh = false): string {
  return String(text || '')
    .replace(/\bgalaxy_[a-z_]*ids?\s*[=:]\s*["']?[A-Za-z0-9-]{6,}["']?,?\s?/gi, '')
    .replace(/\bgalaxy_[a-z_]*ids?\b/gi, zh ? '数据集 ID' : 'dataset ID')
    .replace(/\b(your|the user's)\s+Galaxy\s+(?:history|histories)\b/gi, (_m, p: string) => (p[0] === 'Y' ? 'Your' : 'your') + ' data')
    .replace(/\b(your|the user's)\s+Galaxy\s+(dataset|datasets)\b/gi, (_m, p: string, n: string) => (p[0] === 'Y' ? 'Your' : 'your') + ' ' + n.toLowerCase())
    .replace(/(你的|您的)\s*Galaxy\s*(?:历史记录|历史)/g, '$1数据')
    .replace(/(你的|您的)\s*Galaxy\s*数据集/g, '$1数据集');
}

/** Split text into prose and code segments: fenced blocks, inline `code`, and 4-space / tab
 *  indented lines are code and are never rewritten. */
function mapProse(text: string, f: (prose: string) => string): string {
  return String(text || '').split(/(```[\s\S]*?```|`[^`\n]+`|(?:^|\n)(?: {4}|\t)[^\n]*)/g)
    .map((part, i) => (i % 2 === 1 ? part : f(part))).join('');
}

/** Final reply text shown to the user: backend identifiers removed from prose only. */
export function redactUserFacingReply(text: string, zh = false): string {
  return mapProse(text, (p) => redactInternalBackend(p, zh));
}

/** A tool's result as shown in the expanded chat card: internal id fields and backend-named keys
 *  dropped, UUID values removed, storage URIs reduced to file names, backend nouns neutralised. */
export function userFacingToolOutput(value: unknown, depth = 0): unknown {
  if (depth > 6) return undefined;
  if (typeof value === 'string') {
    if (new RegExp(`^\\s*${UUID_RE.source}\\s*$`, 'i').test(value)) return undefined;
    const s = value.replace(/(?:s3|gs|file):\/\/[^\s"',)\]]+/gi, (m) => baseName(m) || m);
    return redactInternalBackend(s);
  }
  if (Array.isArray(value)) return value.map(v => userFacingToolOutput(v, depth + 1)).filter(v => v !== undefined);
  if (value && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      // `__`-prefixed keys are internal (model-facing notes, image-block markers) — never shown.
      if (k.startsWith('__') || ID_KEY_RE.test(k) || /galaxy|s3_?(?:key|uri|bucket)/i.test(k)) continue;
      const cleaned = userFacingToolOutput(v, depth + 1);
      if (cleaned !== undefined) out[k] = cleaned;
    }
    return out;
  }
  return value;
}
