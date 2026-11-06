#!/bin/bash
# Dump the EXACT chat payloads the cold-start UI sends (every module/track/modality + domain
# shapes) by calling the UI's own prepareColdStartExample() in a temporary vitest (fetch stubbed,
# so no demo files load; the temp test is removed afterwards).
# Usage: scripts/routing_eval/dump_payloads.sh <out.json>
set -euo pipefail
OUT="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "$0")/../../frontend"
T=client/src/components/__tmp_dump_payloads.test.ts
trap 'rm -f "$T"' EXIT
cat > "$T" <<'TS'
import { it, vi } from 'vitest';
import { writeFileSync } from 'node:fs';
import { COLD_MODULES, COLD_DOMAINS, seedWithModality } from './cold-start-dashboard';
import { prepareColdStartExample } from './cold-start-examples';
it('dump', async () => {
  vi.stubGlobal('fetch', async () => new Response(new Blob(['x'], { type: 'text/plain' })));
  const out: any[] = [];
  for (const m of COLD_MODULES as any[]) for (const t of m.tracks) {
    const seeds: [string, string][] = t.ex.map((x: string) => ['default', x]);
    if (t.exBy) for (const [mod, texts] of Object.entries(t.exBy)) for (const x of texts as string[]) seeds.push([mod, seedWithModality(x, mod as any)]);
    for (const [mod, seed] of seeds) { const p = await prepareColdStartExample(seed); out.push({ module: m.id, track: t.k, mod, seed, prompt: p.prompt, files: p.files.map(f => f.name) }); }
  }
  for (const d of COLD_DOMAINS as any[]) for (const s of d.shapes) { const p = await prepareColdStartExample(s.seed); out.push({ module: 'domain:' + d.id, track: s.t, mod: 'default', seed: s.seed, prompt: p.prompt, files: p.files.map(f => f.name) }); }
  out.forEach((r, i) => (r.idx = i));
  writeFileSync(process.env.DUMP_OUT!, JSON.stringify(out, null, 1));
});
TS
DUMP_OUT="$OUT" npx vitest run "$T" 2>&1 | grep -E "Tests|FAIL"
echo "wrote $(python3 -c "import json;print(len(json.load(open('$OUT'))))") payloads -> $OUT"
