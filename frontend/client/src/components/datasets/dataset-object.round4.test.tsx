/**
 * Dataset panel round-4 seams (live dev walkthrough 2026-11-12), behaviour through the dataset
 * object. Our own endpoints are faked at fetch.
 *  N5  each fact once: numbers in the stat grid, findings in the QC card, content in the preview,
 *      and no second Download / Ask-in-chat beside the header's (mtx, bam, xlsx, h5ad);
 *  N6  the plot opens on a measurement column, not featureCounts' "Start";
 *  N9  "Run full QC" says what it does (a chat-run QC report), not "FastQC + MultiQC";
 *  N11 a header-only table offers no Run full QC and no Edit; a partially loaded table's plot says
 *      it uses the loaded rows and offers them all;
 *  N8  the tab list scrolls sideways instead of wrapping;
 *  N12 the QC card names the file by its base name (full path on hover).
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, fireEvent, waitFor, within } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { DatasetObject, type DatasetRef } from "./dataset-object"

let profiles: Record<string, unknown> = {}
let rowsByFile: Record<string, { columns: string[]; rows: string[][]; [k: string]: unknown }> = {}
let rowRequests: string[] = []

beforeEach(() => {
  profiles = {}; rowsByFile = {}; rowRequests = []
  global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const raw = String(input)
    const res = (status: number, body: unknown) =>
      ({ ok: status < 400, status, json: async () => body, text: async () => "" }) as unknown as Response
    const url = new URL(raw, "http://x")
    const fileId = url.pathname.split("/files/")[1]?.split("/")[0]
    if (url.pathname === "/api/perception/profile") {
      const { datasetRef } = JSON.parse(String(init?.body ?? "{}"))
      return profiles[datasetRef] ? res(200, profiles[datasetRef]) : res(403, {})
    }
    if (url.pathname.endsWith("/rows")) {
      rowRequests.push(url.search)
      const t = rowsByFile[fileId!]
      if (!t) return res(415, {})
      // Paged like the real endpoint: `pageSize` rows from `offset`.
      const offset = Number(url.searchParams.get("offset") ?? 0)
      const size = Number(t.pageSize ?? 200)
      return res(200, { ...t, rows: t.rows.slice(offset, offset + size), offset, limit: size, totalRows: t.rows.length })
    }
    if (url.pathname.endsWith("/versions")) return res(200, { versions: [] })
    return res(200, {})
  }) as unknown as typeof fetch
})

const qc = () => new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
const ds = (name: string): DatasetRef => ({ id: `id-${name}`, name, ref: `projects/p1/inputs/${name}`, size: 1000, source: "upload" })
function renderObj(dataset: DatasetRef, props: Record<string, unknown> = {}) {
  return render(
    <QueryClientProvider client={qc()}>
      <DatasetObject projectId="p1" dataset={dataset} onRunQC={() => {}} onDownload={() => {}} onAnalyze={() => {}} {...props} />
    </QueryClientProvider>,
  )
}
/** How many times `text` occurs in the page. */
const occurrences = (text: string) => (document.body.textContent ?? "").split(text).length - 1

