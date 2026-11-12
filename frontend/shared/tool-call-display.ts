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

/** The internal execution backend is never named to the user (founder 2026-11-12: "there should
 *  not have galaxy in output"). Removes backend id fields (`galaxy_dataset_id=<id>`, bare
 *  `galaxy_*_id` names) and rewrites the backend's own nouns ("Galaxy history / backend / dataset /
 *  server / API") to neutral words. A user asking about the Galaxy platform itself ("import a Galaxy
 *  workflow", ".ga file") is untouched. Prose only — callers skip code blocks. */
export function redactInternalBackend(text: string, zh = false): string {
  return String(text || '')
    .replace(/`?\bgalaxy_[a-z_]*ids?\b`?\s*[=:]\s*`?[A-Za-z0-9-]+`?\s*,?\s*/gi, '')
    .replace(/`?\bgalaxy_[a-z_]*ids?\b`?/gi, zh ? '数据集 ID' : 'dataset ID')
    .replace(/\b(?:(?:the|a|your)\s+)?Galaxy\s+(?:history|histories)\b/gi, (_m: string, offset: number, all: string) => zh ? '你的数据'
      : (/(?:^|[.!?]\s+)$/.test(all.slice(0, offset)) ? 'Your data' : 'your data'))
    .replace(/\bGalaxy\s+(dataset|datasets)\b/gi, (_m, n: string) => zh ? '数据集' : n.toLowerCase())
    .replace(/\b(?:the\s+)?Galaxy\s+(?:backend|server|instance|API)\b/gi, 'BioMate')
    .replace(/Galaxy\s*(?:历史记录|历史|后端|服务器|数据集)/g, (m) => /数据集/.test(m) ? '数据集' : /历史/.test(m) ? '你的数据' : 'BioMate');
}

/** A tool's result as shown in the expanded chat card: internal id fields and backend-named keys
 *  dropped, UUID values removed, storage URIs reduced to file names, backend nouns neutralised. */
export function userFacingToolOutput(value: unknown, depth = 0): unknown {
  if (depth > 6) return undefined;
  if (typeof value === 'string') {
    if (UUID_RE.test(value) && value.trim().length <= 40) return undefined;
    const s = value.replace(/(?:s3|gs|file):\/\/[^\s"',)\]]+/gi, (m) => baseName(m) || m);
    return redactInternalBackend(s.replace(new RegExp(UUID_RE.source, 'gi'), '').replace(/\(\s*(?:id:?\s*)?\)/g, ''));
  }
  if (Array.isArray(value)) return value.map(v => userFacingToolOutput(v, depth + 1)).filter(v => v !== undefined);
  if (value && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      if (ID_KEY_RE.test(k) || /galaxy|s3_?(?:key|uri|bucket)/i.test(k)) continue;
      const cleaned = userFacingToolOutput(v, depth + 1);
      if (cleaned !== undefined) out[k] = cleaned;
    }
    return out;
  }
  return value;
}
