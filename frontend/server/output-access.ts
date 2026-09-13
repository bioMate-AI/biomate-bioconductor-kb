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
  getUserProjects?: (userId: string) => Promise<Array<{ id?: string | null }> | undefined>;
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

export type OutputAccessDecision<TOut extends OutputLike = OutputLike> =
  | { allowed: true; output: TOut; via: 'owner' | 'project_member' }
  | { allowed: false; status: 401 | 403 | 404; error: string };

/** Authorize access to an output addressed by its id. Returns the fetched
 *  output on success so callers need not re-read it. */
export async function decideOutputAccess<TOut extends OutputLike>(
  outputId: string,
  userId: string | null | undefined,
  deps: OutputAccessDeps<TOut>,
): Promise<OutputAccessDecision<TOut>> {
  const output = await deps.getOutput(outputId);
  if (!output) return { allowed: false, status: 404, error: 'Output not found' };

  const inv = output.invocationId ? await deps.getInvocation(output.invocationId) : undefined;
  const target = await accessTargetForInvocation(inv, deps);
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
