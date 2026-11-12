/**
 * Dataset panel round-5 seams (live dev walkthrough 2026-11-12, audit5), behaviour through the
 * dataset object. Our own endpoints are faked at fetch.
 *  1  "How it shaped the plan" never shows on a file page (there is no plan there);
 *  2  each number once: a finding that only restates the stat grid (VCF variants · samples, AnnData
 *     cells × genes) and "Sheets (1): X" beside the caption naming X are not repeated in the QC card
 *     — decided by code + params, so a finding with more to say stays;
 *  4  the plot never opens on an identifier / annotation column: measurements first, the rest under
 *     "Other columns"; a JSONL whose only number is its "page" asks which column to draw;
 *  5  a tab list that does not fit shows a fade + chevron instead of a tab cut mid-word;
 *  7  a header-only table shows "No data rows yet", no filter box and no "All 0 rows loaded".
 */
import React from "react"
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { render, screen, fireEvent, waitFor, within } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { DatasetObject, type DatasetRef } from "./dataset-object"

let profiles: Record<string, unknown> = {}
let rowsByFile: Record<string, { columns: string[]; rows: string[][]; [k: string]: unknown }> = {}

beforeEach(() => {
  profiles = {}; rowsByFile = {}
  global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const res = (status: number, body: unknown) =>
      ({ ok: status < 400, status, json: async () => body, text: async () => "" }) as unknown as Response
    const url = new URL(String(input), "http://x")
    const fileId = url.pathname.split("/files/")[1]?.split("/")[0]
    if (url.pathname === "/api/perception/profile") {
      const { datasetRef } = JSON.parse(String(init?.body ?? "{}"))
      return profiles[datasetRef] ? res(200, profiles[datasetRef]) : res(403, {})
    }
    if (url.pathname.endsWith("/rows")) {
      const t = rowsByFile[fileId!]
      if (!t) return res(415, {})
      return res(200, { ...t, offset: 0, limit: 200, totalRows: t.rows.length })
    }
    if (url.pathname.endsWith("/versions")) return res(200, { versions: [] })
    return res(200, {})
  }) as unknown as typeof fetch
})

const qc = () => new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
const ds = (name: string): DatasetRef => ({ id: `id-${name}`, name, ref: `projects/p1/inputs/${name}`, size: 1000, source: "upload" })
function renderObj(dataset: DatasetRef) {
  return render(
    <QueryClientProvider client={qc()}>
      <DatasetObject projectId="p1" dataset={dataset} onRunQC={() => {}} onDownload={() => {}} onAnalyze={() => {}} />
    </QueryClientProvider>,
  )
}
const cardCodes = (card: HTMLElement) => within(card).queryAllByTestId("perception-finding").map((e) => e.getAttribute("data-code"))

const VCF_COLS = ["CHROM", "POS", "ID", "REF", "ALT", "QUAL", "FILTER", "INFO", "FORMAT", "wgs2"]
const VCF_ROWS = Array.from({ length: 30 }, (_, i) => ["chr1", String(500 * (i + 1)), ".", "C", "T", ".", ".", "DP=10", "GT", "1/1"])
const VCF_PROFILE = {
  shape: { rows: 30, cols: 10 }, quality: "good", notes: [], viewKind: "variants",
  format: { ext: "vcf", label: "VCF", source: "galaxy" },
  columns: VCF_COLS, sampleRows: VCF_ROWS.slice(0, 10),
  stats: [{ code: "variants", value: 30 }, { code: "samples", value: 1 }],
  findings: [
    { section: "signal", code: "vcf_records", level: "info", params: { variants: 30, samples: 1 } },
    { section: "note", code: "vcf_summary", level: "info", params: { variants: 30, samples: 1 } },
    { section: "note", code: "vcf_malformed_lines", level: "info", params: { count: 2 } },
    { section: "plan", code: "vcf_sized", level: "info", params: { variants: 30, samples: 1 } },
  ],
}