describe("N5 — each fact once, one set of actions", () => {
  it("matrix.mtx: rows / columns / entries only in the stat grid; notes only in the QC card; one Download", async () => {
    const a = ds("tenx/matrix.mtx")
    profiles[a.ref!] = {
      shape: { rows: 0, cols: 0 }, quality: "unassessed", notes: [], viewKind: "matrix",
      format: { ext: "mtx", label: "Matrix Market", source: "galaxy" },
      stats: [{ code: "rows", value: 4 }, { code: "columns", value: 5 }, { code: "entries", value: 8 }],
      findings: [
        { section: "note", code: "mtx_tenx_pairing", level: "info", params: {} },
        { section: "note", code: "format_metadata_only", level: "watch", params: { format: "Matrix Market" } },
      ],
    }
    renderObj(a)
    const summary = await screen.findByTestId("dataset-kind-summary")
    await screen.findByTestId("data-perception")
    // No numbers and no notes inside the preview: they are the stat grid's and the QC card's.
    expect(summary.querySelector("dl")).toBeNull()
    expect(summary.querySelector("li")).toBeNull()
    expect(within(summary).queryByTestId("dataset-kind-download")).toBeNull()
    expect(occurrences("Matrix Market metadata was read")).toBe(1)
    const grid = screen.getByTestId("dataset-stat-grid")
    expect(grid.querySelector('[data-stat="entries"]')).toHaveTextContent("8")
    expect(screen.getAllByRole("button", { name: /Download/ })).toHaveLength(1)
  })

  it("1.bam: the reference count and the @RG note appear once", async () => {
    const a = ds("1.bam")
    profiles[a.ref!] = {
      shape: { rows: 0, cols: 0 }, quality: "watch", notes: [], viewKind: "alignment",
      stats: [{ code: "references", value: 168 }],
      findings: [
        { section: "signal", code: "alignment_no_read_groups", level: "watch", params: {} },
        { section: "note", code: "alignment_sorted", level: "info", params: { order: "coordinate" } },
      ],
    }
    // Alignment content is the IGV viewer slot (Wave 2); facts still live once in QC + stats.
    renderObj(a, { preview: <div data-testid="dataset-igv-preview">igv</div> })
    await screen.findByTestId("dataset-igv-preview")
    await screen.findByTestId("data-perception")
    expect(screen.queryByTestId("dataset-kind-summary")).toBeNull()
    expect(occurrences("No read groups (@RG)")).toBe(1)
    expect(occurrences("168")).toBe(1)
  })

  it("samples.xlsx: sheet count once; the 'preview of sheet' note is not repeated under the preview's caption", async () => {
    const a = ds("samples.xlsx")
    profiles[a.ref!] = {
      shape: { rows: 0, cols: 0 }, quality: "unassessed", notes: [], viewKind: "document",
      previewSheet: "Sheet1", columns: ["id", "name"], sampleRows: [["1", "Eldon"], ["2", "Barry"]],
      stats: [{ code: "sheets", value: 3 }],
      findings: [
        { section: "signal", code: "spreadsheet_sheets", level: "info", params: { count: 3, sheets: ["Sheet1", "QC", "Raw"] } },
        { section: "note", code: "spreadsheet_preview", level: "info", params: { sheet: "Sheet1", rows: 2 } },
      ],
    }
    renderObj(a)
    await screen.findByTestId("dataset-spreadsheet-preview")
    const card = await screen.findByTestId("data-perception")
    expect(within(card).queryAllByTestId("perception-finding").map((e) => e.getAttribute("data-code"))).not.toContain("spreadsheet_preview")
    expect(screen.getByTestId("dataset-kind-summary").querySelector("dl")).toBeNull()
    expect(screen.getByTestId("dataset-stat-grid").querySelector('[data-stat="sheets"]')).toHaveTextContent("3")
    expect(screen.getAllByRole("button", { name: /Download/ })).toHaveLength(1)
  })

  it("an h5ad: obs / var / parts shown in the summary only; one Ask in chat (the header's)", async () => {
    const a = ds("pbmc.h5ad")
    profiles[a.ref!] = {
      shape: { rows: 0, cols: 0 }, quality: "unassessed", notes: [], viewKind: "anndata",
      stats: [{ code: "cells", value: 640 }, { code: "genes", value: 11 }],
      findings: [
        { section: "signal", code: "anndata_shape", level: "info", params: { cells: 640, genes: 11 } },
        { section: "note", code: "anndata_obs", level: "info", params: { count: 1, columns: ["cell_type"] } },
        { section: "note", code: "anndata_components", level: "info", params: { count: 3, components: ["X", "obs", "var"] } },
      ],
    }
    renderObj(a)
    const sum = await screen.findByTestId("dataset-anndata-summary")
    const card = await screen.findByTestId("data-perception")
    expect(within(sum).getByTestId("dataset-anndata-obs")).toHaveTextContent("cell_type")
    const cardCodes = within(card).queryAllByTestId("perception-finding").map((e) => e.getAttribute("data-code"))
    expect(cardCodes).not.toContain("anndata_obs")
    expect(cardCodes).not.toContain("anndata_components")
    expect(screen.getAllByRole("button", { name: /Ask in chat/ })).toHaveLength(1)
    expect(within(sum).getByTestId("dataset-anndata-groups")).toHaveTextContent("Stored parts of the file")
  })
})

