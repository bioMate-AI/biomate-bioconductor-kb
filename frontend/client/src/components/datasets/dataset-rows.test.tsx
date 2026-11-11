/**
 * Full rows, not a sample (D2): useDatasetRows pages GET /api/projects/:id/files/:fileId/rows,
 * the table shows the TRUE total, loads more on scroll, labels sort/filter scope honestly,
 * and "Load all rows" makes them whole-file. Network faked at fetch (our own endpoint).
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { DatasetObject } from "./dataset-object"
import { DatasetRowsTable } from "./dataset-rows-table"
import { rowsSupported } from "./datasets-api"

const TOTAL = 2281
const COLUMNS = ["source", "drug", "page", "headers", "rows"]
const record = (i: number) => ["epar_table", `drug${i}`, String(i), '["A","B"]', '[["x"]]']
let rowCalls: Array<{ offset: number; limit: number }> = []

beforeEach(() => {
  rowCalls = []
  global.fetch = vi.fn(async (input: RequestInfo | URL) => {
    const url = new URL(String(input), "http://x")
    const ok = (body: unknown) => ({ ok: true, status: 200, json: async () => body, text: async () => "" }) as unknown as Response
    if (url.pathname.endsWith("/rows")) {
      const offset = Number(url.searchParams.get("offset")), limit = Number(url.searchParams.get("limit"))
      rowCalls.push({ offset, limit })
      const rows = Array.from({ length: Math.max(0, Math.min(limit, TOTAL - offset)) }, (_, k) => record(offset + k))
      return ok({ kind: "jsonl", columns: COLUMNS, rows, offset, limit, totalRows: TOTAL })
    }
    if (url.pathname === "/api/perception/profile") {
      return ok({
        shape: { rows: TOTAL, cols: 5 }, quality: "watch", notes: [], columns: COLUMNS, sampleRows: [record(0)],
        effectiveN: 2280, effectiveNReason: "dedup", duplicateRows: 1,
        findings: [{ section: "signal", code: "near_constant", level: "watch", params: { count: 1, columns: ["source"], pct: 99 } }],
      })
    }
    return ok({})
  }) as unknown as typeof fetch
})

function renderObj() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  return render(
    <QueryClientProvider client={qc}>
      <DatasetObject
        projectId="p1"
        dataset={{ id: "f1", name: "epar_study_tables.jsonl", ref: "projects/p1/inputs/epar_study_tables.jsonl", size: 1_000_000, source: "upload" }}
      />
    </QueryClientProvider>,
  )
}

describe("rowsSupported", () => {
  it("covers csv/tsv/jsonl (and gz), not FASTQ", () => {
    expect(rowsSupported("a.jsonl")).toBe(true)
    expect(rowsSupported("a.csv.gz")).toBe(true)
    expect(rowsSupported("a.fastq.gz")).toBe(false)
  })
})

describe("DatasetObject preview — full rows", () => {
  it("shows the true total, every column, and QC directly under the table", async () => {
    renderObj()
    await waitFor(() => expect(screen.getByTestId("dataset-preview-rowcount")).toHaveTextContent("200 of 2,281 rows loaded"))
    expect(rowCalls[0]).toEqual({ offset: 0, limit: 200 })
    expect(screen.getByTestId("dataset-stat-grid")).toHaveTextContent("2,281")
    expect(screen.getByTestId("dataset-preview-scope")).toHaveTextContent("apply to the loaded rows only")
    // QC sits in the Preview tab, after the table.
    const qc = await screen.findByTestId("dataset-quality")
    const table = screen.getByTestId("dataset-preview-table")
    expect(table.compareDocumentPosition(qc) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy()
    expect(screen.getByTestId("perception-effective-n-hint")).toHaveTextContent("1 duplicate rows are counted once")
  })

  it("scrolling to the bottom loads the next page", async () => {
    renderObj()
    await waitFor(() => expect(rowCalls).toHaveLength(1))
    // The scroll box renders after the first rows response is processed — wait for it
    // (getBy raced the render under full-suite load).
    const box = await screen.findByTestId("dataset-preview-scroll")
    Object.defineProperty(box, "scrollHeight", { value: 5200, configurable: true })
    Object.defineProperty(box, "clientHeight", { value: 600, configurable: true })
    box.scrollTop = 4700
    fireEvent.scroll(box)
    await waitFor(() => expect(rowCalls[1]).toEqual({ offset: 200, limit: 200 }))
    await waitFor(() => expect(screen.getByTestId("dataset-preview-rowcount")).toHaveTextContent("400 of 2,281"))
  })

  it("Load all rows → whole-file sort/filter, and Columns stats say they cover all rows", async () => {
    renderObj()
    await waitFor(() => expect(rowCalls).toHaveLength(1))
    // The fetch firing is not the page rendering: wait for the button the response brings.
    fireEvent.click(await screen.findByTestId("dataset-rows-load-all", {}, { timeout: 5000 }))
    await waitFor(() => expect(screen.getByTestId("dataset-preview-rowcount")).toHaveTextContent("All 2,281 rows loaded"), { timeout: 5000 })
    expect(screen.getByTestId("dataset-preview-scope")).toHaveTextContent("apply to all rows")
    fireEvent.click(screen.getByTestId("dataset-preview-toggle-columns"))
    expect(screen.getByTestId("dataset-columns-sample-note")).toHaveTextContent("Computed on all 2,281 rows.")
    expect(screen.getAllByTestId("dataset-column-row")).toHaveLength(5)
  })

  it("Columns stats on a partial load name the rows they were computed on", async () => {
    renderObj()
    await waitFor(() => expect(rowCalls).toHaveLength(1))
    fireEvent.click(screen.getByTestId("dataset-preview-toggle-columns"))
    expect(screen.getByTestId("dataset-columns-sample-note")).toHaveTextContent("Computed on the 200 loaded rows of 2,281.")
  })
})

describe("DatasetRowsTable — windowing + filter", () => {
  it("renders only a window of rows and filters over the loaded rows", () => {
    const rows = Array.from({ length: 5000 }, (_, i) => [String(i), i % 2 ? "odd" : "even"])
    render(<DatasetRowsTable columns={["n", "parity"]} rows={rows} total={10000} loading={false} error={null} onNeedMore={() => {}} />)
    expect(screen.getAllByTestId("dataset-preview-row").length).toBeLessThan(200)
    fireEvent.change(screen.getByTestId("dataset-preview-filter"), { target: { value: "odd" } })
    expect(screen.getByTestId("dataset-preview-rowcount")).toHaveTextContent("2,500 match the filter")
  })
})
