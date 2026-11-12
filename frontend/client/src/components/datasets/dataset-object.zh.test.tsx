/**
 * zh coverage for the per-kind views: an image ("未检查"), an AnnData summary, FASTQ reads and a
 * spreadsheet summary render with no untranslated English UI words (data, proper nouns and units
 * removed). The i18n locale is resolved at module load, so the modules are re-imported after
 * setting the stored language preference.
 */
import { describe, it, expect, vi, afterEach } from "vitest"

const PROFILES: Record<string, unknown> = {
  "umap.png": {
    shape: { rows: 0, cols: 0 }, quality: "watch", notes: [],
    format: { ext: "png", label: "PNG", source: "galaxy" },
    findings: [{ section: "note", code: "format_identified", level: "watch", params: { format: "PNG", size: "110.7 KB" } }],
  },
  "pbmc.h5ad": {
    shape: { rows: 2700, cols: 32738 }, quality: "watch", notes: [],
    format: { ext: "h5ad", label: "AnnData (h5ad)", source: "galaxy" },
    findings: [
      { section: "signal", code: "anndata_shape", level: "info", params: { cells: 2700, genes: 32738 } },
      { section: "note", code: "anndata_obs", level: "info", params: { count: 2, columns: ["louvain", "n_genes"] } },
      { section: "note", code: "anndata_embeddings", level: "info", params: { count: 1, embeddings: ["X_umap"] } },
      { section: "note", code: "format_metadata_only", level: "watch", params: { format: "AnnData" } },
    ],
  },
  "S1_R1.fastq.gz": {
    shape: { rows: 10000, cols: 151 }, quality: "good", notes: [], viewKind: "reads",
    format: { ext: "fastqsanger.gz", label: "FASTQ (gzip)", source: "galaxy" },
    findings: [
      { section: "signal", code: "fastq_reads", level: "info", params: { reads: 10000, at_least: true, mean_len: 151 } },
      { section: "signal", code: "fastq_mean_quality", level: "info", params: { q: 35.2 } },
    ],
  },
  "book.xlsx": {
    shape: { rows: 0, cols: 0 }, quality: "watch", notes: [],
    format: { ext: "xlsx", label: "Excel (xlsx)", source: "galaxy" },
    findings: [
      { section: "signal", code: "spreadsheet_sheets", level: "info", params: { count: 2, sheets: ["Sheet1", "QC"] } },
      { section: "note", code: "spreadsheet_convert", level: "info", params: {} },
      { section: "note", code: "format_metadata_only", level: "watch", params: { format: "Excel" } },
    ],
  },
}

const ALLOWED = [
  "umap.png", "pbmc.h5ad", "S1_R1.fastq.gz", "book.xlsx", "louvain", "n_genes", "X_umap", "Sheet1", "QC",
  "BioMate", "FastQC", "MultiQC", "PNG", "AnnData", "h5ad", "obs", "obsm", "var", "FASTQ", "gzip", "Excel", "xlsx", "CSV", "Phred", "Jupyter", "KB", "MB", "bp",
]
function leftoverEnglish(text: string): string[] {
  let rest = text
  for (const tok of [...ALLOWED].sort((a, b) => b.length - a.length)) rest = rest.split(tok).join(" ")
  return Array.from(new Set(rest.match(/[A-Za-z]{2,}/g) ?? []))
}

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

describe("dataset object per-kind views in Chinese", () => {
  for (const name of Object.keys(PROFILES)) {
    it(`${name}: no leftover English`, async () => {
      vi.resetModules()
      localStorage.setItem("biomate-user-settings", JSON.stringify({ language: "chinese" }))
      global.fetch = vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input)
        const body = url.includes("/api/perception/profile") ? PROFILES[name] : {}
        return { ok: true, status: url.includes("/rows") ? 415 : 200, json: async () => body, text: async () => "" } as unknown as Response
      }) as unknown as typeof fetch
      const React = await import("react")
      const { render, screen } = await import("@testing-library/react")
      const { QueryClient, QueryClientProvider } = await import("@tanstack/react-query")
      const { DatasetObject } = await import("./dataset-object")
      const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
      const { container } = render(React.createElement(QueryClientProvider, { client: qc },
        React.createElement(DatasetObject, {
          projectId: "p1", onDownload: () => {}, onRunQC: () => {},
          dataset: { id: name, name, ref: `projects/p1/inputs/${name}`, size: 113_000, source: "upload" },
          preview: name.endsWith(".png") ? React.createElement("div", null) : undefined,
        })))
      await screen.findByTestId("data-perception")
      const parts = [container.textContent ?? ""]
      container.querySelectorAll("[title],[aria-label]").forEach((el) => {
        for (const a of ["title", "aria-label"]) { const v = el.getAttribute(a); if (v) parts.push(v) }
      })
      const text = parts.join("\n")
      const leftover = leftoverEnglish(text)
      if (leftover.length) console.log("LEFTOVER", name, leftover, text.slice(0, 2000))
      expect(leftover).toEqual([])
      if (name === "umap.png") expect(text).toContain("未检查")
      // The read count lives in the stat grid ("at least" kept); the QC card does not repeat it (round 5).
      if (name === "S1_R1.fastq.gz") {
        expect(screen.getByTestId("dataset-stat-grid").textContent).toContain("至少 10,000")
        expect(text).not.toContain("已扫描读段数")
      }
    }, 30_000)
  }
})
