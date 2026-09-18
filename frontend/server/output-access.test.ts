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

// ── L1c: canonical `${runId}:${s3Key}` id path ───────────────────────────────
// The reproducibility record + findings now emit outputs with id
// `${runId}:${s3Key}`. Unlike the OutputDataset-PK path (in-memory, 404s after a
// restart), this resolves the OWNER from the persisted ExecutionRun and serves
// the matching output from runsOutputsService.list(runId).
const RUN_ID = 'run-uuid-1';
const S3_KEY = 'nextflow/outputs/dom/hash/result.csv';
const CANON_ID = `${RUN_ID}:${S3_KEY}`;

function makeCanonDeps(over: Partial<OutputAccessDeps> = {}): OutputAccessDeps {
  return {
    // The legacy PK store misses entirely for a canonical id (no OutputDataset
    // row) — exactly the restart case the canonical path exists to survive.
    getOutput: vi.fn(async () => undefined),
    getInvocation: vi.fn(async () => undefined),
    getRunByGalaxyId: vi.fn(async () => undefined),
    getInvocationByGalaxyId: vi.fn(async () => undefined),
    getUserProjects: vi.fn(async (uid) => (uid === MEMBER ? [{ id: PROJECT }] : [])),
    getExecutionRun: vi.fn(async (id) =>
      id === RUN_ID ? { userId: OWNER, projectId: PROJECT } : undefined),
    getExecutionRunByGalaxyId: vi.fn(async () => undefined),
    listRunOutputs: vi.fn(async (runId) =>
      runId === RUN_ID
        ? [{ id: CANON_ID, name: 'result.csv', s3Uri: `s3://bucket/${S3_KEY}` }]
        : []),
    ...over,
  };
}

describe('decideOutputAccess — canonical-id path (L1c)', () => {
  it('allows the owner via the ExecutionRun (durable across restart)', async () => {
    const deps = makeCanonDeps();
    const d = await decideOutputAccess(CANON_ID, OWNER, deps);
    expect(d.allowed).toBe(true);
    if (d.allowed) {
      expect(d.via).toBe('owner');
      expect(d.output.id).toBe(CANON_ID);
      expect((d.output as any).s3Uri).toBe(`s3://bucket/${S3_KEY}`);
    }
    // Authorized at the RUN level — never touched the legacy OutputDataset store.
    expect(deps.getOutput).not.toHaveBeenCalled();
    // Mutation check: the run WAS resolved (removing that call would break auth).
    expect(deps.getExecutionRun).toHaveBeenCalledWith(RUN_ID);
  });

  it('allows a project member via the run project', async () => {
    const d = await decideOutputAccess(CANON_ID, MEMBER, makeCanonDeps());
    expect(d.allowed).toBe(true);
    if (d.allowed) expect(d.via).toBe('project_member');
  });

  it('denies a stranger with 403 (IDOR blocked on canonical ids)', async () => {
    const d = await decideOutputAccess(CANON_ID, STRANGER, makeCanonDeps());
    expect(d).toMatchObject({ allowed: false, status: 403 });
  });

  it('denies an unauthenticated caller with 401', async () => {
    const d = await decideOutputAccess(CANON_ID, null, makeCanonDeps());
    expect(d).toMatchObject({ allowed: false, status: 401 });
  });

  it('404s when the run is authorized but the file is not in its output set', async () => {
    const deps = makeCanonDeps({ listRunOutputs: vi.fn(async () => []) });
    const d = await decideOutputAccess(CANON_ID, OWNER, deps);
    expect(d).toMatchObject({ allowed: false, status: 404 });
  });

  it('falls through to the legacy PK path when the runId prefix is not a real run', async () => {
    // Canonical-shaped id whose prefix resolves to no run → the canonical path
    // returns undefined and the legacy getOutput lookup takes over. Here the
    // legacy store also misses → 404 (not a false 403).
    const deps = makeCanonDeps({
      getExecutionRun: vi.fn(async () => undefined),
      getExecutionRunByGalaxyId: vi.fn(async () => undefined),
    });
    const d = await decideOutputAccess('not-a-run:some/key.txt', OWNER, deps);
    expect(d).toMatchObject({ allowed: false, status: 404 });
    // It genuinely tried the legacy path (mutation check).
    expect(deps.getOutput).toHaveBeenCalledWith('not-a-run:some/key.txt');
  });

  it('resolves the run by galaxy id when getExecutionRun misses', async () => {
    const deps = makeCanonDeps({
      getExecutionRun: vi.fn(async () => undefined),
      getExecutionRunByGalaxyId: vi.fn(async (gid) =>
        gid === RUN_ID ? { userId: OWNER, projectId: PROJECT } : undefined),
    });
    const d = await decideOutputAccess(CANON_ID, OWNER, deps);
    expect(d.allowed).toBe(true);
  });
});

describe('decideOutputAccess — legacy OutputDataset-PK path still works', () => {
  it('resolves a legacy PK id through output → invocation → run when canonical deps are present', async () => {
    // out-1 has NO ':' → skips the canonical path → legacy PK lookup succeeds.
    const deps = makeDeps({
      getExecutionRun: vi.fn(async () => undefined),
      getExecutionRunByGalaxyId: vi.fn(async () => undefined),
      listRunOutputs: vi.fn(async () => []),
    });
    const owner = await decideOutputAccess('out-1', OWNER, deps);
    expect(owner.allowed).toBe(true);
    if (owner.allowed) expect(owner.output.id).toBe('out-1');
    const stranger = await decideOutputAccess('out-1', STRANGER, deps);
    expect(stranger).toMatchObject({ allowed: false, status: 403 });
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
