/**
 * Dataset panel round-3 seams in the per-kind views and the file tree (live dev walkthrough
 * 2026-11-12):
 *  W6  a file named .png whose content the profiler read as text shows that text;
 *  P7  an image shows its pixel size and fits the frame (zoom toggle to actual size); a structure
 *      is zoomed to its polymer (waters/ligands do not set the zoom);
 *  P5  a multi-line cell opens to show every line while edited; the row height stays fixed;
 *  P9  a table wider than the panel says there are more columns to scroll to;
 *  P1  the rename hint is one short line, the input shows the start of the path;
 *  tree quality dot: stored verdict first; a file over 50 MB is never profiled from the list.
 */
import React from "react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { render, screen, waitFor, cleanup, fireEvent } from "@testing-library/react"

const zoomCalls: unknown[] = []
vi.mock("3dmol", () => ({
  default: {
    createViewer: () => ({
      addModel: () => {}, removeAllModels: () => {},
      selectedAtoms: (sel: { atom?: string[]; hetflag?: boolean }) => (sel?.atom ? [{ atom: "CA" }] : sel?.hetflag === false ? [{ atom: "CA" }] : []),
      setStyle: () => {}, zoomTo: (sel: unknown) => { zoomCalls.push(sel) }, render: () => {}, resize: () => {},
    }),
  },
}))
import { DatasetFilePreview } from "./dataset-file-preview"
import { DatasetRowsTable } from "./dataset-rows-table"
import { InlineStructureViewer } from "../viewers/inline-content-viewers"
import { ProjectFileTree, TREE_AUTO_PROFILE_MAX_BYTES, type ProjectFile } from "../project-file-tree"

afterEach(() => { cleanup(); vi.unstubAllGlobals() })

function mockTextFile(text: string) {
  const value = new TextEncoder().encode(text)
  const read = vi.fn().mockResolvedValueOnce({ value, done: false }).mockResolvedValue({ done: true })
  vi.stubGlobal("fetch", vi.fn()
    .mockResolvedValueOnce({ ok: true, json: async () => ({ url: "https://files.example/test" }) })
    .mockResolvedValueOnce({ ok: true, body: { getReader: () => ({ read, cancel: vi.fn(), releaseLock: vi.fn() }) } }))
}

describe("W6 — text under an image name is shown as text", () => {
  it("fake.png read as Text shows its first lines and says why", async () => {
    mockTextFile("this is not a png\nline two\n")
    render(<DatasetFilePreview projectId="p" fileId="f" name="fake.png" kind="document" format="txt" />)
    const view = await screen.findByTestId("dataset-text-preview")
    expect(view).toHaveTextContent("this is not a png")
    expect(screen.getByTestId("dataset-preview-name-mismatch")).toHaveTextContent("Its name says PNG, but it holds text")
    expect(screen.queryByTestId("dataset-preview-image-invalid")).toBeNull()
  })

  it("a real PNG is still an image", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ url: "https://files.example/img" }) }))
    render(<DatasetFilePreview projectId="p" fileId="f" name="micro.png" kind="image" format="png" />)
    expect(await screen.findByTestId("dataset-preview-image")).toBeInTheDocument()
  })
})

describe("P7 — image size and fit; structure fitted to its polymer", () => {
  it("shows W × H px, fits the frame, and toggles to actual size", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ url: "https://files.example/img" }) }))
    render(<DatasetFilePreview projectId="p" fileId="f" name="micro.png" kind="image" format="png" />)
    const img = await screen.findByTestId("dataset-preview-image") as HTMLImageElement
    Object.defineProperty(img, "naturalWidth", { value: 32 })
    Object.defineProperty(img, "naturalHeight", { value: 24 })
    fireEvent.load(img)
    expect(await screen.findByTestId("dataset-preview-image-dims")).toHaveTextContent("32 × 24 px")
    const frame = screen.getByTestId("dataset-preview-image-frame")
    expect(frame).toHaveAttribute("data-zoom", "fit")
    expect(img.className).toMatch(/object-contain/)
    fireEvent.click(screen.getByTestId("dataset-preview-image-zoom"))
    expect(frame).toHaveAttribute("data-zoom", "actual")
  })

  it("the cartoon view zooms to the polymer (hetflag false), not to every atom", async () => {
    zoomCalls.length = 0
    render(<InlineStructureViewer text={"ATOM      1  CA  ALA A   1       0.000   0.000   0.000  1.00 10.00           C\n"} ext="pdb" />)
    await waitFor(() => expect(zoomCalls.length).toBeGreaterThan(0))
    expect(zoomCalls[0]).toEqual({ hetflag: false })
  })
})

describe("P5 — multi-line cell editor shows every line while edited", () => {
  it("expands on focus (all lines), back to one row on blur; the cell box keeps its height", () => {
    render(
      <DatasetRowsTable columns={["note"]} rows={[["line one\nline two\nline three"]]} total={1}
        loading={false} error={null} onNeedMore={() => {}} editable edits={{}} onEdit={() => {}} />,
    )
    const ta = screen.getByTestId("dataset-edit-cell-0-0") as HTMLTextAreaElement
    expect(ta.tagName).toBe("TEXTAREA")
    expect(ta.rows).toBe(1)
    fireEvent.focus(ta)
    expect(ta.rows).toBe(3)
    expect(ta).toHaveAttribute("data-expanded", "true")
    // The overlay sits in a fixed-height box: the table row does not grow.
    expect((ta.parentElement!.parentElement as HTMLElement).style.height).toBe("22px")
    fireEvent.blur(ta)
    expect(ta.rows).toBe(1)
  })
})

