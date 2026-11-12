/**
 * ProjectFileTree — the per-row quality dot shows the SAME verdict as the dataset object
 * (effectiveQuality, audit 2026-11-12 U4): a profile whose only "watch" reasons say the file
 * was identified but not analysed is "unassessed" (grey), never an orange warning; a real watch
 * finding stays watch; the backend's own "unassessed" is grey too.
 * Network is faked at fetch (our own endpoints).
 */
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, waitFor } from "@testing-library/react"
import { ProjectFileTree, type ProjectFile } from "./project-file-tree"

function pf(id: string, name: string): ProjectFile {
  return {
    id, name, s3_key: `projects/p1/inputs/${name}`, size: 10, content_type: "text/plain",
    source: "upload", run_id: null, workflow_name: null, step_name: null, input_context: null,
    created_at: "2026-11-12T00:00:00Z",
  }
}

const PROFILES: Record<string, unknown> = {
  // An older backend: "watch" only because the content was not analysed.
  "old.txt": { quality: "watch", shape: { rows: 0, cols: 0 }, notes: [],
    findings: [{ section: "note", code: "format_identified", level: "watch", params: {} }] },
  // A real warning.
  "bad.csv": { quality: "watch", shape: { rows: 3, cols: 2 }, notes: [],
    findings: [{ section: "note", code: "ragged_rows", level: "watch", params: { count: 1, expected: 2 } }] },
  // The current backend's own verdict.
  "new.txt": { quality: "unassessed", shape: { rows: 0, cols: 0 }, notes: [], findings: [] },
}

beforeEach(() => {
  global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input)
    if (url.endsWith("/api/perception/profile")) {
      const { name } = JSON.parse(String(init?.body ?? "{}"))
      return { ok: true, status: 200, json: async () => PROFILES[name] } as Response
    }
    if (url.endsWith("/files")) {
      return { ok: true, status: 200, json: async () => ({ files: [pf("1", "old.txt"), pf("2", "bad.csv"), pf("3", "new.txt")] }) } as Response
    }
    return { ok: true, status: 200, json: async () => ({}) } as Response
  }) as unknown as typeof fetch
})

describe("ProjectFileTree — quality dot uses effectiveQuality", () => {
  it("not-analysed 'watch' is grey 'unassessed'; a real watch stays watch", async () => {
    render(<ProjectFileTree projectId="p1" />)
    await waitFor(() => expect(screen.getByTestId("file-quality-2").getAttribute("data-quality")).toBe("watch"))
    await waitFor(() => expect(screen.getByTestId("file-quality-1").getAttribute("data-quality")).toBe("unassessed"))
    await waitFor(() => expect(screen.getByTestId("file-quality-3").getAttribute("data-quality")).toBe("unassessed"))
    for (const id of ["1", "3"]) {
      const dot = screen.getByTestId(`file-quality-${id}`)
      expect(dot.className).not.toMatch(/amber/)
      expect(dot.className).toMatch(/bg-muted-foreground/)
    }
    expect(screen.getByTestId("file-quality-2").className).toMatch(/amber/)
  })
})
