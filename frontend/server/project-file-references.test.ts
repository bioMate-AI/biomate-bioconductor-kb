import { describe, it, expect, vi } from 'vitest';
import {
  resolveProjectFileReferences,
  type ProjectFileResolverDeps,
} from './project-file-references';

const PID = '11111111-1111-1111-1111-111111111111';
const UID = 'user-42';
const FILE_A = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const FILE_B = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

function makeDeps(over: Partial<ProjectFileResolverDeps> = {}): ProjectFileResolverDeps {
  return {
    isOwnerOrMember: vi.fn(async () => true),
    queryFilesByIds: vi.fn(async (_pid, ids) =>
      ids
        .filter((id) => id === FILE_A || id === FILE_B)
        .map((id) => ({
          id,
          name: id === FILE_A ? 'comparison-a.csv' : 'comparison-b.csv',
          s3_key: `projects/${PID}/inputs/${id === FILE_A ? 'comparison-a.csv' : 'comparison-b.csv'}`,
        })),
    ),
    stageToBatch: vi.fn(async (_s3Key, pid, fileName) => `s3://biomate-nextflow-work/uploads/project-${pid}/${fileName}`),
    ...over,
  };
}

describe('resolveProjectFileReferences', () => {
  it('resolves authorized project files to runnable, staged entries by exact id', async () => {
    const deps = makeDeps();
    const out = await resolveProjectFileReferences(
      [{ id: FILE_A }, { id: FILE_B }],
      PID,
      UID,
      deps,
    );
    expect(out.size).toBe(2);
    const a = out.get(FILE_A)!;
    expect(a.name).toBe('comparison-a.csv');
    expect(a.type).toBe('project file');
    expect(a.projectFileId).toBe(FILE_A);
    expect(a.projectId).toBe(PID);
    expect(a.s3_key).toContain('comparison-a.csv');
    expect(a.s3_uri).toBe(`s3://biomate-nextflow-work/uploads/project-${PID}/comparison-a.csv`);
  });

  it('blocks resolution when the caller is not owner or member (no IDOR)', async () => {
    const deps = makeDeps({ isOwnerOrMember: vi.fn(async () => false) });
    const out = await resolveProjectFileReferences([{ id: FILE_A }], PID, UID, deps);
    expect(out.size).toBe(0);
    // Must not even query files for an unauthorized project.
    expect(deps.queryFilesByIds).not.toHaveBeenCalled();
  });

  it('never substitutes a same-named or unknown file — unknown id is absent', async () => {
    const deps = makeDeps();
    const unknown = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    const out = await resolveProjectFileReferences([{ id: unknown }], PID, UID, deps);
    expect(out.has(unknown)).toBe(false);
    expect(out.size).toBe(0);
  });

  it('skips non-UUID ids (e.g. Galaxy dataset ids) without querying', async () => {
    const deps = makeDeps();
    const out = await resolveProjectFileReferences(
      [{ id: 'f2db41e1fa331b3e' }],
      PID,
      UID,
      deps,
    );
    expect(out.size).toBe(0);
    expect(deps.isOwnerOrMember).not.toHaveBeenCalled();
    expect(deps.queryFilesByIds).not.toHaveBeenCalled();
  });

  it('returns empty when project or user is missing (cannot authorize)', async () => {
    const deps = makeDeps();
    expect((await resolveProjectFileReferences([{ id: FILE_A }], undefined, UID, deps)).size).toBe(0);
    expect((await resolveProjectFileReferences([{ id: FILE_A }], PID, undefined, deps)).size).toBe(0);
    expect(deps.queryFilesByIds).not.toHaveBeenCalled();
  });

  it('resolves the file even when staging fails, with s3_uri null', async () => {
    const deps = makeDeps({ stageToBatch: vi.fn(async () => undefined) });
    const out = await resolveProjectFileReferences([{ id: FILE_A }], PID, UID, deps);
    const a = out.get(FILE_A)!;
    expect(a).toBeTruthy();
    expect(a.s3_uri).toBeNull();
    expect(a.s3_key).toContain('comparison-a.csv');
  });

  it('uses the session cache and stages each file at most once', async () => {
    const store: Record<string, string> = {};
    const deps = makeDeps({
      cacheGet: (id) => store[id],
      cacheSet: (id, uri) => { store[id] = uri; },
    });
    await resolveProjectFileReferences([{ id: FILE_A }], PID, UID, deps);
    await resolveProjectFileReferences([{ id: FILE_A }], PID, UID, deps);
    expect(deps.stageToBatch).toHaveBeenCalledTimes(1);
    expect(store[FILE_A]).toContain('comparison-a.csv');
  });

  it('dedupes repeated ids in a single request', async () => {
    const deps = makeDeps();
    const out = await resolveProjectFileReferences(
      [{ id: FILE_A }, { id: FILE_A }],
      PID,
      UID,
      deps,
    );
    expect(out.size).toBe(1);
    expect(deps.stageToBatch).toHaveBeenCalledTimes(1);
  });
});
