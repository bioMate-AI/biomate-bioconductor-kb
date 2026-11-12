// @vitest-environment node
/**
 * Dataset panel audit round 3 (live dev walkthrough 2026-11-12) — server fixes, as route BEHAVIOUR
 * over loopback HTTP: the real registerProjectRoutes + the real perception proxy middleware chain
 * (perceptionProxyGate → datasetAccessGate → recordProfileSummary → backendPassthrough), with
 * Postgres / S3 replaced by project-files-fake-store.ts and the Python backend by a mock.
 *
 *   B2  after a saved edit the panel's profile call was 403: the gate accepted only a file's
 *       CURRENT key, and the panel still held the key it opened (now an archived version).
 *       A member may read the current key and every archived version key of a file they can
 *       read; nothing else. Edit / restore / rename return the list-shaped row (new s3_key).
 *   B4  the tree's quality dot reads the profiler's verdict stored per object key
 *       (profileSummary on the list row), the same result the panel got — not a client allowlist.
 *   diff  changedCellCount counts every changed cell (changedCells is capped at 100).
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import type { AddressInfo } from "net";
import express from "express";
import type { Server } from "http";
import { fakeStore as store } from "./project-files-fake-store";

const httpFetch = globalThis.fetch;
const P = "11111111-1111-4111-8111-111111111111";
const OTHER_P = "22222222-2222-4222-8222-222222222222";
const OWNER = "owner-1", EDITOR = "editor-2", VIEWER = "viewer-3", STRANGER = "stranger-9";

const galaxyFetch = vi.fn();
vi.mock("./db", async () => ({ pool: (await import("./project-files-fake-store")).fakeStore.pool }));
vi.mock("./s3-client", async () => ({ s3Service: (await import("./project-files-fake-store")).fakeStore.s3 }));
vi.mock("./auth-middleware", () => ({ authenticateToken: (_q: any, _s: any, next: any) => next() }));
vi.mock("./memory-repository", () => ({
  memoryService: {
    projects: { getProject: async (id: string) => (id === "11111111-1111-4111-8111-111111111111" ? { id, userId: "owner-1" } : null) },
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
  const { datasetAccessGate } = await import("./dataset-reference-access");
  const { recordProfileSummary } = await import("./project-file-profiles");
  const { perceptionProxyGate } = await import("./perception-proxy-gate");
  const { backendPassthrough } = await import("./backend-passthrough");
  const q = (t: string, p?: unknown[]) => store.pool.query(t, p as any[]);
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    const as = req.headers["x-test-user"];
    (req as any).user = { id: typeof as === "string" ? as : OWNER };
    next();
  });
  registerProjectRoutes(app);
  // The same chain routes.ts mounts (folder context omitted: it only adds a body field).
  const gate = (fromPath = false) => datasetAccessGate({ query: q, bucket: () => store.s3.getBucketName() }, fromPath);
  const proxy = backendPassthrough("DL surface");
  app.post("/api/perception/profile", perceptionProxyGate, gate(), recordProfileSummary(q), proxy);
  app.all("/api/perception/*", perceptionProxyGate, gate(), proxy);
  app.all("/api/datasets/*", gate(true), proxy);
  await new Promise<void>((r) => { server = app.listen(0, "127.0.0.1", () => r()); });
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
afterAll(() => server?.close());

/** What the Python backend answers: a profile per path, the rows-reader layout for the diff. */
let profileFor: (ref: string) => Record<string, unknown> = () => ({ quality: "good", findings: [], viewKind: "table" });
const jsonResponse = (body: unknown) => new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } });
beforeEach(() => {
  vi.clearAllMocks();
  store.reset();
  store.projects.push({ id: P, user_id: OWNER }, { id: OTHER_P, user_id: STRANGER });
  store.members.push({ project_id: P, user_id: EDITOR, role: "editor" }, { project_id: P, user_id: VIEWER, role: "viewer" });
  profileFor = () => ({ quality: "good", findings: [], viewKind: "table" });
  galaxyFetch.mockImplementation(async (_req: any, url: string, init: any) => {
    const body = init?.body ? JSON.parse(init.body) : {};
    if (url.endsWith("/api/perception/profile")) return jsonResponse(profileFor(body.datasetRef));
    if (url.endsWith("/api/perception/rows")) {
      return jsonResponse({ kind: "table", tabular: true, columns: ["id", "v"], rows: [], offset: 0, limit: 1, totalRows: 0, headerRow: true, skipLines: 0, delimiter: "," });
    }
    return jsonResponse({ ok: true });
  });
});

