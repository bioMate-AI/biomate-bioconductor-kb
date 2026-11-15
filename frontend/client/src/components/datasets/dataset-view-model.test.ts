/**
 * The per-kind view model is the single place that decides which preview views, stats and
 * actions a file gets (U1/U2/U11). These cases pin the kind → views table.
 */
import { describe, it, expect } from "vitest"
import { datasetKind, datasetViewModel, effectiveQuality, profileStats, columnProblems, kindFromName, OPEN_IN_AVAILABLE } from "./dataset-view-model"

const vm = (name: string, opts: Record<string, unknown> = {}) =>
  datasetViewModel(kindFromName(name), { name, hasColumns: true, versionable: true, projectFile: true, ...opts })

describe("kind → views", () => {
  it("tables get Table / Columns / Plot / Edit; records the same minus Edit", () => {
    expect(vm("counts.csv").views).toEqual(["table", "columns", "plot", "edit"])
    expect(vm("records.jsonl").views).toEqual(["table", "columns", "plot"])
  })
  it("every non-table kind has exactly one view of its own (no Table/Columns/Plot toggles)", () => {
    for (const n of ["plot.png", "scan.tiff", "report.pdf", "notes.md", "5e5z.pdb", "genome.fasta", "r1.fastq.gz",
      "a.bam", "pbmc.h5ad", "x.loom", "matrix.mtx", "config.json", "calls.vcf.gz", "data.zip", "blob.bin", "thing.xyz"]) {
      expect(vm(n).views, n).toEqual(["content"])
    }
  })
  it("chooses the right renderer per kind", () => {
    expect(vm("pbmc.h5ad").content).toBe("anndata")
    expect(vm("x.loom").content).toBe("anndata")
    expect(vm("a.bam").content).toBe("viewer") // IGV.js slot — not Interactive Tools
    expect(vm("plot.png").content).toBe("viewer")
    expect(vm("data.zip").content).toBe("download")
    expect(vm("thing.xyz").content).toBe("download")
    expect(vm("peaks.bed").content).toBe("rows")
  })
  it("a spreadsheet the rows reader cannot parse is a summary, not empty Table/Columns", () => {
    const m = datasetViewModel("table", { name: "book.xlsx", hasColumns: false, columnsPending: false, versionable: true })
    expect(m.views).toEqual(["content"])
    expect(m.content).toBe("summary")
    expect(m.canEdit).toBe(false)
  })
  it("Edit only for an uncompressed delimited table in a project; Run full QC / Open in only where meaningful", () => {
    expect(vm("counts.csv.gz").canEdit).toBe(false)
    expect(vm("counts.tsv", { versionable: false }).views).not.toContain("edit")
    expect(vm("plot.png").canRunQC).toBe(false)
    expect(vm("notes.md").canRunQC).toBe(false)
    expect(vm("r1.fastq.gz").canRunQC).toBe(true)
    expect(vm("plot.png").openInSupported).toBe(false)
    expect(vm("model.rds").openInSupported).toBe(true)
  })
  it("Open-in is offered only while its launch path is available (one switch for button + copy)", () => {
    expect(vm("model.rds").canOpenIn).toBe(OPEN_IN_AVAILABLE)
    expect(vm("cells.h5ad").canOpenIn).toBe(OPEN_IN_AVAILABLE)
  })
  it("content-first: the profiler's viewKind beats the extension", () => {
    expect(datasetKind("reads.txt", { viewKind: "reads" })).toBe("reads")
    expect(datasetKind("reads.txt", {})).toBe("table")
    expect(datasetKind("fake.png", { viewKind: "unknown" })).toBe("unknown")
  })
})

