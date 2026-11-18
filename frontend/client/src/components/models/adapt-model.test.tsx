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
  it("always offers a built-in base to fine-tune, plus your own models to version", async () => {
    mockModels([CUSTOM, HOSTED])
    render(<AdaptModel project="proj-1" />, { wrapper: wrapper() })
    const sel = (await screen.findByTestId("adapt-model-base")) as HTMLSelectElement
    // Owned models load async; wait for them to appear in the picker.
    await waitFor(() => expect([...sel.options].map((o) => o.value)).toContain("custom:camp1/herg"))
    const vals = [...sel.options].map((o) => o.value).filter(Boolean)
    expect(vals).toContain("base:llm-small")       // built-in base always present
    expect(vals).not.toContain("bionemo:boltz2")   // hosted BioNeMo excluded
  })

  it("is usable with NO registered models — the built-in base keeps it functional", async () => {
    mockModels([HOSTED]) // nothing of the user's
    render(<AdaptModel project="proj-1" />, { wrapper: wrapper() })
    const sel = (await screen.findByTestId("adapt-model-base")) as HTMLSelectElement
    expect([...sel.options].map((o) => o.value).filter(Boolean)).toEqual(["base:llm-small"])
    expect(screen.queryByTestId("adapt-model-empty")).toBeNull() // not a dead empty state
  })

  it("reveals the launcher and shows the right mode (new model vs next version)", async () => {
    mockModels([CUSTOM])
    render(<AdaptModel project="proj-1" />, { wrapper: wrapper() })
    const sel = (await screen.findByTestId("adapt-model-base")) as HTMLSelectElement
    expect(screen.queryByTestId("training-launcher-general")).toBeNull()
    fireEvent.change(sel, { target: { value: "base:llm-small" } })
    await waitFor(() => expect(screen.getByTestId("training-launcher-general")).toBeTruthy())
    expect(screen.getByTestId("adapt-model-mode").textContent).toMatch(/new model/i)
    await waitFor(() => expect([...sel.options].map((o) => o.value)).toContain("custom:camp1/herg"))
    fireEvent.change(sel, { target: { value: "custom:camp1/herg" } })
    await waitFor(() => expect(screen.getByTestId("adapt-model-mode").textContent).toMatch(/next version/i))
  })

  it("keeps the scope honest — CPU/small-model today, GPU tier deferred", async () => {
    mockModels([CUSTOM])
    render(<AdaptModel project="proj-1" />, { wrapper: wrapper() })
    const scope = await screen.findByTestId("adapt-model-scope")
    expect(scope.textContent).toMatch(/CPU|small-model/i)
    expect(scope.textContent).toMatch(/deferred|GPU/i)
  })
})
