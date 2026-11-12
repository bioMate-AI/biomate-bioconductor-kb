/**
 * Header inference reaches the edit route: the rows reader reports whether line 1 is a header
 * record (`headerRow`); useDatasetRows keeps it and the save sends it back as `headerRows`, so a
 * header-less table's data rows are numbered from line 1 (2026-11-11). Network faked at fetch
 * (our own endpoints).
 */
import { describe, it, expect, vi, beforeEach } from "vitest"
import { renderHook, waitFor } from "@testing-library/react"
import { readFileSync } from "node:fs"
import { join } from "node:path"
import { useDatasetRows } from "./datasets-api"

let headerRow: unknown = false

beforeEach(() => {
  global.fetch = vi.fn(async () => ({
    ok: true, status: 200, text: async () => "",
    json: async () => ({ kind: "table", columns: ["column_1", "column_2"], rows: [["1", "2"], ["3", "4"]], offset: 0, limit: 200, totalRows: 2, headerRow }),
  }) as unknown as Response) as unknown as typeof fetch
})

describe("headerRow from the rows reader", () => {
  it("useDatasetRows keeps the reader's headerRow (false for a header-less file)", async () => {
    headerRow = false
    const { result } = renderHook(() => useDatasetRows("p1", "f1", "values.csv"))
    await waitFor(() => expect(result.current.total).toBe(2))
    expect(result.current.headerRow).toBe(false)
    expect(result.current.columns).toEqual(["column_1", "column_2"])
  })

  it("an older backend without headerRow leaves it unknown (null)", async () => {
    headerRow = undefined
    const { result } = renderHook(() => useDatasetRows("p1", "f1", "values.csv"))
    await waitFor(() => expect(result.current.total).toBe(2))
    expect(result.current.headerRow).toBeNull()
  })

  it("the save sends headerRows from the rows response; the server honours 0/1 and defaults to 1", () => {
    const obj = readFileSync(join(__dirname, "dataset-object.tsx"), "utf-8")
    expect(/headerRows: rowsQ\.headerRow \? 1 : 0/.test(obj)).toBe(true)
    const routes = readFileSync(join(__dirname, "../../../../server/project-routes.ts"), "utf-8")
    expect(/headerRowsRaw !== 0 && headerRowsRaw !== 1[\s\S]{0,120}status\(400\)/.test(routes)).toBe(true)
    expect(routes.includes('const headerRows: 0 | 1 = headerRowsRaw === 0 ? 0 : 1;')).toBe(true)
    expect(routes.includes("applyCellEdits(text, delim, parsed, { headerRows })")).toBe(true)
    // The rows route forwards the reader's headerRow to the client.
    expect(/headerRow: typeof body\.headerRow === "boolean" \? body\.headerRow : null/.test(routes)).toBe(true)
  })
})
