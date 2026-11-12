/**
 * Dataset panel round-3b: the client adopts the profiler's round-3 contract
 * (origin/fix/ds-r3-profiler-20261112 @ f74176aac8, data_perception.py / folder_profile.py):
 *  W7  `labelColumn` (confident labels only) decides effective N / groups / leakage;
 *  W2  `columnStats` (type parsed with the decimal mark + role) drive the Columns view;
 *  B5  an xlsx's first-sheet preview (`previewSheet` + `columns` + `sampleRows`) is shown read-only;
 *  W5  AnnData `layers` vs its stored components; the note matches the actions on offer;
 *  W3  a recognised tool layout's format label ("featureCounts counts");
 *  W8/W9/P10 folder: `dir: null` = this folder, the single-end samplesheet + its excluded files,
 *      the sheet's layout / path base, every pairing pattern, the roll-up's per-file labels.
 * Our own endpoints are faked at fetch; the profiles are the backend's round-3 shape.
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, waitFor, within } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { DataPerception, findingText, type DataProfile } from "@/components/data-perception"
import { DatasetObject, type DatasetRef } from "./dataset-object"
import { computeColumnStats, DatasetColumnsView } from "./dataset-columns-view"
import { AnnDataSummary } from "./dataset-kind-views"
import { FolderProfileView } from "./folder-profile-view"
import { formatLabelText } from "./format-labels"
import { t } from "@/lib/i18n"
import { MIXED_FOLDER } from "./round3b.fixtures"

let profiles: Record<string, unknown> = {}
let folderBody: unknown = {}
beforeEach(() => {
  profiles = {}
  folderBody = {}
  global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(String(input), "http://x")
    const res = (status: number, body: unknown) =>
      ({ ok: status < 400, status, json: async () => body, text: async () => "" }) as unknown as Response
    if (url.pathname === "/api/perception/profile") {
      const { datasetRef } = JSON.parse(String(init?.body ?? "{}"))
      return profiles[datasetRef] ? res(200, profiles[datasetRef]) : res(403, {})
    }
    if (url.pathname.endsWith("/folders/profile")) return res(200, folderBody)
    if (url.pathname.endsWith("/rows")) return res(415, {})
    return res(200, {})
  }) as unknown as typeof fetch
})

const qc = () => new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
const ds = (name: string): DatasetRef => ({ id: `id-${name}`, name, ref: `projects/p1/inputs/${name}`, size: 4000, source: "upload" })
const wrap = (el: React.ReactElement) => render(<QueryClientProvider client={qc()}>{el}</QueryClientProvider>)

// ── W7: labelColumn is the signal ──────────────────────────────────────────────
describe("labelColumn decides effective N / groups / leakage", () => {
  const base: DataProfile = {
    shape: { rows: 12, cols: 3 }, quality: "good", notes: [], viewKind: "table",
    effectiveN: 8, effectiveNReason: "imbalance",
    classBalance: [{ label: "ctrl", frac: 0.75 }, { label: "trt", frac: 0.25 }],
    findings: [{ section: "leakage", code: "leaked_id", level: "info", params: { column: "sample_id" } }],
  }
  it("a non-confident label (no labelColumn) shows no groups, effective N or leakage", () => {
    render(<DataPerception profile={{ ...base, label: { column: "condition", confident: false } }} />)
    expect(screen.queryByTestId("perception-class-balance")).toBeNull()
    expect(screen.queryByTestId("perception-effective-n")).toBeNull()
    expect(screen.queryByTestId("perception-leakage")).toBeNull()
  })
  it("a confident label (labelColumn) shows them, headed by the column", () => {
    render(<DataPerception profile={{ ...base, label: { column: "condition", confident: true }, labelColumn: "condition" }} />)
    expect(screen.getByTestId("perception-class-balance")).toHaveTextContent("condition")
    expect(screen.getByTestId("perception-effective-n")).toBeInTheDocument()
    expect(screen.getByTestId("perception-leakage")).toBeInTheDocument()
  })
})

// ── W2: columnStats ────────────────────────────────────────────────────────────
describe("Columns view uses the profiler's columnStats", () => {
  // featureCounts: Chr is an annotation column (one chromosome → constant / sparse by design);
  // Geneid an identifier; the loaded sample has Chr missing on most rows.
  const cols = ["Geneid", "Chr", "S1"]
  const rows = [["G1", "", "1,5"], ["G2", "", "2,5"], ["G3", "chr1", "3,0"]]
  const columnStats = [
    { name: "Geneid", type: "text", present: 500, missing: 0, distinct: 500, role: "identifier" },
    { name: "Chr", type: "categorical", present: 120, missing: 380, distinct: 1, role: "annotation" },
    { name: "S1", type: "numeric", present: 500, missing: 0, distinct: 300, min: 0.5, max: 12.5, mean: 3.25 },
  ] as any

  it("identifier / annotation columns are labelled as such, not 'watch'; type follows the profiler", () => {
    const s = computeColumnStats(cols, rows, [], { profileStats: columnStats, decimal: "," })
    expect(s.map((c) => [c.name, c.type, c.role ?? null, c.watch])).toEqual([
      ["Geneid", "text", "identifier", false],
      ["Chr", "categorical", "annotation", false],
      ["S1", "numeric", null, false],
    ])
    render(<DatasetColumnsView columns={cols} sampleRows={rows} findings={[]} totalRows={500}
      profileStats={columnStats} decimal="," t={t} />)
    const roles = screen.getAllByTestId("dataset-column-role").map((e) => e.getAttribute("data-role"))
    expect(roles).toEqual(["identifier", "annotation"])
    expect(screen.queryByTestId("dataset-column-watch")).toBeNull()
    expect(screen.getAllByTestId("dataset-column-range")[2]).toHaveTextContent("0.5 – 12.5 (mean 3.25)")
    expect(screen.getByTestId("dataset-columns-sample-note")).toHaveTextContent("Computed by the profiler on all 500 rows.")
  })

  it("a column named by a profiler finding is still 'watch'", () => {
    const s = computeColumnStats(cols, rows, [{ section: "signal", code: "high_missing", level: "watch", params: { columns: ["S1"] } }],
      { profileStats: columnStats })
    expect(s.find((c) => c.name === "S1")!.watch).toBe(true)
  })

  it("without columnStats, numbers are read with the table's decimal mark (\"1,5\" is numeric)", () => {
    const s = computeColumnStats(cols, rows, [], { decimal: "," })
    expect(s.find((c) => c.name === "S1")!.type).toBe("numeric")
  })
})

// ── B5: xlsx first-sheet preview ───────────────────────────────────────────────
describe("spreadsheet preview", () => {
  it("shows the first sheet's first rows read-only, captioned, instead of 'export to CSV'", async () => {
    profiles["projects/p1/inputs/plate.xlsx"] = {
      shape: { rows: 0, cols: 0 }, quality: "unassessed", notes: [], viewKind: "document",
      format: { ext: "xlsx", label: "Excel (xlsx)", source: "galaxy" },
      stats: [{ code: "sheets", value: 2 }],
      columns: ["well", "od600"], sampleRows: [["A1", "0.41"], ["A2", "0.39"]], previewSheet: "Plate 1",
      findings: [
        { section: "signal", code: "spreadsheet_sheets", level: "info", params: { count: 2, sheets: ["Plate 1", "Notes"] } },
        { section: "note", code: "spreadsheet_preview", level: "info", params: { sheet: "Plate 1", rows: 2 } },
        { section: "note", code: "spreadsheet_convert", level: "info", params: {} },
      ],
    }
    wrap(<DatasetObject projectId="p1" dataset={ds("plate.xlsx")} onDownload={() => {}} onRunQC={() => {}} />)
    const prev = await screen.findByTestId("dataset-spreadsheet-preview")
    expect(prev.getAttribute("data-sheet")).toBe("Plate 1")
    expect(screen.getByTestId("dataset-spreadsheet-caption")).toHaveTextContent("Sheet “Plate 1” · first 2 rows")
    const table = within(prev).getByTestId("dataset-preview-table")
    expect(within(table).getByText("A1")).toBeInTheDocument()
    expect(within(table).getByText("od600")).toBeInTheDocument()
    // The preview itself is the rows, not advice to export (the QC card keeps the profiler's note
    // on how to get the table checks).
    expect(screen.getByTestId("dataset-kind-summary").textContent).not.toMatch(/export the sheet to CSV/)
    expect(screen.queryByTestId("dataset-preview-toggle-edit")).toBeNull()
    expect(within(prev).queryAllByRole("textbox").filter((e) => e.tagName === "TEXTAREA")).toEqual([])
    expect(screen.getByTestId("dataset-preview").getAttribute("data-preview-kind")).toBe("document")
  })
})

// ── W5 + item 4: AnnData ───────────────────────────────────────────────────────
describe("AnnData summary", () => {
  const prof: DataProfile = {
    shape: { rows: 0, cols: 0 }, quality: "unassessed", notes: [], viewKind: "anndata", layers: [],
    stats: [{ code: "cells", value: 2700 }, { code: "genes", value: 32738 }],
    findings: [
      { section: "note", code: "anndata_no_layers", level: "info", params: {} },
      { section: "note", code: "anndata_components", level: "info", params: { count: 4, components: ["X", "obs", "var", "uns"] } },
    ],
  }
  it("no layers says X only; the stored components are listed apart", () => {
    render(<AnnDataSummary profile={prof} kind="anndata" />)
    expect(screen.getByTestId("dataset-anndata-no-layers")).toHaveTextContent("No layers: the expression values are in X only.")
    expect(screen.queryByTestId("dataset-anndata-layers")).toBeNull()
    expect(screen.getByTestId("dataset-anndata-groups")).toHaveTextContent("Stored parts of the file · 4")
    expect(screen.getByTestId("dataset-anndata-groups")).toHaveTextContent("uns")
  })
  it("the note does not point to Jupyter while Open-in is not offered", async () => {
    profiles["projects/p1/inputs/pbmc.h5ad"] = prof
    wrap(<DatasetObject projectId="p1" dataset={ds("pbmc.h5ad")} onDownload={() => {}} onRunQC={() => {}} onAnalyze={() => {}} />)
    const note = await screen.findByTestId("dataset-anndata-note")
    expect(screen.queryByTestId("dataset-object-open-in")).toBeNull()
    expect(note.textContent).not.toMatch(/Jupyter/)
    expect(note).toHaveTextContent("Ask in chat")
  })
})

// ── W3: recognised tool layouts ────────────────────────────────────────────────
describe("tool-layout format labels", () => {
  it("featureCounts / MAGeCK / Salmon / RSEM labels read naturally in Chinese", () => {
    expect(formatLabelText({ ext: "tsv", label: "featureCounts counts" }, "zh")).toBe("featureCounts 计数表")
    expect(formatLabelText({ ext: "tsv", label: "MAGeCK counts" }, "zh")).toBe("MAGeCK sgRNA 计数表")
    expect(formatLabelText({ ext: "tsv", label: "Salmon quantification" }, "zh")).toBe("Salmon 定量结果")
    expect(formatLabelText({ ext: "tsv", label: "RSEM quantification" }, "zh")).toBe("RSEM 定量结果")
    expect(formatLabelText({ ext: "tsv", label: "featureCounts counts" }, "en")).toBe("featureCounts counts")
  })
  it("the format chip shows the layout's label and carries the layout", async () => {
    profiles["projects/p1/inputs/counts.txt"] = {
      shape: { rows: 2, cols: 7 }, quality: "good", notes: [], viewKind: "table",
      format: { ext: "tabular", label: "featureCounts counts", source: "biomate", layout: "featurecounts" },
      columns: ["Geneid", "Chr", "Start", "End", "Strand", "Length", "S1"], sampleRows: [["G1", "chr1", "1", "9", "+", "9", "4"]],
      findings: [],
    }
    wrap(<DatasetObject projectId="p1" dataset={ds("counts.txt")} onDownload={() => {}} onRunQC={() => {}} />)
    const chip = await screen.findByTestId("dataset-header-format")
    expect(chip).toHaveTextContent("featureCounts counts")
    expect(chip.getAttribute("data-format-layout")).toBe("featurecounts")
  })
})

// ── folder profile ─────────────────────────────────────────────────────────────
describe("folder profile (round 3)", () => {
  it("this folder, single-end sheet + excluded files, layout / path base, patterns, per-file roll-up labels", async () => {
    folderBody = MIXED_FOLDER
    wrap(<FolderProfileView projectId="p1" path="" />)
    await waitFor(() => expect(screen.getByTestId("folder-profile").getAttribute("data-kind")).toBe("mixed"))
    const codeText = (code: string) => screen.getAllByTestId("folder-finding").find((e) => e.getAttribute("data-code") === code)!.textContent
    expect(codeText("folder_tenx_recognised")).toContain("10x Genomics matrix (v3) in this folder: 5 cells × 7 genes")
    expect(codeText("folder_fastq_pairs")).toContain("from the _R1/_R2 and _1/_2 file naming")
    expect(codeText("folder_samplesheet")).toContain("(paired-end; sample, fastq_1, fastq_2); rows: 2. Paths are relative to the project's input files.")
    expect(codeText("folder_samplesheet_single_end")).toContain("separate single-end samplesheet (samplesheet_single_end.csv, rows: 1): S3_R1.fastq.gz")
    expect(screen.getByTestId("folder-tenx-set-.")).toHaveTextContent("this folder")

    const single = screen.getByTestId("folder-samplesheet-single-download")
    expect(single).toHaveTextContent("Single-end samplesheet")
    expect(single.getAttribute("download")).toBe("inputs_samplesheet_single_end.csv")
    expect(decodeURIComponent(single.getAttribute("href")!.split(",").slice(1).join(","))).toBe("sample,fastq_1,fastq_2\nS3,S3_R1.fastq.gz,\n")
    expect(screen.getByTestId("folder-samplesheet-download").getAttribute("data-layout")).toBe("paired")
    expect(screen.getByTestId("folder-samplesheet-excluded")).toHaveTextContent("Not in the paired samplesheet (no mate in this folder): S3_R1.fastq.gz")
    expect(screen.getByTestId("folder-samplesheet-paths")).toHaveTextContent("paired-end samplesheet · paths are relative to the project's input files")
    expect(screen.getByTestId("folder-fastq-patterns")).toHaveTextContent("Pairs named by _R1/_R2 and _1/_2")

    const parts = screen.getAllByTestId("folder-rollup-part")
    expect(parts.map((p) => [p.textContent, p.getAttribute("data-view-kind")])).toEqual([
      ["5 FASTQ · pairs: 2", "reads"], ["1 TSV", "table"], ["1 featureCounts counts", "table"], ["1 Matrix Market", "matrix"], ["1 TSV", null],
    ])
    expect(screen.getByTestId("folder-rollup")).toHaveTextContent("Files: 9 — 5 FASTQ · pairs: 2, 1 TSV, 1 featureCounts counts, 1 Matrix Market, 1 TSV")
  })

  it("an older profile's '.' dir also reads as this folder", () => {
    expect(findingText({ section: "note", code: "folder_tenx_incomplete", level: "watch", params: { dir: ".", missing: "barcodes.tsv" } }))
      .toBe("The 10x matrix in this folder is missing its barcodes.tsv file.")
    expect(findingText({ section: "note", code: "folder_tenx_incomplete", level: "watch", params: { dir: "run1/filtered", missing: "barcodes.tsv" } }))
      .toBe("The 10x matrix in run1/filtered is missing its barcodes.tsv file.")
  })
})
