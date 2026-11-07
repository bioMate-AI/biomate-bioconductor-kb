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

  it("Open-in — a data file stages + launches an interactive tool (§4.3.1)", async () => {
    const openSpy = vi.fn()
    vi.stubGlobal("open", openSpy)
    const base = global.fetch as any
    global.fetch = vi.fn(async (input: RequestInfo | URL, init?: any) => {
      const url = typeof input === "string" ? input : input.toString()
      if (url.includes("/open-in")) {
        expect(init?.method).toBe("POST")
        return ({ ok: true, status: 200, json: async () => ({ success: true, url: "https://dev/interactivetool/jobs/abc" }), text: async () => "" }) as unknown as Response
      }
      return base(input, init)
    }) as unknown as typeof fetch
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
    render(
      <QueryClientProvider client={qc}>
        <DatasetObject dataset={RUN} projectId="proj-rna" onOpenRun={vi.fn()} onDownload={vi.fn()} onAnalyze={vi.fn()} />
      </QueryClientProvider>,
    )
    const btn = await screen.findByTestId("dataset-object-open-in")  // de_results.tsv → table → shown
    fireEvent.click(btn)
    await waitFor(() => expect(openSpy).toHaveBeenCalledWith("https://dev/interactivetool/jobs/abc", "_blank", "noopener"))
    vi.unstubAllGlobals()
  })

  it("surfaces the content hash + dedup note in the origin (§4.5.1)", async () => {
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
    render(
      <QueryClientProvider client={qc}>
        <DatasetObject dataset={{ ...RUN, contentHash: "abcdef0123456789deadbeef" }} onOpenRun={vi.fn()} onDownload={vi.fn()} onAnalyze={vi.fn()} />
      </QueryClientProvider>,
    )
    fireEvent.click(screen.getByTestId("dataset-tab-wherefrom"))
    const hash = await screen.findByTestId("dataset-content-hash", {}, { timeout: 4000 })
    expect(hash.textContent).toContain("abcdef012345")       // abbreviated
    expect(hash).toHaveAttribute("title", "sha256:abcdef0123456789deadbeef")
  })

  it("Versions tab shows 'used by N runs' on the current version (from consumers)", async () => {
    const base = global.fetch as any
    global.fetch = vi.fn(async (input: RequestInfo | URL) => {
      const url = typeof input === "string" ? input : input.toString()
      if (url.includes("/versions")) return ({ ok: true, status: 200, json: async () => ({
        versions: [{ version: "1", label: "v1", current: true, ref: RUN.ref, createdAt: null, note: null, author: null }],
      }), text: async () => "" }) as unknown as Response
      return base(input)  // consumers → the 2-run list from routeFetch
    }) as unknown as typeof fetch
    renderObj()
    fireEvent.click(screen.getByTestId("dataset-tab-versions"))
    const usedby = await screen.findByTestId("dataset-version-usedby", {}, { timeout: 4000 })
    expect(usedby.textContent).toMatch(/2/)  // two consumer runs in routeFetch
  })

  it("Versions tab — app-level versions from the Node store, with append-only Restore (§4.4)", async () => {
    let restored = false
    const base = global.fetch as any
    global.fetch = vi.fn(async (input: RequestInfo | URL, init?: any) => {
      const url = typeof input === "string" ? input : input.toString()
      if (/\/api\/projects\/[^/]+\/files\/[^/]+\/versions\/[^/]+\/restore$/.test(url)) {
        restored = true
        return ({ ok: true, status: 200, json: async () => ({ file: {}, restoredFrom: 1 }), text: async () => "" }) as unknown as Response
      }
      if (/\/api\/projects\/[^/]+\/files\/[^/]+\/versions$/.test(url)) {
        return ({ ok: true, status: 200, json: async () => ({ versions: restored
          ? [{ version: "3", label: "v3", current: true }, { version: "2", label: "v2", current: false }, { version: "1", label: "v1", current: false }]
          : [{ version: "2", label: "v2", current: true }, { version: "1", label: "v1", current: false, note: "original upload" }] }), text: async () => "" }) as unknown as Response
      }
      return base(input, init)
    }) as unknown as typeof fetch
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
    render(
      <QueryClientProvider client={qc}>
        <DatasetObject dataset={{ ...RUN, source: "upload" }} projectId="proj-rna" onOpenRun={vi.fn()} onDownload={vi.fn()} onAnalyze={vi.fn()} />
      </QueryClientProvider>,
    )
    fireEvent.click(screen.getByTestId("dataset-tab-versions"))
    const restoreBtn = await screen.findByTestId("dataset-version-restore-1", {}, { timeout: 4000 })
    fireEvent.click(restoreBtn)
    await waitFor(() => expect(restored).toBe(true))
  })

  it("lineage 'what came out' — a consumer run's produced dataset opens as its own object", async () => {
    // Extend the route mock with the project's files so the lineage section can
    // resolve each consumer run's produced datasets (spec 04 §4.5.3).
    const base = global.fetch as any
    global.fetch = vi.fn(async (input: RequestInfo | URL) => {
      const url = typeof input === "string" ? input : input.toString()
      if (url.includes("/api/projects/") && url.endsWith("/files")) {
        return ({ ok: true, status: 200, json: async () => ({
          files: [
            { id: "out-de", name: "de_results_v2.tsv", source: "run_output", run_id: "run-def-222" },
            { id: "up-raw", name: "counts.tsv", source: "upload", run_id: null },
          ],
        }), text: async () => "" }) as unknown as Response
      }
      return base(input)
    }) as unknown as typeof fetch
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
    render(
      <QueryClientProvider client={qc}>
        <DatasetObject dataset={RUN} projectId="proj-rna" onOpenRun={vi.fn()} onDownload={vi.fn()} onAnalyze={vi.fn()} />
      </QueryClientProvider>,
    )
    fireEvent.click(screen.getByTestId("dataset-tab-wherefrom"))
    // under the named consumer run, its produced dataset is listed and openable
    const produced = await screen.findByTestId("dataset-produced-run-def-222", {}, { timeout: 4000 })
    const link = within(produced).getByTestId("dataset-produced-output")
    expect(link).toHaveAttribute("href", "/files?file=out-de")
    expect(link.textContent).toContain("de_results_v2.tsv")
    // the uploaded (non-run_output) file is NOT listed as "produced"
    expect(produced.textContent).not.toContain("counts.tsv")
  })
})

