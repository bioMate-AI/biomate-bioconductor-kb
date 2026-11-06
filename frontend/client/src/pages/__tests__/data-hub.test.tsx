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
    // Status renders as the localized lifecycle label (statusLabel → t("data_hub.status_completed")),
    // not the raw lowercase enum, so assert the human-readable label.
    expect(admet.textContent).toContain("Completed")

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

  it("opens a file as a first-class DatasetObject showing real identity + quality", async () => {
    ctx.projects = PROJECTS
    ctx.activeProjectId = "proj-rna"
    ctx.activeProject = PROJECTS[0]

    // One real uploaded file in the project (source "upload" \u2192 the default-
    // expanded "inputs" folder, so its open button is immediately clickable).
    const FILE = {
      id: "file-counts",
      name: "counts.csv",
      s3_key: "projects/proj-rna/inputs/counts.csv",
      size: 20480,
      content_type: "text/csv",
      source: "upload",
      run_id: null,
      workflow_name: null,
      step_name: null,
      input_context: null,
      created_at: "2026-08-02T09:00:00.000Z",
    }
    // A real perception profile so the DatasetObject renders actual quality
    // (verdict + shape + preview table) \u2014 not a fabricated placeholder.
    const PROFILE = {
      shape: { rows: 12000, cols: 4 },
      quality: "watch",
      notes: ["3 columns are highly correlated"],
      columns: ["gene", "sample_a", "sample_b", "sample_c"],
      sampleRows: [
        ["TP53", "104", "98", "110"],
        ["EGFR", "12", "9", "15"],
      ],
      classBalance: [
        { label: "control", frac: 0.5 },
        { label: "treated", frac: 0.5 },
      ],
    }

    // Route fetch by URL: the files list, and the perception profile POST that
    // both the file-tree quality dot and DatasetObject's Preview/Quality tabs hit.
    global.fetch = vi.fn(async (input: RequestInfo | URL) => {
      const url = typeof input === "string" ? input : input.toString()
      if (url.includes("/api/perception/profile")) {
        return {
          ok: true,
          status: 200,
          json: async () => PROFILE,
          text: async () => JSON.stringify(PROFILE),
        } as unknown as Response
      }
      if (url.includes("/api/projects/proj-rna/files")) {
        return {
          ok: true,
          status: 200,
          json: async () => ({ files: [FILE] }),
          text: async () => JSON.stringify({ files: [FILE] }),
        } as unknown as Response
      }
      // Any other tab endpoint (lineage/consumers/versions) is not exercised here.
      return {
        ok: true,
        status: 200,
        json: async () => ({}),
        text: async () => "{}",
      } as unknown as Response
    }) as unknown as typeof fetch

    render(<DataHubPage />, { wrapper: wrapper() })

    // The file row surfaces in the tree with an open affordance.
    await waitFor(() =>
      expect(screen.getByTestId("file-open-file-counts")).toBeInTheDocument(),
    )
    // Before selection there is no DatasetObject, only the honest empty prompt.
    expect(screen.queryByTestId("dataset-object")).toBeNull()
    expect(screen.getByTestId("data-hub-detail-empty")).toBeInTheDocument()

    // Open the file \u2192 it becomes a first-class DatasetObject.
    fireEvent.click(screen.getByTestId("file-open-file-counts"))
    await waitFor(() =>
      expect(screen.getByTestId("dataset-object")).toBeInTheDocument(),
    )
    // The empty prompt is gone \u2014 the detail pane now shows the object.
    expect(screen.queryByTestId("data-hub-detail-empty")).toBeNull()

    // Real identity: name + id + content-type carried straight from the file.
    // The breadcrumb shows the human filename; the immutable id stays on hover.
    expect(screen.getByTestId("dataset-object-name").textContent).toContain("counts.csv")
    expect(screen.getByTestId("dataset-object-id").textContent).toContain("counts.csv")
    expect(screen.getByTestId("dataset-object-id").getAttribute("title")).toBe("file-counts")

    // Real quality: the default Preview tab renders the actual profiled table
    // (columns + a real sample row), not a placeholder.
    await waitFor(() =>
      expect(screen.getByTestId("dataset-preview-table")).toBeInTheDocument(),
    )
    expect(screen.getByTestId("dataset-preview-table").textContent).toContain("TP53")

    // Quality at ingest lives in the "Where it came from" tab (design §4.5.2):
    // opening it renders the honest verdict from the profile (watch), proving
    // quality is real.
    fireEvent.click(screen.getByTestId("dataset-tab-wherefrom"))
    const dp = await screen.findByTestId("data-perception", {}, { timeout: 4000 })
    expect(dp.getAttribute("data-quality")).toBe("watch")
  })

})
