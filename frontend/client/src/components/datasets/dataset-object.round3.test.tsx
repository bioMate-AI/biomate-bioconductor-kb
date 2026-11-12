/**
 * Dataset panel round-3 seams (live dev walkthrough 2026-11-12), behaviour through the dataset
 * object. Our own endpoints are faked at fetch.
 *  B1  the Versions tab never shows another file's open diff;
 *  B2  after a save / restore the panel profiles the NEW storage key (the old one is archived) and
 *      hands the owner the new file row;
 *  W1  restore asks first, closes the stale diff and the "Saved as" line, says "Restored v1 as v3";
 *  W7  effective N / groups / "gives the group away" only for a labelled table, in plain words;
 *  W11 a JSON document's counts say what they count;
 *  P2  the title is the bare file name, its folders are breadcrumb segments;
 *  P3  the kind's measures are shown once (stat grid), not again in the QC card;
 *  P4  Plot is offered only when a column holds numbers (decimal comma included);
 *  P6  provenance wording: source in words, export under its own heading;
 *  P8  count-safe diff wording.
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, fireEvent, waitFor, within } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { DatasetObject, type DatasetRef } from "./dataset-object"
import { parseCellNumber } from "./dataset-sample-plot"

let profiles: Record<string, unknown> = {}
let profileRefs: string[] = []
let rowsByFile: Record<string, unknown> = {}
let versionsByFile: Record<string, unknown[]> = {}
let diffBody: unknown = {}
let editResponse: { status: number; body: unknown } = { status: 200, body: {} }
let restoreResponse: { status: number; body: unknown } = { status: 200, body: {} }
let restoreCalls = 0

beforeEach(() => {
  profiles = {}; profileRefs = []; rowsByFile = {}; versionsByFile = {}; diffBody = {}; restoreCalls = 0
  global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const raw = String(input)
    const res = (status: number, body: unknown) =>
      ({ ok: status < 400, status, json: async () => body, text: async () => "" }) as unknown as Response
    const url = new URL(raw, "http://x")
    const fileId = url.pathname.split("/files/")[1]?.split("/")[0]
    if (url.pathname === "/api/perception/profile") {
      const { datasetRef } = JSON.parse(String(init?.body ?? "{}"))
      profileRefs.push(datasetRef)
      return profiles[datasetRef] ? res(200, profiles[datasetRef]) : res(403, { error: "forbidden" })
    }
    if (url.pathname.endsWith("/rows")) return rowsByFile[fileId!] ? res(200, rowsByFile[fileId!]) : res(415, {})
    if (url.pathname.endsWith("/diff")) return res(200, diffBody)
    if (url.pathname.endsWith("/restore")) { restoreCalls++; return res(restoreResponse.status, restoreResponse.body) }
    if (url.pathname.endsWith("/edit")) return res(editResponse.status, editResponse.body)
    if (url.pathname.endsWith("/versions")) return res(200, { versions: versionsByFile[fileId!] ?? [] })
    return res(200, {})
  }) as unknown as typeof fetch
})

const qc = () => new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
function ds(name: string, extra: Partial<DatasetRef> = {}): DatasetRef {
  return { id: `id-${name}`, name, ref: `projects/p1/inputs/${name}`, size: 1000, source: "upload", ...extra }
}
function renderObj(dataset: DatasetRef, props: Record<string, unknown> = {}) {
  const client = qc()
  const ui = (d: DatasetRef) => (
    <QueryClientProvider client={client}>
      <DatasetObject projectId="p1" dataset={d} onRunQC={() => {}} onDownload={() => {}} {...props} />
    </QueryClientProvider>
  )
  const r = render(ui(dataset))
  return { ...r, show: (d: DatasetRef) => r.rerender(ui(d)) }
}

const TABLE = (rows: string[][], cols = ["gene_id", "ctrl_1"]) => ({
  columns: cols, rows, totalRows: rows.length, offset: 0, limit: 200, headerRow: true, version: 2, skipLines: 0, delimiter: "\t",
})
const tableProfile = (extra: Record<string, unknown> = {}) => ({
  shape: { rows: 2, cols: 2 }, quality: "good", notes: [], viewKind: "table", columns: ["gene_id", "ctrl_1"],
  sampleRows: [["G1", "10"], ["G2", "20"]], findings: [], ...extra,
})
const VERSIONS = [
  { version: "2", label: "v2", current: true, createdAt: "2026-11-12T03:00:00Z" },
  { version: "1", label: "v1", current: false, createdAt: "2026-11-12T02:00:00Z" },
]

describe("B1 — versions state belongs to the file it was opened on", () => {
  it("a diff opened on counts.tsv is not shown in samples_quoted.csv's Versions tab", async () => {
    const a = ds("counts.tsv"), b = ds("samples_quoted.csv")
    profiles[a.ref!] = tableProfile(); profiles[b.ref!] = tableProfile()
    versionsByFile[a.id] = VERSIONS; versionsByFile[b.id] = VERSIONS
    diffBody = { changedCells: [{ row: 0, col: "ctrl_1", from: "1868", to: "4242" }], changedCellCount: 1 }
    const { show } = renderObj(a)
    fireEvent.click(screen.getByTestId("dataset-tab-versions"))
    fireEvent.click(await screen.findByTestId("dataset-version-compare-1"))
    expect(await screen.findByTestId("dataset-version-diff-1")).toHaveTextContent("1868")
    show(b)
    fireEvent.click(screen.getByTestId("dataset-tab-versions"))
    await screen.findByTestId("dataset-version-compare-1")
    expect(screen.queryByTestId("dataset-version-diff-1")).toBeNull()
    expect(screen.getByTestId("dataset-version-compare-1")).toHaveAttribute("aria-expanded", "false")
  })
})

describe("B2 — after a save the panel reads the file at its NEW key", () => {
  it("profiles the key the edit response returned (not the archived one) and gives the owner the new row", async () => {
    const a = ds("counts.tsv")
    const newKey = "projects/p1/inputs/counts.tsv.v3"
    profiles[a.ref!] = tableProfile()
    profiles[newKey] = tableProfile({ quality: "watch" })
    rowsByFile[a.id] = TABLE([["G1", "10"], ["G2", "20"]])
    editResponse = { status: 200, body: { file: { id: a.id, name: a.name, s3_key: newKey, size: "1001", version_no: 3, content_hash: "abc" } } }
    const onFileChanged = vi.fn()
    renderObj(a, { onFileChanged })
    fireEvent.click(await screen.findByTestId("dataset-preview-toggle-edit"))
    fireEvent.change(await screen.findByTestId("dataset-edit-cell-0-1"), { target: { value: "11" } })
    fireEvent.click(screen.getByTestId("dataset-edit-save"))
    await waitFor(() => expect(profileRefs).toContain(newKey))
    // The QC card shows the new version's profile — never "Profile not available".
    await waitFor(() => expect(screen.getByTestId("data-perception")).toHaveAttribute("data-quality", "watch"))
    expect(screen.queryByTestId("dataset-quality-error")).toBeNull()
    expect(onFileChanged).toHaveBeenCalledWith(expect.objectContaining({ s3_key: newKey, version_no: 3 }))
  })
})

describe("W1 — restore asks first and leaves no stale diff / save message", () => {
  it("confirm → restore; the diff closes and 'Restored v1 as v3' is shown", async () => {
    const a = ds("counts.tsv")
    profiles[a.ref!] = tableProfile()
    profiles["projects/p1/inputs/counts.tsv.v3"] = tableProfile()
    versionsByFile[a.id] = VERSIONS
    diffBody = { changedCells: [{ row: 0, col: "ctrl_1", from: "1", to: "2" }], changedCellCount: 1 }
    restoreResponse = { status: 200, body: { file: { id: a.id, s3_key: "projects/p1/inputs/counts.tsv.v3", version_no: 3 }, restoredFrom: 1 } }
    renderObj(a)
    fireEvent.click(screen.getByTestId("dataset-tab-versions"))
    fireEvent.click(await screen.findByTestId("dataset-version-compare-1"))
    await screen.findByTestId("dataset-version-diff-1")
    fireEvent.click(screen.getByTestId("dataset-version-restore-1"))
    // Asked, not done.
    expect(screen.getByTestId("dataset-version-restore-confirm-1")).toHaveTextContent("Restore v1?")
    expect(restoreCalls).toBe(0)
    fireEvent.click(screen.getByTestId("dataset-version-restore-yes-1"))
    await waitFor(() => expect(restoreCalls).toBe(1))
    expect(await screen.findByTestId("dataset-version-restored")).toHaveTextContent("Restored v1 as v3.")
    expect(screen.queryByTestId("dataset-version-diff-1")).toBeNull()
  })

  it("cancel writes nothing", async () => {
    const a = ds("counts.tsv")
    profiles[a.ref!] = tableProfile(); versionsByFile[a.id] = VERSIONS
    renderObj(a)
    fireEvent.click(screen.getByTestId("dataset-tab-versions"))
    fireEvent.click(await screen.findByTestId("dataset-version-restore-1"))
    fireEvent.click(screen.getByTestId("dataset-version-restore-cancel-1"))
    expect(screen.queryByTestId("dataset-version-restore-confirm-1")).toBeNull()
    expect(restoreCalls).toBe(0)
  })
})

describe("W7 — labelled-table measures only for a labelled table, in plain words", () => {
  it("a count matrix with no label column shows no effective N, groups or leakage line", async () => {
    const a = ds("counts.tsv")
    profiles[a.ref!] = tableProfile({ shape: { rows: 40, cols: 5 }, effectiveN: 40,
      findings: [{ section: "note", code: "table_clean_unlabelled", level: "info", params: { rows: 40, cols: 5 } }] })
    renderObj(a)
    const card = await screen.findByTestId("data-perception")
    expect(within(card).queryByTestId("perception-effective-n")).toBeNull()
    expect(within(card).queryByTestId("perception-class-balance")).toBeNull()
    expect(card.textContent).not.toMatch(/Effective N/i)
  })

  it("a sample sheet with a condition column says 'Groups in “condition”: control 50% · treated 50%'", async () => {
    const a = ds("samples.csv")
    profiles[a.ref!] = tableProfile({ shape: { rows: 4, cols: 4 }, effectiveN: 4, labelColumn: "condition",
      classBalance: [{ label: "control", frac: 0.5 }, { label: "treated", frac: 0.5 }] })
    renderObj(a)
    const groups = await screen.findByTestId("perception-class-balance")
    expect(groups).toHaveTextContent("Groups in “condition”")
    expect(within(groups).getByTestId("perception-groups")).toHaveTextContent("control 50% · treated 50%")
    expect(groups.textContent).not.toMatch(/Class balance/)
    // Effective N equal to the rows adds nothing.
    expect(screen.queryByTestId("perception-effective-n")).toBeNull()
  })
})

describe("W11 — a JSON document's counts say what they count", () => {
  it("top-level keys in the stat grid; keys / values at all levels in the QC card, with tooltips", async () => {
    const a = ds("qc_metrics.json")
    profiles[a.ref!] = { shape: { rows: 0, cols: 0 }, quality: "unassessed", notes: [], viewKind: "json",
      structured: { format: "JSON", root: "object", nodes: 10, keys: 7, nulls: 0, depth: 3 },
      stats: [{ code: "entries", value: 5 }], findings: [] }
    renderObj(a, { preview: <div /> })
    const grid = await screen.findByTestId("dataset-stat-grid")
    await waitFor(() => expect(grid.querySelector('[data-stat="entries"]')).toHaveTextContent("Top-level keys"))
    expect(grid.querySelector('[data-stat="entries"] [title]')!.getAttribute("title")).toMatch(/outermost object/)
    expect(screen.getByTestId("perception-structured-keys")).toHaveTextContent("Keys (all levels)")
    expect(screen.getByTestId("perception-structured-values")).toHaveTextContent("Values (all levels)")
    expect(within(screen.getByTestId("perception-structured-keys")).getByTestId("perception-stat-gloss").getAttribute("title")).toMatch(/every depth/)
  })
})

describe("P2 — the title is the bare file name; folders are breadcrumb segments", () => {
  it("pairs/S1_R1.fastq.gz → title 'S1_R1.fastq.gz' (full path on hover), crumb 'pairs'", async () => {
    const a = ds("pairs/S1_R1.fastq.gz")
    profiles[a.ref!] = { shape: { rows: 0, cols: 0 }, quality: "good", notes: [], viewKind: "reads", findings: [] }
    renderObj(a, { preview: <div /> })
    const title = screen.getByTestId("dataset-object-name")
    expect(title.textContent).toBe("S1_R1.fastq.gz")
    expect(title).toHaveAttribute("title", "pairs/S1_R1.fastq.gz")
    expect(screen.getAllByTestId("dataset-object-crumb-folder").map((e) => e.textContent)).toEqual(["pairs"])
    expect(screen.getByTestId("dataset-object-id").textContent).toBe("S1_R1.fastq.gz")
    // May wrap only after a separator, never mid-word.
    expect(title.querySelectorAll("wbr").length).toBeGreaterThan(0)
    expect(title.className).not.toMatch(/overflow-wrap:anywhere/)
  })
})

describe("P3 — rows / columns shown once", () => {
  it("the table's rows and columns are in the stat grid, not repeated in the QC card", async () => {
    const a = ds("counts.tsv")
    profiles[a.ref!] = tableProfile()
    rowsByFile[a.id] = TABLE([["G1", "10"], ["G2", "20"]])
    renderObj(a)
    const card = await screen.findByTestId("data-perception")
    await waitFor(() => expect(screen.getByTestId("dataset-stat-grid").querySelector('[data-stat="rows"]')).toHaveTextContent("2"))
    expect(within(card).queryByTestId("perception-stat-rows")).toBeNull()
    expect(within(card).queryByTestId("perception-stat-columns")).toBeNull()
  })
})

describe("P4 — Plot only where something can be plotted", () => {
  it("a gene list (one text column) has no Plot", async () => {
    const a = ds("gene_list.txt")
    profiles[a.ref!] = tableProfile({ columns: ["column_1"], sampleRows: [["TP53"], ["BRCA1"]] })
    rowsByFile[a.id] = TABLE([["TP53"], ["BRCA1"], ["EGFR"]], ["column_1"])
    renderObj(a)
    await screen.findByTestId("dataset-preview-toggle-table")
    await waitFor(() => expect(screen.getAllByTestId("dataset-preview-row")).toHaveLength(3))
    expect(screen.queryByTestId("dataset-preview-toggle-plot")).toBeNull()
  })

  it("a header-only table has no Plot", async () => {
    const a = ds("header_only.tsv")
    profiles[a.ref!] = tableProfile({ shape: { rows: 0, cols: 2 }, sampleRows: [] })
    rowsByFile[a.id] = { ...TABLE([]), totalRows: 0 }
    renderObj(a)
    await screen.findByTestId("dataset-preview-no-rows")
    expect(screen.queryByTestId("dataset-preview-toggle-plot")).toBeNull()
  })

  it("decimal-comma numbers count once the reader reports decimal ','", async () => {
    const a = ds("eu_measurements.csv")
    profiles[a.ref!] = tableProfile({ columns: ["sample", "conc"] })
    rowsByFile[a.id] = { ...TABLE([["s1", "1,5"], ["s2", "2,25"], ["s3", "1.234,5"]], ["sample", "conc"]), delimiter: ";", decimal: "," }
    renderObj(a)
    fireEvent.click(await screen.findByTestId("dataset-preview-toggle-plot"))
    expect(await screen.findByTestId("dataset-sample-plot-caption")).toHaveTextContent("Distribution of column “conc” · rows loaded: 3")
    expect(parseCellNumber("1,5", ",")).toBe(1.5)
    expect(parseCellNumber("1.234,5", ",")).toBe(1234.5)
    expect(Number.isNaN(parseCellNumber("1,5"))).toBe(true)
  })
})

describe("P6 — provenance in plain words", () => {
  it("source 'upload' reads 'Uploaded file'; Export has its own heading, apart from 'Input to workflow'", async () => {
    const a = ds("counts.tsv", { contentHash: "0123456789abcdef" })
    profiles[a.ref!] = tableProfile()
    renderObj(a)
    fireEvent.click(screen.getByTestId("dataset-tab-wherefrom"))
    const origin = await screen.findByTestId("dataset-origin")
    expect(origin).toHaveTextContent("Uploaded file")
    expect(origin.textContent).not.toMatch(/\bupload\b/)
    expect(screen.getByTestId("dataset-content-hash")).toHaveTextContent("adding the same file again reuses this entry")
    const exp = screen.getByTestId("dataset-export")
    expect(exp).toHaveTextContent("Export")
    expect(within(exp).getByTestId("dataset-object-rocrate")).toBeInTheDocument()
    expect(within(screen.getByTestId("dataset-consumers")).queryByTestId("dataset-object-rocrate")).toBeNull()
  })
})

describe("P8 — count-safe diff wording", () => {
  it("'Changed cells: 1', and 'at least N' when the count is a lower bound", async () => {
    const a = ds("counts.tsv")
    profiles[a.ref!] = tableProfile(); versionsByFile[a.id] = VERSIONS
    diffBody = { changedCells: [{ row: 0, col: "ctrl_1", from: "1", to: "2" }], changedCellCount: 1, changedCellCountExact: true }
    renderObj(a)
    fireEvent.click(screen.getByTestId("dataset-tab-versions"))
    fireEvent.click(await screen.findByTestId("dataset-version-compare-1"))
    expect(await screen.findByTestId("dataset-diff-cellcount")).toHaveTextContent("Changed cells: 1")
    expect(screen.getByTestId("dataset-diff-cellcount").textContent).not.toMatch(/1 changed cells/)
    fireEvent.click(screen.getByTestId("dataset-version-compare-1"))
    diffBody = { changedCells: Array.from({ length: 6 }, (_, i) => ({ row: i, col: "ctrl_1", from: "1", to: "2" })), changedCellCount: 5000, changedCellCountExact: false, changedCellsTruncated: true }
    fireEvent.click(screen.getByTestId("dataset-version-compare-1"))
    await waitFor(() => expect(screen.getByTestId("dataset-diff-cellcount")).toHaveTextContent("Changed cells: at least 5,000"))
    expect(screen.getByTestId("dataset-diff-cellcount")).toHaveTextContent("First 5 shown.")
  })
})