const FC_COLS = ["Geneid", "Chr", "Start", "End", "Strand", "Length", "S1.bam", "S2.bam"]
const FC_ROWS = Array.from({ length: 6 }, (_, i) => [`G${i}`, "chr1", String(1 + i * 1000), String(800 + i * 1000), "+", "800", String(100 + i * 37), String(50 + i * 11)])
const role = (name: string) => (["Geneid", "Chr", "Start", "End", "Strand", "Length"].includes(name) ? "annotation" : "measurement")

describe("N6 — the plot opens on a measurement column", () => {
  it("featureCounts with roles: S1.bam (measurement), never Start", async () => {
    const a = ds("featurecounts.txt")
    profiles[a.ref!] = {
      shape: { rows: 6, cols: 8 }, quality: "good", notes: [], viewKind: "table", columns: FC_COLS, sampleRows: FC_ROWS, findings: [],
      columnStats: FC_COLS.map((n) => ({ name: n, type: "numeric", present: 6, missing: 0, distinct: 6, role: role(n) })),
    }
    rowsByFile[a.id] = { columns: FC_COLS, rows: FC_ROWS, headerRow: true, version: 1, skipLines: 1, delimiter: "\t" }
    renderObj(a)
    fireEvent.click(await screen.findByTestId("dataset-preview-toggle-plot"))
    expect(await screen.findByTestId("dataset-sample-plot-caption")).toHaveTextContent("“S1.bam”")
    // The selector still offers the others.
    expect(within(screen.getByTestId("dataset-sample-plot-col")).getAllByRole("option").map((o) => o.textContent)).toContain("Start")
  })

  it("an older profile without roles: coordinate names are skipped too", async () => {
    const a = ds("featurecounts.txt")
    profiles[a.ref!] = { shape: { rows: 6, cols: 8 }, quality: "good", notes: [], viewKind: "table", columns: FC_COLS, sampleRows: FC_ROWS, findings: [] }
    rowsByFile[a.id] = { columns: FC_COLS, rows: FC_ROWS, headerRow: true, version: 1, skipLines: 1, delimiter: "\t" }
    renderObj(a)
    fireEvent.click(await screen.findByTestId("dataset-preview-toggle-plot"))
    expect(await screen.findByTestId("dataset-sample-plot-caption")).toHaveTextContent("“S1.bam”")
  })
})

