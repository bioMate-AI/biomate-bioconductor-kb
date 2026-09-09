/**
 * DataHubPage — RTL coverage for the styled data-centric surface.
 *
 * Covers:
 *   - Project picker: styled cards render from the real project list (name,
 *     status badge, domain, created date), and clicking one activates it.
 *   - No-projects honest empty state.
 *   - Two-pane hub renders once a project is active (file tree + detail pane),
 *     with the honest "select a dataset" prompt before any file is picked.
 *
 * The active-project context is mocked so the test drives activeProjectId /
 * projects directly (the context itself is covered elsewhere). Fetch is mocked
 * at the network boundary for the ProjectFileTree's /api/projects/:id/files
 * call — no msw, no live server — matching models.test.tsx conventions.
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"

// ── mock the active-project context ──────────────────────────────────────────
const ctx = {
  activeProjectId: null as string | null,
  activeProject: null as any,
  projects: [] as any[],
  loading: false,
  setActiveProjectId: vi.fn((id: string | null) => {
    ctx.activeProjectId = id
    ctx.activeProject = id ? ctx.projects.find((p) => p.id === id) ?? null : null
  }),
  refresh: vi.fn(),
  createProject: vi.fn(),
  archiveProject: vi.fn(),
  deleteProject: vi.fn(),
  renameProject: vi.fn(),
}
vi.mock("@/contexts/active-project-context", () => ({
  useActiveProject: () => ctx,
}))

import DataHubPage from "../data-hub"

const PROJECTS = [
  {
    id: "proj-rna",
    name: "RNA-seq pilot",
    description: "Bulk RNA-seq of the cohort",
    status: "active",
    primaryDomain: "transcriptomics",
    createdAt: "2026-08-01T10:00:00.000Z",
  },
  {
    id: "proj-admet",
    name: "ADMET screen",
    description: null,
    status: "completed",
    primaryDomain: "drug_discovery",
    createdAt: "2026-07-15T10:00:00.000Z",
  },
]

function wrapper() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
}

beforeEach(() => {
  ctx.activeProjectId = null
  ctx.activeProject = null
  ctx.projects = []
  ctx.loading = false
  ctx.setActiveProjectId.mockClear()
  vi.restoreAllMocks()
})

describe("DataHubPage — project picker", () => {
  it("renders an honest empty state when the account has no projects", () => {
    ctx.projects = []
    render(<DataHubPage />, { wrapper: wrapper() })
    expect(screen.getByTestId("data-hub-picker")).toBeInTheDocument()
    expect(screen.getByText(/No projects yet/i)).toBeInTheDocument()
  })

  it("renders a styled card per project with real fields, and activates on click", () => {
    ctx.projects = PROJECTS
    render(<DataHubPage />, { wrapper: wrapper() })

    // A card exists per project.
    expect(screen.getByTestId("data-hub-project-grid")).toBeInTheDocument()
    const rna = screen.getByTestId("data-hub-project-proj-rna")
    const admet = screen.getByTestId("data-hub-project-proj-admet")

    // Real fields surface: name, status, domain, description.
    expect(rna.textContent).toContain("RNA-seq pilot")
    expect(rna.textContent).toContain("transcriptomics")
    expect(rna.textContent).toContain("Bulk RNA-seq of the cohort")
    expect(admet.textContent).toContain("ADMET screen")
    expect(admet.textContent).toContain("completed")

    // Clicking activates the project via the context setter.
    fireEvent.click(rna)
    expect(ctx.setActiveProjectId).toHaveBeenCalledWith("proj-rna")
  })
})

describe("DataHubPage — two-pane hub", () => {
  it("shows the file-tree pane + honest detail prompt when a project is active", async () => {
    ctx.projects = PROJECTS
    ctx.activeProjectId = "proj-rna"
    ctx.activeProject = PROJECTS[0]

    // The file tree fetches /api/projects/:id/files — return an empty list so
    // the tree shows its own honest empty state (no fabricated files).
    vi.spyOn(global, "fetch").mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ files: [] }),
      text: async () => JSON.stringify({ files: [] }),
    } as unknown as Response)

    render(<DataHubPage />, { wrapper: wrapper() })

    // Two-pane layout is present.
    expect(screen.getByTestId("data-hub-panes")).toBeInTheDocument()
    // File tree pane mounted.
    await waitFor(() =>
      expect(screen.getByTestId("project-file-tree")).toBeInTheDocument(),
    )
    // Before any file is selected, the detail pane shows the honest prompt.
    expect(screen.getByTestId("data-hub-detail-empty")).toBeInTheDocument()
    expect(screen.getByText(/Select a dataset/i)).toBeInTheDocument()

    // Breadcrumb + change-project control reflect the active project.
    expect(screen.getByTestId("data-hub-change-project")).toBeInTheDocument()
  })
})
