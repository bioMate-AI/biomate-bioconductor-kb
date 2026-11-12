// @vitest-environment jsdom
import { render, screen, cleanup } from "@testing-library/react"
import { afterEach, describe, expect, it } from "vitest"
import { computeColumnStats, DatasetColumnsView } from "./dataset-columns-view"

afterEach(cleanup)
const t = (k: string) => k  // identity: assert on keys/structure, not copy

describe("computeColumnStats", () => {
  const cols = ["gene", "expr", "batch", "label"]
  const rows = [
    ["TP53", "10.2", "NA", "ctrl"],
    ["BRCA1", "8.1", "NA", "treat"],
    ["EGFR", "9.9", "", "ctrl"],
    ["MYC", "7.3", "NA", "treat"],
  ]
  it("infers type, % missing, distinct per column", () => {
    const s = computeColumnStats(cols, rows, [])
    const gene = s[0], expr = s[1], batch = s[2], label = s[3]
    expect(expr.type).toBe("numeric")
    expect(label.type).toBe("categorical")  // 2 distinct over 4 present
    expect(gene.type).toBe("text")          // 4 unique strings
    expect(gene.allUnique).toBe(true)
    expect(batch.type).toBe("empty")        // all NA/empty
    expect(Math.round(batch.missingPct * 100)).toBe(100)
    expect(label.distinct).toBe(2)
  })
  it("flags only the column a finding names as a problem (structured params, U8)", () => {
    const findings = [
      { section: "leakage", code: "leaked_id", level: "watch", params: { column: "label" } },
      // A note whose TEXT mentions "expr" but is not about that column must not flag it.
      { section: "note", code: "table_summary", level: "info", params: { rows: 4, cols: 4 } },
    ] as any
    const s = computeColumnStats(cols, rows, findings)
    expect(s.find(c => c.name === "label")!.watch).toBe(true)
    expect(s.find(c => c.name === "label")!.watchFindings.map(f => f.code)).toEqual(["leaked_id"])
    expect(s.find(c => c.name === "expr")!.watch).toBe(false)
  })
  it("a healthy column is not flagged because its name appears inside a note's text (U8)", () => {
    // Old behaviour: any note mentioning the word "label"/"gene" flagged that column.
    const findings = [
      { section: "note", code: "label_spellings", level: "watch", params: { a: "gene", b: "Gene" } },
      { section: "signal", code: "near_constant", level: "watch", params: { count: 1, columns: ["batch_id"], pct: 99 } },
    ] as any
    const s = computeColumnStats(["gene", "label", "batch_id"], [["a", "x", "1"], ["b", "y", "1"]], findings)
    expect(s.find(c => c.name === "gene")!.watch).toBe(false)
    expect(s.find(c => c.name === "label")!.watch).toBe(false)
    expect(s.find(c => c.name === "batch_id")!.watch).toBe(true)
  })
  it("flags a high-missing column as watch even without a note", () => {
    const s = computeColumnStats(cols, rows, [])
    expect(s.find(c => c.name === "batch")!.watch).toBe(true)  // 100% missing
  })
})

describe("DatasetColumnsView", () => {
  it("renders one row per column with a watch chip where flagged", () => {
    render(<DatasetColumnsView
      columns={["gene", "batch"]}
      sampleRows={[["TP53", "NA"], ["EGFR", "NA"]]}
      findings={[]}
      totalRows={1000}
      t={t as any}
    />)
    expect(screen.getByTestId("dataset-preview-columns")).toBeInTheDocument()
    expect(screen.getAllByTestId("dataset-column-row")).toHaveLength(2)
    // batch is 100% missing → watch chip present
    expect(screen.getAllByTestId("dataset-column-watch").length).toBeGreaterThanOrEqual(1)
    expect(screen.getByTestId("dataset-columns-sample-note")).toBeInTheDocument()
  })
})

describe("DatasetColumnsView — header-only table (U3)", () => {
  it("lists the columns of a header-only file and says it has no data rows", () => {
    render(<DatasetColumnsView columns={["gene_id", "ctrl_1", "ctrl_2", "ctrl_3"]} sampleRows={[]} findings={[]} totalRows={0} t={t as any} />)
    expect(screen.getAllByTestId("dataset-column-row")).toHaveLength(4)
    expect(screen.getByTestId("dataset-preview-columns")).toHaveTextContent("gene_id")
    expect(screen.getByTestId("dataset-columns-sample-note")).toHaveTextContent("dataset_obj.columns_header_only")
    expect(screen.queryByTestId("dataset-column-watch")).toBeNull()
  })
})