describe("N11 — header-only and partially loaded tables", () => {
  it("a header-only table offers no Run full QC and no Edit", async () => {
    const a = ds("header_only.tsv")
    profiles[a.ref!] = { shape: { rows: 0, cols: 2 }, quality: "watch", notes: [], viewKind: "table", columns: ["gene_id", "ctrl_1"], sampleRows: [], findings: [] }
    rowsByFile[a.id] = { columns: ["gene_id", "ctrl_1"], rows: [], headerRow: true, version: 1, skipLines: 0, delimiter: "\t" }
    renderObj(a)
    await screen.findByTestId("dataset-preview-no-rows")
    await screen.findByTestId("data-perception")
    expect(screen.queryByTestId("dataset-object-run-qc")).toBeNull()
    expect(screen.queryByTestId("dataset-preview-toggle-edit")).toBeNull()
  })

  it("a table with rows keeps both (control)", async () => {
    const a = ds("counts.tsv")
    profiles[a.ref!] = { shape: { rows: 2, cols: 2 }, quality: "good", notes: [], viewKind: "table", columns: ["gene_id", "ctrl_1"], sampleRows: [["G1", "1"], ["G2", "2"]], findings: [] }
    rowsByFile[a.id] = { columns: ["gene_id", "ctrl_1"], rows: [["G1", "1"], ["G2", "2"]], headerRow: true, version: 1, skipLines: 0, delimiter: "\t" }
    renderObj(a)
    await screen.findByTestId("dataset-preview-toggle-edit")
    expect(await screen.findByTestId("dataset-object-run-qc")).toBeInTheDocument()
  })

  it("plot over 200 of 500 loaded rows says so and offers 'Load all rows to plot all'", async () => {
    const a = ds("screen.count.txt")
    const rows = Array.from({ length: 500 }, (_, i) => [`sg${i}`, String(1000 + (i % 97))])
    profiles[a.ref!] = { shape: { rows: 500, cols: 2 }, quality: "good", notes: [], viewKind: "table", columns: ["sgRNA", "sample"], sampleRows: rows.slice(0, 20), findings: [] }
    rowsByFile[a.id] = { columns: ["sgRNA", "sample"], rows, headerRow: true, version: 1, skipLines: 0, delimiter: "\t", pageSize: 200 }
    renderObj(a)
    fireEvent.click(await screen.findByTestId("dataset-preview-toggle-plot"))
    const caption = await screen.findByTestId("dataset-sample-plot-caption")
    expect(caption).toHaveTextContent("uses the 200 loaded rows of 500")
    fireEvent.click(screen.getByTestId("dataset-sample-plot-load-all"))
    await waitFor(() => expect(screen.getByTestId("dataset-sample-plot-caption")).toHaveTextContent("rows loaded: 500"))
    expect(screen.queryByTestId("dataset-sample-plot-load-all")).toBeNull()
  })
})

describe("N9 — Run full QC says what it does", () => {
  it("the tooltip describes a chat-run QC report, not a FastQC + MultiQC workflow", async () => {
    const a = ds("counts.tsv")
    profiles[a.ref!] = { shape: { rows: 2, cols: 2 }, quality: "good", notes: [], viewKind: "table", columns: ["gene_id", "ctrl_1"], sampleRows: [["G1", "1"], ["G2", "2"]], findings: [] }
    rowsByFile[a.id] = { columns: ["gene_id", "ctrl_1"], rows: [["G1", "1"], ["G2", "2"]], headerRow: true, version: 1, skipLines: 0, delimiter: "\t" }
    renderObj(a)
    const tip = (await screen.findByTestId("dataset-object-run-qc")).getAttribute("title") ?? ""
    expect(tip).not.toMatch(/FastQC|MultiQC/)
    expect(tip).toMatch(/chat/i)
  })
})

describe("N8 / N12 — layout and naming", () => {
  it("the tab list keeps one line and scrolls sideways; the QC card names the base name, full path on hover", async () => {
    const a = ds("pairs/S1_R1.fastq.gz")
    profiles[a.ref!] = { shape: { rows: 0, cols: 0 }, quality: "good", notes: [], viewKind: "reads", findings: [] }
    renderObj(a, { preview: <div /> })
    const tabs = screen.getByTestId("dataset-tablist")
    expect(tabs.className).toMatch(/flex-nowrap/)
    expect(tabs.className).toMatch(/overflow-x-auto/)
    const name = within(await screen.findByTestId("data-perception")).getByTestId("data-perception-name")
    expect(name.textContent).toBe("S1_R1.fastq.gz")
    expect(name.getAttribute("title")).toBe("pairs/S1_R1.fastq.gz")
  })
})
