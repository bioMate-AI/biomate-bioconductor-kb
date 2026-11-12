/**
 * Header inference reaches the edit route: the rows reader reports whether line 1 is a header
 * record (`headerRow`); useDatasetRows keeps it and the save sends it back as `headerRows`, so a
 * header-less table's data rows are numbered from line 1 (2026-11-11); likewise `skipLines`
 * (leading comment / blank lines, 2026-11-12). The payload itself is tested behaviourally in
 * dataset-object.kinds.test.tsx. Network faked at fetch (our own endpoints).
 */
import { describe, it, expect, vi, beforeEach } from "vitest"
import { renderHook, waitFor } from "@testing-library/react"
import { useDatasetRows } from "./datasets-api"

let headerRow: unknown = false
let skipLines: unknown = undefined

beforeEach(() => {
  global.fetch = vi.fn(async () => ({
    ok: true, status: 200, text: async () => "",
    json: async () => ({ kind: "table", columns: ["column_1", "column_2"], rows: [["1", "2"], ["3", "4"]], offset: 0, limit: 200, totalRows: 2, headerRow, skipLines }),
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

  it("useDatasetRows keeps the reader's skipLines (leading comment lines) for the edit; null when not reported", async () => {
    skipLines = 3
    const { result } = renderHook(() => useDatasetRows("p1", "f1", "values.csv"))
    await waitFor(() => expect(result.current.total).toBe(2))
    expect(result.current.skipLines).toBe(3)
    skipLines = undefined
    const { result: r2 } = renderHook(() => useDatasetRows("p1", "f2", "values.csv"))
    await waitFor(() => expect(r2.current.total).toBe(2))
    expect(r2.current.skipLines).toBeNull()
  })
})
