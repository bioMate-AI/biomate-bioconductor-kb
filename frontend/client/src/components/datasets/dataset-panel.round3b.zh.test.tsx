/**
 * Round-3b in Chinese: the round-3 profiler's new codes, the folder's single-end samplesheet /
 * patterns / "this folder", the spreadsheet preview caption and a featureCounts format chip read as
 * natural Chinese with no untranslated English UI words (data values, file names, format and tool
 * names removed). The i18n locale is resolved at module load, so modules are re-imported after the
 * stored language preference is set.
 */
import { describe, it, expect, vi, afterEach } from "vitest"
import { MIXED_FOLDER } from "./round3b.fixtures"

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function leftoverEnglish(text: string, allowed: string[]): string[] {
  let rest = text
  for (const tok of [...allowed].sort((a, b) => b.length - a.length)) rest = rest.split(tok).join(" ")
  return Array.from(new Set(rest.match(/[A-Za-z]{2,}/g) ?? []))
}
function textWithTitles(container: HTMLElement): string {
  const parts = [container.textContent ?? ""]
  container.querySelectorAll("[title],[aria-label]").forEach((el) => {
    for (const a of ["title", "aria-label"]) { const v = el.getAttribute(a); if (v) parts.push(v) }
  })
  return parts.join("\n")
}

async function zhModules(body: (url: string) => { status: number; body: unknown }) {
  vi.resetModules()
  localStorage.setItem("biomate-user-settings", JSON.stringify({ language: "chinese" }))
  global.fetch = vi.fn(async (input: RequestInfo | URL) => {
    const r = body(String(input))
    return { ok: r.status < 400, status: r.status, json: async () => r.body, text: async () => "" } as unknown as Response
  }) as unknown as typeof fetch
  const React = await import("react")
  const rtl = await import("@testing-library/react")
  const { QueryClient, QueryClientProvider } = await import("@tanstack/react-query")
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  const wrap = (el: React.ReactElement) => rtl.render(React.createElement(QueryClientProvider, { client: qc }, el))
  return { React, rtl, wrap }
}

