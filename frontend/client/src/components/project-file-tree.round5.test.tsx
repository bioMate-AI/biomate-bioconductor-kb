/**
 * Round 5 (2026-11-12 walkthrough), project page Files tab:
 *  - a .jsonl file has the eye quick look (its first lines, as text);
 *  - the row icon follows the profiled content kind when it is known (`profileSummary.viewKind`):
 *    fake.png, which is text, gets a document icon and a text quick look, not an image icon / a
 *    broken <img>; a real PNG keeps the image icon.
 * Network is faked at fetch (our own endpoints).
 */
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { ProjectFileTree, type ProjectFile } from "./project-file-tree"

function pf(id: string, name: string, viewKind?: string): ProjectFile {
  return {
    id, name, s3_key: `projects/p1/inputs/${name}`, size: 200, content_type: "application/octet-stream",
    source: "upload", run_id: null, workflow_name: null, step_name: null, input_context: null,
    created_at: "2026-11-12T00:00:00Z",
    profileSummary: viewKind ? { quality: "good", findings: [], viewKind } : null,
  }
}

const JSONL = ['{"source":"epar_table","page":30}', '{"source":"epar_table","page":31}', '{"source":"epar_table","page":34}'].join("\n")
const CONTENT: Record<string, string> = { "u-1": JSONL, "u-2": "this is not a PNG\njust text\n" }

beforeEach(() => {
  global.fetch = vi.fn(async (input: RequestInfo | URL) => {
    const url = String(input)
    const ok = (body: unknown, text = "") => ({ ok: true, status: 200, json: async () => body, text: async () => text }) as Response
    if (url.endsWith("/files")) {
      return ok({ files: [pf("1", "epar_study_tables.jsonl", "records"), pf("2", "fake.png", "document"), pf("3", "microscopy.png", "image")] })
    }
    const m = url.match(/\/files\/(\d)\/url$/)
    if (m) return ok({ url: `u-${m[1]}`, name: "x" })
    if (CONTENT[url] !== undefined) return ok({}, CONTENT[url])
    return ok({})
  }) as unknown as typeof fetch
})

describe("Files tab quick look + icons (round 5)", () => {
  it(".jsonl has the eye preview and shows its first lines as text", async () => {
    render(<ProjectFileTree projectId="p1" />)
    const toggle = await screen.findByTestId("file-preview-toggle-1", undefined, { timeout: 5000 })
    fireEvent.click(toggle)
    await waitFor(() => expect(screen.getByTestId("file-preview-1")).toHaveTextContent('{"source":"epar_table","page":30}'))
    expect(screen.getByTestId("file-preview-1").querySelector("pre")).not.toBeNull()
  })

  it("fake.png (text content): document icon and a text quick look; a real PNG keeps the image icon", async () => {
    render(<ProjectFileTree projectId="p1" />)
    const fakeIcon = await screen.findByTestId("file-icon-2", undefined, { timeout: 5000 })
    expect(fakeIcon.getAttribute("class")).toContain("lucide-file-text")
    expect(fakeIcon.getAttribute("class")).not.toContain("lucide-file-image")
    expect(screen.getByTestId("file-icon-3").getAttribute("class")).toContain("lucide-file-image")
    fireEvent.click(screen.getByTestId("file-preview-toggle-2"))
    await waitFor(() => expect(screen.getByTestId("file-preview-2")).toHaveTextContent("this is not a PNG"))
    expect(screen.getByTestId("file-preview-2").querySelector("img")).toBeNull()
  })
})
