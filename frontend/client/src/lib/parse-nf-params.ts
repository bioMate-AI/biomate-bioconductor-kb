/**
 * Minimal Nextflow DSL2 param extractor.
 *
 * Handles the common patterns:
 *   params { foo = 'bar' }          → name=foo, default='bar', type=string
 *   params { count = 10 }           → name=count, default='10', type=integer
 *   params { flag = true }          → name=flag, default='true', type=boolean
 *   params.foo = 'bar'              → name=foo, default='bar', type=string
 *
 * Returns an empty array for .ga workflows (parsed differently) or when
 * the file has no params block. Caller should show a free-form JSON editor
 * in that case.
 */

export interface NfParam {
  name: string;
  type: 'string' | 'integer' | 'float' | 'boolean';
  default: string | null;
  required: boolean;
}

const BLOCK_RE = /params\s*\{([^}]*)\}/gs;
const ASSIGN_RE = /^\s*([\w.]+)\s*=\s*(.+?)\s*(?:\/\/.*)?$/;
const FLAT_RE = /params\.([\w]+)\s*=\s*(.+?)(?:\s*\/\/[^\n]*)?\n/g;

function inferType(raw: string): NfParam['type'] {
  if (raw === 'true' || raw === 'false') return 'boolean';
  if (/^-?\d+$/.test(raw)) return 'integer';
  if (/^-?\d+\.\d+$/.test(raw)) return 'float';
  return 'string';
}

function stripQuotes(raw: string): string {
  return raw.replace(/^['"]|['"]$/g, '');
}

export function parseNfParams(content: string): NfParam[] {
  const seen = new Set<string>();
  const params: NfParam[] = [];

  function push(name: string, rawVal: string) {
    if (seen.has(name)) return;
    seen.add(name);
    const isNull = rawVal === 'null' || rawVal === 'false' || rawVal === '';
    params.push({
      name,
      type: inferType(rawVal),
      default: isNull ? null : stripQuotes(rawVal),
      required: rawVal === 'null',
    });
  }

  // params { ... } blocks
  for (const match of content.matchAll(BLOCK_RE)) {
    for (const line of match[1].split('\n')) {
      const m = ASSIGN_RE.exec(line);
      if (m) push(m[1], m[2].trim());
    }
  }

  // flat params.foo = ... assignments (outside blocks)
  for (const match of content.matchAll(FLAT_RE)) {
    push(match[1], match[2].trim());
  }

  return params;
}