describe("round-3b in Chinese", () => {
  it("folder: 本文件夹, 单端样本表 + excluded note, layout / path base, patterns", async () => {
    const { React, rtl, wrap } = await zhModules((u) => ({ status: 200, body: u.includes("/folders/profile") ? MIXED_FOLDER : {} }))
    const { FolderProfileView } = await import("./folder-profile-view")
    const { container } = wrap(React.createElement(FolderProfileView, { projectId: "p1", path: "" }))
    await rtl.waitFor(() => expect(rtl.screen.getByTestId("folder-profile").getAttribute("data-kind")).toBe("mixed"))
    const text = textWithTitles(container)
    expect(text).toContain("本文件夹中的 10x Genomics 矩阵（v3）")
    expect(text).toContain("根据 _R1/_R2 和 _1/_2 命名规则识别出 2 个双端样本")
    expect(text).toContain("已生成 nf-core 样本表（双端；sample、fastq_1、fastq_2）：共 2 行。路径相对于项目输入文件。")
    expect(text).toContain("单独生成单端样本表（samplesheet_single_end.csv，共 1 行）：S3_R1.fastq.gz")
    expect(rtl.screen.getByTestId("folder-samplesheet-single-download")).toHaveTextContent("单端样本表")
    expect(rtl.screen.getByTestId("folder-samplesheet-paths")).toHaveTextContent("双端样本表 · 路径相对于项目输入文件")
    expect(rtl.screen.getByTestId("folder-samplesheet-excluded")).toHaveTextContent("未放入双端样本表（本文件夹中没有配对文件）：S3_R1.fastq.gz")
    expect(rtl.screen.getByTestId("folder-rollup")).toHaveTextContent("1 个 featureCounts 计数表")
    const leftover = leftoverEnglish(text, [
      "S1_R1.fastq.gz", "S1_R2.fastq.gz", "WT_1_1.fq.gz", "WT_1_2.fq.gz", "S3_R1.fastq.gz", "samplesheet_single_end.csv",
      "matrix.mtx", "barcodes.tsv", "features.tsv", "S1", "S3", "WT_1", "_R1/_R2", "_1/_2", "FASTQ", "TSV", "featureCounts",
      "Matrix Market", "nf-core", "sample", "fastq_1", "fastq_2", "10x Genomics", "Cell Ranger", "v3", "R1", "R2", "barcodes", "features",
    ])
    if (leftover.length) console.log("LEFTOVER", leftover, text.slice(0, 2000))
    expect(leftover).toEqual([])
  }, 30_000)

  it("new finding codes, the spreadsheet caption and a featureCounts chip read in Chinese", async () => {
    const PROFILES: Record<string, unknown> = {
      "projects/p1/inputs/plate.xlsx": {
        shape: { rows: 0, cols: 0 }, quality: "unassessed", notes: [], viewKind: "document",
        format: { ext: "xlsx", label: "Excel (xlsx)", source: "galaxy" }, stats: [{ code: "sheets", value: 1 }],
        columns: ["well", "od600"], sampleRows: [["A1", "0.41"]], previewSheet: "Plate1",
        findings: [
          { section: "signal", code: "spreadsheet_sheets", level: "info", params: { count: 1, sheets: ["Plate1"] } },
          { section: "note", code: "spreadsheet_preview", level: "info", params: { sheet: "Plate1", rows: 1 } },
          { section: "note", code: "duplicate_rows", level: "info", params: { count: 3 } },
        ],
      },
      "projects/p1/inputs/counts.txt": {
        shape: { rows: 12, cols: 7 }, quality: "good", notes: [], viewKind: "table",
        format: { ext: "tabular", label: "featureCounts counts", source: "biomate", layout: "featurecounts" },
        label: { column: "group", confident: false },
        columns: ["Geneid", "S1"], sampleRows: [["G1", "4"]],
        findings: [
          { section: "note", code: "label_few_rows", level: "info", params: { column: "group", rows: 12, min_rows: 20 } },
          { section: "note", code: "table_clean_label_unchecked", level: "info", params: { rows: 12, cols: 7 } },
        ],
      },
    }
    for (const [ref, name] of [["projects/p1/inputs/plate.xlsx", "plate.xlsx"], ["projects/p1/inputs/counts.txt", "counts.txt"]] as const) {
      const { React, rtl, wrap } = await zhModules((u) => ({
        status: u.includes("/rows") ? 415 : 200,
        body: u.includes("/api/perception/profile") ? PROFILES[ref] : {},
      }))
      const { DatasetObject } = await import("./dataset-object")
      const { container, unmount } = wrap(React.createElement(DatasetObject, {
        projectId: "p1", onDownload: () => {}, onRunQC: () => {},
        dataset: { id: name, name, ref, size: 4000, source: "upload" },
      }))
      await rtl.screen.findByTestId("data-perception")
      const text = textWithTitles(container)
      if (name === "plate.xlsx") {
        expect(rtl.screen.getByTestId("dataset-spreadsheet-caption")).toHaveTextContent("工作表“Plate1” · 前 1 行")
        expect(text).toContain("完全重复的行：3 行。")
      } else {
        expect(rtl.screen.getByTestId("dataset-header-format")).toHaveTextContent("featureCounts 计数表")
        expect(text).toContain("列“group”看似分组列（如处理条件），但只有")
      }
      const leftover = leftoverEnglish(text, [
        "plate.xlsx", "counts.txt", "Plate1", "well", "od600", "A1", "Excel", "xlsx", "CSV", "Geneid", "S1", "G1", "group",
        "featureCounts", "BioMate", "KB", "QC", "FastQC", "MultiQC",
      ])
      if (leftover.length) console.log("LEFTOVER", name, leftover, text.slice(0, 2000))
      expect(leftover).toEqual([])
      unmount()
    }
  }, 60_000)
})
