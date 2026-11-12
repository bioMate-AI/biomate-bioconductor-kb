/**
 * Path confinement for every passthrough that forwards the caller's request path to another
 * server (the Python backend, the MCP server).
 *
 * Express matches a route on the RAW request path: `/api/generate/../perception/folder_profile`
 * and `/api/generate/%2e%2e/perception/profile` both match `app.all("/api/generate/*")`. The
 * passthrough then built `${GALAXY_URL}${req.path}` and fetch() (WHATWG URL) normalised the dot
 * segments, so the request reached `/api/perception/folder_profile` — a route this server gates
 * (perceptionProxyGate, requireDatasetAccess) — with the caller's body and, for an anonymous
 * caller on an optionalAuth prefix, the shared GALAXY_API_KEY (2026-11-12 audit NEW-3).
 *
 * The rule: a passthrough mounted on prefix P forwards only a path that is P or under P/ and
 * that no decoding or normalisation can move: no `.`/`..` segment at ANY decoding depth (`..`,
 * `%2e%2e`, `%252e%252e`, `..%2f`, …), no backslash (WHATWG treats `\` as `/`), no control
 * characters, and nothing fetch() would rewrite. Encoded slashes inside a segment stay allowed
 * (dataset refs are URL-encoded S3 keys, `/api/datasets/projects%2F…/lineage`) — they are only
 * refused when they smuggle a dot segment.
 */

export type ProxyPath =
  | { ok: true; path: string; query: string }
  | { ok: false; reason: string };

const MAX_DECODE_DEPTH = 5;
// eslint-disable-next-line no-control-regex
const CONTROL = /[\u0000-\u001f\u007f]/;

/** One round of %XX decoding, byte-wise and tolerant: an invalid sequence stays literal (a file
 *  named `50%.csv` must not make a later `%2e%2e` invisible). ASCII is all the checks need. */
function decodeOnce(s: string): string {
  return s.replace(/%([0-9a-fA-F]{2})/g, (_m, h: string) => String.fromCharCode(parseInt(h, 16)));
}

function underPrefix(path: string, prefix: string): boolean {
  return path === prefix || path.startsWith(prefix + "/");
}

/**
 * Check `rawUrl` (path + optional query, as received) against `prefix` (no trailing slash).
 * Returns the path to forward (unchanged — it is already canonical) and the query string
 * (including its leading `?`, or "").
 */
export function confineProxyPath(rawUrl: string, prefix: string): ProxyPath {
  const q = rawUrl.indexOf("?");
  const rawPath = q >= 0 ? rawUrl.slice(0, q) : rawUrl;
  const query = q >= 0 ? rawUrl.slice(q) : "";
  const pre = prefix.replace(/\/+$/, "");
  if (!pre.startsWith("/")) return { ok: false, reason: "no_prefix" };
  if (!rawPath.startsWith("/") || rawPath.includes("#")) return { ok: false, reason: "malformed" };
  if (!underPrefix(rawPath, pre)) return { ok: false, reason: "outside_prefix" };

  let stage = rawPath;
  for (let depth = 0; ; depth++) {
    if (stage.includes("\\")) return { ok: false, reason: "backslash" };
    if (CONTROL.test(stage)) return { ok: false, reason: "control_char" };
    if (stage.split("/").some((seg) => seg === "." || seg === "..")) return { ok: false, reason: "dot_segment" };
    if (!underPrefix(stage, pre)) return { ok: false, reason: "outside_prefix" };
    const next = decodeOnce(stage);
    if (next === stage) break;
    if (depth >= MAX_DECODE_DEPTH) return { ok: false, reason: "over_encoded" };
    stage = next;
  }
  // Whatever fetch()/new URL would do to the path must be nothing.
  let normalised: string;
  try {
    normalised = new URL(rawPath, "http://proxy.internal").pathname;
  } catch {
    return { ok: false, reason: "malformed" };
  }
  if (normalised !== rawPath) return { ok: false, reason: "not_canonical" };
  return { ok: true, path: rawPath, query };
}

/** The literal prefix of the route that matched `req`: `/api/generate/*` → `/api/generate`,
 *  `/oauth/tools/:name` → `/oauth/tools`, an exact path → itself. Null for a regex route. */
export function routePrefix(req: any): string | null {
  const p = req?.route?.path;
  if (typeof p !== "string" || !p.startsWith("/")) return null;
  const out: string[] = [];
  for (const seg of p.split("/").slice(1)) {
    if (/[*:(?+]/.test(seg)) break;
    out.push(seg);
  }
  return "/" + out.join("/");
}

/**
 * The confined path + query of an incoming request, against `prefix` or, by default, the
 * literal prefix of the route that matched it. Uses req.originalUrl (the raw request target).
 */
export function proxyTarget(req: any, prefix?: string): ProxyPath {
  const pre = prefix ?? routePrefix(req);
  if (!pre) return { ok: false, reason: "no_prefix" };
  return confineProxyPath(String(req.originalUrl ?? req.url ?? ""), pre);
}

/** The refusal every passthrough sends for a path outside its prefix. */
export function rejectProxyPath(res: any, out: { reason: string }): void {
  res.status(400).json({ error: "invalid_path", reason: out.reason });
}
