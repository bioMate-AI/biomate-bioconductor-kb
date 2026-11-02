import React from "react"
import { describe, it, expect, beforeEach, vi } from "vitest"
import { render, screen, fireEvent, waitFor, within } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { DatasetObject, type DatasetRef } from "./dataset-object"

/**
 * Dataset panel — Provenance tab contract (2026-10-28 terminology + step-pin
 * review). Renders a run-output DatasetObject against real-shaped API responses
 * (no component mocks) and asserts the plain-language labels, the producing-step
 * pin, the accession-as-origin, and that NO raw run id is ever a visible label.
 */

const RUN_ID = "fbd72e81-4bb7-488b-9eb8-ff045dad0b3d"
const OPAQUE_CONSUMER = "run-opaque-abc123def456"

const RUN: DatasetRef = {
  id: "file-deg",
  name: "de_results.tsv",
  ref: "projects/proj-rna/results/de_results.tsv",
  size: 1572864, // 1.5 MB — a real number (prod sends BIGINT-as-string; UI coerces)
  contentType: "text/tab-separated-values",
  source: "run_output",
  accession: "GSE227835", // the id the user supplied → origin
  runId: RUN_ID,
  workflowName: "nf-core/rnaseq",
  stepName: "STAR_ALIGN",
  consumers: [],
  versions: [],
}

const PROFILE = {
  shape: { rows: 18000, cols: 6 },
  quality: "good",
  notes: [],
  columns: ["gene", "log2fc", "padj"],
  sampleRows: [["TP53", "2.1", "0.001"]],
}

function routeFetch() {
  global.fetch = vi.fn(async (input: RequestInfo | URL) => {
    const url = typeof input === "string" ? input : input.toString()
    const ok = (body: unknown) =>
      ({ ok: true, status: 200, json: async () => body, text: async () => JSON.stringify(body) }) as unknown as Response
    if (url.includes("/api/perception/profile")) return ok(PROFILE)
    if (url.includes("/lineage")) return ok({ producedBy: { runId: RUN_ID, workflow: "nf-core/rnaseq", status: "completed" } })
    if (url.includes("/consumers"))
      return ok({
        consumers: [
          { runId: OPAQUE_CONSUMER, workflow: null, status: "running" }, // no name → show the action, never the id
          { runId: "run-def-222", workflow: "nf-core/differentialabundance", status: "completed" },
        ],
      })
    if (url.includes("/versions")) return ok({ versions: [] })
    return ok({})
  }) as unknown as typeof fetch
}

function renderObj() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  return render(
    <QueryClientProvider client={qc}>
      <DatasetObject dataset={RUN} onOpenRun={vi.fn()} onDownload={vi.fn()} onAnalyze={vi.fn()} />
    </QueryClientProvider>,
  )
}

describe("DatasetObject — Provenance tab (plain labels, step pin, no raw ids)", () => {
  beforeEach(() => { routeFetch() })

  it("shows content-type + size in the stat grid, not duplicated in the header (design de-dup)", () => {
    renderObj()
    // Type + size badges were removed from the header (2026-11-01) and now live
    // once, in the stat grid, per the design.
    expect(screen.queryByTestId("dataset-header-type")).toBeNull()
    expect(screen.queryByTestId("dataset-header-size")).toBeNull()
    const grid = screen.getByTestId("dataset-stat-grid")
    expect(grid.textContent).toContain("text/tab-separated-values")
    expect(grid.textContent).toMatch(/MB|KB/) // a real size, not blank/NaN
  })

  it("pins the producing run to its exact step: '<workflow> · <step>'", async () => {
    renderObj()
    fireEvent.click(screen.getByTestId("dataset-tab-wherefrom"))
    const row = await screen.findByTestId("lineage-open-run", {}, { timeout: 4000 })
    // label is the row key; the step-pinned value is on the lineage-open-run cell
    expect(screen.getByText("Output from workflow")).toBeInTheDocument()
    expect(row.textContent).toContain("nf-core/rnaseq · STAR_ALIGN")
    // The raw run id is the click target only — never shown as a label.
    expect(row.textContent).not.toContain(RUN_ID)
    expect(screen.queryByText(new RegExp(RUN_ID))).toBeNull()
  })

  it("shows the accession id as the origin", async () => {
    renderObj()
    fireEvent.click(screen.getByTestId("dataset-tab-wherefrom"))
    const origin = await screen.findByTestId("dataset-origin", {}, { timeout: 4000 })
    expect(within(origin).getByText("GSE227835")).toBeInTheDocument()
    expect(within(origin).getByText(/Accession/i)).toBeInTheDocument()
    // storage-ref (the S3 key) must NOT be surfaced as provenance
    expect(origin.textContent).not.toContain("projects/proj-rna/results")
  })

  it("Input-to-workflow consumers never render a raw run id", async () => {
    renderObj()
    fireEvent.click(screen.getByTestId("dataset-tab-wherefrom"))
    await screen.findByTestId(`dataset-consumer-${OPAQUE_CONSUMER}`, {}, { timeout: 4000 })
    // named consumer shows its workflow; unnamed one shows the action, not the id
    expect(screen.getByText("nf-core/differentialabundance")).toBeInTheDocument()
    expect(screen.getByText(/Open the run that produced it/i)).toBeInTheDocument()
    expect(screen.queryByText(new RegExp(OPAQUE_CONSUMER))).toBeNull()
  })

  it("labels the data-quality card 'Data QC' (not jargon, not 'QC results')", async () => {
    renderObj()
    fireEvent.click(screen.getByTestId("dataset-tab-wherefrom"))
    const q = await screen.findByTestId("dataset-quality", {}, { timeout: 4000 })
    expect(within(q).getByText("Data QC")).toBeInTheDocument()
  })
})
