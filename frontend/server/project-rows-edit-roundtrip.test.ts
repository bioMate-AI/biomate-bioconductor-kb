// @vitest-environment node
/**
 * Rows → edit → diff ROUND TRIP over the real project routes (2026-11-12 round-2 audit NEW-1,
 * NEW-2, R13).
 *
 * The rows route's response fields must reach the edit route exactly as the client sends them
 * back, and the edit must use the SAME layout the rows reader used: header records
 * (`headerRow` → `headerRows`), leading comment/blank lines (`skipLines`) and the delimiter
 * (`delimiter`), with the row the user saw (`rowFrom`) as the safety check. The version diff
 * numbers rows with the same layout.
 *
 * The Python reader is not run here: its outputs for four real layouts were RECORDED once with
 * backend/lib/galaxy/ai/data_perception.py read_rows (python3.9, by file path) —
 * __fixtures__/rows-layout/record.py — and are served for the stored object's key:
 *   fc_comment_tsv   featureCounts counts.txt: one '# Program:' line, tab-separated
 *   blank_first_csv  a CSV whose first line is blank
 *   headerless_csv   a header-less numeric CSV
 *   semicolon_csv    a semicolon CSV with decimal commas
 * Each case edits a cell whose value ALSO appears in another row of that column where it can,
 * so a layout field dropped anywhere either lands the edit on the wrong row (caught by
 * `rowFrom` → 409) or mis-splits the record (`from` mismatch → 409) — never a silent success.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import express from "express";
import type { Server } from "http";
import type { AddressInfo } from "net";
import { readFileSync } from "fs";
import path from "path";
import { fakeStore as store } from "./project-files-fake-store";
import { pickDelimiter } from "./delimited-text";

const httpFetch = globalThis.fetch;
const P = "11111111-1111-4111-8111-111111111111";

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

type Recorded = { name: string; text: string; rows: Record<string, any> };
const FIX = path.join(__dirname, "__fixtures__", "rows-layout");
const load = (c: string): Recorded => JSON.parse(readFileSync(path.join(FIX, `${c}.json`), "utf8"));

// case → the cell the user edits (data row, column, new value)
const CASES: Record<string, { row: number; col: number; value: string }> = {
  fc_comment_tsv: { row: 1, col: 2, value: "-" },      // G2 Strand "+" (G1's Strand is "+" too)
  blank_first_csv: { row: 1, col: 1, value: "20" },     // B val "2"
  headerless_csv: { row: 1, col: 0, value: "40" },      // second data line, first value "4"
  semicolon_csv: { row: 1, col: 1, value: "chr9" },     // B chr "chr1" (A's chr is "chr1" too)
};

let server: Server;
let base = "";
/** stored object key (without a .vN version suffix) → recorded reader output */
const reader = new Map<string, Recorded>();

beforeAll(async () => {
  const { registerProjectRoutes } = await import("./project-routes");
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => { (req as any).user = { id: "owner-1" }; next(); });
  registerProjectRoutes(app);
  await new Promise<void>((r) => { server = app.listen(0, "127.0.0.1", () => r()); });
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
afterAll(() => server?.close());
beforeEach(() => {
  vi.clearAllMocks();
  store.reset();
  reader.clear();
  // The recorded reader: /api/perception/rows answers with the recorded output for the object
  // (any version of it — the edits keep the layout), paged like the real reader.
  galaxyFetch.mockImplementation(async (_req: any, url: string, init: any) => {
    expect(url).toBe("http://galaxy.test/api/perception/rows");
    const b = JSON.parse(init.body);
    const rec = reader.get(String(b.datasetRef).replace(/\.v\d+$/, ""));
    if (!rec) return { ok: false, status: 404, json: async () => ({ error: "unresolvable_ref" }) };
    const out = { ...rec.rows, offset: b.offset, limit: b.limit, rows: rec.rows.rows.slice(b.offset, b.offset + b.limit) };
    return { ok: true, status: 200, json: async () => out };
  });
});

const key = (name: string) => `projects/${P}/inputs/${name}`;
const json = async (r: Response) => ({ status: r.status, body: await r.json() as any });

function seed(c: string) {
  const rec = load(c);
  reader.set(key(rec.name), rec);
  const f = store.addFile({ project_id: P, name: rec.name, s3_key: key(rec.name) }, rec.text);
  return { rec, f };
}

// ── The client, mirrored ────────────────────────────────────────────────────────────────────
// datasets-api.ts (useDatasetRows: the rows state taken from the rows response) and
// dataset-object.tsx (onCellEdit → rowFrom; handleSaveEdit → the edit body). `delimiter` is the
// contract field the client sends back like skipLines. Keep in step with both files.
function clientRowsState(body: any) {
  return {
    rows: Array.isArray(body?.rows) ? body.rows as string[][] : [],
    headerRow: typeof body?.headerRow === "boolean" ? body.headerRow as boolean : null,
    version: typeof body?.version === "number" ? body.version as number : null,
    skipLines: Number.isInteger(body?.skipLines) && body.skipLines >= 0 ? body.skipLines as number : null,
    delimiter: typeof body?.delimiter === "string" ? body.delimiter as string : null,
  };
}
function clientEditPayload(st: ReturnType<typeof clientRowsState>, row: number, col: number, value: string) {
  const from = String(st.rows[row][col]);
  const rowFrom = (st.rows[row] ?? []).map(String);
  return {
    edits: [{ row, col, from, value, rowFrom }],
    ...(st.headerRow === null ? {} : { headerRows: st.headerRow ? 1 : 0 }),
    ...(st.version != null ? { baseVersion: st.version } : {}),
    ...(st.skipLines != null ? { skipLines: st.skipLines } : {}),
    ...(st.delimiter != null ? { delimiter: st.delimiter } : {}),
  };
}

async function readRows(fileId: string) {
  return json(await httpFetch(`${base}/api/projects/${P}/files/${fileId}/rows?offset=0&limit=200`));
}
async function edit(fileId: string, body: unknown) {
  return json(await httpFetch(`${base}/api/projects/${P}/files/${fileId}/edit`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
  }));
}
/** The file's bytes after the edit, built WITHOUT our parser: the recorded row's physical line
 *  (the fixtures have no quoting) with the one cell replaced. */
