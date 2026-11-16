import { describe, expect, it, vi } from 'vitest';
import { createLegacyRunGuard, legacyRunUpdateSchema } from './legacy-run-access';
function response() {
 const res = { status: vi.fn(), json: vi.fn() };
 res.status.mockReturnValue(res); res.json.mockReturnValue(res);
 return res;
}
const own = { id: 'canonical-id', userId: 'owner', projectId: 'project' };
const deps = () => ({ resolveRun: vi.fn(async (): Promise<typeof own | undefined> => own), getUserProjects: vi.fn(async (): Promise<Array<{ id: string }>> => []) });
describe('legacy run endpoint boundary', () => {
 it('rejects anonymous callers before resolving or proxying a run', async () => {
  const d = deps(), res = response(), proxy = vi.fn();
  await createLegacyRunGuard(d, 'read')({ params: { id: 'backend-alias' } }, res, proxy);
  expect(res.status).toHaveBeenCalledWith(401);expect(d.resolveRun).not.toHaveBeenCalled();expect(proxy).not.toHaveBeenCalled();
 });
 it('rejects a stranger and does not reach the privileged backend', async () => {
  const d = deps(), res = response(), proxy = vi.fn();
  await createLegacyRunGuard(d, 'read')({ user: { id: 'stranger' }, params: { id: 'backend-alias' } }, res, proxy);
  expect(res.status).toHaveBeenCalledWith(403);expect(proxy).not.toHaveBeenCalled();
 });
 it('allows an owner alias and normalizes it to the registered identity', async () => {
  const d = deps(), res = response(), proxy = vi.fn(), req = { user: { id: 'owner' }, params: { id: 'backend-alias' } };
  await createLegacyRunGuard(d, 'read')(req, res, proxy);
  expect(req.params.id).toBe('canonical-id');expect((req as any).authorizedLegacyRun).toEqual(own);expect(proxy).toHaveBeenCalledTimes(1);
 });
 it('preserves project-member reads without granting member mutation rights', async () => {
  const d = deps();d.getUserProjects.mockResolvedValue([{ id: 'project' }]);
  const req = () => ({ user: { id: 'member' }, params: { id: 'backend-alias' } });
  const read = vi.fn(), write = vi.fn(), res = response();
  await createLegacyRunGuard(d, 'read')(req(), res, read);
  await createLegacyRunGuard(d, 'write')(req(), res, write);
  expect(read).toHaveBeenCalledTimes(1);expect(write).not.toHaveBeenCalled();expect(res.status).toHaveBeenCalledWith(403);
 });
 it('never proxies unregistered raw IDs and fails closed on lookup errors', async () => {
  const d = deps(), req = { user: { id: 'owner' }, params: { id: 'unknown' } }, res = response(), proxy = vi.fn();
  d.resolveRun.mockResolvedValue(undefined);
  await createLegacyRunGuard(d, 'write', 'id')(req, res, proxy);expect(res.status).toHaveBeenCalledWith(404);
  d.resolveRun.mockRejectedValue(new Error('database unavailable'));
  await createLegacyRunGuard(d, 'write', 'id')(req, res, proxy);expect(res.status).toHaveBeenCalledWith(503);expect(proxy).not.toHaveBeenCalled();
 });
 it('protects the alternate rerun parameter name', async () => {
  const d = deps(), req = { user: { id: 'owner' }, params: { runId: 'backend-alias' } }, proxy = vi.fn();
  await createLegacyRunGuard(d, 'write', 'runId')(req, response(), proxy);
  expect(req.params.runId).toBe('canonical-id');expect(proxy).toHaveBeenCalledTimes(1);
 });
});
it('allows real parameter overrides but rejects forged output/owner/launch records', () => {
 expect(legacyRunUpdateSchema.safeParse({ parameters: { version: 2, toolParameters: { train: { alpha: 0.05 } } } }).success).toBe(true);
 // workflowName is an allowed display-label edit (owner-gated), but must be non-empty and bounded.
 expect(legacyRunUpdateSchema.safeParse({ workflowName: 'My BACE potency model' }).success).toBe(true);
 expect(legacyRunUpdateSchema.safeParse({ workflowName: '' }).success).toBe(false);
 expect(legacyRunUpdateSchema.safeParse({ workflowName: 'x'.repeat(201) }).success).toBe(false);
 for (const key of ['userId','projectId','workflowDefinition','execution','inputBindings','id']) {
  expect(legacyRunUpdateSchema.safeParse({ [key]: key === 'execution' ? { outputs: { private: 's3://other/private' }, trainingLaunchParameters: {} } : 'forged' }).success).toBe(false);
 }
});
