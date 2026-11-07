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
  it("flags a column named in a quality note as watch", () => {
    const s = computeColumnStats(cols, rows, ["two spellings of control in the label column"])
    expect(s.find(c => c.name === "label")!.watch).toBe(true)
    expect(s.find(c => c.name === "expr")!.watch).toBe(false)
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
      notes={[]}
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
