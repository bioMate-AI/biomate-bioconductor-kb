/**
 * R14 (client): the dataset header's Download goes through the same-origin
 * `/files/:id/url?redirect=1` link — the server redirects to a signed URL that names the file
 * by its display name. The page never fetches the raw storage URL and points an anchor at it
 * (which navigated the tab to S3 for text/image files and saved them as `name.csv.v2`).
 */
import React from "react"
import { describe, it, expect, vi, afterEach } from "vitest"
import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"

vi.mock("@/contexts/active-project-context", () => ({
  useActiveProject: () => ({
    activeProjectId: "proj-1",
    activeProject: { id: "proj-1", name: "Pilot", status: "active" },
    projects: [],
    loading: false,
    setActiveProjectId: () => {},
  }),
}))
const FILE = {
  id: "f-1", name: "study/samples.csv", s3_key: "projects/proj-1/inputs/study/samples.csv.v2", size: 10,
  content_type: "text/csv", source: "upload", run_id: null, workflow_name: null, step_name: null,
  input_context: null, created_at: "2026-11-10T09:00:00Z",
}
vi.mock("@/components/project-file-tree", () => ({
  ProjectFileTree: ({ onOpenDataset }: { onOpenDataset: (f: unknown) => void }) => (
    <button data-testid="open-file" onClick={() => onOpenDataset(FILE)}>open</button>
  ),
}))

afterEach(() => { vi.restoreAllMocks() })

describe("Data hub header Download (R14)", () => {
  it("clicks a same-origin ?redirect=1 link named after the display name; never fetches/navigates to the storage URL", async () => {
    global.fetch = vi.fn(async (input: RequestInfo | URL) => {
      const u = String(input)
      const body = u.includes("/api/perception/profile")
        ? { shape: { rows: 1, cols: 1 }, quality: "good", notes: [] }
        : { url: "https://bucket.s3.amazonaws.com/projects/proj-1/inputs/study/samples.csv.v2" }
      return { ok: true, status: 200, json: async () => body } as unknown as Response
    }) as unknown as typeof fetch
    const clicked: Array<{ href: string; download: string }> = []
    vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(function (this: HTMLAnchorElement) {
      clicked.push({ href: this.getAttribute("href") ?? "", download: this.download })
    })
    const { default: DataHubPage } = await import("./data-hub")
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
    render(<QueryClientProvider client={qc}><DataHubPage /></QueryClientProvider>)
    fireEvent.click(screen.getByTestId("open-file"))
    fireEvent.click(await screen.findByTestId("dataset-object-download"))
    await waitFor(() => expect(clicked).toHaveLength(1))
    expect(clicked[0].href).toBe("/api/projects/proj-1/files/f-1/url?redirect=1")
    expect(clicked[0].download).toBe("samples.csv")
    expect(clicked.some((c) => c.href.includes("amazonaws"))).toBe(false)
  }, 30_000)
})
