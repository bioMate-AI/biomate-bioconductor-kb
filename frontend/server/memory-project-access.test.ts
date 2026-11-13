import { describe, expect, it, vi } from 'vitest';
import { memoryProjectAccess, memoryProjectUpdate } from './memory-project-access';

function run(mw: any, req: any) {
  const res: any = { statusCode: 200, body: null, status(c: number) { this.statusCode = c; return this; }, json(b: any) { this.body = b; return this; } };
  const next = vi.fn();
  return mw(req, res, next).then(() => ({ res, next }));
}
const checks = {
  member: async (p: string, u: string) => p === 'p1' && (u === 'owner' || u === 'viewer' || u === 'editor'),
  editor: async (p: string, u: string) => p === 'p1' && (u === 'owner' || u === 'editor'),
};

describe('project memory routes are authorised (committee audit: any login could rewrite/take over a project)', () => {
  it('a stranger gets 404 on read and write', async () => {
    for (const level of ['member', 'editor'] as const) {
      const { res, next } = await run(memoryProjectAccess(level, checks), { params: { projectId: 'p1' }, user: { id: 'stranger' } });
      expect(res.statusCode).toBe(404); expect(next).not.toHaveBeenCalled();
    }
  });
  it('a viewer can read but not write; an editor can write', async () => {
    expect((await run(memoryProjectAccess('member', checks), { params: { projectId: 'p1' }, user: { id: 'viewer' } })).next).toHaveBeenCalledWith();
    expect((await run(memoryProjectAccess('editor', checks), { params: { projectId: 'p1' }, user: { id: 'viewer' } })).res.statusCode).toBe(404);
    expect((await run(memoryProjectAccess('editor', checks), { params: { projectId: 'p1' }, user: { id: 'editor' } })).next).toHaveBeenCalledWith();
  });
  it('no user → 404; the shadowed "search" route passes through', async () => {
    expect((await run(memoryProjectAccess('member', checks), { params: { projectId: 'p1' } })).res.statusCode).toBe(404);
    expect((await run(memoryProjectAccess('member', checks), { params: { projectId: 'search' }, user: { id: 'x' } })).next).toHaveBeenCalledWith('route');
  });
  it('an update can never change ownership or identity', () => {
    expect(memoryProjectUpdate({ researchGoal: 'r', userId: 'attacker', id: 'x', createdAt: 1, name: 'n' })).toEqual({ researchGoal: 'r', name: 'n' });
  });
});
