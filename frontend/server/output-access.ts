/**
 * Authorization for output/artifact surfaces that address data by an OUTPUT or
 * INVOCATION id rather than a run id.
 *
 * An output id is not a credential. The legacy `/api/outputs/:id*` and
 * `/api/invocations/:id*` routes fetched by id and streamed bytes with no
 * authorization — any caller could enumerate ids and read another user's
 * results (IDOR). This module applies the SAME owner/project-member policy the
 * run surfaces use (`decideRunAccess`), by walking the object graph back to the
 * owning ExecutionRun:
 *
 *     output --(invocationId)--> invocation --(galaxyInvocationId)--> run
 *
 * When an object cannot be resolved to an owning run it FAILS CLOSED: an
 * orphan output with no owner information is denied, never served.
 *
 * Dependencies are injected so this is unit-testable without a live store.
 */
import { decideRunAccess, type AccessControlledRun } from './run-access';

export interface OutputLike {
  id: string;
  invocationId?: string | null;
}

/**
 * A canonical output as returned by `runsOutputsService.list(runId)`
 * (`CanonicalOutput`). Only the fields this module needs to match and serve
 * one output are modelled; callers keep the full object through the decision.
 */
export interface CanonicalOutputLike {
  /** `${runId}:${s3Key}`. */
  id: string;
  name?: string;
  s3Uri?: string;
}

export interface InvocationLike {
  userId?: string | null;
  projectId?: string | null;
  galaxyInvocationId?: string | null;
}

// Generic over the concrete output type so callers keep their real object type
// (e.g. OutputDataset) through the decision rather than the loose OutputLike.
export interface OutputAccessDeps<TOut extends OutputLike = OutputLike> {
  getOutput: (id: string) => Promise<TOut | undefined>;
  getInvocation: (id: string) => Promise<InvocationLike | undefined>;
  getRunByGalaxyId: (galaxyInvocationId: string) => Promise<AccessControlledRun | undefined>;
  // Resolve a WorkflowInvocation by its galaxyInvocationId. Optional so existing
  // callers/tests keep working, but required to authorize nextflow outputs whose
  // `invocationId` field carries a galaxyInvocationId rather than an invocation PK.
  getInvocationByGalaxyId?: (galaxyInvocationId: string) => Promise<InvocationLike | undefined>;
  getUserProjects?: (userId: string) => Promise<Array<{ id?: string | null }> | undefined>;
  // ── Canonical-id resolution (L1c) ──────────────────────────────────────────
  // These let single-file surfaces authorize a canonical `${runId}:${s3Key}` id
  // at the RUN level (owner lives on the ExecutionRun, so it survives restart)
  // and serve the matching output from the canonical resolver. Optional so
  // existing callers/tests that only exercise the legacy OutputDataset-PK path
  // keep working.
  getExecutionRun?: (runId: string) => Promise<AccessControlledRun | undefined>;
  getExecutionRunByGalaxyId?: (galaxyInvocationId: string) => Promise<AccessControlledRun | undefined>;
  /** Canonical outputs for a run — `runsOutputsService.list(runId)`. */
  listRunOutputs?: (runId: string) => Promise<CanonicalOutputLike[]>;
}

/**
 * Resolve the ExecutionRun-level access target that owns an invocation. Prefers
 * the linked ExecutionRun (owner + project → full owner/member policy); falls
 * back to the invocation's own owner when no run is linked (legacy rows). A
 * `projectId` is only trusted when it comes from a real ExecutionRun.
 */
async function accessTargetForInvocation(
  inv: InvocationLike | undefined,
  deps: OutputAccessDeps<any>,
): Promise<AccessControlledRun | undefined> {
  if (!inv) return undefined;
  if (inv.galaxyInvocationId) {
    const run = await deps.getRunByGalaxyId(inv.galaxyInvocationId);
    if (run) return run;
  }
  if (inv.userId != null && inv.userId !== '') {
    // Legacy invocation with no linked run — authorize by its own owner only.
    return { userId: inv.userId, projectId: inv.projectId ?? null };
  }
  return undefined;
}