function expectedText(rec: Recorded, row: number, col: number, value: string): string {
  const d = rec.rows.delimiter as string;
  const line = (rec.rows.rows[row] as string[]).join(d);
  const edited = (rec.rows.rows[row] as string[]).map((v, j) => (j === col ? value : v)).join(d);
  expect(rec.text.split(/\r?\n/)).toContain(line);
  expect(rec.text.indexOf(line)).toBe(rec.text.lastIndexOf(line));
  return rec.text.replace(line, edited);
}

describe("recorded reader fixtures — the layouts under test", () => {
  it("cover every layout field the edit depends on", () => {
    const fc = load("fc_comment_tsv").rows, blank = load("blank_first_csv").rows;
    const hl = load("headerless_csv").rows, semi = load("semicolon_csv").rows;
    expect([fc.skipLines, fc.delimiter, fc.headerRow]).toEqual([1, "\t", true]);
    expect([blank.skipLines, blank.delimiter, blank.headerRow]).toEqual([1, ",", true]);
    expect([hl.skipLines, hl.headerRow, hl.columns]).toEqual([0, false, ["column_1", "column_2", "column_3"]]);
    expect([semi.skipLines, semi.delimiter, semi.headerRow]).toEqual([0, ";", true]);
    // the extension / first-line guess is WRONG for two of them (why the delimiter must travel)
    expect(pickDelimiter(load("fc_comment_tsv").text, "txt")).not.toBe("\t");
    expect(pickDelimiter(load("semicolon_csv").text, "csv")).not.toBe(";");
  });
});

describe("rows → edit round trip with the client's payload", () => {
  for (const [c, e] of Object.entries(CASES)) {
    it(`${c}: the rows response carries the layout and the edit lands on the cell the user saw`, async () => {
      const { rec, f } = seed(c);
      const rows = await readRows(f.id);
      expect(rows.status).toBe(200);
      expect(rows.body).toMatchObject({
        version: 1, headerRow: rec.rows.headerRow, skipLines: rec.rows.skipLines, delimiter: rec.rows.delimiter,
        columns: rec.rows.columns, rows: rec.rows.rows,
      });
      const payload = clientEditPayload(clientRowsState(rows.body), e.row, e.col, e.value);
      expect(payload).toMatchObject({
        baseVersion: 1, headerRows: rec.rows.headerRow ? 1 : 0, skipLines: rec.rows.skipLines, delimiter: rec.rows.delimiter,
        edits: [{ rowFrom: rec.rows.rows[e.row] }],
      });
      const r = await edit(f.id, payload);
      expect(r.status).toBe(200);
      expect(r.body.editedCells).toBe(1);
      const now = store.files.find((x) => x.id === f.id)!;
      expect(now.version_no).toBe(2);
      expect(store.objects.get(now.s3_key)!.toString("utf8")).toBe(expectedText(rec, e.row, e.col, e.value));
    });
  }
});