const send = (method: string, path: string, body?: unknown, user?: string) => httpFetch(`${base}${path}`, {
  method, headers: { "Content-Type": "application/json", ...(user ? { "x-test-user": user } : {}) },
  ...(body === undefined ? {} : { body: JSON.stringify(body) }),
});
const json = async (r: Response) => ({ status: r.status, body: await r.json() as any });
const key = (name: string, p = P) => `projects/${p}/inputs/${name}`;
const profile = (ref: string, user?: string) => send("POST", "/api/perception/profile", { datasetRef: ref, name: "x" }, user);
const listItem = async (id: string, user?: string) =>
  (await json(await send("GET", `/api/projects/${P}/files`, undefined, user))).body.files.find((f: any) => String(f.id) === id);
const edit = (id: string, baseVersion: number, from: string, value: string, user?: string) =>
  send("POST", `/api/projects/${P}/files/${id}/edit`, { baseVersion, edits: [{ row: 0, col: 1, from, value }] }, user);

describe("B2 — profiling after an edit / restore (dataset gate)", () => {
  it("edit returns the list-shaped row; the new key, the archived (old) key → 200; a non-member → 403", async () => {
    const f = store.addFile({ project_id: P, name: "counts.tsv", s3_key: key("counts.tsv") }, "id\tv\n1\t1868\n");
    const oldKey = f.s3_key;
    expect((await profile(oldKey)).status).toBe(200);

    const e = await json(await edit(f.id, 1, "1868", "4242"));
    expect(e.status).toBe(200);
    const newKey = e.body.file.s3_key;
    expect(newKey).not.toBe(oldKey);
    expect(newKey).toBe(store.files[0].s3_key);
    // Same shape (and values) as the files list item: the client swaps it in as-is.
    expect(JSON.parse(JSON.stringify(e.body.file))).toEqual(await listItem(f.id));

    expect((await profile(newKey)).status).toBe(200);
    // The key the panel opened is now an archived version: a member may still read it (the
    // panel's in-flight refetch, Compare / version views) — the 403 of the live walkthrough.
    expect((await profile(oldKey)).status).toBe(200);
    expect((await profile(oldKey, VIEWER)).status).toBe(200);
    expect((await profile(newKey, EDITOR)).status).toBe(200);
    // Rows and the datasets surface use the same gate.
    expect((await send("POST", "/api/perception/rows", { datasetRef: oldKey, offset: 0, limit: 10 }, VIEWER)).status).toBe(200);
    expect((await send("GET", `/api/datasets/${encodeURIComponent(oldKey)}/versions`, undefined, VIEWER)).status).toBe(200);

    // A non-member: neither the current nor the archived key, nor via the datasets surface.
    for (const k of [newKey, oldKey]) {
      expect((await profile(k, STRANGER)).status).toBe(403);
      expect((await send("GET", `/api/datasets/${encodeURIComponent(k)}/versions`, undefined, STRANGER)).status).toBe(403);
    }
  });

  it("restore returns the list-shaped row with the restored key; every version stays readable to members", async () => {
    const f = store.addFile({ project_id: P, name: "t.csv", s3_key: key("t.csv") }, "id,v\n1,a\n");
    const v1 = f.s3_key;
    const v2 = (await json(await edit(f.id, 1, "a", "b"))).body.file.s3_key;
    const r = await json(await send("POST", `/api/projects/${P}/files/${f.id}/versions/1/restore`, { baseVersion: 2 }));
    expect(r.status).toBe(200);
    expect(r.body.file.s3_key).toBe(v1);
    expect(r.body.file.version_no).toBe(3);
    expect(JSON.parse(JSON.stringify(r.body.file))).toEqual(await listItem(f.id));
    for (const k of [v1, v2]) {
      expect((await profile(k, VIEWER)).status).toBe(200);
      expect((await profile(k, STRANGER)).status).toBe(403);
    }
  });

  it("never anything else: another project's key, a deleted file's versions, an unregistered key → 403", async () => {
    const mine = store.addFile({ project_id: P, name: "a.csv", s3_key: key("a.csv") }, "id,v\n1,a\n");
    const theirs = store.addFile({ project_id: OTHER_P, name: "b.csv", s3_key: key("b.csv", OTHER_P), user_id: STRANGER }, "x\n");
    store.versions.push({ file_id: theirs.id, project_id: OTHER_P, version_no: 1, s3_key: key("b.csv.v0", OTHER_P), size: 2, created_at: store.now() });
    expect((await profile(theirs.s3_key, EDITOR)).status).toBe(403);
    expect((await profile(key("b.csv.v0", OTHER_P), EDITOR)).status).toBe(403);
    expect((await profile(theirs.s3_key, STRANGER)).status).toBe(200);
    expect((await profile(key("never-registered.csv"))).status).toBe(403);
    // Refused requests never reach the backend: only the stranger's own-file profile did.
    expect(galaxyFetch.mock.calls.filter((c) => String(c[1]).endsWith("/profile"))).toHaveLength(1);
    // Delete removes the file's versions too — its old keys stop being readable.
    const old = mine.s3_key;
    await edit(mine.id, 1, "a", "z");
    expect((await profile(old)).status).toBe(200);
    expect((await send("DELETE", `/api/projects/${P}/files/${mine.id}`)).status).toBe(200);
    expect((await profile(old)).status).toBe(403);
  });

  it("rename returns the list-shaped row (same key, still profilable)", async () => {
    const f = store.addFile({ project_id: P, name: "r.csv", s3_key: key("r.csv") }, "id\n1\n");
    const r = await json(await send("PATCH", `/api/projects/${P}/files/${f.id}`, { name: "renamed.csv" }));
    expect(r.status).toBe(200);
    expect(r.body.file.name).toBe("renamed.csv");
    expect(JSON.parse(JSON.stringify(r.body.file))).toEqual(await listItem(f.id));
    expect((await profile(r.body.file.s3_key, VIEWER)).status).toBe(200);
  });
});

