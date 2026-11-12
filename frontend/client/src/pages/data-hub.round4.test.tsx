/**
 * N8 (round 4): at a narrow width the data hub stacks its panes, and the opened file appeared
 * BELOW the whole file tree with no scroll — a tap on a file seemed to do nothing. Opening a file
 * in the stacked layout now scrolls the object into view; side by side (wide) it does not.
 */
import React from "react"
import { describe, it, expect, vi, afterEach } from "vitest"
import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"

vi.mock("@/contexts/active-project-context", () => ({
  useActiveProject: () => ({ activeProjectId: "proj-1", activeProject: { id: "proj-1", name: "Pilot", status: "active" }, projects: [], loading: false, setActiveProjectId: () => {} }),
}))
const FILE = { id: "f-1", name: "counts.tsv", s3_key: "projects/proj-1/inputs/counts.tsv", size: 10, content_type: "text/tab-separated-values",
  source: "upload", run_id: null, workflow_name: null, step_name: null, input_context: null, created_at: "2026-11-10T09:00:00Z" }
vi.mock("@/components/project-file-tree", () => ({
  ProjectFileTree: ({ onOpenDataset }: { onOpenDataset: (f: unknown) => void }) => <button data-testid="open-file" onClick={() => onOpenDataset(FILE)}>open</button>,
}))

afterEach(() => { vi.restoreAllMocks() })

const rect = (top: number, height: number) => ({ top, bottom: top + height, height, left: 0, right: 300, width: 300, x: 0, y: top, toJSON: () => ({}) }) as DOMRect

async function openWithLayout(stacked: boolean) {
  global.fetch = vi.fn(async () => ({ ok: true, status: 200, json: async () => ({ shape: { rows: 0, cols: 0 }, quality: "good", notes: [] }) })) as unknown as typeof fetch
  const scrolled: Element[] = []
  vi.spyOn(Element.prototype, "getBoundingClientRect").mockImplementation(function (this: Element) {
    const list = this.classList.contains("data-hub-file-list")
    // Stacked: the detail starts under the 320px-tall list; wide: both start at the top.
    return list ? rect(100, 320) : rect(stacked ? 440 : 100, 600)
  })
  ;(Element.prototype as any).scrollIntoView = function (this: Element) { scrolled.push(this) }
  const { default: DataHubPage } = await import("./data-hub")
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  render(<QueryClientProvider client={qc}><DataHubPage /></QueryClientProvider>)
  fireEvent.click(screen.getByTestId("open-file"))
  await screen.findByTestId("dataset-object")
  return scrolled
}

describe("data hub — the opened object comes into view when the panes are stacked", () => {
  it("stacked (narrow): scrolls the detail pane into view", async () => {
    const scrolled = await openWithLayout(true)
    await waitFor(() => expect(scrolled.map((e) => e.getAttribute("data-testid"))).toContain("data-hub-detail"))
  }, 30_000)
  it("side by side (wide): no scroll", async () => {
    const scrolled = await openWithLayout(false)
    expect(scrolled).toHaveLength(0)
  }, 30_000)
})
