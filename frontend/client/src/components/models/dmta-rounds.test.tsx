/**
 * RoundsSection — the sequence (peptide/biologic) setup controls.
 *
 * Fetch is mocked at the network boundary (the app's unit-test convention); the
 * assertions are on the real client contract:
 *  - Generate candidate library POSTs the SELECTED modality (regression for the
 *    generate-before-create bug: the server must not fall back to small_molecule).
 *  - Upload measured sequences ensures the campaign carries the modality, then
 *    POSTs the CSV to ingest-assay and surfaces the real ingested count.
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"

import { RoundsSection } from "./dmta-rounds"

const PROJECT = "11111111-1111-4111-8111-111111111111"

vi.mock("@/contexts/active-project-context", () => ({
  useActiveProjectSafe: () => ({
    activeProjectId: PROJECT,
    projects: [{ id: PROJECT, name: "Test project" }],
    setActiveProjectId: () => {},
  }),
}))

function wrapper() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
}

type Call = { url: string; init?: RequestInit }

function mockFetch(onIngest: () => unknown, calls: Call[]) {
  return vi.fn(async (url: string, init?: RequestInit) => {
    calls.push({ url, init })
    if (url.endsWith("/generate-library")) {
      return { ok: true, status: 200, json: async () => ({ generated: 200 }) } as Response
    }
    if (url.endsWith("/ingest-assay")) {
      return { ok: true, status: 200, json: async () => onIngest() } as Response
    }
    // /campaigns ensure + anything else
    return { ok: true, status: 200, json: async () => ({}) } as Response
  })
}

describe("RoundsSection sequence controls", () => {
  beforeEach(() => { vi.restoreAllMocks() })

  it("Generate candidate library sends the selected modality (not small_molecule)", async () => {
    const calls: Call[] = []
    vi.stubGlobal("fetch", mockFetch(() => ({}), calls))
    render(<RoundsSection projectId={PROJECT} onOpenModel={() => {}} />, { wrapper: wrapper() })

    fireEvent.click(screen.getByTestId("optimise-modality-peptide"))
    fireEvent.change(screen.getByTestId("optimise-gen-seed"), { target: { value: "GQVGRQLAIIGDDINR" } })
    fireEvent.click(screen.getByTestId("optimise-generate-library"))

    await waitFor(() => {
      const gen = calls.find((c) => c.url.endsWith("/generate-library"))
      expect(gen).toBeTruthy()
      const body = JSON.parse(String(gen!.init!.body))
      expect(body.modality).toBe("peptide")
      expect(body.seed).toBe("GQVGRQLAIIGDDINR")
    })
  })

  it("Upload measured sequences ensures campaign modality then ingests the CSV", async () => {
    const calls: Call[] = []
    vi.stubGlobal("fetch", mockFetch(() => ({ ingested: 18, errors: [] }), calls))
    render(<RoundsSection projectId={PROJECT} onOpenModel={() => {}} />, { wrapper: wrapper() })

    fireEvent.click(screen.getByTestId("optimise-modality-peptide"))
    const input = screen.getByTestId("optimise-upload-input") as HTMLInputElement
    const file = new File(
      ["compound_id,smiles,assay_type,value,unit,assay_date\nP1,GQVGRQLAIIGDDINR,IC50,100,nM,2026-01-01\n"],
      "assays.csv",
      { type: "text/csv" },
    )
    fireEvent.change(input, { target: { files: [file] } })

    await waitFor(() => {
      // Campaign is (re)created with the sequence modality so entities validate as sequences.
      const ensure = calls.find((c) => c.url.endsWith("/campaigns"))
      expect(ensure).toBeTruthy()
      expect(JSON.parse(String(ensure!.init!.body)).modality).toBe("peptide")
      // CSV is POSTed as multipart to ingest-assay.
      const ingest = calls.find((c) => c.url.endsWith("/ingest-assay"))
      expect(ingest).toBeTruthy()
      expect(ingest!.init!.body).toBeInstanceOf(FormData)
    })
    expect(await screen.findByText(/Ingested 18 measured sequences/)).toBeTruthy()
  })

  it("hides the sequence generator and uploader for small molecule", () => {
    vi.stubGlobal("fetch", mockFetch(() => ({}), []))
    render(<RoundsSection projectId={PROJECT} onOpenModel={() => {}} />, { wrapper: wrapper() })
    expect(screen.queryByTestId("optimise-generate")).toBeNull()
    expect(screen.queryByTestId("optimise-upload")).toBeNull()
  })
})
