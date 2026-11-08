import { afterEach, expect, it, vi } from 'vitest';
import { authorizeModelProject, fetchOwnedModelSurface, isTrackedAdaptJob } from './model-surface-access';
afterEach(() => { vi.unstubAllEnvs(); vi.unstubAllGlobals(); });
it('denies anonymous and foreign project access before privileged backend lookup', async () => {
 const projects = vi.fn(async () => [{ id: 'owned-project' }]);
 await expect(authorizeModelProject(undefined, undefined, projects)).rejects.toMatchObject({status:401});
 expect(projects).not.toHaveBeenCalled();
 await expect(authorizeModelProject('owner', 'foreign-project', projects)).rejects.toMatchObject({status:403});
 await expect(authorizeModelProject('owner', ['owned-project'], projects)).rejects.toMatchObject({status:403});
 await authorizeModelProject('owner', 'owned-project', projects);
});
it('overwrites caller headers with server-owned identity and credentials', async () => {
 vi.stubEnv('GALAXY_API_KEY','server-test-key'); vi.stubEnv('GALAXY_URL','http://backend');
 const fetcher = vi.fn(async () => ({status:200})); vi.stubGlobal('fetch',fetcher);
 await fetchOwnedModelSurface('real-owner','/api/models',{ headers:{'X-API-Key':'spoof','X-BioMate-User-Id':'victim'} });
 expect(fetcher).toHaveBeenCalledWith('http://backend/api/models',expect.objectContaining({headers:{'Content-Type':'application/json','X-API-Key':'server-test-key','X-BioMate-User-Id':'real-owner'}}));
});
it('never promotes arbitrary routes or anonymous calls to an administrator', async () => {
 vi.stubEnv('GALAXY_API_KEY','server-test-key'); vi.stubEnv('GALAXY_URL','http://backend');
 const fetcher=vi.fn();vi.stubGlobal('fetch',fetcher);
 for (const path of ['/api/models/../../users','https://foreign.example/api/models','/api/users'])
  await expect(fetchOwnedModelSurface('owner',path)).rejects.toMatchObject({status:400});
 await expect(fetchOwnedModelSurface(undefined,'/api/models')).rejects.toMatchObject({status:401});
 expect(fetcher).not.toHaveBeenCalled();
});
it('fails closed without configured privileged bridge credentials', async () => {
 vi.stubEnv('GALAXY_API_KEY','');
 await expect(fetchOwnedModelSurface('owner','/api/models')).rejects.toMatchObject({status:503});
});

it('never invents queued executions from denied, empty or untracked backend responses', () => {
 for (const [status, body] of [[403,{error:'denied'}],[409,{error:'unbound data'}],[200,{}],[200,{job_id:'j'}],[200,{job_id:'',status:'queued'}]])
  expect(isTrackedAdaptJob(status as number,body)).toBe(false);
 expect(isTrackedAdaptJob(200,{job_id:'real-job',status:'succeeded'})).toBe(true);
 expect(isTrackedAdaptJob(200,{job_id:'real-job',status:'failed'})).toBe(true);
});