/**
 * Resolve the ExecutionRun-level access target that owns an output, given the
 * value stored in `output.invocationId`. That field is overloaded across run
 * types, so we try each meaning in turn and fail closed only if none resolves:
 *
 *   1. a WorkflowInvocation PK          → invocation → owning run/owner
 *   2. a galaxyInvocationId directly    → owning ExecutionRun   (nextflow outputs
 *                                          are keyed by galaxy id, often with no
 *                                          WorkflowInvocation PK row at all)
 *   3. a galaxyInvocationId             → WorkflowInvocation → owning run/owner
 *
 * Before this, only (1) was attempted — so a legitimate owner was denied (403)
 * on their own nextflow outputs, whose invocationId is a galaxy id, not a PK.
 */
async function accessTargetForOutputInvocationId(
  invId: string,
  deps: OutputAccessDeps<any>,
): Promise<AccessControlledRun | undefined> {
  if (!invId) return undefined;
  // (1) invId as a WorkflowInvocation PK.
  const invByPk = await deps.getInvocation(invId);
  if (invByPk) {
    const t = await accessTargetForInvocation(invByPk, deps);
    if (t) return t;
  }
  // (2) invId as a galaxyInvocationId pointing straight at the owning run.
  const runByGalaxy = await deps.getRunByGalaxyId(invId);
  if (runByGalaxy) return runByGalaxy;
  // (3) invId as a galaxyInvocationId pointing at a WorkflowInvocation row.
  if (deps.getInvocationByGalaxyId) {
    const invByGalaxy = await deps.getInvocationByGalaxyId(invId);
    if (invByGalaxy) {
      const t = await accessTargetForInvocation(invByGalaxy, deps);
      if (t) return t;
    }
  }
  return undefined;
}

export type OutputAccessDecision<TOut extends OutputLike = OutputLike> =
  | { allowed: true; output: TOut; via: 'owner' | 'project_member' }
  | { allowed: false; status: 401 | 403 | 404; error: string };

/**
 * A canonical output id is `${runId}:${s3Key}`. The runId is an ExecutionRun
 * UUID (no colon), so the run id is everything before the FIRST colon and the
 * s3 key is the remainder. Returns null when the id has no ':' (a legacy
 * OutputDataset PK, which is opaque and must go through the PK path instead).
 */
function splitCanonicalOutputId(id: string): { runId: string; s3Key: string } | null {
  const idx = id.indexOf(':');
  if (idx <= 0 || idx >= id.length - 1) return null;
  return { runId: id.slice(0, idx), s3Key: id.slice(idx + 1) };
}

/**
 * Canonical-id path (L1c). Authorize a `${runId}:${s3Key}` output at the RUN
 * level and return the matching canonical output.
 *
 * Owner + s3Uri both come from the persisted ExecutionRun, so this survives a
 * container restart — unlike the OutputDataset-PK path, whose map is in-memory
 * and 404s after a recycle. Returns undefined (not a decision) when the deps
 * needed for this path aren't wired or the run can't be resolved, so the caller
 * can fall back to the legacy PK path.
 */
