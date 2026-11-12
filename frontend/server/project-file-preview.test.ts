// @vitest-environment node
/**
 * GET /api/projects/:id/files/:fileId/preview.png — a TIFF drawn as PNG by the Python renderer
 * (backend galaxy/ai/tiff_preview.py, POST /api/perception/preview_image; its behaviour is covered
 * by backend/lib/galaxy/ai/tests/test_tiff_preview.py). Route BEHAVIOUR over loopback HTTP against
 * the real registerProjectRoutes, with Postgres + S3 replaced by project-files-fake-store.ts and
 * Galaxy by a fake fetch that records what the route sent.
 *
 *   access   owner / member only (a non-member and an unknown file → 404, nothing sent);
 *   ref      the backend gets the project_files key + projectId — a client cannot point it at
 *            another key, project or path (query/body fields are ignored; only series/page count);
 *   bytes    PNG + X-Preview-Info passed through; renderer refusals keep their code + reason;
 *   cache    ETag from content_hash + selection → 304 on revalidation; no-store on errors.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import type { AddressInfo } from "net";
import express from "express";
import type { Server } from "http";
import { fakeStore as store } from "./project-files-fake-store";

const httpFetch = globalThis.fetch;
const P = "11111111-1111-4111-8111-111111111111";
const OTHER = "22222222-2222-4222-8222-222222222222";
const OWNER = "owner-1", MEMBER = "member-2", STRANGER = "stranger-3";
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4]);
const INFO = JSON.stringify({ seriesCount: 1, planeCount: 3, plane: 0, dtype: "uint16", shape: [3, 20, 24], stretch: { percentiles: [0.5, 99.5], low: [10], high: [3990] } });

const galaxyFetch = vi.fn();
vi.mock("./db", async () => ({ pool: (await import("./project-files-fake-store")).fakeStore.pool }));
vi.mock("./s3-client", async () => ({ s3Service: (await import("./project-files-fake-store")).fakeStore.s3 }));
vi.mock("./auth-middleware", () => ({ authenticateToken: (_q: any, _s: any, next: any) => next() }));
vi.mock("./memory-repository", () => ({
  memoryService: {
    projects: { getProject: async (id: string) => (
      id === "11111111-1111-4111-8111-111111111111" ? { id, userId: "owner-1" }
      : id === "22222222-2222-4222-8222-222222222222" ? { id, userId: "stranger-3" } : null) },
    ensureLtmUser: async () => {},
  },
}));
vi.mock("./galaxy-user-fetch", () => ({
  fetchGalaxyAsUser: (...a: any[]) => galaxyFetch(...a),
  galaxyBaseUrl: () => "http://galaxy.test",
}));

let server: Server;
let base = "";

beforeAll(async () => {
  const { registerProjectRoutes } = await import("./project-routes");
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    const as = req.headers["x-test-user"];
    (req as any).user = { id: typeof as === "string" ? as : OWNER };
    next();
  });
  registerProjectRoutes(app);
  await new Promise<void>((r) => { server = app.listen(0, "127.0.0.1", () => r()); });
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
afterAll(() => server?.close());
beforeEach(() => {
  vi.clearAllMocks();
  store.reset();
  store.members.push({ project_id: P, user_id: MEMBER, role: "viewer" });
  // A fresh Response per call (a body can be read once).
  galaxyFetch.mockImplementation(async () => new Response(PNG, { status: 200, headers: { "Content-Type": "image/png", "X-Preview-Info": INFO } }));
});

const key = (name: string, pid = P) => `projects/${pid}/inputs/${name}`;
const get = (path: string, headers: Record<string, string> = {}) => httpFetch(`${base}${path}`, { headers });
const previewPath = (fileId: string, q = "", pid = P) => `/api/projects/${pid}/files/${fileId}/preview.png${q}`;
const sent = () => JSON.parse(galaxyFetch.mock.calls[0][2].body);

describe("GET /files/:fileId/preview.png", () => {
  it("renders the project_files object: PNG + X-Preview-Info passed through, backend sent the DB key + projectId", async () => {
    const f = store.addFile({ project_id: P, name: "imgs/stack.ome.tif", s3_key: key("imgs/stack.ome.tif"), content_type: "image/tiff" }, Buffer.from("II*\0tiff"));
    const r = await get(previewPath(f.id, "?page=2"));
    expect(r.status).toBe(200);
    expect(r.headers.get("content-type")).toBe("image/png");
    expect(r.headers.get("x-content-type-options")).toBe("nosniff");
    expect(JSON.parse(r.headers.get("x-preview-info")!)).toMatchObject({ planeCount: 3, dtype: "uint16" });
    expect(Buffer.from(await r.arrayBuffer()).equals(PNG)).toBe(true);
    expect(galaxyFetch.mock.calls[0][1]).toBe("http://galaxy.test/api/perception/preview_image");
    expect(sent()).toEqual({ projectId: P, datasetRef: key("imgs/stack.ome.tif"), series: 0, page: 2 });
  });

  it("a member may preview; a non-member and an unknown file get 404 and nothing is rendered", async () => {
    const f = store.addFile({ project_id: P, name: "a.tif", s3_key: key("a.tif") }, Buffer.from("II*\0"));
    expect((await get(previewPath(f.id), { "x-test-user": MEMBER })).status).toBe(200);
    galaxyFetch.mockClear();
    const s = await get(previewPath(f.id), { "x-test-user": STRANGER });
    expect(s.status).toBe(404);
    expect(s.headers.get("cache-control")).toBe("private, no-store");
    expect((await get(previewPath("f1f1f1f1-0000-4000-8000-000000000000"))).status).toBe(404);
    expect((await get(`/api/projects/${P}/files/not-a-uuid/preview.png`)).status).toBe(404);
    expect(galaxyFetch).not.toHaveBeenCalled();
  });

  it("a client cannot point it elsewhere: another project's file id, query/key fields and traversal are ignored or refused", async () => {
    const mine = store.addFile({ project_id: P, name: "a.tif", s3_key: key("a.tif") }, Buffer.from("II*\0"));
    const theirs = store.addFile({ project_id: OTHER, name: "secret.tif", s3_key: key("secret.tif", OTHER), user_id: STRANGER }, Buffer.from("II*\0"));
    // Their file id under MY project → not found (the row is looked up by id AND project).
    expect((await get(previewPath(theirs.id))).status).toBe(404);
    // Their project with my credentials → 404 (not a member).
    expect((await get(previewPath(theirs.id, "", OTHER))).status).toBe(404);
    expect(galaxyFetch).not.toHaveBeenCalled();
    // Extra query fields naming data are not forwarded: the backend gets the row's key only.
    const r = await get(previewPath(mine.id, `?datasetRef=/etc/passwd&projectId=${OTHER}&s3_key=${encodeURIComponent(key("secret.tif", OTHER))}`));
    expect(r.status).toBe(200);
    expect(sent()).toEqual({ projectId: P, datasetRef: key("a.tif"), series: 0, page: 0 });
    // A malformed selection is refused before anything is read.
    galaxyFetch.mockClear();
    for (const q of ["?page=-1", "?series=1.5", "?page=../../x", "?page=9999999"]) {
      expect((await get(previewPath(mine.id, q))).status).toBe(400);
    }
    expect(galaxyFetch).not.toHaveBeenCalled();
  });

  it("a file stored outside the project's prefix (a run output) is not previewable — never sent to be refused", async () => {
    const f = store.addFile({ project_id: P, name: "out/cells.tif", s3_key: "nextflow/runs/r1/output/cells.tif", source: "run_output", content_hash: null }, Buffer.from("II*\0"));
    const r = await get(previewPath(f.id));
    expect(r.status).toBe(422);
    expect(await r.json()).toMatchObject({ error: "not_previewable" });
    expect(galaxyFetch).not.toHaveBeenCalled();
  });

  it("size cap: a file over 256 MiB → 413 without calling the renderer", async () => {
    const f = store.addFile({ project_id: P, name: "huge.tif", s3_key: key("huge.tif"), size: 257 * 1024 * 1024, content_hash: "h" });
    const r = await get(previewPath(f.id));
    expect(r.status).toBe(413);
    expect((await r.json()).error).toBe("too_large");
    expect(galaxyFetch).not.toHaveBeenCalled();
  });

  it("ETag by content_hash + selection: revalidation answers 304 without rendering; a new version changes it", async () => {
    const f = store.addFile({ project_id: P, name: "a.tif", s3_key: key("a.tif") }, Buffer.from("II*\0v1"));
    const r1 = await get(previewPath(f.id));
    const etag = r1.headers.get("etag")!;
    expect(etag).toContain(f.content_hash);
    expect(r1.headers.get("cache-control")).toBe("private, no-cache");
    galaxyFetch.mockClear();
    const r2 = await get(previewPath(f.id), { "If-None-Match": etag });
    expect(r2.status).toBe(304);
    expect(galaxyFetch).not.toHaveBeenCalled();
    const p1 = await get(previewPath(f.id, "?page=1"), { "If-None-Match": etag });
    expect(p1.status).toBe(200);           // another page is another picture
    store.files[0].content_hash = "new-hash"; // an edit / restore keeps the id, changes the bytes
    const r3 = await get(previewPath(f.id), { "If-None-Match": etag });
    expect(r3.status).toBe(200);
    expect(r3.headers.get("etag")).not.toBe(etag);
  });

  it("renderer refusals keep their code + reason (no-store); a 403 or an unexpected answer is a 502", async () => {
    const f = store.addFile({ project_id: P, name: "a.tif", s3_key: key("a.tif") }, Buffer.from("x"));
    const backend = (status: number, body: unknown) =>
      galaxyFetch.mockResolvedValueOnce(new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } }));
    backend(415, { error: "not_tiff", reason: "not a readable TIFF" });
    let r = await get(previewPath(f.id));
    expect(r.status).toBe(415);
    expect(await r.json()).toEqual({ error: "not_tiff", reason: "not a readable TIFF" });
    expect(r.headers.get("cache-control")).toBe("private, no-store");
    expect(r.headers.get("etag") ?? "").not.toContain("tiffprev"); // never the picture's validator
    backend(503, { error: "preview_unavailable", reason: "TIFF rendering is not installed on this server" });
    r = await get(previewPath(f.id));
    expect([r.status, (await r.json()).error]).toEqual([503, "preview_unavailable"]);
    backend(413, { error: "too_large", reason: "the image plane is 50000 × 50000 px" });
    r = await get(previewPath(f.id));
    expect([r.status, (await r.json()).reason]).toEqual([413, "the image plane is 50000 × 50000 px"]);
    backend(403, { error: "ref_refused", reason: "x" });
    r = await get(previewPath(f.id));
    expect([r.status, (await r.json()).error]).toEqual([502, "preview_unavailable"]);
    galaxyFetch.mockResolvedValueOnce(new Response("<html>gateway</html>", { status: 200, headers: { "Content-Type": "text/html" } }));
    r = await get(previewPath(f.id));
    expect(r.status).toBe(502);
    galaxyFetch.mockRejectedValueOnce(new Error("ECONNREFUSED"));
    r = await get(previewPath(f.id));
    expect([r.status, (await r.json()).error]).toEqual([502, "preview_unavailable"]);
  });
});
