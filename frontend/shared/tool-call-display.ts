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
      parts.push(s.length > MAX_PART ? `${s.slice(0, MAX_PART)}…` : s);
    }
  }
  return Array.from(new Set(parts)).join(' · ');
}