describe("B4 — the tree's quality = the profiler's verdict for the file's current version", () => {
  const PROFILES: Record<string, Record<string, unknown>> = {
    "ref.fasta": { quality: "good", viewKind: "sequences", findings: [{ code: "format_identified", level: "info", section: "data" }] },
    "genes.gtf": { quality: "good", viewKind: "annotation", findings: [] },
    "peaks.bed": { quality: "good", viewKind: "intervals", findings: [] },
    "reads.bam": { quality: "unassessed", viewKind: "alignment", findings: [{ code: "format_metadata_only", level: "info" }] },
    "rows.jsonl": { quality: "watch", viewKind: "records", findings: [{ code: "high_missing", level: "watch", section: "data" }] },
    "fake.png": { quality: "unassessed", viewKind: "unknown", findings: [{ code: "unprofilable", level: "info" }] },
  };

  it("every profiled file — FASTA/GTF/BED/BAM/JSONL/PNG alike — carries the verdict the panel got", async () => {
    const files = Object.keys(PROFILES).map((n) => store.addFile({ project_id: P, name: n, s3_key: key(n) }, "x\n"));
    profileFor = (ref) => PROFILES[ref.split("/").pop()!];
    // Before anything was profiled: null (the client profiles), never a guessed "unsupported".
    for (const f of files) expect((await listItem(f.id)).profileSummary).toBeNull();
    for (const f of files) {
      const r = await json(await profile(f.s3_key));
      expect(r.status).toBe(200);
      expect(r.body).toEqual(PROFILES[f.name]); // relayed unchanged
    }
    for (const f of files) {
      const s = (await listItem(f.id, VIEWER)).profileSummary;
      const p = PROFILES[f.name] as any;
      expect(s).toMatchObject({ quality: p.quality, viewKind: p.viewKind, findings: p.findings });
      expect(typeof s.profiledAt).toBe("string");
    }
  });

  it("an edit's new version has no summary until profiled; a restore brings back that version's; failures to reach the bytes are not stored", async () => {
    const f = store.addFile({ project_id: P, name: "t.csv", s3_key: key("t.csv") }, "id,v\n1,a\n");
    await profile(f.s3_key);
    expect((await listItem(f.id)).profileSummary.quality).toBe("good");
    const e = await json(await edit(f.id, 1, "a", "b"));
    expect(e.body.file.profileSummary).toBeNull();             // new bytes: not profiled yet
    expect((await listItem(f.id)).profileSummary).toBeNull();
    profileFor = () => ({ quality: "blocked", viewKind: "unknown", findings: [{ code: "unresolvable_ref", level: "blocked" }] });
    await profile(e.body.file.s3_key);
    expect((await listItem(f.id)).profileSummary).toBeNull(); // the object was not reached: says nothing about the file
    profileFor = () => ({ quality: "blocked", viewKind: "unknown", findings: [{ code: "parse_failed", level: "blocked" }] });
    await profile(e.body.file.s3_key);
    expect((await listItem(f.id)).profileSummary.quality).toBe("blocked");
    const r = await json(await send("POST", `/api/projects/${P}/files/${f.id}/versions/1/restore`, { baseVersion: 2 }));
    expect(r.body.file.profileSummary.quality).toBe("good");   // v1's bytes, v1's verdict
  });

  it("a refused profile request stores nothing", async () => {
    const f = store.addFile({ project_id: P, name: "t.csv", s3_key: key("t.csv") }, "id\n1\n");
    expect((await profile(f.s3_key, STRANGER)).status).toBe(403);
    expect(store.profiles.size).toBe(0);
  });
});

