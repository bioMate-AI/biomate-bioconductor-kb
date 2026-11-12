// @vitest-environment node
/**
 * Data panel fixes (2026-11-10) — route BEHAVIOUR tests for
 *   - POST /api/projects/:id/files/upload with a folder `relativePath`
 *   - GET  /api/projects/:id/files/:fileId/rows (paged FULL rows contract, incl. JSONL)
 *
 * Mounts the real registerProjectRoutes on express over loopback HTTP (same harness as
 * project-activity.test.ts). Faked seams are our own modules only: ./db, ./auth-middleware,
 * ./memory-repository, ./s3-client and ./galaxy-user-fetch (the Python rows reader is
 * covered by backend/lib/galaxy/ai/tests/test_data_perception.py).
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import type { AddressInfo } from "net";
import express from "express";
import type { Server } from "http";
import { projectInputPath, decodeMultipartFilename } from "./project-file-paths";

const httpFetch = globalThis.fetch;

let fileRows: Array<Record<string, any>> = [];
let membership: Array<Record<string, any>> = [];
const inserted: any[][] = [];

async function fakeQuery(text: string, params: any[] = []): Promise<any> {
  const t = text.replace(/\s+/g, " ").trim();
  if (/FROM project_members WHERE project_id/.test(t)) return { rows: membership };
  if (t.startsWith("INSERT INTO project_files")) {
    inserted.push(params);
    return { rows: [{ id: "f-new", name: params[2], s3_key: params[3], size: params[4], content_type: params[5], source: "upload" }] };
  }
  if (/SELECT s3_key, name(, source)? FROM project_files WHERE id = \$1 AND project_id = \$2/.test(t)) {
    return { rows: fileRows.filter((r) => r.id === params[0] && r.project_id === params[1]) };
  }
  return { rows: [] };
}

const getProject = vi.fn();
const putObject = vi.fn();
const galaxyFetch = vi.fn();

vi.mock("./db", () => ({ pool: { query: (t: string, p?: any[]) => fakeQuery(t, p) } }));
vi.mock("./auth-middleware", () => ({ authenticateToken: (_q: any, _s: any, next: any) => next() }));
vi.mock("./memory-repository", () => ({ memoryService: { projects: { getProject: (...a: any[]) => getProject(...a) }, ensureLtmUser: async () => {} } }));
vi.mock("./s3-client", () => ({ s3Service: { putObject: (...a: any[]) => putObject(...a) } }));
vi.mock("./galaxy-user-fetch", () => ({
  fetchGalaxyAsUser: (...a: any[]) => galaxyFetch(...a),
  galaxyBaseUrl: () => "http://galaxy.test",
}));

let server: Server;
let base = "";
let currentUser: { id: string } | null = { id: "owner-1" };

beforeAll(async () => {
  const { registerProjectRoutes } = await import("./project-routes");
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => { if (currentUser) (req as any).user = currentUser; next(); });
  registerProjectRoutes(app);
  await new Promise<void>((r) => { server = app.listen(0, "127.0.0.1", () => r()); });
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
afterAll(() => server?.close());
beforeEach(() => {
  vi.clearAllMocks();
  fileRows = [];
  membership = [];
  inserted.length = 0;
  currentUser = { id: "owner-1" };
  getProject.mockResolvedValue({ id: "p1", userId: "owner-1" });
});

describe("projectInputPath — folder structure + safe keys", () => {
  it("keeps folders in the name and the key; drops traversal segments", () => {
    expect(projectInputPath("S1.fastq.gz", "run1/fastq/S1.fastq.gz")).toEqual({
      name: "run1/fastq/S1.fastq.gz", keyPath: "run1/fastq/S1.fastq.gz",
    });
    const evil = projectInputPath("x.csv", "../../etc/./x.csv");
    expect(evil.name).toBe("etc/x.csv");
    expect(evil.keyPath).toBe("etc/x.csv");
    expect(projectInputPath("a.csv", "").name).toBe("a.csv");
    expect(projectInputPath("C:\\Users\\me\\a.csv", null).name).toBe("a.csv");
  });
  it("never collapses two non-ASCII names onto one S3 key", () => {
    const a = projectInputPath("数据.csv", "数据.csv");
    const b = projectInputPath("样本.csv", "样本.csv");
    expect(a.name).toBe("数据.csv");
    expect(a.keyPath).toMatch(/^__-[0-9a-f]{8}\.csv$/);
    expect(a.keyPath).not.toBe(b.keyPath);
  });
  it("re-decodes multer's latin1 filename as UTF-8", () => {
    const mojibake = Buffer.from("样本.csv", "utf8").toString("latin1");
    expect(decodeMultipartFilename(mojibake)).toBe("样本.csv");
    expect(decodeMultipartFilename("plain.csv")).toBe("plain.csv");
    expect(decodeMultipartFilename("样本.csv")).toBe("样本.csv");
  });
});

describe("POST /files/upload — relativePath", () => {
  it("stores the folder-relative name and a matching S3 key", async () => {
    const form = new FormData();
    form.append("relativePath", "batch_01/tables/epar.jsonl");
    form.append("file", new Blob(['{"a":1}\n'], { type: "" }), "epar.jsonl");
    const r = await httpFetch(`${base}/api/projects/p1/files/upload`, { method: "POST", body: form });
    expect(r.status).toBe(201);
    const body = await r.json();
    expect(body.file.name).toBe("batch_01/tables/epar.jsonl");
    expect(body.file.s3_key).toBe("projects/p1/inputs/batch_01/tables/epar.jsonl");
    expect(body.file.content_type).toBe("application/x-ndjson");
    expect(putObject.mock.calls[0][0]).toBe("projects/p1/inputs/batch_01/tables/epar.jsonl");
  });

  it("a plain file pick (no relativePath) keeps the basename", async () => {
    const form = new FormData();
    form.append("file", new Blob(["a,b\n1,2\n"]), "counts.csv");
    const r = await httpFetch(`${base}/api/projects/p1/files/upload`, { method: "POST", body: form });
    expect(r.status).toBe(201);
    expect((await r.json()).file.name).toBe("counts.csv");
  });
});

describe("GET /files/:fileId/rows — contract", () => {
  const ok = (body: unknown) => ({ ok: true, status: 200, json: async () => body });

  it("returns a page of full JSONL rows with the true total", async () => {
    fileRows = [{ id: "f1", project_id: "p1", s3_key: "projects/p1/inputs/epar.jsonl", name: "epar.jsonl" }];
    galaxyFetch.mockResolvedValue(ok({
      kind: "jsonl", tabular: true, offset: 200, limit: 200, totalRows: 2281,
      columns: ["source", "drug", "page", "headers", "rows"],
      rows: [["epar_table", "pluvicto", "30", '["A","B"]', '[["x"]]']],
    }));
    const r = await httpFetch(`${base}/api/projects/p1/files/f1/rows?offset=200&limit=200`);
    expect(r.status).toBe(200);
    const body = await r.json();
    expect(body).toEqual({
      kind: "jsonl", offset: 200, limit: 200, totalRows: 2281,
      columns: ["source", "drug", "page", "headers", "rows"],
      rows: [["epar_table", "pluvicto", "30", '["A","B"]', '[["x"]]']],
    });
    // Backend called with the DB's key (never a client-supplied path) and the requested range.
    const [, url, init] = galaxyFetch.mock.calls[0];
    expect(url).toBe("http://galaxy.test/api/perception/rows");
    expect(JSON.parse(init.body)).toMatchObject({ datasetRef: "projects/p1/inputs/epar.jsonl", offset: 200, limit: 200 });
    // The S3 key is not leaked to the client.
    expect(JSON.stringify(body)).not.toContain("projects/p1/inputs");
  });

  it("404s for a non-member without touching the backend (no existence leak)", async () => {
    currentUser = { id: "stranger" };
    fileRows = [{ id: "f1", project_id: "p1", s3_key: "k", name: "a.csv" }];
    const r = await httpFetch(`${base}/api/projects/p1/files/f1/rows`);
    expect(r.status).toBe(404);
    expect(galaxyFetch).not.toHaveBeenCalled();
  });

  it("404s for a file outside the project, 400s for a bad range", async () => {
    expect((await httpFetch(`${base}/api/projects/p1/files/missing/rows`)).status).toBe(404);
    expect((await httpFetch(`${base}/api/projects/p1/files/f1/rows?offset=-1`)).status).toBe(400);
  });

  it("maps non-tabular and parse failures to explicit statuses", async () => {
    fileRows = [{ id: "f1", project_id: "p1", s3_key: "k", name: "r.fastq" }];
    galaxyFetch.mockResolvedValueOnce(ok({ kind: "fastq", tabular: false }));
    const r1 = await httpFetch(`${base}/api/projects/p1/files/f1/rows`);
    expect(r1.status).toBe(415);
    expect(await r1.json()).toEqual({ error: "not_tabular", kind: "fastq" });
    galaxyFetch.mockResolvedValueOnce(ok({ error: "parse_failed", detail: "x" }));
    expect((await httpFetch(`${base}/api/projects/p1/files/f1/rows`)).status).toBe(422);
    galaxyFetch.mockResolvedValueOnce({ ok: false, status: 500, json: async () => ({}) });
    expect((await httpFetch(`${base}/api/projects/p1/files/f1/rows`)).status).toBe(502);
  });
});