describe("DatasetObject — unavailable metadata and action error scope", () => {
  it("shows unknown dimensions and readable JSON MIME for non-tabular generic-storage objects", async () => {
    global.fetch = vi.fn(async () => ({ ok: true, json: async () => ({ shape: { rows: 0, cols: 0 }, quality: "watch", notes: [] }) })) as unknown as typeof fetch
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    render(<QueryClientProvider client={qc}><DatasetObject dataset={{ ...RUN, name: "report.json", contentType: "application/octet-stream" }} /></QueryClientProvider>)
    await screen.findByTestId("dataset-header-quality")
    const grid = screen.getByTestId("dataset-stat-grid")
    expect(grid).toHaveTextContent("application/json")
    expect(within(grid).getAllByText("—")).toHaveLength(2)
  })

  it("shows a useful launch failure and clears it when another file opens", async () => {
    routeFetch()
    const original = global.fetch
    global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      if (String(input).endsWith("/open-in")) return { ok: false, status: 503, json: async () => ({ error: "InteractiveLaunchError", message: "The session is still starting. Check active sessions." }) } as Response
      return original(input, init)
    }) as typeof fetch
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    const props = { dataset: RUN, projectId: "proj-rna" }
    const { rerender } = render(<QueryClientProvider client={qc}><DatasetObject {...props} /></QueryClientProvider>)
    fireEvent.click(screen.getByTestId("dataset-object-open-in"))
    expect(await screen.findByRole("alert")).toHaveTextContent("Jupyter: The session is still starting")
    rerender(<QueryClientProvider client={qc}><DatasetObject {...props} dataset={{ ...RUN, id: "another-file" }} /></QueryClientProvider>)
    await waitFor(() => expect(screen.queryByTestId("dataset-open-in-error")).toBeNull())
  })
})