describe("1 + 2 — a VCF page: no plan section, each number once", () => {
  it("shows variants / samples only in the stat grid; keeps a finding with more to say", async () => {
    const a = ds("1.vcf")
    profiles[a.ref!] = VCF_PROFILE
    rowsByFile[a.id] = { columns: VCF_COLS, rows: VCF_ROWS, headerRow: true, version: 1 }
    renderObj(a)
    const card = await screen.findByTestId("data-perception")
    expect(within(card).queryByTestId("perception-plan-impact")).toBeNull()
    expect(card.textContent).not.toContain("plan sized accordingly")
    const codes = cardCodes(card)
    expect(codes).not.toContain("vcf_records")
    expect(codes).not.toContain("vcf_summary")
    expect(codes).toContain("vcf_malformed_lines")
    const grid = screen.getByTestId("dataset-stat-grid")
    expect(grid).toHaveTextContent("30")
    expect(grid.querySelector('[data-stat="variants"]')).not.toBeNull()
  })

  it("a finding whose numbers DIFFER from the grid is kept (matched by value, not by code alone)", async () => {
    const a = ds("2.vcf")
    profiles[a.ref!] = { ...VCF_PROFILE, stats: [{ code: "variants", value: 31 }, { code: "samples", value: 1 }] }
    rowsByFile[a.id] = { columns: VCF_COLS, rows: VCF_ROWS, headerRow: true, version: 1 }
    renderObj(a)
    const card = await screen.findByTestId("data-perception")
    await waitFor(() => expect(cardCodes(card)).toContain("vcf_records"))
  })
})

describe("2 — AnnData cells × genes and a single-sheet workbook's sheet name, once", () => {
  it("h5ad: anndata_shape is not repeated beside the CELLS / GENES cards", async () => {
    const a = ds("pbmc3k_tiny.h5ad")
    profiles[a.ref!] = {
      shape: { rows: 0, cols: 0 }, quality: "unassessed", notes: [], viewKind: "anndata",
      format: { ext: "h5ad", label: "AnnData (h5ad)", source: "galaxy" },
      stats: [{ code: "cells", value: 1 }, { code: "genes", value: 1 }],
      findings: [
        { section: "signal", code: "anndata_shape", level: "info", params: { cells: 1, genes: 1 } },
        { section: "note", code: "format_metadata_only", level: "info", params: { format: "AnnData (h5ad)" } },
      ],
    }
    renderObj(a)
    const card = await screen.findByTestId("data-perception")
    await waitFor(() => expect(cardCodes(card)).toContain("format_metadata_only"))
    expect(cardCodes(card)).not.toContain("anndata_shape")
  })

  it("xlsx: 'Sheets (1): X' is dropped when X is the previewed sheet; a 2-sheet workbook keeps its list", async () => {
    const one = ds("samples.xlsx")
    const base = {
      shape: { rows: 0, cols: 0 }, quality: "unassessed", notes: [], viewKind: "document",
      format: { ext: "xlsx", label: "Excel (xlsx)", source: "galaxy" },
      columns: ["well", "od600"], sampleRows: [["A1", "0.41"], ["A2", "0.39"]], previewSheet: "Sample-spreadsheet-file",
    }
    profiles[one.ref!] = {
      ...base, stats: [{ code: "sheets", value: 1 }],
      findings: [
        { section: "signal", code: "spreadsheet_sheets", level: "info", params: { count: 1, sheets: ["Sample-spreadsheet-file"] } },
        { section: "note", code: "spreadsheet_convert", level: "info", params: {} },
      ],
    }
    const view = renderObj(one)
    let card = await screen.findByTestId("data-perception")
    await waitFor(() => expect(cardCodes(card)).toContain("spreadsheet_convert"))
    expect(cardCodes(card)).not.toContain("spreadsheet_sheets")
    view.unmount()

    const two = ds("plates.xlsx")
    profiles[two.ref!] = {
      ...base, previewSheet: "Plate1", stats: [{ code: "sheets", value: 2 }],
      findings: [{ section: "signal", code: "spreadsheet_sheets", level: "info", params: { count: 2, sheets: ["Plate1", "QC"] } }],
    }
    renderObj(two)
    card = await screen.findByTestId("data-perception")
    await waitFor(() => expect(cardCodes(card)).toContain("spreadsheet_sheets"))
  })
})

const FC_COLS = ["Geneid", "Chr", "Start", "End", "Strand", "Length", "S1.bam", "S2.bam"]
const FC_ROWS = Array.from({ length: 6 }, (_, i) => [`G${i}`, "chr1", String(1 + i * 1000), String(800 + i * 1000), "+", String(800 + i), String(100 + i * 37), String(50 + i * 11)])