describe("a layout field dropped anywhere is refused, never applied elsewhere", () => {
  // Drop each field the case depends on (its value differs from the route's default): the
  // edit must come back 409 and nothing may be written.
  const drops: Array<[string, "skipLines" | "headerRows" | "delimiter"]> = [];
  for (const c of Object.keys(CASES)) {
    const rec = load(c);
    if (rec.rows.skipLines > 0) drops.push([c, "skipLines"]);
    if (rec.rows.headerRow === false) drops.push([c, "headerRows"]);
    if (pickDelimiter(rec.text, rec.name.split(".").pop()!) !== rec.rows.delimiter) drops.push([c, "delimiter"]);
  }
  it("every field is exercised by at least one case", () => {
    expect(new Set(drops.map(([, k]) => k))).toEqual(new Set(["skipLines", "headerRows", "delimiter"]));
  });
  for (const [c, field] of drops) {
    it(`${c} without ${field} → 409, file unchanged`, async () => {
      const { rec, f } = seed(c);
      const e = CASES[c];
      const payload: any = clientEditPayload(clientRowsState((await readRows(f.id)).body), e.row, e.col, e.value);
      delete payload[field];
      const r = await edit(f.id, payload);
      expect(r.status).toBe(409);
      expect(r.body.error).toBe("cell_conflict");
      expect(store.puts).toEqual([]);
      expect(store.objects.get(key(rec.name))!.toString("utf8")).toBe(rec.text);
    });
  }

  it("rowFrom is what refuses a mis-numbered row holding the same value (featureCounts, skipLines lost)", async () => {
    const { rec, f } = seed("fc_comment_tsv");
    const payload: any = clientEditPayload(clientRowsState((await readRows(f.id)).body), 1, 2, "-");
    delete payload.skipLines;  // row 1 now names G1, whose Strand is also "+"
    const r = await edit(f.id, payload);
    expect(r.status).toBe(409);
    expect(r.body.conflicts[0]).toMatchObject({ row: 1, col: 2, rowMismatch: true });
    expect(store.objects.get(key(rec.name))!.toString("utf8")).toBe(rec.text);
  });

  it("a delimiter outside the reader's set → 400", async () => {
    const { f } = seed("semicolon_csv");
    const payload: any = clientEditPayload(clientRowsState((await readRows(f.id)).body), 1, 1, "chr9");
    for (const bad of [":", "ab", "", 1, "\n"]) {
      const r = await edit(f.id, { ...payload, delimiter: bad });
      expect(r.status).toBe(400);
      expect(r.body.error).toMatch(/delimiter must be one of/);
    }
    expect(store.puts).toEqual([]);
  });
});

describe("version diff numbers rows like the reader (R13)", () => {
  for (const [c, e] of Object.entries(CASES)) {
    it(`${c}: rowNumber / column are the row and column the user edited`, async () => {
      const { rec, f } = seed(c);
      const payload = clientEditPayload(clientRowsState((await readRows(f.id)).body), e.row, e.col, e.value);
      expect((await edit(f.id, payload)).status).toBe(200);
      const d = await json(await httpFetch(`${base}/api/projects/${P}/files/${f.id}/versions/1/diff`));
      expect(d.status).toBe(200);
      expect(d.body.tabular).toBe(true);
      expect(d.body.columns).toEqual({ added: [], removed: [] });
      expect(d.body.changedCells).toEqual([{
        row: e.row, rowNumber: e.row + 1, col: rec.rows.columns[e.col], from: rec.rows.rows[e.row][e.col], to: e.value,
      }]);
    });
  }

  it("a version whose bytes cannot be read → 502, not a fake 'no changes'", async () => {
    const { rec, f } = seed("semicolon_csv");
    const payload = clientEditPayload(clientRowsState((await readRows(f.id)).body), 1, 1, "chr9");
    expect((await edit(f.id, payload)).status).toBe(200);
    store.objects.delete(key(rec.name));  // v1's object is gone
    const d = await json(await httpFetch(`${base}/api/projects/${P}/files/${f.id}/versions/1/diff`));
    expect(d.status).toBe(502);
    expect(d.body.error).toBe("diff_unavailable");
    expect(d.body.changedCells).toBeUndefined();
  });

  it("the reader failing → 502, not a diff on guessed rows", async () => {
    const { f } = seed("fc_comment_tsv");
    const payload = clientEditPayload(clientRowsState((await readRows(f.id)).body), 1, 2, "-");
    expect((await edit(f.id, payload)).status).toBe(200);
    galaxyFetch.mockImplementation(async () => ({ ok: false, status: 503, json: async () => ({}) }));
    const d = await json(await httpFetch(`${base}/api/projects/${P}/files/${f.id}/versions/1/diff`));
    expect(d.status).toBe(502);
    expect(d.body.error).toBe("diff_unavailable");
  });
});