describe("diff — count-safe changed-cell totals", () => {
  it("changedCellCount counts every changed cell; changedCells stays capped at 100", async () => {
    const rows = (v: string) => "id,v\n" + Array.from({ length: 150 }, (_, i) => `${i},${v}${i}`).join("\n") + "\n";
    const f = store.addFile({ project_id: P, name: "d.csv", s3_key: key("d.csv.v2"), version_no: 2 }, rows("b"));
    store.objects.set(key("d.csv"), Buffer.from(rows("a")));
    store.versions.push({ file_id: f.id, project_id: P, version_no: 1, s3_key: key("d.csv"), size: 10, content_hash: "old", created_at: store.now() });
    const r = await json(await send("GET", `/api/projects/${P}/files/${f.id}/versions/1/diff`));
    expect(r.status).toBe(200);
    expect(r.body.changedCells).toHaveLength(100);
    expect(r.body).toMatchObject({ changedCellCount: 150, changedCellCountExact: true, changedCellsTruncated: true });
  });

  it("one changed cell → changedCellCount 1, not truncated", async () => {
    const f = store.addFile({ project_id: P, name: "e.csv", s3_key: key("e.csv.v2"), version_no: 2 }, "id,v\n1,4242\n");
    store.objects.set(key("e.csv"), Buffer.from("id,v\n1,1868\n"));
    store.versions.push({ file_id: f.id, project_id: P, version_no: 1, s3_key: key("e.csv"), size: 12, content_hash: "old", created_at: store.now() });
    const r = await json(await send("GET", `/api/projects/${P}/files/${f.id}/versions/1/diff`));
    expect(r.body).toMatchObject({ changedCellCount: 1, changedCellCountExact: true, changedCellsTruncated: false });
  });
});