describe("stats per kind (U2)", () => {
  it("uses profile.stats when present", () => {
    expect(profileStats({ shape: { rows: 0, cols: 0 }, quality: "good", notes: [], stats: [{ code: "cells", value: 2700 }] }, "anndata"))
      .toEqual([{ code: "cells", value: 2700 }])
  })
  it("never rows × columns for a non-table; derived from the kind's own findings on older profiles", () => {
    const png = { shape: { rows: 0, cols: 0 }, quality: "watch" as const, notes: [] }
    expect(profileStats(png, "image")).toEqual([])
    const fq = { shape: { rows: 1000, cols: 150 }, quality: "good" as const, notes: [],
      findings: [{ section: "signal" as const, code: "fastq_reads", level: "info" as const, params: { reads: 1000, mean_len: 150 } }] }
    expect(profileStats(fq, "reads")).toEqual([{ code: "reads", value: 1000 }, { code: "read_length", value: 150 }])
    const h5ad = { shape: { rows: 1, cols: 1 }, quality: "watch" as const, notes: [],
      findings: [{ section: "signal" as const, code: "anndata_shape", level: "info" as const, params: { cells: 2700, genes: 32738 } }] }
    expect(profileStats(h5ad, "anndata")).toEqual([{ code: "cells", value: 2700 }, { code: "genes", value: 32738 }])
  })
})

describe("quality: not analysed is 'unassessed', not Watch (U4)", () => {
  it("backend unassessed passes through; an old 'watch' whose only reason is 'not analysed' becomes unassessed", () => {
    expect(effectiveQuality({ quality: "unassessed", findings: [] })).toBe("unassessed")
    expect(effectiveQuality({ quality: "watch", findings: [{ section: "note", code: "format_identified", level: "watch", params: {} }] })).toBe("unassessed")
    expect(effectiveQuality({ quality: "watch", findings: [
      { section: "note", code: "format_identified", level: "watch", params: {} },
      { section: "signal", code: "high_missing", level: "watch", params: {} },
    ] })).toBe("watch")
  })
})

describe("columnProblems (U8)", () => {
  it("maps only the columns a problem finding names", () => {
    const m = columnProblems([
      { section: "signal", code: "high_missing", level: "watch", params: { columns: ["a", "b"] } },
      { section: "leakage", code: "leaked_id", level: "watch", params: { column: "id" } },
      { section: "note", code: "intervals_stranded", level: "info", params: { column: "strand" } },
    ])
    expect([...m.keys()].sort()).toEqual(["a", "b", "id"])
  })
})

describe("extension fallback speaks the profiler's decide() vocabulary (2026-11-12 seams)", () => {
  it("old profiles without viewKind get the kind the profiler would decide", () => {
    expect(kindFromName("book.xlsx")).toBe("document")
    expect(kindFromName("report.docx")).toBe("document")
    expect(kindFromName("drugs.smi")).toBe("table")
    expect(kindFromName("drugs.sdf")).toBe("molecules")
    expect(kindFromName("map.mrc")).toBe("image")
    // `.map` / `.rec` are not MRC by name (a PLINK .map is a text table): only the profiler says so.
    expect(kindFromName("chr1.map")).toBe("unknown")
    expect(kindFromName("tomo.rec")).toBe("unknown")
    expect(kindFromName("reads.pod5")).toBe("binary")
    expect(kindFromName("x.bw")).toBe("binary")
  })
  it("a spreadsheet document shows the profile summary; molecules are not paged as rows", () => {
    expect(datasetViewModel("document", { name: "book.xlsx" }).content).toBe("summary")
    expect(datasetViewModel("document", { name: "notes.md" }).content).toBe("viewer")
    expect(datasetViewModel("molecules", { name: "drugs.sdf" }).useRows).toBe(false)
    expect(datasetViewModel("table", { name: "drugs.smi" }).useRows).toBe(true)
  })
  it("backend stats keep atLeast; an old fastq_reads finding's at_least marks reads only", () => {
    expect(profileStats({ shape: { rows: 0, cols: 0 }, quality: "good", notes: [], stats: [{ code: "reads", value: 9, atLeast: true }] }, "reads"))
      .toEqual([{ code: "reads", value: 9, atLeast: true }])
    expect(profileStats({ shape: { rows: 0, cols: 0 }, quality: "good", notes: [],
      findings: [{ section: "signal", code: "fastq_reads", level: "info", params: { reads: 9, mean_len: 100, at_least: true } }] }, "reads"))
      .toEqual([{ code: "reads", value: 9, atLeast: true }, { code: "read_length", value: 100 }])
  })
})
