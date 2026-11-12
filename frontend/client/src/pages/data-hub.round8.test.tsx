/**
 * Round 8 (dev 0fead9b9): renaming the OPEN file in the tree updated the tree, but the open object
 * kept the old name in its title / breadcrumb (and sent the old name to the profiler, which reads
 * the format from it). The open object held a snapshot of the row; the tree's list — the source of
 * truth — never reached it. Now the open object follows the tree:
 *  - a renamed / moved file: same id, new name (the storage key does not change on a rename);
 *  - a deleted file: the object closes and says so;
 *  - a renamed / moved folder: an open folder view (or one inside it) follows to the new path.
 */
import React from "react"
import { describe, it, expect, vi, afterEach } from "vitest"
import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"

vi.mock("@/contexts/active-project-context", () => ({
  useActiveProject: () => ({ activeProjectId: "proj-1", activeProject: { id: "proj-1", name: "Pilot", status: "active" }, projects: [], loading: false, setActiveProjectId: () => {} }),
}))

const FILE = { id: "f-1", name: "big.csv", s3_key: "projects/proj-1/inputs/big.csv", size: 10, content_type: "text/csv",
  source: "upload", run_id: null, workflow_name: null, step_name: null, input_context: null, created_at: "2026-11-12T09:00:00Z" }
const OTHER = { ...FILE, id: "f-2", name: "other.csv", s3_key: "projects/proj-1/inputs/other.csv" }

vi.mock("@/components/project-file-tree", () => ({
  ProjectFileTree: (p: {
    onOpenDataset: (f: unknown) => void
    onOpenFolder: (path: string) => void
    onFileList?: (files: unknown[]) => void
    onFolderRenamed?: (from: string, to: string) => void
  }) => (
    <div>
      <button data-testid="open-file" onClick={() => p.onOpenDataset(FILE)}>open</button>
      <button data-testid="open-folder" onClick={() => p.onOpenFolder("run1/fastq")}>folder</button>
      <button data-testid="list-renamed" onClick={() => p.onFileList?.([{ ...FILE, name: "archive/big_renamed.csv" }, OTHER])}>renamed</button>
      <button data-testid="list-deleted" onClick={() => p.onFileList?.([OTHER])}>deleted</button>
      <button data-testid="folder-renamed" onClick={() => p.onFolderRenamed?.("run1", "archive/run1")}>moved</button>
    </div>
  ),
}))

afterEach(() => { vi.restoreAllMocks() })

async function renderHub() {
  global.fetch = vi.fn(async () => ({ ok: true, status: 200, json: async () => ({ shape: { rows: 0, cols: 0 }, quality: "good", notes: [], versions: [] }) })) as unknown as typeof fetch
  const { default: DataHubPage } = await import("./data-hub")
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  render(<QueryClientProvider client={qc}><DataHubPage /></QueryClientProvider>)
}

describe("data hub — the open object follows the file tree", () => {
  it("a renamed / moved open file shows its new name", async () => {
    await renderHub()
    fireEvent.click(screen.getByTestId("open-file"))
    expect((await screen.findByTestId("dataset-object-name")).textContent).toContain("big.csv")
    fireEvent.click(screen.getByTestId("list-renamed"))
    await waitFor(() => expect(screen.getByTestId("dataset-object-name").textContent).toContain("big_renamed.csv"))
    // The profile request carries the new name (the profiler reads the format from it).
    await waitFor(() => {
      const bodies = (global.fetch as any).mock.calls
        .filter((c: any[]) => String(c[0]).includes("/api/perception/profile"))
        .map((c: any[]) => String(c[1]?.body ?? ""))
      expect(bodies.some((b: string) => b.includes("big_renamed.csv"))).toBe(true)
    })
  }, 30_000)

  it("a deleted open file closes the object and says so", async () => {
    await renderHub()
    fireEvent.click(screen.getByTestId("open-file"))
    await screen.findByTestId("dataset-object")
    fireEvent.click(screen.getByTestId("list-deleted"))
    await waitFor(() => expect(screen.queryByTestId("dataset-object")).toBeNull())
    expect(screen.getByTestId("data-hub-open-file-deleted").textContent).toContain("big.csv")
  }, 30_000)

  it("an open folder inside a moved folder follows to its new path", async () => {
    await renderHub()
    fireEvent.click(screen.getByTestId("open-folder"))
    expect((await screen.findByTestId("folder-profile")).getAttribute("data-path")).toBe("run1/fastq")
    fireEvent.click(screen.getByTestId("folder-renamed"))
    await waitFor(() => expect(screen.getByTestId("folder-profile").getAttribute("data-path")).toBe("archive/run1/fastq"))
  }, 30_000)
})
