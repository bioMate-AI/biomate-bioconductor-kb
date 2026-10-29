/**
 * Gated entry point for on-demand tool discovery.
 *
 * Wires a chat / HTTP request for a BEYOND-DB capability to BioMate's existing
 * GitHub tool-ingest pipeline (auto_update/scripts/request_single_tool.py),
 * which otherwise only runs as a nightly cron.
 *
 * This is the single place the gate is enforced. BOTH the chat tool
 * (`request_new_tool` in galaxy-assistant.ts) and the HTTP endpoint
 * (`POST /api/tools/request-discovery` in routes.ts) call `requestToolDiscovery`,
 * so neither can bypass the gate.
 *
 * GATE (all must hold before any GitHub fetch / registration happens):
 *   1. Env flag `BIOMATE_TOOL_DISCOVERY_ENABLED` must be "true"/"1" (default OFF).
 *   2. The caller must pass `confirm: true` (explicit user confirmation).
 *      Without it we return `confirmation_required` and touch nothing.
 *   3. A capability description OR an exact `owner/name` repo is required.
 *   4. An authenticated userId is required (callers pass it in).
 *
 * The underlying Python wrapper only ever fetches ONE repo (or the single best
 * match for a query) — never an unbounded multi-topic crawl — and reuses the
 * pipeline's own feasibility / API / duplicate / XML-validation / integration
 * gates unchanged. Newly registered tools are marked `auto_discovered` by the
 * pipeline.
 */

import path from 'path';

export type ToolDiscoveryStatus =
  | 'disabled'
  | 'confirmation_required'
  | 'invalid_request'
  | 'registered'
  | 'already_exists'
  | 'not_feasible'
  | 'has_api'
  | 'needs_review'
  | 'not_found'
  | 'error';

export interface ToolDiscoveryRequest {
  capability?: string;      // free-text capability description
  repo?: string;            // exact "owner/name" (optional, takes precedence)
  confirm?: boolean;        // explicit user confirmation
  userId?: string | number; // authenticated user (required when confirmed)
}

export interface ToolDiscoveryResult {
  status: ToolDiscoveryStatus;
  message: string;
  tool?: string;
  repo?: string;
  quality_score?: number;
  classification?: string;
  errors?: string[];
}

function flagEnabled(): boolean {
  const v = (process.env.BIOMATE_TOOL_DISCOVERY_ENABLED || '').trim().toLowerCase();
  return v === 'true' || v === '1' || v === 'yes';
}

/** Absolute path to the targeted single-tool wrapper. Node cwd is `frontend/`. */
function scriptPath(): string {
  return (
    process.env.AUTO_UPDATE_SINGLE_TOOL_SCRIPT ||
    path.join(process.cwd(), '..', 'auto_update', 'scripts', 'request_single_tool.py')
  );
}

/** Parse the sentinel-delimited JSON result block emitted by the Python wrapper. */
function parseResultBlock(stdout: string): ToolDiscoveryResult | null {
  const start = stdout.indexOf('===REQUEST_SINGLE_TOOL_RESULT===');
  const end = stdout.indexOf('===END_RESULT===');
  if (start === -1 || end === -1 || end <= start) return null;
  const jsonText = stdout.slice(start + '===REQUEST_SINGLE_TOOL_RESULT==='.length, end).trim();
  try {
    return JSON.parse(jsonText) as ToolDiscoveryResult;
  } catch {
    return null;
  }
}

export async function requestToolDiscovery(
  req: ToolDiscoveryRequest
): Promise<ToolDiscoveryResult> {
  const capability = (req.capability || '').toString().trim();
  const repo = (req.repo || '').toString().trim();

  // GATE 1: hard env flag — default OFF. Nothing runs when disabled.
  if (!flagEnabled()) {
    return {
      status: 'disabled',
      message:
        'On-demand tool discovery is disabled on this deployment. ' +
        'No external tool was fetched. An administrator can enable it by setting ' +
        'BIOMATE_TOOL_DISCOVERY_ENABLED=true. Until then, compose an answer from the ' +
        'existing catalog or tell the user the capability is not yet available.',
    };
  }

  // GATE 3: must describe something to look for.
  if (!capability && !repo) {
    return {
      status: 'invalid_request',
      message: 'Provide a capability description (or an exact owner/name repo) to search for.',
    };
  }

  // GATE 2: explicit confirmation. No GitHub fetch / registration without it.
  if (req.confirm !== true) {
    const target = repo ? `the repository "${repo}"` : `a new tool for: "${capability}"`;
    return {
      status: 'confirmation_required',
      message:
        `This will search GitHub for ${target}, then fetch, wrap, validate and register ` +
        `it into BioMate's tool catalog as an auto-discovered tool. This reaches an external ` +
        `service and modifies the catalog. Ask the user to explicitly confirm; only then call ` +
        `this tool again with confirm=true. Do not confirm on the user's behalf.`,
    };
  }

  // GATE 4: authenticated user required for a mutating, external-reaching action.
  if (req.userId === undefined || req.userId === null || `${req.userId}`.length === 0) {
    return {
      status: 'invalid_request',
      message: 'An authenticated user is required to request tool discovery.',
    };
  }

  const { execFile } = await import('child_process');
  const { promisify } = await import('util');
  const execFileP = promisify(execFile);

  const script = scriptPath();
  const args = ['--json'];
  if (repo) {
    args.push('--repo', repo);
  } else {
    args.push('--query', capability);
  }

  const python = process.env.PYTHON_BIN || 'python3';
  try {
    const { stdout } = await execFileP(python, [script, ...args], {
      // No execution-test by default (matches cron), so a few minutes is ample.
      timeout: Number(process.env.TOOL_DISCOVERY_TIMEOUT_MS || 240000),
      maxBuffer: 8 * 1024 * 1024,
      env: process.env,
    });
    const parsed = parseResultBlock(stdout);
    if (!parsed) {
      return {
        status: 'error',
        message: 'Tool discovery ran but returned no parseable result. Needs manual review.',
      };
    }
    return parsed;
  } catch (e: any) {
    // Try to recover a result block even on non-zero exit / timeout.
    const parsed = e?.stdout ? parseResultBlock(String(e.stdout)) : null;
    if (parsed) return parsed;
    const reason = e?.killed ? 'timed out' : (e?.message || String(e));
    return {
      status: 'error',
      message: `Tool discovery failed (${reason}). No tool was registered.`,
    };
  }
}