describe("P9 — a table wider than the panel says so", () => {
  it("shows 'More columns → scroll sideways' while columns are hidden to the right", () => {
    render(
      <DatasetRowsTable columns={["a", "b", "c", "d", "e"]} rows={[["1", "2", "3", "4", "5"]]} total={1}
        loading={false} error={null} onNeedMore={() => {}} />,
    )
    const box = screen.getByTestId("dataset-preview-scroll")
    Object.defineProperty(box, "scrollWidth", { configurable: true, value: 800 })
    Object.defineProperty(box, "clientWidth", { configurable: true, value: 340 })
    fireEvent.scroll(box)
    expect(box).toHaveAttribute("data-more-right", "true")
    expect(screen.getByTestId("dataset-preview-more-columns")).toHaveTextContent("More columns")
    Object.defineProperty(box, "scrollLeft", { configurable: true, value: 460 })
    fireEvent.scroll(box)
    expect(screen.queryByTestId("dataset-preview-more-columns")).toBeNull()
  })
})

function pf(id: string, name: string, extra: Partial<ProjectFile> = {}): ProjectFile {
  return {
    id, name, s3_key: `projects/p1/inputs/${name}`, size: 10, content_type: "text/plain",
    source: "upload", run_id: null, workflow_name: null, step_name: null, input_context: null,
    created_at: "2026-11-12T00:00:00Z", ...extra,
  }
}
function stubTree(files: ProjectFile[]) {
  const profileCalls: string[] = []
  vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input)
    if (url.endsWith("/api/perception/profile")) {
      profileCalls.push(JSON.parse(String(init?.body ?? "{}")).name)
      return { ok: true, status: 200, json: async () => ({ quality: "good", findings: [] }) } as Response
    }
    if (url.endsWith("/files")) return { ok: true, status: 200, json: async () => ({ files }) } as Response
    return { ok: true, status: 200, json: async () => ({}) } as Response
  }))
  return profileCalls
}

describe("P1 — rename hint is one short line; the input shows the path's start", () => {
  it("nested file: short one-line hint, example inside its own folder, caret at the start", async () => {
    stubTree([pf("f1", "top/mageck_count/brunello_library_screen_day14_vs_plasmid_replicate1_sgrna_counts.count.txt")])
    render(<ProjectFileTree projectId="p1" />)
    fireEvent.click(await screen.findByTestId("folder-inputs/top"))
    fireEvent.click(await screen.findByTestId("folder-inputs/top/mageck_count"))
    fireEvent.click(await screen.findByTestId("file-rename-f1"))
    const hint = screen.getByTestId("file-rename-f1-hint")
    expect(hint.className).toMatch(/whitespace-nowrap/)
    expect(hint.firstChild!.textContent).toBe("Enter saves · Esc cancels · “/” = folder")
    expect(hint.getAttribute("data-example")).toBe("top/mageck_count/archive/brunello_library_screen_day14_vs_plasmid_replicate1_sgrna_counts.count.txt")
    const input = screen.getByTestId("file-rename-f1-input") as HTMLInputElement
    fireEvent.focus(input)
    expect(input.selectionStart).toBe(0)
    expect(input.selectionEnd).toBe(input.value.length)
    expect(input.selectionDirection).toBe("backward")
  })
})

describe("tree quality dot — stored verdict, and no whole-file download of a huge file from the list", () => {
  it("a 2 GB BAM row triggers no profile request and reads 'not checked yet — open to check'", async () => {
    const calls = stubTree([pf("big", "huge.bam", { size: 2 * 1024 ** 3, profileSummary: null })])
    render(<ProjectFileTree projectId="p1" />)
    const dot = await screen.findByTestId("file-quality-big")
    await new Promise((r) => setTimeout(r, 30))
    expect(calls).toEqual([])
    expect(dot).toHaveAttribute("data-quality", "pending")
    expect(dot.getAttribute("title")).toMatch(/open the file to check/)
  })

  it("a small unprofiled file is profiled once; a stored summary is used without a request", async () => {
    const calls = stubTree([
      pf("s", "small.csv", { size: TREE_AUTO_PROFILE_MAX_BYTES, profileSummary: null }),
      pf("k", "known.csv", { profileSummary: { quality: "watch", findings: [{ code: "ragged_rows", level: "watch" }] } }),
      pf("u", "blob.xyz", { profileSummary: { quality: "watch", findings: [{ code: "unprofilable", level: "watch" }] } }),
    ])
    render(<ProjectFileTree projectId="p1" />)
    await waitFor(() => expect(screen.getByTestId("file-quality-s")).toHaveAttribute("data-quality", "good"))
    expect(calls).toEqual(["small.csv"])
    expect(screen.getByTestId("file-quality-k")).toHaveAttribute("data-quality", "watch")
    expect(screen.getByTestId("file-quality-u")).toHaveAttribute("data-quality", "unassessed")
  })
})
