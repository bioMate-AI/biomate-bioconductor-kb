#!/usr/bin/env node
/**
 * Declared-vs-fired analytics event audit.
 *
 * Parses the AnalyticsEvent union in frontend/client/src/lib/analytics.ts,
 * then grep-scans the client source tree for analytics.track('…') call sites,
 * and reports:
 *   - declared events with no call site (probably stale or aspirational)
 *   - call-site events not in the union (would have failed tsc but might
 *     have escaped via 'as any' casts)
 *
 * Exit codes:
 *   0 — everything declared is fired AND every fired event is declared
 *   1 — any drift detected (declared-unfired OR fired-undeclared)
 *
 * Treat declared-unfired as a soft warning by passing --allow-unfired (or
 * setting BIOMATE_ANALYTICS_ALLOW_UNFIRED=1); fired-undeclared is always
 * a hard failure since it indicates a typo or bypass.
 *
 * Usage:
 *   node frontend/scripts/check-analytics-events.mjs
 *   node frontend/scripts/check-analytics-events.mjs --allow-unfired
 *
 * Wire in CI as: `node frontend/scripts/check-analytics-events.mjs`
 *
 * Doc: docs/20260528_ANALYTICS_PIPELINE_COMPLETE.md
 */

import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');
const ANALYTICS_FILE = resolve(ROOT, 'client/src/lib/analytics.ts');
const SCAN_ROOT = resolve(ROOT, 'client/src');

const args = process.argv.slice(2);
const allowUnfired =
  args.includes('--allow-unfired') ||
  process.env.BIOMATE_ANALYTICS_ALLOW_UNFIRED === '1';

// ── Parse declared events ──────────────────────────────────────────────────
// We extract from the AnalyticsEvent union only. The regex matches lines
// that start with `  | 'event_name'` — typical for our discriminated union
// declaration.
const src = readFileSync(ANALYTICS_FILE, 'utf8');
const unionMatch = src.match(
  /export type AnalyticsEvent =([\s\S]*?);/m,
);
if (!unionMatch) {
  console.error('FATAL: could not find AnalyticsEvent union in', ANALYTICS_FILE);
  process.exit(2);
}
const declared = new Set(
  [...unionMatch[1].matchAll(/^\s*\|\s*'([a-z_]+)'/gm)].map((m) => m[1]),
);

// ── Find call sites ────────────────────────────────────────────────────────
// grep recursively for `analytics.track('event_name'` literal calls. Dynamic
// names (template strings, variables) are unverifiable by this script and are
// reported separately so they aren't silently treated as "fired".
let grepOutput = '';
try {
  grepOutput = execSync(
    `grep -rh --include="*.ts" --include="*.tsx" -E "analytics\\.track\\(['\\\"][a-z_]+['\\\"]" "${SCAN_ROOT}"`,
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] },
  );
} catch (e) {
  // grep returns 1 when there are no matches; treat as empty
  if (e.status !== 1) throw e;
}
const fired = new Set(
  [...grepOutput.matchAll(/analytics\.track\(['"]([a-z_]+)['"]/g)].map(
    (m) => m[1],
  ),
);

// Also detect dynamic-name calls so we can mention them in the report.
let dynGrep = '';
try {
  dynGrep = execSync(
    `grep -rhnE "analytics\\.track\\(\\\`" "${SCAN_ROOT}" --include="*.ts" --include="*.tsx" || true`,
    { encoding: 'utf8' },
  );
} catch {
  /* ignore */
}
const dynamicCount = dynGrep.trim().split('\n').filter(Boolean).length;

// ── Diff ───────────────────────────────────────────────────────────────────
const unfired = [...declared].filter((e) => !fired.has(e)).sort();
const undeclared = [...fired].filter((e) => !declared.has(e)).sort();

// ── Report ─────────────────────────────────────────────────────────────────
console.log(`Analytics event audit — ${ANALYTICS_FILE}`);
console.log(`  declared: ${declared.size}`);
console.log(`  fired (literal): ${fired.size}`);
console.log(`  fired (dynamic, unverifiable): ${dynamicCount} call sites`);
console.log('');

let failed = false;

if (undeclared.length > 0) {
  console.error('❌ FIRED but NOT DECLARED (typo or bypass):');
  for (const e of undeclared) console.error(`   - ${e}`);
  console.error('');
  console.error(
    'Each of these would have been caught by tsc unless cast with `as any`.',
  );
  console.error(
    'Fix by adding the event to the AnalyticsEvent union, or removing the call.',
  );
  console.error('');
  failed = true;
}

if (unfired.length > 0) {
  const label = allowUnfired ? '⚠️ ' : '❌';
  const sink = allowUnfired ? console.warn : console.error;
  sink(`${label} DECLARED but NEVER FIRED (stale or aspirational):`);
  for (const e of unfired) sink(`   - ${e}`);
  sink('');
  sink('Either wire the event at its intended user-action site, or remove');
  sink('it from the AnalyticsEvent union to keep the catalog honest.');
  sink('');
  if (!allowUnfired) failed = true;
}

if (!failed) {
  console.log('✅ all declared events have at least one call site');
  console.log('✅ no rogue call-site event names');
}

process.exit(failed ? 1 : 0);
