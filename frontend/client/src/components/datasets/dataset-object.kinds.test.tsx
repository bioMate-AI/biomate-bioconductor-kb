/**
 * The dataset object renders what the per-kind view model says (U1–U5, U11, edit contract):
 * an image or AnnData file has no Table/Columns/Plot toggles and no rows × columns, a file
 * that was only identified is "Not checked" (grey, never Watch), tab choices reset per file,
 * and an edit is sent against the version the user saw. Our own endpoints are faked at fetch.
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, fireEvent, waitFor, within } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { DatasetObject } from "./dataset-object"
import { DatasetFilePreview } from "./dataset-file-preview"

let profileBody: Record<string, unknown> = {}
let rowsBody: { status: number; body: unknown } = { status: 200, body: {} }
let editResponse: { status: number; body: unknown } = { status: 200, body: { file: { version_no: 3 } } }
let editBodies: any[] = []
let rowCalls = 0
let restoreBodies: any[] = []
let versionsBody: unknown = { versions: [] }
let urlStatus = 200
let afterRestoreRows: { status: number; body: unknown } | null = null

beforeEach(() => {
  editBodies = []
  rowCalls = 0
  restoreBodies = []
  versionsBody = { versions: [] }
  urlStatus = 200
  afterRestoreRows = null
  editResponse = { status: 200, body: { file: { version_no: 3 } } }
  global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(String(input), "http://x")
    const res = (status: number, body: unknown) =>
      ({ ok: status < 400, status, json: async () => body, text: async () => "" }) as unknown as Response
    if (url.pathname.endsWith("/rows")) { rowCalls += 1; return res(rowsBody.status, rowsBody.body) }
    if (url.pathname.endsWith("/edit")) { editBodies.push(JSON.parse(String(init?.body))); return res(editResponse.status, editResponse.body) }
    if (url.pathname.endsWith("/restore")) {
      restoreBodies.push(JSON.parse(String(init?.body ?? "{}")))
      if (afterRestoreRows) rowsBody = afterRestoreRows   // the server now serves the restored version
      return res(200, { file: { version_no: 8 } })
    }
    if (url.pathname.endsWith("/versions")) return res(200, versionsBody)
    if (url.pathname.endsWith("/url")) return res(urlStatus, { url: "https://files.example/x" })
    if (url.pathname === "/api/perception/profile") return res(200, profileBody)
    return res(200, {})
  }) as unknown as typeof fetch
})

const qc = () => new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
function obj(name: string, extra: Record<string, unknown> = {}) {
  return (
    <DatasetObject
      projectId="p1"
      dataset={{ id: `id-${name}`, name, ref: `projects/p1/inputs/${name}`, size: 113_000, source: "upload" }}
      onRunQC={() => {}}
      onDownload={() => {}}
      {...extra}
    />
  )
}
function renderObj(name: string, extra: Record<string, unknown> = {}) {
  const client = qc()
  const view = render(<QueryClientProvider client={client}>{obj(name, extra)}</QueryClientProvider>)
  return { ...view, client }
}

const PNG_PROFILE = {
  shape: { rows: 0, cols: 0 }, quality: "watch", notes: [],
  findings: [{ section: "note", code: "format_identified", level: "watch", params: { format: "PNG", size: "110.7 KB" } }],
  format: { ext: "png", label: "PNG", source: "galaxy" },
}

describe("image (U1/U2/U4/U11)", () => {
  it("no Table/Columns/Plot toggles, no rows/columns stats, no Run full QC; quality 'Not checked' in grey", async () => {
    profileBody = PNG_PROFILE
    renderObj("umap.png", { preview: <div data-testid="image-viewer">img</div> })
    await screen.findByTestId("data-perception")
    expect(screen.getByTestId("image-viewer")).toBeInTheDocument()
    expect(screen.queryByTestId("dataset-preview-toggles")).toBeNull()
    expect(screen.queryByTestId("dataset-preview-toggle-table")).toBeNull()
    expect(screen.queryByTestId("dataset-preview-toggle-columns")).toBeNull()
    expect(screen.queryByTestId("dataset-object-run-qc")).toBeNull()
    const card = screen.getByTestId("data-perception")
    expect(card).toHaveAttribute("data-quality", "unassessed")
    expect(card).not.toHaveTextContent(/Rows|Columns/)
    expect(within(card).getByTestId("perception-quality-badge")).toHaveTextContent("Not checked")
    expect(within(card).getByTestId("perception-quality-badge").className).not.toMatch(/amber/)
    expect(screen.queryByTestId("perception-why")).toBeNull()
    const pill = screen.getByTestId("dataset-header-quality")
    expect(pill).toHaveAttribute("data-quality", "unassessed")
    expect(pill.innerHTML).not.toMatch(/amber/)
    expect(screen.getByTestId("dataset-stat-grid")).not.toHaveTextContent(/Rows|Columns/)
    expect(screen.getByTestId("dataset-stat-grid").querySelector("[data-testid=dataset-stat][data-stat=type]")).toHaveTextContent("Image")
  })

  it("a backend 'unassessed' verdict is grey too", async () => {
    profileBody = { ...PNG_PROFILE, quality: "unassessed", viewKind: "image" }
    renderObj("umap.png", { preview: <div /> })
    expect(await screen.findByTestId("dataset-header-quality")).toHaveAttribute("data-quality", "unassessed")
    expect(screen.getByTestId("dataset-header-quality")).toHaveTextContent("Not checked")
  })
})

describe("AnnData (U5)", () => {
  it("shows a cells × genes summary with obs/var columns, embeddings and layers — not a table", async () => {
    profileBody = {
      shape: { rows: 1, cols: 1 }, quality: "watch", notes: [], viewKind: "anndata",
      stats: [{ code: "cells", value: 2700 }, { code: "genes", value: 32738 }],
      findings: [
        { section: "signal", code: "anndata_shape", level: "info", params: { cells: 2700, genes: 32738 } },
        { section: "note", code: "anndata_obs", level: "info", params: { count: 3, columns: ["n_genes", "louvain", "batch"] } },
        { section: "note", code: "anndata_var", level: "info", params: { count: 1, columns: ["gene_ids"] } },
        { section: "note", code: "anndata_embeddings", level: "info", params: { count: 2, embeddings: ["X_pca", "X_umap"] } },
        { section: "note", code: "hdf5_groups", level: "info", params: { count: 5, groups: ["X", "obs", "obsm", "var", "varm"] } },
        { section: "note", code: "format_metadata_only", level: "watch", params: { format: "AnnData" } },
      ],
      layers: ["counts"],
    }
    renderObj("pbmc3k.h5ad")
    const sum = await screen.findByTestId("dataset-anndata-summary")
    expect(within(sum).getByTestId("dataset-anndata-shape")).toHaveTextContent("2,700")
    expect(within(sum).getByTestId("dataset-anndata-shape")).toHaveTextContent("32,738")
    expect(within(sum).getByTestId("dataset-anndata-obs")).toHaveTextContent("louvain")
    expect(within(sum).getByTestId("dataset-anndata-var")).toHaveTextContent("gene_ids")
    expect(within(sum).getByTestId("dataset-anndata-embeddings")).toHaveTextContent("X_umap")
    // Real layers (adata.layers) apart from the file's stored HDF5 groups (W5).
    expect(within(sum).getByTestId("dataset-anndata-layers")).toHaveTextContent("Layers · 1")
    expect(within(sum).getByTestId("dataset-anndata-layers")).toHaveTextContent("counts")
    expect(within(sum).getByTestId("dataset-anndata-layers")).not.toHaveTextContent("obsm")
    expect(within(sum).getByTestId("dataset-anndata-groups")).toHaveTextContent("Stored components (HDF5 groups) · 5")
    expect(screen.queryByTestId("dataset-preview-toggle-table")).toBeNull()
    // cells × genes, not "rows 1 / columns 1" — shown once, in the stat grid (P3), not again in the QC card.
    const card = screen.getByTestId("data-perception")
    expect(within(card).queryByTestId("perception-stat-cells")).toBeNull()
    expect(screen.getByTestId("dataset-stat-grid").querySelector('[data-stat="cells"]')).toHaveTextContent("2,700")
    expect(card).not.toHaveTextContent(/Rows/)
    expect(rowCalls).toBe(0)
  })
})

describe("archive / unknown: honest download state", () => {
  it("says it cannot be shown here and offers Download", async () => {
    profileBody = { shape: { rows: 0, cols: 0 }, quality: "unassessed", notes: [], viewKind: "archive", findings: [] }
    const onDownload = vi.fn()
    renderObj("bundle.zip", { onDownload })
    const state = await screen.findByTestId("dataset-download-state")
    fireEvent.click(within(state).getByTestId("dataset-kind-download"))
    expect(onDownload).toHaveBeenCalled()
  })
})

describe("header-only TSV (U3)", () => {
  it("Columns lists the header's columns with 'no data rows', not 'not a table'", async () => {
    profileBody = { shape: { rows: 0, cols: 4 }, quality: "good", notes: [], columns: ["gene", "a", "b", "c"], sampleRows: [] }
    rowsBody = { status: 200, body: { columns: ["gene", "a", "b", "c"], rows: [], totalRows: 0, offset: 0, limit: 200, version: 1 } }
    renderObj("mock_control_counts.tsv")
    await waitFor(() => expect(screen.getByTestId("dataset-preview-no-rows")).toBeInTheDocument())
    fireEvent.click(screen.getByTestId("dataset-preview-toggle-columns"))
    expect(screen.getAllByTestId("dataset-column-row")).toHaveLength(4)
    expect(screen.getByTestId("dataset-columns-sample-note")).toHaveTextContent("no data rows")
    expect(screen.queryByTestId("dataset-preview-columns-none")).toBeNull()
  })
})

describe("view choice resets per file (U11)", () => {
  it("the next file opens on its own default view, not the previous file's Columns", async () => {
    profileBody = { shape: { rows: 2, cols: 2 }, quality: "good", notes: [], columns: ["g", "v"], sampleRows: [["a", "1"], ["b", "2"]] }
    rowsBody = { status: 200, body: { columns: ["g", "v"], rows: [["a", "1"], ["b", "2"]], totalRows: 2, offset: 0, limit: 200, version: 1 } }
    const client = qc()
    const { rerender } = render(<QueryClientProvider client={client}>{obj("one.csv")}</QueryClientProvider>)
    await waitFor(() => expect(screen.getByTestId("dataset-preview-table")).toBeInTheDocument())
    fireEvent.click(screen.getByTestId("dataset-preview-toggle-columns"))
    expect(screen.getByTestId("dataset-preview-toggle-columns")).toHaveAttribute("aria-pressed", "true")
    rerender(<QueryClientProvider client={client}>{obj("two.csv")}</QueryClientProvider>)
    await waitFor(() => expect(screen.getByTestId("dataset-preview-toggle-table")).toHaveAttribute("aria-pressed", "true"))
    expect(screen.getByTestId("dataset-preview-toggle-columns")).toHaveAttribute("aria-pressed", "false")
  })
})

describe("edit contract: baseVersion + distinct 409s", () => {
  async function editOneCell() {
    profileBody = { shape: { rows: 2, cols: 2 }, quality: "good", notes: [], columns: ["g", "v"], sampleRows: [["a", "1"], ["b", "1"]] }
    rowsBody = { status: 200, body: { columns: ["g", "v"], rows: [["a", "1"], ["b", "1"]], totalRows: 2, offset: 0, limit: 200, headerRow: true, version: 7 } }
    renderObj("tbl.csv")
    await waitFor(() => expect(screen.getByTestId("dataset-preview-toggle-edit")).toBeInTheDocument())
    fireEvent.click(screen.getByTestId("dataset-preview-toggle-edit"))
    const cell = await screen.findByTestId("dataset-edit-cell-1-1")
    fireEvent.change(cell, { target: { value: "2" } })
    fireEvent.blur(cell)
    fireEvent.click(screen.getByTestId("dataset-edit-save"))
  }

  it("sends the version of the rows the user saw as baseVersion", async () => {
    await editOneCell()
    await waitFor(() => expect(editBodies).toHaveLength(1))
    expect(editBodies[0].baseVersion).toBe(7)
    expect(editBodies[0].edits[0]).toMatchObject({ row: 1, col: 1, from: "1", value: "2" })
  })

  it("version_conflict and cell_conflict get different messages", async () => {
    editResponse = { status: 409, body: { error: "version_conflict" } }
    await editOneCell()
    const msg = await screen.findByTestId("dataset-edit-error")
    expect(msg).toHaveTextContent("a newer version of this file was saved")
  })

  it("cell_conflict says a cell changed", async () => {
    editResponse = { status: 409, body: { error: "cell_conflict" } }
    await editOneCell()
    expect(await screen.findByTestId("dataset-edit-error")).toHaveTextContent("no longer holds the value shown")
  })
})

describe("edit payload: rowFrom + headerRows + skipLines (server seam 2026-11-12)", () => {
  it("each edited cell carries the whole row the user saw; headerRows and skipLines come from the rows response", async () => {
    profileBody = { shape: { rows: 2, cols: 2 }, quality: "good", notes: [], viewKind: "table", columns: ["g", "v"], sampleRows: [["a", "1"], ["b", "1"]] }
    rowsBody = { status: 200, body: { columns: ["g", "v"], rows: [["a", "1"], ["b", "1"]], totalRows: 2, offset: 0, limit: 200, headerRow: true, version: 7, skipLines: 2 } }
    renderObj("counts.tsv")
    await waitFor(() => expect(screen.getByTestId("dataset-preview-toggle-edit")).toBeInTheDocument())
    fireEvent.click(screen.getByTestId("dataset-preview-toggle-edit"))
    const cell = await screen.findByTestId("dataset-edit-cell-1-1")
    fireEvent.change(cell, { target: { value: "5" } })
    fireEvent.click(screen.getByTestId("dataset-edit-save"))
    await waitFor(() => expect(editBodies).toHaveLength(1))
    // Row 0 also holds "1" in column v: rowFrom pins the edit to row 1 ("b").
    expect(editBodies[0].edits).toEqual([{ row: 1, col: 1, from: "1", value: "5", rowFrom: ["b", "1"] }])
    expect(editBodies[0]).toMatchObject({ baseVersion: 7, headerRows: 1, skipLines: 2 })
  })
})

describe("edit payload for a header-less table", () => {
  it("headerRows 0 from the reader's headerRow:false; no skipLines when the reader reports none", async () => {
    profileBody = { shape: { rows: 2, cols: 2 }, quality: "good", notes: [], viewKind: "table", columns: ["column_1", "column_2"], sampleRows: [["TP53", "1"], ["EGFR", "1"]] }
    rowsBody = { status: 200, body: { columns: ["column_1", "column_2"], rows: [["TP53", "1"], ["EGFR", "1"]], totalRows: 2, offset: 0, limit: 200, headerRow: false, version: 2 } }
    renderObj("genes.tsv")
    fireEvent.click(await screen.findByTestId("dataset-preview-toggle-edit"))
    fireEvent.change(await screen.findByTestId("dataset-edit-cell-0-1"), { target: { value: "9" } })
    fireEvent.click(screen.getByTestId("dataset-edit-save"))
    await waitFor(() => expect(editBodies).toHaveLength(1))
    expect(editBodies[0]).toEqual({ edits: [{ row: 0, col: 1, from: "1", value: "9", rowFrom: ["TP53", "1"] }], headerRows: 0, baseVersion: 2 })
  })
})

describe("restore re-reads the rows (the next edit is based on the restored version)", () => {
  it("after a restore, rows reload and the next edit sends the new version as baseVersion", async () => {
    profileBody = { shape: { rows: 2, cols: 2 }, quality: "good", notes: [], viewKind: "table", columns: ["g", "v"], sampleRows: [["a", "1"], ["b", "2"]] }
    rowsBody = { status: 200, body: { columns: ["g", "v"], rows: [["a", "1"], ["b", "2"]], totalRows: 2, offset: 0, limit: 200, headerRow: true, version: 7 } }
    versionsBody = { versions: [
      { version: "7", label: "v7", current: true, ref: "r" },
      { version: "6", label: "v6", current: false, ref: "r" },
    ] }
    // The restore writes version 8 (v6's bytes); the rows endpoint then serves it.
    afterRestoreRows = { status: 200, body: { columns: ["g", "v"], rows: [["a", "1"], ["b", "3"]], totalRows: 2, offset: 0, limit: 200, headerRow: true, version: 8 } }
    renderObj("tbl.csv")
    await waitFor(() => expect(screen.getByTestId("dataset-preview-table")).toBeInTheDocument())
    expect(rowCalls).toBe(1)
    fireEvent.click(screen.getByTestId("dataset-tab-versions"))
    fireEvent.click(await screen.findByTestId("dataset-version-restore-6"))
    // Restore asks first (W1); confirming sends it.
    fireEvent.click(await screen.findByTestId("dataset-version-restore-yes-6"))
    // The restore is made against the version the list showed as current.
    await waitFor(() => expect(restoreBodies).toEqual([{ baseVersion: 7 }]))
    await waitFor(() => expect(rowCalls).toBe(2))
    fireEvent.click(screen.getByTestId("dataset-tab-preview"))
    fireEvent.click(await screen.findByTestId("dataset-preview-toggle-edit"))
    const cell = await screen.findByTestId("dataset-edit-cell-1-1")
    await waitFor(() => expect(cell).toHaveValue("3"))
    fireEvent.change(cell, { target: { value: "4" } })
    fireEvent.click(screen.getByTestId("dataset-edit-save"))
    await waitFor(() => expect(editBodies).toHaveLength(1))
    expect(editBodies[0].baseVersion).toBe(8)
    expect(editBodies[0].edits[0]).toMatchObject({ from: "3", rowFrom: ["b", "3"] })
  })
})

describe("e2e contract attributes (format-matrix harness)", () => {
  const stats = () => Array.from(document.querySelectorAll("[data-testid=dataset-stat]")).map((e) => e.getAttribute("data-stat"))

  it("a table: data-view-kind / data-preview-kind = table, rows + columns stat cards, th[data-column-name]", async () => {
    profileBody = { shape: { rows: 2, cols: 2 }, quality: "good", notes: [], viewKind: "table", columns: ["g", "v"], sampleRows: [["a", "1"], ["b", "2"]] }
    rowsBody = { status: 200, body: { columns: ["g", "v"], rows: [["a", "1"], ["b", "2"]], totalRows: 2, offset: 0, limit: 200, version: 1 } }
    renderObj("one.csv")
    await waitFor(() => expect(screen.getByTestId("dataset-preview")).toHaveAttribute("data-preview-kind", "table"))
    await waitFor(() => expect(screen.getByTestId("dataset-preview")).not.toHaveAttribute("aria-busy"))
    expect(screen.getByTestId("dataset-object")).toHaveAttribute("data-view-kind", "table")
    expect(stats()).toEqual(["rows", "columns", "size", "type"])
    expect(Array.from(document.querySelectorAll("th[data-column-name]")).map((e) => e.getAttribute("data-column-name"))).toEqual(["g", "v"])
  })

  it("reads: the backend viewKind wins over the name; the kind's own stats with 'at least'; no rows/columns", async () => {
    profileBody = { shape: { rows: 0, cols: 0 }, quality: "good", notes: [], viewKind: "reads",
      stats: [{ code: "reads", value: 1000, atLeast: true }, { code: "read_length", value: 151 }], findings: [] }
    renderObj("reads.txt", { preview: <div data-testid="custom-viewer" /> })
    await waitFor(() => expect(screen.getByTestId("dataset-object")).toHaveAttribute("data-view-kind", "reads"))
    await waitFor(() => expect(screen.getByTestId("dataset-preview")).toHaveAttribute("data-preview-kind", "reads"))
    expect(stats()).toEqual(["reads", "read_length", "size", "type"])
    const reads = document.querySelector("[data-testid=dataset-stat][data-stat=reads]")!
    expect(reads).toHaveTextContent("at least 1,000")
  })

  it("an xlsx (viewKind document) shows the profile summary, not 'preview unsupported'", async () => {
    profileBody = { shape: { rows: 0, cols: 0 }, quality: "unassessed", notes: [], viewKind: "document",
      stats: [{ code: "sheets", value: 2 }],
      findings: [{ section: "note", code: "spreadsheet_sheets", level: "info", params: { count: 2, sheets: ["A", "B"] } }] }
    renderObj("book.xlsx", { preview: <DatasetFilePreview projectId="p1" fileId="id-book.xlsx" name="book.xlsx" /> })
    await screen.findByTestId("dataset-kind-summary")
    expect(screen.getByTestId("dataset-preview")).toHaveAttribute("data-preview-kind", "document")
    expect(screen.queryByTestId("dataset-file-preview-unsupported")).toBeNull()
    expect(stats()).toEqual(["sheets", "size", "type"])
  })

  it("the file viewer's failure is data-preview-kind=error; while it loads the preview is aria-busy", async () => {
    profileBody = { shape: { rows: 0, cols: 0 }, quality: "good", notes: [], viewKind: "sequences", findings: [] }
    urlStatus = 403
    renderObj("seqs.fasta", { preview: <DatasetFilePreview projectId="p1" fileId="id-seqs.fasta" name="seqs.fasta" /> })
    expect(screen.getByTestId("dataset-preview")).toHaveAttribute("aria-busy", "true")
    await waitFor(() => expect(screen.getByTestId("dataset-preview")).toHaveAttribute("data-preview-kind", "error"))
    expect(screen.getByTestId("dataset-preview")).not.toHaveAttribute("aria-busy")
  })
})

describe("header version chip", () => {
  it("shows the CURRENT version as soon as the file opens (was v1 until the Versions tab was visited)", async () => {
    versionsBody = { versions: [
      { version: "2", label: "v2", current: true, createdAt: "2026-11-12T09:06:21Z", authorName: "A" },
      { version: "1", label: "v1", current: false, createdAt: "2026-11-12T09:06:20Z", authorName: "A" },
    ] }
    // Self-contained: a plain table profile and rows, independent of earlier tests' state.
    profileBody = { shape: { rows: 1, cols: 2 }, quality: "good", notes: [], viewKind: "table", columns: ["a", "b"], sampleRows: [["1", "3"]] }
    rowsBody = { status: 200, body: { tabular: true, viewKind: "table", columns: ["a", "b"], rows: [["1", "3"]], totalRows: 1, version: 2, headerRow: true } }
    renderObj("v.csv")
    await waitFor(() => expect(screen.getByTestId("dataset-header-version")).toHaveTextContent("v2"))
  })
})
