/**
 * Gate for the generic /api/perception/* proxy (routes.ts → Galaxy perception.py).
 *
 * The proxy authorizes ONE dataset reference — body.datasetRef, through requireDatasetAccess.
 * Anything else in the body that names data would reach the backend unchecked: folder_profile
 * reads every files[].datasetRef it is given (any path or S3 key), and the backend also accepts
 * a snake_case `dataset_ref`. So the proxy forwards only an allowlist:
 *   POST /api/perception/profile  {datasetRef, name}
 *   POST /api/perception/rows     {datasetRef, name, offset, limit}
 * folder_profile is NOT exposed here: GET /api/projects/:id/folders/profile calls it after the
 * membership check, with files resolved from project_files; preview_image (TIFF → PNG) is NOT
 * exposed either: GET /api/projects/:id/files/:fileId/preview.png calls it with the file's own
 * project_files key. `folderContext` is dropped (the
 * server attaches its own, attachFolderContext). Any other field → 400; any other path → 404.
 */
const ALLOWED: Record<string, ReadonlySet<string>> = {
  "/api/perception/profile": new Set(["datasetRef", "name"]),
  "/api/perception/rows": new Set(["datasetRef", "name", "offset", "limit"]),
};
const SERVER_OWNED = new Set(["folderContext"]);

export type PerceptionGateResult =
  | { ok: true; body: Record<string, unknown> }
  | { ok: false; status: 400 | 404 | 405; error: string; fields?: string[] };

export function gatePerceptionRequest(method: string, path: string, body: unknown): PerceptionGateResult {
  const allowed = ALLOWED[path.replace(/\/+$/, "")];
  if (!allowed) return { ok: false, status: 404, error: "not_found" };
  if (String(method).toUpperCase() !== "POST") return { ok: false, status: 405, error: "method_not_allowed" };
  if (body === undefined || body === null) body = {};
  if (typeof body !== "object" || Array.isArray(body)) return { ok: false, status: 400, error: "invalid_body" };
  const extra = Object.keys(body as object).filter((k) => !allowed.has(k) && !SERVER_OWNED.has(k));
  if (extra.length) return { ok: false, status: 400, error: "unexpected_fields", fields: extra };
  const clean: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(body as Record<string, unknown>)) if (allowed.has(k)) clean[k] = v;
  return { ok: true, body: clean };
}

/** Express middleware form: replaces req.body with the allowlisted body, or answers the refusal. */
export function perceptionProxyGate(req: any, res: any, next: () => void): void {
  const pathname = new URL(req.originalUrl, "http://internal").pathname;
  const out = gatePerceptionRequest(req.method, pathname, req.body);
  if (!out.ok) {
    res.status(out.status).json({ error: out.error, ...(out.fields ? { fields: out.fields } : {}) });
    return;
  }
  req.body = out.body;
  next();
}