describe("4 — plot column choice", () => {
  it("featureCounts without roles: measurements first, Start / End / Length under 'Other columns'", async () => {
    const a = ds("featurecounts.txt")
    profiles[a.ref!] = { shape: { rows: 6, cols: 8 }, quality: "good", notes: [], viewKind: "table", columns: FC_COLS, sampleRows: FC_ROWS, findings: [] }
    rowsByFile[a.id] = { columns: FC_COLS, rows: FC_ROWS, headerRow: true, version: 1 }
    renderObj(a)
    fireEvent.click(await screen.findByTestId("dataset-preview-toggle-plot"))
    expect(await screen.findByTestId("dataset-sample-plot-caption")).toHaveTextContent("“S1.bam”")
    const select = screen.getByTestId("dataset-sample-plot-col")
    const options = within(select).getAllByRole("option")
    expect(options.slice(0, 2).map((o) => o.textContent)).toEqual(["S1.bam", "S2.bam"])
    const other = within(select).getByTestId("dataset-sample-plot-other")
    expect(other.getAttribute("label")).toBe("Other columns")
    expect(within(other).getAllByRole("option").map((o) => o.textContent)).toEqual(["Start", "End", "Length"])
  })

  it("JSONL whose only number is 'page' (identifier role): no histogram of pages — it asks for a column", async () => {
    const a = ds("epar_study_tables.jsonl")
    const cols = ["source", "drug", "page", "headers", "rows"]
    const rows = [30, 31, 34, 35, 48, 49].map((p) => ["epar_table", "pluvicto", String(p), "[]", "[]"])
    profiles[a.ref!] = {
      shape: { rows: 6, cols: 5 }, quality: "good", notes: [], viewKind: "records", columns: cols, sampleRows: rows, findings: [],
      columnStats: [
        { name: "source", type: "categorical", present: 6, missing: 0, distinct: 1, role: "constant" },
        { name: "page", type: "numeric", present: 6, missing: 0, distinct: 6, role: "identifier" },
      ],
    }
    rowsByFile[a.id] = { columns: cols, rows, headerRow: true, version: 1 }
    renderObj(a)
    fireEvent.click(await screen.findByTestId("dataset-preview-toggle-plot"))
    const plot = await screen.findByTestId("dataset-sample-plot")
    expect(plot.getAttribute("data-no-measurement")).toBe("true")
    expect(screen.queryByTestId("dataset-sample-plot-caption")).toBeNull()
    expect(screen.getByTestId("dataset-sample-plot-no-measurement")).toBeInTheDocument()
    // Choosing it anyway draws it.
    fireEvent.change(screen.getByTestId("dataset-sample-plot-col"), { target: { value: "2" } })
    expect(await screen.findByTestId("dataset-sample-plot-caption")).toHaveTextContent("“page”")
  })
})

describe("5 — a tab list that does not fit says so", () => {
  const proto = HTMLElement.prototype
  const saved = {
    sw: Object.getOwnPropertyDescriptor(proto, "scrollWidth"),
    cw: Object.getOwnPropertyDescriptor(proto, "clientWidth"),
  }
  beforeEach(() => {
    Object.defineProperty(proto, "scrollWidth", { configurable: true, get() { return (this as HTMLElement).dataset?.testid === "dataset-tablist" ? 360 : 0 } })
    Object.defineProperty(proto, "clientWidth", { configurable: true, get() { return (this as HTMLElement).dataset?.testid === "dataset-tablist" ? 300 : 0 } })
  })
  afterEach(() => {
    if (saved.sw) Object.defineProperty(proto, "scrollWidth", saved.sw); else delete (proto as any).scrollWidth
    if (saved.cw) Object.defineProperty(proto, "clientWidth", saved.cw); else delete (proto as any).clientWidth
  })
  it("overflowing tabs: a fade and a 'more tabs' chevron that scrolls the list", async () => {
    const a = ds("1.vcf")
    profiles[a.ref!] = VCF_PROFILE
    renderObj(a)
    const more = await screen.findByTestId("dataset-tablist-more")
    expect(screen.getByTestId("dataset-tablist-fade")).toBeInTheDocument()
    expect(more).toHaveAttribute("aria-label", "More tabs")
    const list = screen.getByTestId("dataset-tablist")
    const scrollBy = vi.fn()
    ;(list as any).scrollBy = scrollBy
    fireEvent.click(more)
    expect(scrollBy).toHaveBeenCalled()
  })
})

describe("7 — header-only table", () => {
  it("'No data rows yet', no filter box, no 'All 0 rows loaded · … apply to all rows'", async () => {
    const a = ds("header_only.tsv")
    const cols = ["sample", "condition", "read_depth"]
    profiles[a.ref!] = { shape: { rows: 0, cols: 3 }, quality: "watch", notes: [], viewKind: "table", columns: cols, sampleRows: [], findings: [] }
    rowsByFile[a.id] = { columns: cols, rows: [], headerRow: true, version: 1 }
    renderObj(a)
    expect(await screen.findByTestId("dataset-preview-no-rows")).toHaveTextContent("No data rows yet")
    expect(screen.queryByTestId("dataset-preview-filter")).toBeNull()
    expect(screen.queryByTestId("dataset-preview-scope")).toBeNull()
    expect(document.body.textContent).not.toContain("All 0 rows loaded")
    expect(document.body.textContent).not.toContain("Sorting and filtering apply to all rows")
  })
})