async function decideCanonicalOutputAccess<TOut extends OutputLike>(
  runId: string,
  s3Key: string,
  userId: string | null | undefined,
  deps: OutputAccessDeps<TOut>,
): Promise<OutputAccessDecision<TOut> | undefined> {
  if (!deps.getExecutionRun && !deps.getExecutionRunByGalaxyId) return undefined;
  const run =
    (deps.getExecutionRun ? await deps.getExecutionRun(runId) : undefined) ||
    (deps.getExecutionRunByGalaxyId ? await deps.getExecutionRunByGalaxyId(runId) : undefined);
  if (!run) return undefined; // Not a resolvable run — let the legacy path try.

  const decision = await decideRunAccess(run, userId, deps.getUserProjects);
  if (!decision.allowed) return decision;

  // Authorized at the run level. Find the matching output so callers can stream
  // from its s3Uri. Match by the full canonical id first, then by s3Key suffix.
  const wantId = `${runId}:${s3Key}`;
  const outputs = deps.listRunOutputs ? await deps.listRunOutputs(runId) : [];
  const match =
    outputs.find((o) => o.id === wantId) ||
    outputs.find((o) => typeof o.s3Uri === 'string' && o.s3Uri.endsWith(`/${s3Key}`)) ||
    outputs.find((o) => o.id.endsWith(`:${s3Key}`));
  if (!match) {
    // Run is authorized but the file isn't in its output set → 404 (not 403):
    // the caller is allowed to see this run, the artifact just isn't there.
    return { allowed: false, status: 404, error: 'Output not found' };
  }
  return { allowed: true, output: match as unknown as TOut, via: decision.via };
}

/** Authorize access to an output addressed by its id. Returns the fetched
 *  output on success so callers need not re-read it.
 *
 *  Two id shapes are supported (L1c):
 *   - Canonical `${runId}:${s3Key}` (what the reproducibility record + findings
 *     now emit): resolved by ExecutionRun and authorized at the run level, so it
 *     is durable across restarts. Tried first when the id contains ':', and as a
 *     fallback when the legacy PK lookup misses.
 *   - Legacy OutputDataset PK: fetched via `getOutput(id)` and authorized by
 *     walking output → invocation → run. Kept as a shim for one release. */
export async function decideOutputAccess<TOut extends OutputLike>(
  outputId: string,
  userId: string | null | undefined,
  deps: OutputAccessDeps<TOut>,
): Promise<OutputAccessDecision<TOut>> {
  const canonical = splitCanonicalOutputId(outputId);

  // Canonical-id form (contains ':') → try the run-level path first.
  if (canonical) {
    const viaCanonical = await decideCanonicalOutputAccess(
      canonical.runId, canonical.s3Key, userId, deps,
    );
    if (viaCanonical) return viaCanonical;
    // Fell through (run not resolvable / deps not wired) → legacy PK path below.
  }

  const output = await deps.getOutput(outputId);
  if (!output) return { allowed: false, status: 404, error: 'Output not found' };

  const target = output.invocationId
    ? await accessTargetForOutputInvocationId(output.invocationId, deps)
    : undefined;
  if (!target) {
    // Cannot establish an owner → fail closed. Distinguish unauthenticated
    // (401) from authenticated-but-unauthorizable (403) to match run policy.
    return userId
      ? { allowed: false, status: 403, error: 'Forbidden — output has no resolvable owning run' }
      : { allowed: false, status: 401, error: 'Authentication required' };
  }

  const decision = await decideRunAccess(target, userId, deps.getUserProjects);
  if (!decision.allowed) return decision;
  return { allowed: true, output, via: decision.via };
}

export type InvocationAccessDecision =
  | { allowed: true; via: 'owner' | 'project_member' }
  | { allowed: false; status: 401 | 403 | 404; error: string };

/** Authorize access to an already-resolved invocation (the caller's route may
 *  resolve it by id, galaxy id, or via an execution run before calling here). */
export async function decideInvocationAccess(
  inv: InvocationLike | undefined,
  userId: string | null | undefined,
  deps: OutputAccessDeps<any>,
): Promise<InvocationAccessDecision> {
  if (!inv) return { allowed: false, status: 404, error: 'Invocation not found' };
  const target = await accessTargetForInvocation(inv, deps);
  if (!target) {
    return userId
      ? { allowed: false, status: 403, error: 'Forbidden — invocation has no resolvable owner' }
      : { allowed: false, status: 401, error: 'Authentication required' };
  }
  return decideRunAccess(target, userId, deps.getUserProjects);
}
