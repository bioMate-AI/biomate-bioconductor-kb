/**
 * Dataset header format chip + the Preview fallback for files the rows endpoint
 * declines. The Node route turns the backend's `tabular: false` into 415
 * (server/project-file-rows-upload.test.ts covers that mapping); here our own
 * endpoints are faked at fetch to drive the client side of the contract.
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { DatasetObject } from "./dataset-object"
import { rowsSupported } from "./datasets-api"

let profileBody: Record<string, unknown> = {}
let rowsResponse: { status: number; body: unknown } = { status: 200, body: {} }
let rowCalls = 0

beforeEach(() => {
  rowCalls = 0
  profileBody = { shape: { rows: 2, cols: 10 }, quality: "good", notes: [] }
  global.fetch = vi.fn(async (input: RequestInfo | URL) => {
    const url = new URL(String(input), "http://x")
    const res = (status: number, body: unknown) =>
      ({ ok: status < 400, status, json: async () => body, text: async () => "" }) as unknown as Response
    if (url.pathname.endsWith("/rows")) { rowCalls += 1; return res(rowsResponse.status, rowsResponse.body) }
    if (url.pathname === "/api/perception/profile") return res(200, profileBody)
    return res(200, {})
  }) as unknown as typeof fetch
})

function renderObj(name: string) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  return render(
    <QueryClientProvider client={qc}>
      <DatasetObject
        projectId="p1"
        dataset={{ id: "f1", name, ref: `projects/p1/inputs/${name}`, size: 2048, source: "upload" }}
        preview={<div data-testid="text-preview-fallback">text preview</div>}
      />
    </QueryClientProvider>,
  )
}

describe("rowsSupported — header-less spec formats", () => {
  it("asks the rows endpoint for BED-family / GFF / GTF / SMILES (and .gz), not for VCF or FASTQ", () => {
    for (const n of ["a.bed", "a.narrowPeak", "a.broadPeak", "a.bedgraph", "a.bedpe", "a.gtf.gz", "a.gff3", "a.smi", "a.smiles"]) {
      expect(rowsSupported(n)).toBe(true)
    }
    for (const n of ["a.vcf.gz", "a.fastq.gz", "a.bed.bgz"]) expect(rowsSupported(n)).toBe(false)
  })
})

describe("Preview fallback when the server answers tabular: false", () => {
  it("415 (not_tabular) → the text/annotation preview, not a table, error or endless skeleton", async () => {
    rowsResponse = { status: 415, body: { error: "not_tabular", kind: "unknown" } }
    renderObj("sample_peaks.narrowPeak")
    expect(await screen.findByTestId("text-preview-fallback")).toBeInTheDocument()
    expect(rowCalls).toBe(1)
    expect(screen.queryByTestId("dataset-preview-loading")).toBeNull()
    expect(screen.queryByTestId("dataset-rows-error")).toBeNull()
    expect(screen.queryByTestId("dataset-preview-table")).toBeNull()
  })

  it("a served spec format renders the full-rows table with the server's column names", async () => {
    rowsResponse = {
      status: 200,
      body: { kind: "table", columns: ["chrom", "start", "end", "name"], rows: [["chr1", "10", "50", "featA"]], offset: 0, limit: 200, totalRows: 1 },
    }
    renderObj("regions.bed")
    await waitFor(() => expect(screen.getByTestId("dataset-preview-table")).toHaveTextContent("featA"))
    expect(screen.getByTestId("dataset-preview-table")).toHaveTextContent("chrom")
    expect(screen.queryByTestId("text-preview-fallback")).toBeNull()
  })
})

describe("format chip", () => {
  it("shows the detected format next to the version chip, with who identified it", async () => {
    rowsResponse = { status: 415, body: { error: "not_tabular" } }
    profileBody = { ...profileBody, format: { ext: "narrowpeak", label: "narrowPeak", source: "galaxy" } }
    renderObj("sample_peaks.narrowPeak")
    const chip = await screen.findByTestId("dataset-header-format")
    expect(chip).toHaveTextContent("narrowPeak")
    expect(chip).toHaveAttribute("data-format-source", "galaxy")
    expect(chip).toHaveAttribute("title", "File format: narrowPeak (identified from its datatype signature)")
    // Sits right after the version chip in the identity row.
    expect(screen.getByTestId("dataset-header-version").nextElementSibling).toBe(chip)
  })

  it("BioMate-detected formats say so", async () => {
    rowsResponse = { status: 415, body: { error: "not_tabular" } }
    profileBody = { ...profileBody, format: { ext: "smi", label: "SMILES", source: "biomate" } }
    renderObj("ligands.smi")
    expect(await screen.findByTestId("dataset-header-format")).toHaveAttribute("title", "File format: SMILES (identified by BioMate)")
  })

  it("no chip for profiles without a format (older backends)", async () => {
    rowsResponse = { status: 415, body: { error: "not_tabular" } }
    renderObj("sample_peaks.narrowPeak")
    await screen.findByTestId("text-preview-fallback")
    await waitFor(() => expect(screen.getByTestId("dataset-header-quality")).toBeInTheDocument())
    expect(screen.queryByTestId("dataset-header-format")).toBeNull()
  })
})

describe("a file with its own viewer is shown in it, not as the profiler's sample table", () => {
  it("PDB → structure preview even when the profile carries columns/sampleRows", async () => {
    profileBody = {
      shape: { rows: 3, cols: 2 }, quality: "watch", notes: [],
      columns: ["HEADER", "x"], sampleRows: [["ATOM", "1"], ["ATOM", "2"]],
    }
    renderObj("5e5z.pdb")
    expect(await screen.findByTestId("text-preview-fallback")).toBeInTheDocument()
    expect(screen.queryByTestId("dataset-preview-table")).toBeNull()
  })
})
