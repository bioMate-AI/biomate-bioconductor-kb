/**
 * FoldOutputs — the inline Boltz-2 result surface in the Models panel.
 * It must render the predicted structure + confidence + file list WITHOUT a
 * trip to the Run Manager (founder: that detour "deviates from the model panel").
 */
import React from "react"
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { render, screen, waitFor, cleanup } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { FoldOutputs } from "./fold-outputs"

const RUN = "run-boltz-1"
const OUTPUT_FILES = [
  { name: "boltz_input_model_0.cif", size: 120_000, download_endpoint: `/api/runs/${RUN}/output/boltz_input_model_0.cif` },
  { name: "confidence_boltz_input_model_0.json", size: 400, download_endpoint: `/api/runs/${RUN}/output/confidence_boltz_input_model_0.json` },
  { name: "pae_boltz_input_model_0.npz", size: 9_000, download_endpoint: `/api/runs/${RUN}/output/pae_boltz_input_model_0.npz` },
  { name: "boltz_summary.json", size: 300, download_endpoint: `/api/runs/${RUN}/output/boltz_summary.json` },
  // MSA/db intermediates — must be hidden from the headline list.
  { name: "uniref.a3m", size: 1_000_000, download_endpoint: `/api/runs/${RUN}/output/uniref.a3m` },
  { name: "out.tar.gz", size: 2_000_000, download_endpoint: `/api/runs/${RUN}/output/out.tar.gz` },
]
const CONFIDENCE = { confidence_score: 0.87, ptm: 0.91, iptm: 0.74, complex_plddt: 0.83 }

function wrapper() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
}

beforeEach(() => {
  localStorage.setItem("biomate-user-settings", JSON.stringify({ language: "english" }))
})
afterEach(() => {
  cleanup()
  vi.restoreAllMocks()
  localStorage.clear()
})

describe("FoldOutputs", () => {
  it("renders the structure download, confidence headline, and file list inline", async () => {
    global.fetch = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input)
      if (url.includes("/output_files")) {
        return { ok: true, status: 200, json: async () => ({ output_files: OUTPUT_FILES }) } as Response
      }
      if (url.includes("/confidence")) {
        return { ok: true, status: 200, json: async () => CONFIDENCE } as Response
      }
      return { ok: true, status: 200, json: async () => ({}) } as Response
    }) as unknown as typeof fetch

    render(<FoldOutputs runId={RUN} />, { wrapper: wrapper() })

    // Inline result surface present — no Run Manager navigation needed.
    expect(await screen.findByTestId("fold-outputs")).toBeTruthy()

    // Predicted structure is the prominent, downloadable artifact.
    const structure = await screen.findByTestId("fold-structure-download")
    expect(structure.getAttribute("href")).toContain("/output/boltz_input_model_0.cif")

    // Confidence headline parsed from the real confidence JSON (0–1 → %).
    await waitFor(() => expect(screen.getByTestId("fold-confidence")).toBeTruthy())
    const metrics = screen.getAllByTestId("fold-confidence-metric").map((n) => n.textContent)
    expect(metrics.join(" ")).toMatch(/pTM 91%/)
    expect(metrics.join(" ")).toMatch(/ipTM 74%/)

    // File list shows real artifacts and hides MSA/db intermediates.
    const files = screen.getAllByTestId("fold-output-file").map((n) => n.textContent)
    expect(files.join(" ")).toContain("boltz_input_model_0.cif")
    expect(files.join(" ")).toContain("confidence_boltz_input_model_0.json")
    expect(files.join(" ")).not.toContain("uniref.a3m")
    expect(files.join(" ")).not.toContain("out.tar.gz")
  })

  it("shows an honest empty state when the run returned no files", async () => {
    global.fetch = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input)
      if (url.includes("/output_files")) {
        return { ok: true, status: 200, json: async () => ({ output_files: [] }) } as Response
      }
      return { ok: true, status: 200, json: async () => ({}) } as Response
    }) as unknown as typeof fetch

    render(<FoldOutputs runId={RUN} />, { wrapper: wrapper() })
    expect(await screen.findByTestId("fold-outputs-empty")).toBeTruthy()
    expect(screen.queryByTestId("fold-structure-download")).toBeNull()
  })
})
