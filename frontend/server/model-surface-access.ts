/** Trusted Node-to-Galaxy bridge for owner-scoped Models surfaces. */
export class ModelSurfaceAccessError extends Error {
 constructor(public status: number, message: string) { super(message); }
}
export async function authorizeModelProject(userId: string | undefined, project: unknown,
 getProjects: (id: string) => Promise<Array<{id: string}>>): Promise<void> {
 if (!userId) throw new ModelSurfaceAccessError(401, 'Authentication required');
 if (project === undefined) return;
 if (typeof project !== 'string' || !(await getProjects(userId)).some(item => item.id === project))
  throw new ModelSurfaceAccessError(403, 'Project access denied');
}
export async function fetchOwnedModelSurface(userId: string | undefined, path: string, init: RequestInit = {}): Promise<Response> {
 if (!userId) throw new ModelSurfaceAccessError(401, 'Authentication required');
 const key = process.env.GALAXY_API_KEY;
 if (!key) throw new ModelSurfaceAccessError(503, 'Models service is not configured');
 const url = new URL(path, process.env.GALAXY_URL || 'http://localhost:8081');
 if (!/^\/api\/(?:models(?:\/|$)|model-tracks\/|inference\/)/.test(url.pathname)
   || url.origin !== new URL(process.env.GALAXY_URL || 'http://localhost:8081').origin)
  throw new ModelSurfaceAccessError(400, 'Invalid Models service path');
 return fetch(url.toString(), { ...init, headers: {
  'Content-Type': 'application/json', 'X-API-Key': key, 'X-BioMate-User-Id': userId,
 }, signal: AbortSignal.timeout(120000) });
}
/** Only a real accepted backend job may create a first-class execution record. */
export function isTrackedAdaptJob(status: number, body: any): boolean {
 return status >= 200 && status < 300 && typeof body?.job_id === 'string' && !!body.job_id.trim()
  && ['queued','running','succeeded','failed','cancelled'].includes(body.status);
}
