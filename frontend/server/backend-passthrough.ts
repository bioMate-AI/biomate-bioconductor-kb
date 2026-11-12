/**
 * The generic passthrough to the Python backend (the "Galaxy" server), shared by the ind-report,
 * regulatory, grounded, DL / generate / perception / datasets / route proxies in routes.ts.
 * Moved out of routes.ts (2026-11-12) so its path confinement is behaviour-tested on a real
 * express app (backend-passthrough.test.ts).
 */
import { fetchGalaxyAsUser } from "./galaxy-user-fetch";
import { proxyTarget, rejectProxyPath } from "./proxy-path";

/**
 * Forward an /api/... request to the Python backend (the "Galaxy" server) as the signed-in user:
 * same path + query, JSON body for methods other than GET/HEAD/DELETE, and the response relayed
 * back (JSON parsed, otherwise raw bytes; Content-Type and Content-Disposition passed through).
 * The key and its mid-session recovery come from fetchGalaxyAsUser. Shared by the ind-report,
 * regulatory, grounded and DL passthroughs (previously four copies of this body).
 */
export function backendPassthrough(label: string) {
  return async (req: any, res: any) => {
    try {
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      // Only a path under the prefix this passthrough is mounted on (proxy-path.ts).
      const target = proxyTarget(req);
      if (!target.ok) return rejectProxyPath(res, target);
      const fullPath = `${target.path}${target.query}`;
      const fetchOpts: RequestInit = {
        method: req.method.toUpperCase(),
        headers: { 'Content-Type': req.headers['content-type'] || 'application/json' },
        signal: AbortSignal.timeout(120000),
      };
      if (!['GET', 'HEAD', 'DELETE'].includes(fetchOpts.method as string)) {
        fetchOpts.body = JSON.stringify(req.body);
      }
      const resp = await fetchGalaxyAsUser(req, `${galaxyUrl}${fullPath}`, fetchOpts);
      const contentType = resp.headers.get('content-type') || 'application/json';
      res.setHeader('Content-Type', contentType);
      const cd = resp.headers.get('content-disposition');
      if (cd) res.setHeader('Content-Disposition', cd);
      res.status(resp.status);
      if (contentType.includes('application/json')) {
        const data = await resp.json().catch(() => ({}));
        return res.json(data);
      }
      return res.send(Buffer.from(await resp.arrayBuffer()));
    } catch (err: any) {
      const status = err.response?.status || 502;
      return res.status(status).json({ error: `${label} proxy error`, detail: err.message });
    }
  };
}

