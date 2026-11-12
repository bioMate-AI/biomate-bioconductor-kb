// @vitest-environment node
/**
 * Project file integrity (committee audit 2026-11-12, docs/20261112_DATASET_PANEL_AUDIT.md) —
 * route BEHAVIOUR over loopback HTTP against the real registerProjectRoutes, with Postgres and
 * S3 replaced by project-files-fake-store.ts (real per-key advisory locks, ROLLBACK, and the
 * UPDATE's version precondition). Concurrency tests fire real concurrent HTTP requests.
 *
 *   S1/S3  edit + restore carry an optimistic version precondition (baseVersion → 409
 *          version_conflict, nothing written); cell `from` / `rowFrom` → 409 cell_conflict.
 *   S2     concurrent uploads of one new name never leave a row describing other bytes.
 *   R1     the edit reads the WHOLE file (≤ 10 MiB); 422 only for real UTF-8 decoding loss.
 *   R13    versions carry each version's own time + author display name; diff rows 1-based.
 *   R14    downloads are named by the display name (JSON, redirect, versions, on-prem proxy).
 *   R15    upload follows the rename name rule; non-uuid ids → 404; delete removes versions.
 *   rows   the rows page reports the file `version` (the edit's baseVersion).
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import type { AddressInfo } from "net";
import express from "express";
import type { Server } from "http";
import { FakeStore, fakeStore as store } from "./project-files-fake-store";

const httpFetch = globalThis.fetch;
const P = "11111111-1111-4111-8111-111111111111";
const OWNER = "owner-1", EDITOR = "editor-2";

const galaxyFetch = vi.fn();
vi.mock("./db", async () => ({ pool: (await import("./project-files-fake-store")).fakeStore.pool }));
vi.mock("./s3-client", async () => ({ s3Service: (await import("./project-files-fake-store")).fakeStore.s3 }));
vi.mock("./auth-middleware", () => ({ authenticateToken: (_q: any, _s: any, next: any) => next() }));
vi.mock("./memory-repository", () => ({
  memoryService: {
    // projects.id is a uuid column: like drizzle on Postgres, a non-uuid id raises 22P02 (not null).
    projects: { getProject: async (id: string) => {
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) {
        throw (await import("./project-files-fake-store")).uuidCastError(id);
      }
      return id === "11111111-1111-4111-8111-111111111111" ? { id, userId: "owner-1" } : null;
    } },
    ensureLtmUser: async () => {},
  },
}));
vi.mock("./galaxy-user-fetch", () => ({
  fetchGalaxyAsUser: (...a: any[]) => galaxyFetch(...a),
  galaxyBaseUrl: () => "http://galaxy.test",
}));

let server: Server;
let base = "";
let currentUser = { id: OWNER };

beforeAll(async () => {
  const { registerProjectRoutes } = await import("./project-routes");
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => {
    const as = req.headers["x-test-user"];
    (req as any).user = { id: typeof as === "string" ? as : currentUser.id };
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
  currentUser = { id: OWNER };
  store.members.push({ project_id: P, user_id: EDITOR, role: "editor" });
  store.users.push({ id: OWNER, full_name: "Olivia Owner", email: "olivia@x.io" }, { id: EDITOR, full_name: "", email: "ed@x.io" });
  delete process.env.S3_ENDPOINT_URL;
});

const post = (path: string, body: unknown, user?: string) => httpFetch(`${base}${path}`, {
  method: "POST", headers: { "Content-Type": "application/json", ...(user ? { "x-test-user": user } : {}) }, body: JSON.stringify(body),
});
const json = async (r: Response) => ({ status: r.status, body: await r.json() as any });
const upload = (name: string, bytes: string | Buffer, user?: string) => {
  const fd = new FormData();
  fd.append("file", new Blob([typeof bytes === "string" ? Buffer.from(bytes) : bytes]), name);
  return httpFetch(`${base}/api/projects/${P}/files/upload`, { method: "POST", body: fd, headers: user ? { "x-test-user": user } : {} });
};
const key = (name: string) => `projects/${P}/inputs/${name}`;
const editPath = (id: string) => `/api/projects/${P}/files/${id}/edit`;
const fileById = (id: string) => store.files.find((f) => f.id === id)!;
const versionsOf = (id: string) => store.versions.filter((v) => v.file_id === id).map((v) => Number(v.version_no)).sort();

describe("edit — optimistic version precondition (S1, S3)", () => {
  it("requires baseVersion (400) and writes nothing without it", async () => {
    const f = store.addFile({ project_id: P, name: "t.csv", s3_key: key("t.csv") }, "id,v\n1,a\n");
    const r = await json(await post(editPath(f.id), { edits: [{ row: 0, col: 1, from: "a", value: "b" }] }));
    expect(r.status).toBe(400);
    expect(r.body.error).toMatch(/baseVersion/);
    expect(store.puts).toEqual([]);
  });

  it("two concurrent edits of one version: exactly one 200, one 409 version_conflict; history v1, v2", async () => {
    const f = store.addFile({ project_id: P, name: "t.csv", s3_key: key("t.csv") }, "id,v\n1,a\n2,b\n");
    store.putDelayMs = 30; // the winner is mid-write when the loser reaches the lock
    const [a, b] = await Promise.all([
      post(editPath(f.id), { baseVersion: 1, edits: [{ row: 0, col: 1, from: "a", value: "A" }] }).then(json),
      post(editPath(f.id), { baseVersion: 1, edits: [{ row: 1, col: 1, from: "b", value: "B" }] }, EDITOR).then(json),
    ]);
    expect([a.status, b.status].sort()).toEqual([200, 409]);
    const loser = a.status === 409 ? a : b;
    expect(loser.body).toMatchObject({ error: "version_conflict", currentVersion: 2 });
    expect(store.puts).toHaveLength(1);                 // the loser put nothing
    expect(fileById(f.id).version_no).toBe(2);
    expect(versionsOf(f.id)).toEqual([1]);              // v1 archived once, v2 current — no lost or doubled version
    expect(store.integrityProblems()).toEqual([]);
  });

  it("a stale edit whose cell value repeats is refused (409), not applied to another row", async () => {
    // v1 = "id,flag\n1,no\n2,no\n"; someone inserted a row above → v2. The user still sees v1 and
    // edits row 0 (id=1): the `from` value "no" also sits in v2's row 0 (id=0).
    const f = store.addFile({ project_id: P, name: "flags.csv", s3_key: key("flags.csv.v2"), version_no: 2 }, "id,flag\n0,no\n1,no\n2,no\n");
    store.objects.set(key("flags.csv"), Buffer.from("id,flag\n1,no\n2,no\n"));
    store.versions.push({ file_id: f.id, project_id: P, version_no: 1, s3_key: key("flags.csv"), size: 18, created_at: store.now() });
    const r = await json(await post(editPath(f.id), { baseVersion: 1, edits: [{ row: 0, col: 1, from: "no", value: "yes" }] }));
    expect(r.status).toBe(409);
    expect(r.body).toMatchObject({ error: "version_conflict", currentVersion: 2 });
    expect(store.puts).toEqual([]);
    expect(store.versions).toHaveLength(1);
    expect(store.objects.get(key("flags.csv.v2"))!.toString()).toBe("id,flag\n0,no\n1,no\n2,no\n");
  });

  it("cell `from` mismatch → 409 cell_conflict; a mis-numbered row with the same value is caught by rowFrom", async () => {
    const f = store.addFile({ project_id: P, name: "t.csv", s3_key: key("t.csv") }, "id,v\n1,a\n");
    const c = await json(await post(editPath(f.id), { baseVersion: 1, edits: [{ row: 0, col: 1, from: "zzz", value: "b" }] }));
    expect(c.status).toBe(409);
    expect(c.body.error).toBe("cell_conflict");
    expect(c.body.conflicts[0]).toMatchObject({ row: 0, col: 1, expected: "zzz", actual: "a" });
    // header-less BED, client wrongly numbers with headerRows=1: row 0 → the chr2 line, whose
    // column 3 also holds "0". The row the user saw (rowFrom) does not match → refused.
    const bed = store.addFile({ project_id: P, name: "r.txt", s3_key: key("r.txt") }, "chr1\t100\t200\t0\nchr2\t300\t400\t0\n");
    const m = await json(await post(editPath(bed.id), {
      baseVersion: 1, headerRows: 1, edits: [{ row: 0, col: 3, from: "0", value: "9", rowFrom: ["chr1", "100", "200", "0"] }],
    }));
    expect(m.status).toBe(409);
    expect(m.body.error).toBe("cell_conflict");
    expect(m.body.conflicts[0].rowMismatch).toBe(true);
    expect(store.puts).toEqual([]);
  });

  it("a successful edit writes v2 (only the cell changed) and archives v1 with v1's own time and author", async () => {
    const f = store.addFile({ project_id: P, name: "t.csv", s3_key: key("t.csv") }, 'id,v\r\n1,"a, b"\r\n2,c\r\n');
    const v1At = f.version_created_at;
    const r = await json(await post(editPath(f.id), { baseVersion: 1, edits: [{ row: 1, col: 1, from: "c", value: "C" }] }, EDITOR));
    expect(r.status).toBe(200);
    expect(r.body.file.version_no).toBe(2);
    const cur = fileById(f.id);
    expect(store.objects.get(cur.s3_key)!.toString()).toBe('id,v\r\n1,"a, b"\r\n2,C\r\n');
    const v1 = store.versions.find((v) => v.file_id === f.id)!;
    expect(v1).toMatchObject({ version_no: 1, s3_key: key("t.csv"), version_created_at: v1At, version_author: OWNER, author: EDITOR });
    expect(cur.version_author).toBe(EDITOR);
    expect(store.integrityProblems()).toEqual([]);
  });
});

describe("edit reads the whole file (R1)", () => {
  it("a 2.7 MB ASCII CSV edits fine (the read used to be clamped to 1 MiB → '422 not UTF-8')", async () => {
    const lines = ["id,value"];
    for (let i = 0, n = 0; n < 2_700_000; i++) { const l = `${i},v${i % 97}`; lines.push(l); n += l.length + 1; }
    const text = lines.join("\n") + "\n";
    const last = lines.length - 2; // data-row index of the last line
    const f = store.addFile({ project_id: P, name: "big.csv", s3_key: key("big.csv") }, text);
    const [lid, lval] = lines[lines.length - 1].split(",");
    const r = await json(await post(editPath(f.id), { baseVersion: 1, edits: [{ row: last, col: 1, from: lval, value: "EDITED" }] }));
    expect(r.status).toBe(200);
    const out = store.objects.get(fileById(f.id).s3_key)!.toString();
    expect(out).toBe(text.slice(0, text.length - lval.length - 1) + "EDITED\n");
    expect(out.startsWith(text.slice(0, 2_000_000))).toBe(true);
    expect(lid).toBe(String(last));
  });

  it("latin-1 bytes → 422 and nothing written; a BOM and a literal U+FFFD are kept (no false refusal)", async () => {
    const latin = store.addFile({ project_id: P, name: "l.csv", s3_key: key("l.csv") }, Buffer.from("name,city\nJos\xe9,Montr\xe9al\n", "latin1"));
    const r = await json(await post(editPath(latin.id), { baseVersion: 1, edits: [{ row: 0, col: 0, from: "Jos�", value: "x" }] }));
    expect(r.status).toBe(422);
    expect(r.body.code).toBe("not_utf8");
    expect(store.puts).toEqual([]);
    const bom = store.addFile({ project_id: P, name: "b.csv", s3_key: key("b.csv") }, "﻿k,v\nx,�\ny,2\n");
    const ok = await json(await post(editPath(bom.id), { baseVersion: 1, edits: [{ row: 1, col: 1, from: "2", value: "3" }] }));
    expect(ok.status).toBe(200);
    expect(store.objects.get(fileById(bom.id).s3_key)!.toString("utf-8")).toBe("﻿k,v\nx,�\ny,3\n");
  });

  it("over 10 MiB → 413", async () => {
    const f = store.addFile({ project_id: P, name: "huge.csv", s3_key: key("huge.csv") }, Buffer.alloc(10 * 1024 * 1024 + 1, 0x61));
    const r = await json(await post(editPath(f.id), { baseVersion: 1, edits: [{ row: 0, col: 0, from: "", value: "x" }] }));
    expect(r.status).toBe(413);
    expect(r.body.code).toBe("too_large");
  });
});

describe("restore — version precondition + history", () => {
  it("stale baseVersion → 409 nothing archived; a restore writes a new version and keeps history append-only", async () => {
    const f = store.addFile({ project_id: P, name: "t.csv", s3_key: key("t.csv.v2"), version_no: 2 }, "id\n2\n");
    store.objects.set(key("t.csv"), Buffer.from("id\n1\n"));
    store.versions.push({ id: "v1", file_id: f.id, project_id: P, version_no: 1, s3_key: key("t.csv"), size: 5,
      content_type: "text/csv", content_hash: FakeStore.sha("id\n1\n"), created_at: store.now(), version_created_at: store.now(), version_author: OWNER });
    const stale = await json(await post(`/api/projects/${P}/files/${f.id}/versions/1/restore`, { baseVersion: 1 }));
    expect(stale.status).toBe(409);
    expect(stale.body.error).toBe("version_conflict");
    expect(versionsOf(f.id)).toEqual([1]);
    const ok = await json(await post(`/api/projects/${P}/files/${f.id}/versions/1/restore`, { baseVersion: 2 }));
    expect(ok.status).toBe(200);
    expect(ok.body.file.version_no).toBe(3);
    expect(versionsOf(f.id)).toEqual([1, 2]);
    expect(fileById(f.id).s3_key).toBe(key("t.csv"));
    expect(store.integrityProblems()).toEqual([]);
  });
});

describe("upload — key reservation under the project lock (S2) + the shared name rule (R15)", () => {
  it("two concurrent uploads of one NEW name with different bytes: one file, v1 + v2, every row matches its bytes", async () => {
    store.putDelayMs = 25;
    const [a, b] = await Promise.all([upload("a.csv", "x\n1\n"), upload("a.csv", "x\n2\n")]);
    expect([a.status, b.status].sort()).toEqual([200, 201]);
    const rows = store.files.filter((f) => f.name === "a.csv");
    expect(rows).toHaveLength(1);
    expect(rows[0].version_no).toBe(2);
    expect(versionsOf(rows[0].id)).toEqual([1]);
    expect(new Set(store.puts).size).toBe(2);           // two distinct keys — no overwrite
    expect(store.integrityProblems()).toEqual([]);
    expect(store.reservations.size).toBe(0);
  });

  it("two concurrent uploads of the same bytes: one file + one dedup; the loser's object is removed", async () => {
    store.putDelayMs = 25;
    const rs = await Promise.all([upload("same.csv", "q\n1\n"), upload("same.csv", "q\n1\n")]);
    const bodies = await Promise.all(rs.map((r) => r.json() as any));
    expect(rs.map((r) => r.status).sort()).toEqual([200, 201]);
    expect(bodies.filter((b: any) => b.deduplicated)).toHaveLength(1);
    expect(store.files).toHaveLength(1);
    expect([...store.objects.keys()]).toEqual([store.files[0].s3_key]);
    expect(store.reservations.size).toBe(0);
    expect(store.integrityProblems()).toEqual([]);
  });

  it("refuses a name that clashes with a folder or a file-as-folder (409, same body as rename); nothing put", async () => {
    store.addFile({ project_id: P, name: "data/x.csv", s3_key: key("data/x.csv") }, "a\n");
    const r = await json(await upload("data", "b\n"));
    expect(r.status).toBe(409);
    expect(r.body.conflicts).toEqual([{ name: "data", existing: "data/x.csv" }]);
    expect(store.puts).toEqual([]);
    // the rename route gives the same answer for the same clash
    const other = store.addFile({ project_id: P, name: "other.csv", s3_key: key("other.csv") }, "c\n");
    const ren = await json(await httpFetch(`${base}/api/projects/${P}/files/${other.id}`, {
      method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ name: "data" }),
    }));
    expect(ren.status).toBe(409);
    expect(ren.body).toEqual(r.body);
    expect(r.body.code).toBe("name_conflict");
    // 400s carry their code too (folder move into itself; a run output rename)
    const into = await json(await post(`/api/projects/${P}/files/rename-folder`, { from: "data", to: "data/inner" }));
    expect(into).toMatchObject({ status: 400, body: { code: "into_itself" } });
    const ro = store.addFile({ project_id: P, name: "o.html", s3_key: "projects/x/outputs/o.html", source: "run_output" }, "o\n");
    const roR = await json(await httpFetch(`${base}/api/projects/${P}/files/${ro.id}`, {
      method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ name: "p.html" }),
    }));
    expect(roR).toMatchObject({ status: 400, body: { code: "run_output" } });
  });

  it("names of other trees do not clash: a run output or a generated file may share an input's name", async () => {
    store.addFile({ project_id: P, name: "counts.csv", s3_key: "projects/x/outputs/counts.csv", source: "run_output" }, "r\n");
    store.addFile({ project_id: P, name: "QC_Report.txt", s3_key: `projects/${P}/generated/QC_Report.txt`, source: "run_code" }, "g\n");
    expect((await upload("counts.csv", "u1\n")).status).toBe(201);
    expect((await upload("QC_Report.txt", "u2\n")).status).toBe(201);
  });
});

describe("ids (R15)", () => {
  // The fake store / project lookup now raise pg's 22P02 for a non-uuid id bound to a uuid
  // column (as Postgres does), so these 404s come from the _projectFileIds guard: without it
  // each request reaches a uuid comparison and comes back 500.
  it("non-uuid project or file ids → 404, never a 500 cast error", async () => {
    expect((await httpFetch(`${base}/api/projects/p1/files`)).status).toBe(404);
    expect((await httpFetch(`${base}/api/projects/${P}/files/not-a-uuid/url`)).status).toBe(404);
    expect((await post(editPath("1"), { baseVersion: 1, edits: [{ row: 0, col: 0, from: "", value: "" }] })).status).toBe(404);
    expect((await httpFetch(`${base}/api/projects/${P}/files/x'y/versions`)).status).toBe(404);
    expect((await httpFetch(`${base}/api/projects/p1/files/x/rows`)).status).toBe(404);
    expect((await post(`/api/projects/p1/files/compatibility`, { fileIds: [] })).status).toBe(404);
  });

  it("the harness is honest: a non-uuid id that reaches a uuid comparison is a cast error", async () => {
    await expect(store.pool.query("SELECT 1 FROM project_members WHERE project_id = $1 AND user_id::text = $2", ["p1", "u"]))
      .rejects.toMatchObject({ code: "22P02" });
    await expect(store.pool.query("SELECT id FROM project_files WHERE project_id = $1 AND id = ANY($2::uuid[])", [P, ["nope"]]))
      .rejects.toMatchObject({ code: "22P02" });
    // ::text comparisons never cast (that is why the routes compare ids as text)
    await expect(store.pool.query("SELECT 1 FROM project_members WHERE project_id::text = $1 AND user_id::text = $2", ["p1", "u"]))
      .resolves.toBeTruthy();
  });

  it("_projectFileIds answers 404 before the handler runs (route stub that would cast)", async () => {
    const { _projectFileIds } = await import("./project-routes");
    const app = express();
    const reached: string[] = [];
    const castingHandler = (req: any, res: any) => {
      reached.push(req.path);
      for (const v of [req.params.id, req.params.fileId]) {
        if (v !== undefined && !/^[0-9a-f-]{36}$/i.test(v)) return res.status(500).json({ error: "invalid input syntax for type uuid" });
      }
      res.json({ ok: true });
    };
    app.get("/p/:id/f/:fileId", _projectFileIds as any, castingHandler);
    app.get("/p/:id", _projectFileIds as any, castingHandler);
    const srv = await new Promise<Server>((r) => { const s = app.listen(0, "127.0.0.1", () => r(s)); });
    const b = `http://127.0.0.1:${(srv.address() as AddressInfo).port}`;
    try {
      const st = async (u: string) => { const r = await httpFetch(b + u); return { status: r.status, body: await r.json() }; };
      expect(await st("/p/p1")).toEqual({ status: 404, body: { error: "Project not found" } });
      expect(await st(`/p/${P}/f/1`)).toEqual({ status: 404, body: { error: "File not found" } });
      expect(await st(`/p/${P}/f/${P.toUpperCase()}`)).toEqual({ status: 200, body: { ok: true } });
      expect(await st(`/p/${P}`)).toEqual({ status: 200, body: { ok: true } });
      expect(reached).toEqual([`/p/${P}/f/${P.toUpperCase()}`, `/p/${P}`]);
    } finally { srv.close(); }
  });
});

describe("edit — tabular files only", () => {
  // The gate is by extension (csv/tsv/tab/txt): spec formats (.bed, .gtf, …) and JSON/JSONL are
  // tabular to the reader but are not edited in place (their quoting / record rules differ).
  for (const [name, bytes] of [["peaks.bed", "chr1\t10\t20\n"], ["meta.json", '{"a":"x"}\n'], ["r.jsonl", '{"a":"x"}\n']] as const) {
    it(`${name} → 400 and nothing is read, written or versioned`, async () => {
      const f = store.addFile({ project_id: P, name, s3_key: key(name) }, bytes);
      const r = await json(await post(editPath(f.id), { baseVersion: 1, edits: [{ row: 0, col: 0, from: "chr1", value: "chr2" }] }));
      expect(r.status).toBe(400);
      expect(r.body.error).toMatch(/Only tabular files/);
      expect(r.body.code).toBe("not_tabular");
      expect(store.puts).toEqual([]);
      expect(store.versions).toEqual([]);
      expect(fileById(f.id).version_no).toBe(1);
      expect(store.objects.get(key(name))!.toString()).toBe(bytes);
    });
  }
});

describe("delete (R15)", () => {
  it("removes the file, its version rows and their objects — but not an object another row still uses", async () => {
    const f = store.addFile({ project_id: P, name: "t.csv", s3_key: key("t.csv"), version_no: 3 }, "v3\n"); // restored to v1's key
    store.objects.set(key("t.csv.v2"), Buffer.from("v2\n"));
    store.versions.push(
      { file_id: f.id, project_id: P, version_no: 1, s3_key: key("t.csv"), created_at: store.now() },
      { file_id: f.id, project_id: P, version_no: 2, s3_key: key("t.csv.v2"), created_at: store.now() },
    );
    // another file's current bytes live at v2's key (e.g. two registrations of one run output)
    const keep = store.addFile({ project_id: P, name: "k.csv", s3_key: key("t.csv.v2") }, "v2\n");
    const r = await json(await httpFetch(`${base}/api/projects/${P}/files/${f.id}`, { method: "DELETE" }));
    expect(r.status).toBe(200);
    expect(r.body.versionsRemoved).toBe(2);
    expect(store.files.map((x) => x.id)).toEqual([keep.id]);
    expect(store.versions.filter((v) => v.file_id === f.id)).toEqual([]);
    expect(store.deletes).toEqual([key("t.csv")]);          // the restore-shared key once; v2's key is still used
    expect(store.objects.has(key("t.csv.v2"))).toBe(true);
  });
});

describe("download naming (R14)", () => {
  it("JSON and ?redirect=1 presign with the display basename; versions too (no .vN); on-prem proxy carries the name", async () => {
    const f = store.addFile({ project_id: P, name: "run1/S1.csv", s3_key: key("run1/S1-2.csv.v2"), version_no: 2 }, "a\n");
    store.versions.push({ file_id: f.id, project_id: P, version_no: 1, s3_key: key("run1/S1-2.csv"), created_at: store.now() });
    const j = await json(await httpFetch(`${base}/api/projects/${P}/files/${f.id}/url`));
    expect(j.status).toBe(200);
    expect(store.presigned.at(-1)).toEqual({ key: key("run1/S1-2.csv.v2"), name: "S1.csv" });
    const red = await httpFetch(`${base}/api/projects/${P}/files/${f.id}/url?redirect=1`, { redirect: "manual" });
    expect(red.status).toBe(302);
    expect(store.presigned.at(-1)).toEqual({ key: key("run1/S1-2.csv.v2"), name: "S1.csv" });
    const v = await json(await httpFetch(`${base}/api/projects/${P}/files/${f.id}/versions/1/url`));
    expect(v.status).toBe(200);
    expect(v.body.name).toBe("S1.csv");
    expect(store.presigned.at(-1)).toEqual({ key: key("run1/S1-2.csv"), name: "S1.csv" });
    expect((await httpFetch(`${base}/api/projects/${P}/files/${f.id}/versions/9/url`)).status).toBe(404);
    process.env.S3_ENDPOINT_URL = "http://minio:9000";
    const onprem = await json(await httpFetch(`${base}/api/projects/${P}/files/${f.id}/url`));
    expect(onprem.body.url).toBe(`/api/s3/proxy-download?key=${encodeURIComponent(key("run1/S1-2.csv.v2"))}&name=S1.csv`);
  });
});

describe("versions API (R13) + diff numbering", () => {
  it("each version's own creation time and author display name — for rows archived before and after the fix", async () => {
    // Legacy rows (no version_created_at): each archive row is stamped with the time/author of the
    // NEXT version's write. v1 created T0 by owner; v2 written T1 by editor; v3 written T2 by owner.
    const t0 = store.now(), t1 = store.now(), t2 = store.now();
    const f = store.addFile({ project_id: P, name: "t.csv", s3_key: key("t.csv.v3"), version_no: 3,
      created_at: t0, user_id: OWNER, version_created_at: null, version_author: null }, "v3\n");
    store.versions.push(
      { file_id: f.id, project_id: P, version_no: 1, s3_key: key("t.csv"), size: 3, note: "v1", author: EDITOR, created_at: t1 },
      { file_id: f.id, project_id: P, version_no: 2, s3_key: key("t.csv.v2"), size: 3, note: "v2", author: OWNER, created_at: t2 },
    );
    const r = await json(await httpFetch(`${base}/api/projects/${P}/files/${f.id}/versions`));
    expect(r.status).toBe(200);
    const by = Object.fromEntries(r.body.versions.map((v: any) => [v.version, v]));
    expect(by["3"]).toMatchObject({ current: true, createdAt: t2.toISOString(), authorName: "Olivia Owner", author: "Olivia Owner", authorId: OWNER });
    expect(by["2"]).toMatchObject({ current: false, createdAt: t1.toISOString(), authorName: "ed@x.io", authorId: EDITOR });
    expect(by["1"]).toMatchObject({ current: false, createdAt: t0.toISOString(), author: "Olivia Owner" });
    // a new edit (post-fix rows): v3 is archived with ITS time/author, v4 is the editor's
    store.objects.set(key("t.csv.v3"), Buffer.from("k\nv3\n"));
    fileById(f.id).size = 5;
    const e = await post(editPath(f.id), { baseVersion: 3, edits: [{ row: 0, col: 0, from: "v3", value: "v4" }] }, EDITOR);
    expect(e.status).toBe(200);
    const after = await json(await httpFetch(`${base}/api/projects/${P}/files/${f.id}/versions`));
    const by2 = Object.fromEntries(after.body.versions.map((v: any) => [v.version, v]));
    expect(by2["3"]).toMatchObject({ current: false, createdAt: t2.toISOString(), author: "Olivia Owner" });
    expect(by2["4"]).toMatchObject({ current: true, author: "ed@x.io" });
    expect(new Date(by2["4"].createdAt).getTime()).toBeGreaterThan(t2.getTime());
    expect(after.body.versions.map((v: any) => v.version)).toEqual(["4", "3", "2", "1"]);
  });

  it("an author with no user row: authorName omitted (never an id in its place)", async () => {
    const f = store.addFile({ project_id: P, name: "g.csv", s3_key: key("g.csv"), user_id: "ghost-9", version_author: "ghost-9" }, "a\n");
    const r = await json(await httpFetch(`${base}/api/projects/${P}/files/${f.id}/versions`));
    expect(r.body.versions[0]).not.toHaveProperty("authorName");
    expect(r.body.versions[0]).toMatchObject({ author: null, authorId: "ghost-9" });
  });

  it("diff changedCells: row is the 0-based index, rowNumber the 1-based data-row number", async () => {
    const f = store.addFile({ project_id: P, name: "d.csv", s3_key: key("d.csv.v2"), version_no: 2 }, "id,v\n1,a\n2,B\n");
    store.objects.set(key("d.csv"), Buffer.from("id,v\n1,a\n2,b\n"));
    store.versions.push({ file_id: f.id, project_id: P, version_no: 1, s3_key: key("d.csv"), size: 14, content_hash: "old", created_at: store.now() });
    // The rows reader's layout of both versions (headed comma CSV).
    galaxyFetch.mockImplementation(async () => ({ ok: true, status: 200, json: async () => ({
      kind: "table", viewKind: "table", tabular: true, columns: ["id", "v"], rows: [["1", "a"]], offset: 0, limit: 1,
      totalRows: 2, headerRow: true, namesSource: "header", skipLines: 0, delimiter: ",",
    }) }));
    const r = await json(await httpFetch(`${base}/api/projects/${P}/files/${f.id}/versions/1/diff`));
    expect(r.body.changedCells).toEqual([{ row: 1, rowNumber: 2, col: "v", from: "b", to: "B" }]);
  });
});

describe("rows — version contract", () => {
  it("returns the file's current version_no as `version` (the edit's baseVersion)", async () => {
    const f = store.addFile({ project_id: P, name: "t.csv", s3_key: key("t.csv"), version_no: 4 }, "a\n1\n");
    galaxyFetch.mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({ kind: "table", tabular: true, columns: ["a"], rows: [["1"]], offset: 0, limit: 200, totalRows: 1, headerRow: true }) });
    const r = await json(await httpFetch(`${base}/api/projects/${P}/files/${f.id}/rows`));
    expect(r.status).toBe(200);
    expect(r.body.version).toBe(4);
    expect(r.body.headerRow).toBe(true);
  });
});
