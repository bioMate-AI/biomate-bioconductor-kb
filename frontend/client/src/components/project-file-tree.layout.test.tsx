/**
 * ProjectFileTree — row layout, inline preview and rename errors (audit U10 / P1 / copy 5–6,
 * 2026-11-12).
 *
 * Founder screenshot bugAfterAddingFolder.png: in a nested folder the file name shrank to 0–19 px
 * (five invisible hover buttons kept their width), the hover "eye" dumped file contents into the
 * tree, and the name's tooltip said "Open dataset" instead of the name. jsdom has no layout, so the
 * row contract is asserted through computed style: the name is the flexible item with a real
 * minimum width, the hidden actions are absolutely positioned (no layout width), indent is bounded.
 * Network is faked at fetch (our own endpoints).
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { render, screen, fireEvent, waitFor, within } from "@testing-library/react"
import {
  ProjectFileTree, renameErrorReason, renameErrorCode, treeIndent, NAME_MIN_PX, type ProjectFile,
} from "./project-file-tree"
import { t } from "@/lib/i18n"

function pf(id: string, name: string, extra: Partial<ProjectFile> = {}): ProjectFile {
  return {
    id, name, s3_key: `projects/p1/inputs/${name}`, size: 9700, content_type: "text/plain",
    source: "upload", run_id: null, workflow_name: null, step_name: null, input_context: null,
    created_at: "2026-11-10T00:00:00Z", ...extra,
  }
}

const DEEP = "top_level_screen_results/mageck_count_outputs/normalized/sample.count_normalized_with_a_long_name.txt"
const DEEP_FOLDERS = ["inputs/top_level_screen_results", "inputs/top_level_screen_results/mageck_count_outputs",
  "inputs/top_level_screen_results/mageck_count_outputs/normalized"]

let listed: ProjectFile[] = []
let patch: { status: number; body: unknown } = { status: 200, body: {} }
let fetched: string[] = []
const LONG_TEXT = Array.from({ length: 100 }, (_, i) => `sgGENE${i}\tGENE${i}\t${1000 + i}`).join("\n")

beforeEach(() => {
  listed = [pf("deep", DEEP), pf("top", "notes.txt")]
  patch = { status: 200, body: {} }
  fetched = []
  global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input)
    fetched.push(url)
    const method = init?.method ?? "GET"
    if (method === "PATCH" || url.endsWith("/files/rename-folder")) {
      if (patch.status === -1) throw new TypeError("Failed to fetch")
      return { ok: patch.status < 400, status: patch.status, json: async () => patch.body } as Response
    }
    if (url.endsWith("/files")) return { ok: true, status: 200, json: async () => ({ files: listed }) } as Response
    if (url.endsWith("/url")) return { ok: true, status: 200, json: async () => ({ url: "https://bucket.example/obj", name: "x" }) } as Response
    if (url === "https://bucket.example/obj") return { ok: true, status: 200, text: async () => LONG_TEXT } as Response
    return { ok: true, status: 200, json: async () => ({}) } as Response
  }) as unknown as typeof fetch
})

const origScrollIntoView = Element.prototype.scrollIntoView
afterEach(() => { vi.restoreAllMocks(); Element.prototype.scrollIntoView = origScrollIntoView })

async function expandDeep() {
  for (const path of DEEP_FOLDERS) fireEvent.click(await screen.findByTestId(`folder-${path}`))
  return screen.findByTestId("file-row-deep")
}

const px = (v: string) => parseFloat(v || "0")

describe("ProjectFileTree — names stay readable at any depth (U10)", () => {
  it("a file 4 levels deep: the name is the flexible item with a real minimum width and the full name as tooltip", async () => {
    render(<ProjectFileTree projectId="p1" onOpenDataset={() => {}} />)
    const row = await expandDeep()
    const name = screen.getByTestId("file-open-deep")
    const cs = getComputedStyle(name)
    expect(px(cs.minWidth)).toBeGreaterThanOrEqual(64)
    expect(px(cs.minWidth)).toBe(NAME_MIN_PX)
    expect(cs.flexGrow).toBe("1")
    // the tooltip is the full stored path, not an action label
    expect(name.getAttribute("title")).toBe(DEEP)
    expect(name.textContent).toBe("sample.count_normalized_with_a_long_name.txt")
    // indent: bounded per level (old: 16 + depth*20 = 96 px of a 280 px tree at depth 4)
    expect(px(row.style.paddingLeft)).toBe(treeIndent(4))
    expect(px(row.style.paddingLeft)).toBeLessThanOrEqual(56)
  })

  it("hover actions take no layout width: every action button sits in an absolutely positioned overlay", async () => {
    render(<ProjectFileTree projectId="p1" onOpenDataset={() => {}} />)
    const row = await expandDeep()
    const overlay = screen.getByTestId("file-actions-deep")
    expect(getComputedStyle(overlay).position).toBe("absolute")
    for (const id of ["file-copy-deep", "file-download-deep", "file-rename-deep", "file-delete-deep"]) {
      expect(overlay.contains(screen.getByTestId(id))).toBe(true)
    }
    // no button is a direct flex child of the row except the name itself
    const directButtons = Array.from(row.children).filter((c) => c.tagName === "BUTTON")
    expect(directButtons.map((b) => b.getAttribute("data-testid"))).toEqual(["file-open-deep"])
    // still reachable by keyboard (not display:none / not removed)
    expect(screen.getByTestId("file-rename-deep").getAttribute("aria-label")).toBe(t("file_tree.rename"))
  })

  it("row actions are reachable without hover: always shown on touch screens (hover: none)", async () => {
    render(<ProjectFileTree projectId="p1" onOpenDataset={() => {}} />)
    await expandDeep()
    for (const id of ["file-actions-deep", `folder-actions-${DEEP_FOLDERS[2]}`]) {
      const cls = screen.getByTestId(id).className
      expect(cls).toContain("[@media(hover:none)]:opacity-100")
      expect(cls).toContain("[@media(hover:none)]:pointer-events-auto")
    }
  })

  it("folder rows follow the same contract: flexible name with min width, rename in an overlay", async () => {
    render(<ProjectFileTree projectId="p1" onOpenDataset={() => {}} />)
    await expandDeep()
    const path = DEEP_FOLDERS[2]
    const name = screen.getByTestId(`folder-name-${path}`)
    expect(px(getComputedStyle(name).minWidth)).toBe(NAME_MIN_PX)
    expect(getComputedStyle(name).flexGrow).toBe("1")
    expect(name.getAttribute("title")).toBe("top_level_screen_results/mageck_count_outputs/normalized")
    const overlay = screen.getByTestId(`folder-actions-${path}`)
    expect(getComputedStyle(overlay).position).toBe("absolute")
    expect(overlay.contains(screen.getByTestId(`folder-rename-${path}`))).toBe(true)
  })

  it("indent stops growing after a few levels", () => {
    expect(treeIndent(0)).toBe(8)
    expect(treeIndent(12)).toBe(treeIndent(8))
    expect(treeIndent(20)).toBeLessThanOrEqual(104)
  })

  it("the box: header sections never shrink, only the body scrolls", async () => {
    render(<ProjectFileTree projectId="p1" />)
    await screen.findByTestId("folder-inputs")
    expect(screen.getByTestId("project-files-header").className).toMatch(/\bshrink-0\b/)
    const body = screen.getByTestId("project-files-body")
    expect(body.className).toMatch(/\bmin-h-0\b/)
    expect(body.className).toMatch(/\boverflow-y-auto\b/)
  })
})

describe("ProjectFileTree — inline preview never dumps a file into the tree (U10)", () => {
  it("in the data hub (object view available) there is no eye; the name opens the dataset", async () => {
    const opened: string[] = []
    render(<ProjectFileTree projectId="p1" onOpenDataset={(f) => opened.push(f.id)} />)
    await screen.findByTestId("file-row-top")
    expect(screen.queryByTestId("file-preview-toggle-top")).toBeNull()
    expect(screen.queryByTitle(t("file_tree.preview"))).toBeNull()
    fireEvent.click(screen.getByTestId("file-open-top"))
    expect(opened).toEqual(["top"])
    expect(fetched.some((u) => u.endsWith("/url"))).toBe(false)
  })

  it("without an object view, the quick look is a bounded, non-wrapping, scrollable box", async () => {
    render(<ProjectFileTree projectId="p1" />)
    await screen.findByTestId("file-row-top")
    fireEvent.click(screen.getByTestId("file-preview-toggle-top"))
    const box = await screen.findByTestId("file-preview-top")
    await waitFor(() => expect(box.querySelector("pre")).not.toBeNull())
    expect(box.style.maxHeight).toBe("160px")
    expect(box.style.overflow).toBe("auto")
    const pre = box.querySelector("pre")!
    expect(getComputedStyle(pre).whiteSpace).toBe("pre")
    expect(pre.textContent!.split("\n")).toHaveLength(20)
    expect(screen.getByTestId("file-preview-toggle-top").getAttribute("aria-expanded")).toBe("true")
  })
})

// Error texts exactly as the server sends them (server/project-file-paths.ts).
const SERVER_400 = {
  control_chars: "name contains control characters",
  empty: "name is empty",
  dot_segments: "name may not contain '..'",
  segment_too_long: "each folder or file name is limited to 200 characters",
  too_deep: "folders may be nested at most 32 deep",
  run_output: "Run outputs keep the name their run gave them and cannot be renamed.",
  same_name: "The folder already has that name.",
  into_itself: "A folder cannot be moved into itself.",
  limit_after_move: "\"a/b\" would exceed the folder depth or name length limit.",
}

describe("rename errors — one message per server reason (copy audit 5–6)", () => {
  it("every 400 reason maps to its own localized message (folder errors carry a from:/to: prefix)", () => {
    const messages = new Set<string>()
    for (const [code, text] of Object.entries(SERVER_400)) {
      expect(renameErrorCode(400, { error: text })).toBe(code)
      expect(renameErrorCode(400, { error: `to: ${text}` })).toBe(code)
      messages.add(renameErrorReason(400, { error: text }))
    }
    expect(messages.size).toBe(Object.keys(SERVER_400).length)
    expect(messages.has(renameErrorReason(400, { error: "something new" }))).toBe(false)
    // a server-sent code wins over the text
    expect(renameErrorCode(400, { code: "too_deep", error: "whatever" })).toBe("too_deep")
  })

  it("every code the server sends (project-file-paths.ts NameErrorCode) gets its own message", () => {
    // The exact values the server's `code` field carries.
    const SERVER_CODES = ["run_output", "same_name", "into_itself", "control_chars", "dot_segments", "empty",
      "segment_too_long", "too_deep", "limit_after_move"] as const
    const generic = t("file_tree.rename_invalid")
    const messages = new Set<string>()
    for (const code of SERVER_CODES) {
      const m = renameErrorReason(400, { code, error: "server text not matched on purpose" })
      expect(m, code).not.toBe(generic)
      messages.add(m)
    }
    expect(messages.size).toBe(SERVER_CODES.length)
    // name_conflict (409) names the clashing file, with or without the code.
    const conflicts = [{ name: "b.csv", existing: "data/b.csv" }]
    expect(renameErrorReason(409, { code: "name_conflict", error: "x", conflicts })).toBe(t("file_tree.rename_conflict_with", { existing: "data/b.csv" }))
    expect(renameErrorReason(409, { code: "name_conflict", error: "x" })).toBe(t("file_tree.rename_conflict"))
  })

  it("403/404 say it can't be renamed or no longer exists — never 'upload'", () => {
    for (const s of [403, 404]) {
      const m = renameErrorReason(s, { error: "Project not found" })
      expect(m).toBe(t("file_tree.rename_err_gone"))
      expect(m.toLowerCase()).not.toContain("upload")
    }
    expect(renameErrorReason(401)).toBe(t("file_tree.rename_err_signed_out"))
    expect(renameErrorReason(500)).toContain("500")
    expect(renameErrorReason(409, { error: "x", conflicts: [{ name: "b.csv", existing: "data/b.csv" }] })).toContain("data/b.csv")
  })

  it("the editor shows the specific reason the server gave and keeps the example hint until then", async () => {
    patch = { status: 400, body: { error: "name may not contain '..'" } }
    render(<ProjectFileTree projectId="p1" />)
    fireEvent.click(await screen.findByTestId("file-rename-top"))
    expect(screen.getByTestId("file-rename-top-hint").textContent).toMatch(/archive\/notes\.txt/)
    const input = screen.getByTestId("file-rename-top-input")
    fireEvent.change(input, { target: { value: "../x.txt" } })
    fireEvent.keyDown(input, { key: "Enter" })
    expect(await screen.findByTestId("file-rename-top-error")).toHaveTextContent(t("file_tree.rename_err_dot_segment"))
  })

  it("a network failure says nothing was renamed (not the upload wording)", async () => {
    patch = { status: -1, body: null }
    render(<ProjectFileTree projectId="p1" />)
    fireEvent.click(await screen.findByTestId("file-rename-top"))
    const input = screen.getByTestId("file-rename-top-input")
    fireEvent.change(input, { target: { value: "y.txt" } })
    fireEvent.keyDown(input, { key: "Enter" })
    expect(await screen.findByTestId("file-rename-top-error")).toHaveTextContent(t("file_tree.rename_err_network"))
  })

  it("the rename editor scrolls itself fully into view (hint on the last row is not cut off)", async () => {
    const scrolled: Element[] = []
    Element.prototype.scrollIntoView = function (this: Element) { scrolled.push(this) }
    render(<ProjectFileTree projectId="p1" />)
    fireEvent.click(await screen.findByTestId("file-rename-top"))
    const editor = screen.getByTestId("file-rename-top-editor")
    expect(within(editor).getByTestId("file-rename-top-hint")).toBeInTheDocument()
    expect(scrolled).toContain(editor)
  })
})
