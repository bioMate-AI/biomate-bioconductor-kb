/**
 * Regression: the Models page renders <ModelsPanel/> with no `project` prop, so
 * the panel must scope its track queries to the ACTIVE project from context.
 * Otherwise GET /api/model-tracks/optimise is called with no project and the
 * backend falls back to the owner's first campaign — the Design-loop then shows a
 * DIFFERENT campaign's rounds than the active project (while Create/Propose, which
 * read the active project directly, correctly target the active campaign).
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"

import { ModelsPanel } from "./models-panel"

const ACTIVE = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"

vi.mock("@/contexts/active-project-context", () => ({
  useActiveProjectSafe: () => ({
    activeProjectId: ACTIVE,
    projects: [{ id: ACTIVE, name: "Active project" }],
    setActiveProjectId: () => {},
  }),
}))

function wrapper() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
}

describe("ModelsPanel project scoping", () => {
  beforeEach(() => {
    global.fetch = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input)
      const body = url.includes("/api/model-tracks/optimise")
        ? { active: false }
        : url.includes("/api/model-tracks/train")
          ? { runs: [] }
          : url.includes("/api/models")
            ? { models: [] }
            : {}
      return { ok: true, status: 200, json: async () => body } as Response
    }) as any
  })

  it("passes the active project id to the optimise track query when no prop is given", async () => {
    render(<ModelsPanel tab={2} />, { wrapper: wrapper() })
    await waitFor(() => {
      const calls = (global.fetch as any).mock.calls.map((c: any[]) => String(c[0]))
      const optimise = calls.find((u: string) => u.includes("/api/model-tracks/optimise"))
      expect(optimise).toBeTruthy()
      expect(optimise).toContain(`project=${ACTIVE}`)
    })
  })
})
