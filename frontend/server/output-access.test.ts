import { describe, it, expect, vi } from 'vitest';
import {
  decideOutputAccess,
  decideInvocationAccess,
  type OutputAccessDeps,
} from './output-access';

const OWNER = 'user-owner';
const MEMBER = 'user-member';
const STRANGER = 'user-stranger';
const PROJECT = 'proj-1';

// output out-1 → invocation inv-1 → run (owner=OWNER, project=PROJECT)
function makeDeps(over: Partial<OutputAccessDeps> = {}): OutputAccessDeps {
  return {
    getOutput: vi.fn(async (id) =>
      id === 'out-1' ? { id: 'out-1', invocationId: 'inv-1' } :
      id === 'orphan' ? { id: 'orphan', invocationId: null } : undefined),
    getInvocation: vi.fn(async (id) =>
      id === 'inv-1' ? { userId: OWNER, galaxyInvocationId: 'gx-1' } :
      id === 'inv-legacy' ? { userId: OWNER, galaxyInvocationId: null } : undefined),
    getRunByGalaxyId: vi.fn(async (gid) =>
      gid === 'gx-1' ? { userId: OWNER, projectId: PROJECT } : undefined),
    getUserProjects: vi.fn(async (uid) => (uid === MEMBER ? [{ id: PROJECT }] : [])),
    ...over,
  };
}

describe('decideOutputAccess', () => {
  it('allows the owner (via the linked run)', async () => {
    const d = await decideOutputAccess('out-1', OWNER, makeDeps());
    expect(d.allowed).toBe(true);
    if (d.allowed) { expect(d.via).toBe('owner'); expect(d.output.id).toBe('out-1'); }
  });

  it('allows a project member (via the linked run project)', async () => {
    const d = await decideOutputAccess('out-1', MEMBER, makeDeps());
    expect(d.allowed).toBe(true);
    if (d.allowed) expect(d.via).toBe('project_member');
  });

  it('denies a stranger with 403 (IDOR blocked)', async () => {
    const d = await decideOutputAccess('out-1', STRANGER, makeDeps());
    expect(d).toMatchObject({ allowed: false, status: 403 });
  });

  it('denies an unauthenticated caller with 401', async () => {
    const d = await decideOutputAccess('out-1', null, makeDeps());
    expect(d).toMatchObject({ allowed: false, status: 401 });
  });

  it('returns 404 for a missing output', async () => {
    const d = await decideOutputAccess('nope', OWNER, makeDeps());
    expect(d).toMatchObject({ allowed: false, status: 404 });
  });

  it('fails closed (403) for an orphan output with no resolvable owner', async () => {
    const d = await decideOutputAccess('orphan', OWNER, makeDeps());
    expect(d).toMatchObject({ allowed: false, status: 403 });
  });

  it('falls back to the invocation owner when no run is linked (legacy)', async () => {
    const deps = makeDeps({
      getOutput: vi.fn(async () => ({ id: 'out-legacy', invocationId: 'inv-legacy' })),
    });
    const owner = await decideOutputAccess('out-legacy', OWNER, deps);
    expect(owner.allowed).toBe(true);
    const stranger = await decideOutputAccess('out-legacy', STRANGER, deps);
    expect(stranger).toMatchObject({ allowed: false, status: 403 });
    // Never queried a run — there was no galaxyInvocationId to resolve.
    expect(deps.getRunByGalaxyId).not.toHaveBeenCalled();
  });

  // REGRESSION (fixed): nextflow outputs carry a galaxyInvocationId in their
  // `invocationId` field and often have NO WorkflowInvocation PK row. The
  // original resolver only tried getInvocation(pk) → undefined → fail-closed,
  // so the legitimate OWNER was denied 403 on their own outputs. The owning run
  // must be resolved by treating invocationId as a galaxy id.
  it('authorizes the owner of a nextflow output keyed by galaxyInvocationId (no PK invocation)', async () => {
    const deps = makeDeps({
      // invocationId is a galaxy id; getInvocation(pk) misses entirely.
      getOutput: vi.fn(async () => ({ id: 'out-nf', invocationId: 'gx-nf' })),
      getInvocation: vi.fn(async () => undefined),
      getInvocationByGalaxyId: vi.fn(async () => undefined),
      getRunByGalaxyId: vi.fn(async (gid) =>
        gid === 'gx-nf' ? { userId: OWNER, projectId: PROJECT } : undefined),
    });
    const owner = await decideOutputAccess('out-nf', OWNER, deps);
    expect(owner.allowed).toBe(true);
    if (owner.allowed) expect(owner.via).toBe('owner');
    // A stranger is still blocked (IDOR remains closed).
    expect(await decideOutputAccess('out-nf', STRANGER, deps)).toMatchObject({ allowed: false, status: 403 });
  });

  it('authorizes via a WorkflowInvocation resolved by galaxy id (invocationId is a galaxy id with a PK row elsewhere)', async () => {
    const deps = makeDeps({
      getOutput: vi.fn(async () => ({ id: 'out-nf2', invocationId: 'gx-2' })),
      getInvocation: vi.fn(async () => undefined),
      getRunByGalaxyId: vi.fn(async () => undefined),
      getInvocationByGalaxyId: vi.fn(async (gid) =>
        gid === 'gx-2' ? { userId: OWNER, galaxyInvocationId: 'gx-2' } : undefined),
    });
    const owner = await decideOutputAccess('out-nf2', OWNER, deps);
    expect(owner.allowed).toBe(true);
  });
});

describe('decideInvocationAccess', () => {
  it('returns 404 for a null invocation', async () => {
    const d = await decideInvocationAccess(undefined, OWNER, makeDeps());
    expect(d).toMatchObject({ allowed: false, status: 404 });
  });

  it('allows the owner and denies a stranger', async () => {
    const inv = { userId: OWNER, galaxyInvocationId: 'gx-1' };
    expect((await decideInvocationAccess(inv, OWNER, makeDeps())).allowed).toBe(true);
    expect(await decideInvocationAccess(inv, STRANGER, makeDeps())).toMatchObject({ allowed: false, status: 403 });
  });

  it('allows a project member via the linked run', async () => {
    const inv = { userId: OWNER, galaxyInvocationId: 'gx-1' };
    const d = await decideInvocationAccess(inv, MEMBER, makeDeps());
    expect(d.allowed).toBe(true);
  });
});
