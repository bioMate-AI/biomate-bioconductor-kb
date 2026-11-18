/**
 * Tests for the Adapt-a-model flow (general model adaptation), added 2026-11-18.
 *
 * Verifies the base-model picker lists only ADAPTABLE (own/custom) models — hosted
 * BioNeMo models are inference-only and excluded — shows an honest empty state when
 * there are none, and reveals the adaptation launcher once a base is chosen. The
 * launcher's adapt_of threading is covered in training-launcher.test.tsx.
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"

import { AdaptModel } from "./adapt-model"

vi.mock("@/contexts/active-project-context", () => ({
  useActiveProjectSafe: () => ({
    activeProjectId: "proj-1",
    projects: [{ id: "proj-1", name: "P" }],
    setActiveProjectId: () => {},
  }),
}))

function wrapper() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
}

function mockModels(models: unknown[]) {
  global.fetch = vi.fn(async (input: any) => {
    const url = String(input)
    const reply = (ok: boolean, payload: unknown) =>
      ({ ok, status: ok ? 200 : 404, json: async () => payload, text: async () => JSON.stringify(payload) }) as Response
    if (url.includes("/api/models")) return reply(true, models)
    if (url.includes("/files")) return reply(true, { files: [] })
    return reply(true, {})
  }) as unknown as typeof fetch
}

beforeEach(() => { vi.restoreAllMocks() })

const CUSTOM = { id: "custom:camp1/herg", name: "herg", family: "python", version: "2", origin: "custom", usedByCount: 1 }
const HOSTED = { id: "bionemo:boltz2", name: "Boltz-2", family: "structure", version: "2.0", origin: "self_host", usedByCount: 0 }

describe("AdaptModel", () => {
  it("lists only adaptable (own/custom) models and reveals the launcher on selection", async () => {
    mockModels([CUSTOM, HOSTED])
    render(<AdaptModel project="proj-1" />, { wrapper: wrapper() })
    const sel = (await screen.findByTestId("adapt-model-base")) as HTMLSelectElement
    const vals = [...sel.options].map((o) => o.value).filter(Boolean)
    expect(vals).toEqual(["custom:camp1/herg"]) // hosted BioNeMo excluded
    // No launcher until a base is chosen.
    expect(screen.queryByTestId("training-launcher-general")).toBeNull()
    fireEvent.change(sel, { target: { value: "custom:camp1/herg" } })
    await waitFor(() => expect(screen.getByTestId("training-launcher-general")).toBeTruthy())
  })

  it("shows an honest empty state when there are no adaptable models", async () => {
    mockModels([HOSTED])
    render(<AdaptModel project="proj-1" />, { wrapper: wrapper() })
    expect(await screen.findByTestId("adapt-model-empty")).toBeTruthy()
    expect(screen.queryByTestId("adapt-model-base")).toBeNull()
  })

  it("keeps the scope honest — CPU/small-model today, GPU tier deferred", async () => {
    mockModels([CUSTOM])
    render(<AdaptModel project="proj-1" />, { wrapper: wrapper() })
    const scope = await screen.findByTestId("adapt-model-scope")
    expect(scope.textContent).toMatch(/CPU|small-model/i)
    expect(scope.textContent).toMatch(/deferred|GPU/i)
  })
})
