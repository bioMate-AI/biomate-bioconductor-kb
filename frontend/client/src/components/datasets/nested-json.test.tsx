/**
 * JSONL records with nested lists (founder 2026-11-11, epar_study_tables.jsonl: "should not it be
 * analyzed as a json?") — the Preview showed `headers`/`rows` as truncated JSON text.
 * Fixture: real EPAR records (trimmed text), as the rows reader delivers them (compact JSON cells).
 */
import React from "react"
import { describe, it, expect } from "vitest"
import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { parseNested, recordTables } from "./nested-json"
import { DatasetRowsTable } from "./dataset-rows-table"

const columns = ["source", "drug", "page", "headers", "rows"]
const cell = (v: unknown) => JSON.stringify(v)
const vision = [
  "epar_table", "pluvicto", "70",
  cell(["Title: Trial PSMA_617-01 VISION", "", ""]),
  cell([["Study identifier", "PSMA-617-01, EudraCT no. 2018-000459-41, NCT03511664", ""],
        ["Design", "Phase III, open-label, event-driven, randomized", ""]]),
]
const ragged = [
  "epar_table", "pluvicto", "30",
  cell(["Protocol No., Countries & Study Dates", "", "Study Design,"]),
  cell([["", "", "Purpose &", ""], ["Protocol: PSMA-617-01", "Design", "x", "y"]]),
]

describe("parseNested", () => {
  it("classifies matrix / list / object and ignores scalars and plain text", () => {
    expect(parseNested(vision[4])).toMatchObject({ kind: "matrix", rows: 2, cols: 3 })
    expect(parseNested(vision[3])).toMatchObject({ kind: "list", rows: 3 })
    expect(parseNested('{"a":1,"b":[2]}')).toMatchObject({ kind: "object", rows: 2 })
    expect(parseNested("pluvicto")).toBeNull()
    expect(parseNested("70")).toBeNull()
    expect(parseNested("[not json")).toBeNull()
  })
})

describe("recordTables", () => {
  it("pairs a matrix with a same-width string list as its header row", () => {
    const [tb] = recordTables(columns, vision)
    expect(tb.field).toBe("rows")
    expect(tb.headerField).toBe("headers")
    expect(tb.header).toEqual(["Title: Trial PSMA_617-01 VISION", "", ""])
    expect(tb.body).toHaveLength(2)
  })
  it("keeps a ragged extraction as a header-less table (widths differ)", () => {
    const [tb] = recordTables(columns, ragged)
    expect(tb.header).toBeNull()
    expect(tb.body[1]).toEqual(["Protocol: PSMA-617-01", "Design", "x", "y"])
  })
})

describe("DatasetRowsTable with nested JSONL cells", () => {
  const props = { columns, rows: [vision, ragged], total: 2, loading: false, error: null, onNeedMore: () => {} }

  it("shows structure labels instead of truncated JSON, and opens a row as a record with a real table", () => {
    render(<DatasetRowsTable {...props} />)
    const chips = screen.getAllByTestId("dataset-nested-cell").map((e) => e.textContent)
    expect(chips.some((c) => /2\s*×\s*3/.test(c || ""))).toBe(true)
    expect(document.body.textContent).not.toContain('[["Study identifier"')

    fireEvent.click(screen.getAllByTestId("dataset-preview-row")[0])
    const rec = screen.getByTestId("dataset-record-view")
    const table = rec.querySelector('[data-testid="dataset-record-table"] table')!
    expect(table.querySelectorAll("thead th")[0].textContent).toBe("Title: Trial PSMA_617-01 VISION")
    expect(table.querySelectorAll("tbody tr")).toHaveLength(2)
    expect(table.querySelector("tbody td")!.textContent).toBe("Study identifier")
    expect(rec.textContent).toContain("pluvicto")   // scalar fields stay as key/value

    fireEvent.click(screen.getByTestId("dataset-record-close"))
    expect(screen.queryByTestId("dataset-record-view")).toBeNull()
  })

  it("non-table nested values open in the JSON viewer (json-edit-react), searchable", async () => {
    const cols = ["id", "meta"]
    const row = ["r1", cell({ assay: "hERG", doses: [1, 3, 10], lab: { site: "A" } })]
    render(<DatasetRowsTable {...props} columns={cols} rows={[row]} total={1} />)
    fireEvent.click(screen.getAllByTestId("dataset-preview-row")[0])
    const tree = await screen.findByTestId("dataset-json-tree")
    await waitFor(() => expect(tree.textContent).toContain("hERG"))
    expect(tree.textContent).toContain("meta")
    expect(screen.getByTestId("dataset-record-search")).toBeTruthy()
  })

  it("plain CSV rows are unchanged (no chips, rows not clickable)", () => {
    render(<DatasetRowsTable {...props} columns={["a", "b"]} rows={[["1", "x"], ["2", "y"]]} />)
    expect(screen.queryAllByTestId("dataset-nested-cell")).toHaveLength(0)
    fireEvent.click(screen.getAllByTestId("dataset-preview-row")[0])
    expect(screen.queryByTestId("dataset-record-view")).toBeNull()
  })
})
