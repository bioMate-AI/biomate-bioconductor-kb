import { describe, expect, it, vi } from 'vitest';
import { waitForInteractiveSession, type InteractiveReadinessDependencies } from './interactive-session-readiness';
function setup(states: string[] = ['running']) {
 let clock = 0, index = 0;
 const deps: InteractiveReadinessDependencies = {
  getJob: vi.fn(async () => ({ state: states[Math.min(index++, states.length - 1)] })),
  tokenForJob: vi.fn(() => ({ token: 'token123', entry_url: 'ipython/lab' })),
  targetForToken: vi.fn(() => ({ host: '172.17.0.1', port: 32001 })),
  probe: vi.fn(async () => 200), now: () => clock,
  sleep: vi.fn(async ms => { clock += ms; }),
 }; return deps;
}
describe('interactive session readiness', () => {
 it('waits for queued job and unhealthy HTTP to become a running reachable session', async () => {
  const deps = setup(['queued', 'running', 'running', 'running']);
  vi.mocked(deps.probe!).mockResolvedValueOnce(503).mockResolvedValueOnce(200);
  expect(await waitForInteractiveSession('owned-job', deps)).toEqual({ ready: true, url: '/interactive/token123/ipython/lab' });
  expect(deps.getJob).toHaveBeenCalledWith('owned-job');
  expect(deps.probe).toHaveBeenCalledTimes(2);
  expect(deps.probe).toHaveBeenCalledWith('http://172.17.0.1:32001/ipython/lab', 2000);
 });
 it.each(['error','deleted','ok','stopped'])('rejects %s even when an early token exists', async state => {
  const deps = setup([state]); expect(await waitForInteractiveSession('owned-job', deps)).toEqual({ ready: false, reason: 'failed' });
  expect(deps.tokenForJob).not.toHaveBeenCalled(); expect(deps.probe).not.toHaveBeenCalled();
 });
 it('rejects a terminal transition after a healthy HTTP response', async () => {
  const deps = setup(['running','error']); expect(await waitForInteractiveSession('owned-job', deps)).toEqual({ ready: false, reason: 'failed' });
 });
 it('does not return an entry token without a validated target and times out with bounded calls', async () => {
  const deps = setup(); vi.mocked(deps.targetForToken).mockReturnValue(null);
  expect(await waitForInteractiveSession('owned-job', deps, { timeoutMs: 2500 })).toEqual({ ready: false, reason: 'timeout' });
  expect(deps.getJob).toHaveBeenCalledTimes(3); expect(deps.probe).not.toHaveBeenCalled();
 });
 it('fails closed on ownership lookup failure and does not probe a target', async () => {
  const deps = setup(); vi.mocked(deps.getJob).mockRejectedValue(new Error('private response'));
  expect(await waitForInteractiveSession('foreign-job', deps)).toEqual({ ready: false, reason: 'unavailable' });
  expect(deps.probe).not.toHaveBeenCalled();
 });
 it('cannot accept invalid port or traversal path and honors attempt bound', async () => {
  const deps = setup(); vi.mocked(deps.targetForToken).mockReturnValue({ host: 'host', port: 70000 });
  expect((await waitForInteractiveSession('job', deps, { maxAttempts: 2 })).ready).toBe(false);
  expect(deps.getJob).toHaveBeenCalledTimes(2); expect(deps.probe).not.toHaveBeenCalled();
 });
});
