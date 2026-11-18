/**
 * Tests for the Adapt track (house-style adaptation), surfaced 2026-11-17.
 *
 * Verifies the honest contract: it renders recorded before→after edit pairs with a
 * per-pair on/off toggle, an honest empty state, an "Apply house style" action that
 * is disabled with no enabled pairs and queues the retrieval-index build when
 * clicked, and that the copy frames it as personalisation (retrieval), never a
 * model-weight retrain. Fetch is mocked at the network boundary (no msw).
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, fireEvent, waitFor, within } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"

import { AdaptTrack } from "./adapt-track"

function wrapper() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
}

const PAIRS = {
  pendingCount: 1,
  pairs: [
    { id: "p1", learned: "prefer active voice", scope: "§2.6.1", before: "It was observed that",
      after: "We observed", source: "IND editor", on: true },
    { id: "p2", learned: "no hedging", scope: "§2.6.4", before: "may possibly indicate",
      after: "indicates", source: "IND editor", on: false },
  ],
}

function mockFetch(opts: { pairs?: any; capture?: (url: string, init?: any) => void } = {}) {
  const body = opts.pairs ?? PAIRS
  global.fetch = vi.fn(async (url: any, init?: any) => {
    const u = String(url)
    opts.capture?.(u, init)
    if (u.includes("/api/model-tracks/adapt/") && u.includes("/toggle")) {
      return { ok: true, status: 200, json: async () => ({ id: "p2", on: true }) } as any
    }
    if (u.includes("/api/model-tracks/adapt/retrain")) {
      return { ok: true, status: 200, json: async () => ({ job_id: "j1", status: "queued", edit_pair_count: 1 }) } as any
    }
    if (u.includes("/api/model-tracks/adapt")) {
      return { ok: true, status: 200, json: async () => body } as any
    }
    return { ok: true, status: 200, json: async () => ({}) } as any
  }) as unknown as typeof fetch
}

beforeEach(() => { vi.restoreAllMocks() })

describe("AdaptTrack", () => {
  it("renders recorded pairs with before→after and an on/off toggle", async () => {
    mockFetch()
    render(<AdaptTrack project="camp1" />, { wrapper: wrapper() })
    expect(await screen.findByTestId("adapt-pair-p1")).toBeTruthy()
    const p1 = screen.getByTestId("adapt-pair-p1")
    expect(within(p1).getByText("We observed")).toBeTruthy()
    expect(within(p1).getByText("It was observed that")).toBeTruthy()
    // Enabled pair shows "On", disabled shows "Off".
    expect(within(p1).getByTestId("adapt-toggle-p1").textContent).toContain("On")
    expect(within(screen.getByTestId("adapt-pair-p2")).getByTestId("adapt-toggle-p2").textContent).toContain("Off")
  })

  it("frames adaptation as retrieval personalisation, not a model retrain", async () => {
    mockFetch()
    render(<AdaptTrack project="camp1" />, { wrapper: wrapper() })
    await screen.findByTestId("adapt-pair-p1")
    expect(screen.getByTestId("adapt-mechanism").textContent).toMatch(/does not retrain model weights/i)
    expect(screen.getByTestId("adapt-lora-note").textContent).toMatch(/LoRA/i)
  })

  it("shows an honest empty state when no pairs are recorded", async () => {
    mockFetch({ pairs: { pendingCount: 0, pairs: [] } })
    render(<AdaptTrack project="camp1" />, { wrapper: wrapper() })
    expect(await screen.findByTestId("adapt-empty")).toBeTruthy()
    // With nothing enabled, Apply is disabled.
    expect((screen.getByTestId("adapt-apply") as HTMLButtonElement).disabled).toBe(true)
  })

  it("queues the retrieval-index build when Apply is clicked", async () => {
    let retrainCalled = false
    mockFetch({ capture: (u, init) => { if (u.includes("/retrain") && init?.method === "POST") retrainCalled = true } })
    render(<AdaptTrack project="camp1" />, { wrapper: wrapper() })
    await screen.findByTestId("adapt-pair-p1") // wait for pairs → p1 enabled
    const apply = screen.getByTestId("adapt-apply")
    await waitFor(() => expect((apply as HTMLButtonElement).disabled).toBe(false))
    fireEvent.click(apply)
    await waitFor(() => expect(retrainCalled).toBe(true))
    expect(await screen.findByTestId("adapt-applied-msg")).toBeTruthy()
  })

  it("persists a toggle via POST when a pair toggle is clicked", async () => {
    let toggled = ""
    mockFetch({ capture: (u, init) => { if (u.includes("/toggle") && init?.method === "POST") toggled = u } })
    render(<AdaptTrack project="camp1" />, { wrapper: wrapper() })
    const t2 = await screen.findByTestId("adapt-toggle-p2")
    fireEvent.click(t2)
    await waitFor(() => expect(toggled).toContain("/api/model-tracks/adapt/p2/toggle"))
  })
})
