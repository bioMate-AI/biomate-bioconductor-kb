/**
 * Runtime feature flag system.
 *
 * Replaces scattered `process.env.ENABLE_X !== "false"` checks with a
 * database-backed system that can be toggled without redeployment.
 *
 * Data lives in the `feature_flags` PostgreSQL table (see shared/schema.ts).
 * Flags are cached in-process for `CACHE_TTL_MS` to avoid per-request DB hits.
 *
 * Usage:
 *   import { isEnabled } from './feature-flags';
 *
 *   // Global flag (no user context):
 *   if (await isEnabled('ux_feedback')) { ... }
 *
 *   // Per-user flag (respects rolloutPct + userOverrides):
 *   if (await isEnabled('new_param_panel', String(req.user.id))) { ... }
 *
 * Bootstrapping:
 *   On first startup, `seedDefaultFlags()` inserts known flags if absent,
 *   reading initial values from env vars for backwards-compatibility.
 */

import { db } from './db';
import { featureFlags } from '../shared/schema';
import { eq } from 'drizzle-orm';

const CACHE_TTL_MS = 60_000; // 60 s — balance freshness vs DB load

interface CachedFlag {
  enabled: boolean;
  rolloutPct: number;
  userOverrides: Record<string, boolean>;
  expiresAt: number;
}

const cache = new Map<string, CachedFlag>();

async function loadFlag(flagName: string): Promise<CachedFlag | null> {
  const cached = cache.get(flagName);
  if (cached && Date.now() < cached.expiresAt) return cached;

  try {
    const rows = await db.select().from(featureFlags).where(eq(featureFlags.flagName, flagName));
    if (rows.length === 0) return null;
    const row = rows[0];
    let overrides: Record<string, boolean> = {};
    try { overrides = JSON.parse(row.userOverrides || '{}'); } catch {}
    const entry: CachedFlag = {
      enabled: row.enabled,
      rolloutPct: row.rolloutPct,
      userOverrides: overrides,
      expiresAt: Date.now() + CACHE_TTL_MS,
    };
    cache.set(flagName, entry);
    return entry;
  } catch {
    // DB unavailable — fall back to env vars
    return null;
  }
}

/**
 * Check whether a feature flag is enabled, optionally for a specific user.
 *
 * Resolution order:
 * 1. DB flag not found → fall back to `ENV_FALLBACKS` or `false`
 * 2. Per-user override in `userOverrides` JSON → use that value
 * 3. Flag disabled globally → false
 * 4. rolloutPct < 100 → hash userId to determine bucket membership
 * 5. Otherwise → flag.enabled
 */
export async function isEnabled(flagName: string, userId?: string): Promise<boolean> {
  const flag = await loadFlag(flagName);

  if (!flag) {
    // Fall back to environment variable for backwards-compatibility
    return ENV_FALLBACKS[flagName] ?? false;
  }

  // Per-user override takes absolute precedence
  if (userId && userId in flag.userOverrides) {
    return flag.userOverrides[userId];
  }

  if (!flag.enabled) return false;

  // Rollout percentage check (deterministic bucket via simple hash)
  if (flag.rolloutPct < 100 && userId) {
    const bucket = stableHash(flagName + userId) % 100;
    return bucket < flag.rolloutPct;
  }

  return flag.enabled;
}

/** Synchronous version — uses cached value only, returns `fallback` on cache miss. */
export function isEnabledSync(flagName: string, userId?: string, fallback = false): boolean {
  const cached = cache.get(flagName);
  if (!cached || Date.now() >= cached.expiresAt) return fallback;
  if (userId && userId in cached.userOverrides) return cached.userOverrides[userId];
  if (!cached.enabled) return false;
  if (cached.rolloutPct < 100 && userId) {
    return stableHash(flagName + userId) % 100 < cached.rolloutPct;
  }
  return cached.enabled;
}

/** Invalidate cached value (call after admin toggle). */
export function invalidateFlag(flagName: string): void {
  cache.delete(flagName);
}

/** Simple deterministic hash (djb2). */
function stableHash(s: string): number {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h) ^ s.charCodeAt(i);
  return Math.abs(h);
}

// ---------------------------------------------------------------------------
// Known flags with environment-variable fallbacks (backwards-compatibility)
// ---------------------------------------------------------------------------

const ENV_FALLBACKS: Record<string, boolean> = {
  ux_feedback:      process.env.ENABLE_UX_FEEDBACK !== 'false',
  thinking_mode:    process.env.BIOMATE_ENABLE_THINKING === 'true',
  nextflow_aws:     ['true', '1', 'yes'].includes((process.env.NEXTFLOW_USE_AWS || '').toLowerCase()),
  ltm_injection:    true,   // Memory P2: LTM context in system prompt
  mcp_server:       true,   // MCP server available
  domain_guidance:  true,   // S3 domain specialist guidance
  step_control:     true,   // GC-8 step-level rerun buttons
};

/**
 * Insert default flags into the DB on first startup (idempotent).
 * Initial `enabled` values come from ENV_FALLBACKS for backwards-compatibility.
 */
export async function seedDefaultFlags(): Promise<void> {
  const defaults: Array<{ flagName: string; enabled: boolean; description: string }> = [
    { flagName: 'ux_feedback',     enabled: ENV_FALLBACKS.ux_feedback,     description: 'UX feedback collection panel (thumbs up/down + free-text)' },
    { flagName: 'thinking_mode',   enabled: ENV_FALLBACKS.thinking_mode,   description: 'Enable extended thinking (claude-3-7-sonnet-20250219 thinking budget)' },
    { flagName: 'nextflow_aws',    enabled: ENV_FALLBACKS.nextflow_aws,     description: 'Run Nextflow workflows on AWS Batch instead of local Docker' },
    { flagName: 'ltm_injection',   enabled: true,  description: 'Inject long-term memory (user prefs, corrections) into LLM system prompt' },
    { flagName: 'mcp_server',      enabled: true,  description: 'BioMate MCP server enabled for Claude Code CLI integration' },
    { flagName: 'domain_guidance', enabled: true,  description: 'S3 domain specialist guidance injected into generateResponse()' },
    { flagName: 'step_control',    enabled: true,  description: 'Step-level Run/Resume buttons in workflow viewer (GC-8)' },
  ];

  for (const flag of defaults) {
    try {
      await db
        .insert(featureFlags)
        .values({ ...flag, rolloutPct: 100, userOverrides: '{}' })
        .onConflictDoNothing();
    } catch {
      // Table may not exist yet during migration — silently skip
    }
  }
}
