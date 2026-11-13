// @vitest-environment node
/**
 * Folder profile (2026-11-11):
 *   - project-folders.ts helpers (folder path normalization, folder membership, siblings);
 *   - GET /api/projects/:id/folders/profile — route BEHAVIOUR over loopback HTTP (same harness
 *     as project-file-rows-upload.test.ts): owner/member scope, the backend gets the folder's
 *     files with their DB keys, the client never sees a key, ?download=samplesheet;
 *   - GET /files/:fileId/rows forwards the file's folderContext;
 *   - routes.ts attaches the server-side folderContext to /api/perception/* (source contract).
 * Faked seams are our own modules only (./db, ./auth-middleware, ./memory-repository,
 * ./s3-client, ./galaxy-user-fetch). The pairing / 10x logic itself is tested in
 * backend/lib/galaxy/ai/tests/test_folder_profile.py.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import type { AddressInfo } from "net";
import express from "express";
import type { Server } from "http";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import {
  dirOf, filesUnderFolder, folderSiblings, likePrefix, normalizeFolderPath, samplesheetFilename,
  samplesheetStoredName, pickFolderSamplesheetCsv,
} from "./project-folders";

const httpFetch = globalThis.fetch;
const HERE = path.dirname(fileURLToPath(import.meta.url));

let fileRows: Array<Record<string, any>> = [];
const queries: Array<{ t: string; p: any[] }> = [];

function likeMatch(name: string, pattern: string): boolean {
  // Only "<escaped prefix>/%" patterns are generated.
  const prefix = pattern.slice(0, -1).replace(/\\([\\%_])/g, "$1");
  return name.startsWith(prefix);
}

async function fakeQuery(text: string, params: any[] = []): Promise<any> {
  const t = text.replace(/\s+/g, " ").trim();
  queries.push({ t, p: params });
  if (/FROM project_members WHERE project_id/.test(t)) return { rows: [] };
  if (/SELECT s3_key, name, source, version_no FROM project_files WHERE id::text = \$1 AND project_id::text = \$2/.test(t)) {
    return { rows: fileRows.filter((r) => r.id === params[0] && r.project_id === params[1]) };
  }
  if (/^SELECT (id::text AS id, )?name, (s3_key, )?source FROM project_files WHERE project_id::text = \$1/.test(t)
    || /^SELECT id::text AS id, name, s3_key, source FROM project_files WHERE project_id::text = \$1/.test(t)) {
    let rows = fileRows.filter((r) => r.project_id === params[0]);
    if (/name LIKE \$2/.test(t)) rows = rows.filter((r) => likeMatch(r.name, params[1]));
    if (/position\('\/' in name\) = 0/.test(t)) rows = rows.filter((r) => !r.name.includes("/"));
    return { rows: rows.map((r) => ({ id: r.id, name: r.name, s3_key: r.s3_key, source: r.source })) };
  }
  return { rows: [] };
}

const getProject = vi.fn();
const galaxyFetch = vi.fn();
vi.mock("./db", () => ({ pool: { query: (t: string, p?: any[]) => fakeQuery(t, p) } }));
vi.mock("./auth-middleware", () => ({ authenticateToken: (_q: any, _s: any, next: any) => next() }));
vi.mock("./memory-repository", () => ({ memoryService: { projects: { getProject: (...a: any[]) => getProject(...a) }, ensureLtmUser: async () => {} } }));
vi.mock("./s3-client", () => ({ s3Service: { putObject: vi.fn() } }));
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

const PAIRS = [
  { id: "aaaaaaaa-0000-4000-8000-000000000000", project_id: "11111111-1111-4111-8111-111111111111", name: "pairs/S1_R1.fastq.gz", s3_key: "projects/11111111-1111-4111-8111-111111111111/inputs/pairs/S1_R1.fastq.gz", source: "upload" },
  { id: "bbbbbbbb-0000-4000-8000-000000000000", project_id: "11111111-1111-4111-8111-111111111111", name: "pairs/S1_R2.fastq.gz", s3_key: "projects/11111111-1111-4111-8111-111111111111/inputs/pairs/S1_R2.fastq.gz", source: "upload" },
  { id: "cccccccc-0000-4000-8000-000000000000", project_id: "11111111-1111-4111-8111-111111111111", name: "pairs/S2_R1.fastq.gz", s3_key: "projects/11111111-1111-4111-8111-111111111111/inputs/pairs/S2_R1.fastq.gz", source: "upload" },
  { id: "dddddddd-0000-4000-8000-000000000000", project_id: "11111111-1111-4111-8111-111111111111", name: "pairs_x/other.csv", s3_key: "projects/11111111-1111-4111-8111-111111111111/inputs/pairs_x/other.csv", source: "upload" },
  { id: "eeeeeeee-0000-4000-8000-000000000000", project_id: "11111111-1111-4111-8111-111111111111", name: "pairs/qc.html", s3_key: "projects/11111111-1111-4111-8111-111111111111/outputs/qc.html", source: "run_output" },
  { id: "ffffffff-0000-4000-8000-000000000000", project_id: "11111111-1111-4111-8111-111111111111", name: "top.csv", s3_key: "projects/11111111-1111-4111-8111-111111111111/inputs/top.csv", source: "upload" },
];
const PROFILE = {
  path: "pairs", kind: "fastq_set", fileCount: 3, rollup: [{ format: "fastq", label: "FASTQ", count: 3, pairs: 1 }],
  findings: [{ code: "folder_fastq_orphan", level: "watch", params: { name: "S2_R1.fastq.gz", sample: "S2", missing: "R2" } }],
  fastq: { verdict: "mixed", pattern: "Rs", engine: "galaxy", pairs: 1, samples: [], orphans: ["pairs/S2_R1.fastq.gz"], singles: [] },
  samplesheet: { columns: ["sample", "fastq_1", "fastq_2"], rows: [], filename: "samplesheet.csv",
    csv: "sample,fastq_1,fastq_2\nS1,pairs/S1_R1.fastq.gz,pairs/S1_R2.fastq.gz\nS2,pairs/S2_R1.fastq.gz,\n" },
};
const ok = (body: unknown) => ({ ok: true, status: 200, json: async () => body });

beforeEach(() => {
  vi.clearAllMocks();
  queries.length = 0;
  fileRows = PAIRS.map((r) => ({ ...r }));
  currentUser = { id: "owner-1" };
  getProject.mockResolvedValue({ id: "11111111-1111-4111-8111-111111111111", userId: "owner-1" });
  galaxyFetch.mockResolvedValue(ok(PROFILE));
});

describe("project-folders helpers", () => {
  it("normalizes folder paths and rejects traversal / control characters", () => {
    expect(normalizeFolderPath(undefined)).toBe("");
    expect(normalizeFolderPath("pairs/")).toBe("pairs");
    expect(normalizeFolderPath("inputs/run1//fastq")).toBe("run1/fastq");
    expect(normalizeFolderPath("inputs")).toBe("");
    expect(normalizeFolderPath("a/../b")).toBeNull();
    expect(normalizeFolderPath("a\u0000b")).toBeNull();
    expect(normalizeFolderPath(["x"])).toBeNull();
  });
  it("selects input files below a folder (not a sibling folder sharing the prefix, not run outputs)", () => {
    expect(filesUnderFolder(PAIRS, "pairs").map((r) => r.name)).toEqual(["pairs/S1_R1.fastq.gz", "pairs/S1_R2.fastq.gz", "pairs/S2_R1.fastq.gz"]);
    expect(filesUnderFolder(PAIRS, "").length).toBe(5);
    expect(folderSiblings(PAIRS, "pairs/S1_R1.fastq.gz")).toEqual(["pairs/S1_R2.fastq.gz", "pairs/S2_R1.fastq.gz"]);
    expect(folderSiblings(PAIRS, "top.csv")).toEqual([]);
    expect(dirOf("a/b/c.txt")).toBe("a/b");
    expect(likePrefix("a_b%c\\")).toBe("a\\_b\\%c\\\\");
    expect(samplesheetFilename("run1/fastq")).toBe("fastq_samplesheet.csv");
    expect(samplesheetFilename("")).toBe("inputs_samplesheet.csv");
    expect(samplesheetStoredName("pairs", "samplesheet.csv")).toBe("pairs/samplesheet.csv");
    expect(samplesheetStoredName("", null)).toBe("inputs_samplesheet.csv");
    expect(pickFolderSamplesheetCsv({ csv: "a,b\n" })?.csv).toBe("a,b\n");
    expect(pickFolderSamplesheetCsv({ csv: "paired\n", single: { csv: "single\n", filename: "se.csv" } }, "single_end")).toEqual({
      csv: "single\n", filename: "se.csv",
    });
    expect(pickFolderSamplesheetCsv({ csv: undefined })).toBeNull();
  });
});

describe("POST /api/projects/:id/folders/samplesheet (source contract)", () => {
  const src = fs.readFileSync(path.join(HERE, "project-routes.ts"), "utf8");
  it("persists samplesheet via folder_profile + _storeProjectInput (upload source)", () => {
    expect(src).toMatch(/app\.post\("\/api\/projects\/:id\/folders\/samplesheet"/);
    expect(src).toContain("pickFolderSamplesheetCsv");
    expect(src).toContain("samplesheetStoredName");
    expect(src).toMatch(/source:\s*"upload"/);
    expect(src).toContain('error: "no_samplesheet"');
  });
});

describe("GET /api/projects/:id/folders/files", () => {
  it("returns every input file id under the folder prefix (not sibling folders / run outputs)", async () => {
    const r = await httpFetch(`${base}/api/projects/11111111-1111-4111-8111-111111111111/folders/files?path=pairs`);
    expect(r.status).toBe(200);
    const body = await r.json();
    expect(body.path).toBe("pairs");
    expect(body.files).toEqual([
      { id: "aaaaaaaa-0000-4000-8000-000000000000", name: "pairs/S1_R1.fastq.gz" },
      { id: "bbbbbbbb-0000-4000-8000-000000000000", name: "pairs/S1_R2.fastq.gz" },
      { id: "cccccccc-0000-4000-8000-000000000000", name: "pairs/S2_R1.fastq.gz" },
    ]);
  });

  it("404s for an unknown folder; 400 for traversal; 404 for a non-member", async () => {
    expect((await httpFetch(`${base}/api/projects/11111111-1111-4111-8111-111111111111/folders/files?path=nope`)).status).toBe(404);
    expect((await httpFetch(`${base}/api/projects/11111111-1111-4111-8111-111111111111/folders/files?path=../x`)).status).toBe(400);
    currentUser = { id: "stranger" };
    expect((await httpFetch(`${base}/api/projects/11111111-1111-4111-8111-111111111111/folders/files?path=pairs`)).status).toBe(404);
  });
});

describe("GET /api/projects/:id/folders/profile", () => {
  it("sends the folder's input files (DB keys) to the backend and returns the profile without keys", async () => {
    const r = await httpFetch(`${base}/api/projects/11111111-1111-4111-8111-111111111111/folders/profile?path=pairs`);
    expect(r.status).toBe(200);
    const body = await r.json();
    expect(body.kind).toBe("fastq_set");
    const [, url, init] = galaxyFetch.mock.calls[0];
    expect(url).toBe("http://galaxy.test/api/perception/folder_profile");
    expect(JSON.parse(init.body)).toEqual({
      projectId: "11111111-1111-4111-8111-111111111111",
      path: "pairs",
      files: [
        { name: "pairs/S1_R1.fastq.gz", datasetRef: "projects/11111111-1111-4111-8111-111111111111/inputs/pairs/S1_R1.fastq.gz" },
        { name: "pairs/S1_R2.fastq.gz", datasetRef: "projects/11111111-1111-4111-8111-111111111111/inputs/pairs/S1_R2.fastq.gz" },
        { name: "pairs/S2_R1.fastq.gz", datasetRef: "projects/11111111-1111-4111-8111-111111111111/inputs/pairs/S2_R1.fastq.gz" },
      ],
    });
    expect(JSON.stringify(body)).not.toContain("projects/11111111-1111-4111-8111-111111111111/");
    // The folder query is a LIKE on the escaped prefix ("pairs_x" is not under "pairs").
    expect(queries.some((q) => /name LIKE \$2 ESCAPE/.test(q.t) && q.p[1] === "pairs/%")).toBe(true);
  });

  it("downloads the samplesheet CSV as an attachment", async () => {
    const r = await httpFetch(`${base}/api/projects/11111111-1111-4111-8111-111111111111/folders/profile?path=inputs/pairs&download=samplesheet`);
    expect(r.status).toBe(200);
    expect(r.headers.get("content-type")).toMatch(/^text\/csv/);
    expect(r.headers.get("content-disposition")).toBe('attachment; filename="pairs_samplesheet.csv"');
    const csv = await r.text();
    expect(csv.trim().split("\n")).toEqual(["sample,fastq_1,fastq_2", "S1,pairs/S1_R1.fastq.gz,pairs/S1_R2.fastq.gz", "S2,pairs/S2_R1.fastq.gz,"]);
  });

  it("404 no_samplesheet for a folder without FASTQs; 404 for an unknown folder; 400 for traversal", async () => {
    galaxyFetch.mockResolvedValueOnce(ok({ ...PROFILE, kind: "mixed", samplesheet: undefined }));
    expect((await httpFetch(`${base}/api/projects/11111111-1111-4111-8111-111111111111/folders/profile?path=pairs_x&download=samplesheet`)).status).toBe(404);
    expect((await httpFetch(`${base}/api/projects/11111111-1111-4111-8111-111111111111/folders/profile?path=nope`)).status).toBe(404);
    expect((await httpFetch(`${base}/api/projects/11111111-1111-4111-8111-111111111111/folders/profile?path=../x`)).status).toBe(400);
  });

  it("404s for a non-member without touching the backend; 502 when the backend fails", async () => {
    currentUser = { id: "stranger" };
    expect((await httpFetch(`${base}/api/projects/11111111-1111-4111-8111-111111111111/folders/profile?path=pairs`)).status).toBe(404);
    expect(galaxyFetch).not.toHaveBeenCalled();
    currentUser = { id: "owner-1" };
    galaxyFetch.mockResolvedValueOnce({ ok: false, status: 500, json: async () => ({}) });
    expect((await httpFetch(`${base}/api/projects/11111111-1111-4111-8111-111111111111/folders/profile?path=pairs`)).status).toBe(502);
  });
});

describe("GET /files/:fileId/rows — folder context", () => {
  it("forwards the file's folder siblings (input files of the same directory only)", async () => {
    galaxyFetch.mockResolvedValueOnce(ok({ kind: "table", tabular: true, columns: ["a"], rows: [], offset: 0, limit: 200, totalRows: 0 }));
    await httpFetch(`${base}/api/projects/11111111-1111-4111-8111-111111111111/files/aaaaaaaa-0000-4000-8000-000000000000/rows`);
    const sent = JSON.parse(galaxyFetch.mock.calls[0][2].body);
    expect(sent.folderContext).toEqual({ name: "pairs/S1_R1.fastq.gz", siblings: ["pairs/S1_R2.fastq.gz", "pairs/S2_R1.fastq.gz"] });
  });
});

describe("routes.ts — /api/perception/* folder context (source contract)", () => {
  const src = fs.readFileSync(path.join(HERE, "routes.ts"), "utf8");
  it("attaches the server-side folderContext after the dataset access check, before the proxy", () => {
    expect(src).toMatch(/app\.post\("\/api\/perception\/profile", authenticateToken, perceptionProxyGate, requireDatasetAccess\(\), attachFolderContext, recordProfile, _dlProxyHandler\)/);
    expect(src).toMatch(/app\.all\("\/api\/perception\/\*", authenticateToken, perceptionProxyGate, requireDatasetAccess\(\), attachFolderContext, _dlProxyHandler\)/);
  });
  it("never forwards a client-supplied folderContext", () => {
    const body = src.slice(src.indexOf("const attachFolderContext"), src.indexOf('app.post("/api/perception/profile"'));
    expect(body).toContain("delete req.body.folderContext");
    expect(body.indexOf("delete req.body.folderContext")).toBeLessThan(body.indexOf("req.body.folderContext = ctx"));
  });
});
