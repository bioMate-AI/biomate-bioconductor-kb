/**
 * ProjectFileTree — folder upload + drag-drop (Data panel fixes 2026-11-10, D5).
 *
 * - a picked folder (webkitdirectory) uploads file-by-file with its relativePath;
 * - a dropped folder is walked recursively (webkitGetAsEntry) and the folder's own
 *   "directory pseudo-file" is never uploaded (that was the raw "Failed to fetch");
 * - one failed file does not abort the batch, and failures are listed, localized;
 * - stored folder paths render as nested folders.
 * Network is faked at fetch (our own endpoints).
 */
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, fireEvent, waitFor, within } from "@testing-library/react"
import { ProjectFileTree, buildTree, type ProjectFile } from "./project-file-tree"

function pf(id: string, name: string, extra: Partial<ProjectFile> = {}): ProjectFile {
  return {
    id, name, s3_key: `projects/p1/inputs/${name}`, size: 10, content_type: "text/csv",
    source: "upload", run_id: null, workflow_name: null, step_name: null, input_context: null,
    created_at: "2026-11-10T00:00:00Z", ...extra,
  }
}

function withRel(file: File, rel: string): File {
  Object.defineProperty(file, "webkitRelativePath", { value: rel, configurable: true })
  return file
}

type Call = { url: string; relativePath: string | null; fileName: string | null }
let calls: Call[] = []
let listed: ProjectFile[] = []
let failNames = new Set<string>()

beforeEach(() => {
  calls = []
  listed = []
  failNames = new Set()
  global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input)
    if (url.endsWith("/files/upload")) {
      const form = init!.body as FormData
      const file = form.get("file") as File
      const rel = form.get("relativePath") as string | null
      calls.push({ url, relativePath: rel, fileName: file?.name ?? null })
      if (failNames.has(rel ?? "")) return { ok: false, status: 500, json: async () => ({ error: "Upload failed" }) } as Response
      return { ok: true, status: 201, json: async () => ({ file: { id: "x", name: rel } }) } as Response
    }
    if (url.endsWith("/files")) return { ok: true, status: 200, json: async () => ({ files: listed }) } as Response
    return { ok: true, status: 200, json: async () => ({}) } as Response
  }) as unknown as typeof fetch
})

describe("buildTree — folder paths become nested folders", () => {
  it("nests inputs by their stored relative path, folders first", () => {
    const tree = buildTree([pf("1", "top.csv"), pf("2", "run1/fastq/S1.fq"), pf("3", "run1/meta.tsv")])
    const inputs = tree[0] as any
    expect(inputs.path).toBe("inputs")
    expect(inputs.children.map((c: any) => c.name)).toEqual(["run1", "top.csv"])
    const run1 = inputs.children[0]
    expect(run1.path).toBe("inputs/run1")
    expect(run1.children.map((c: any) => c.name)).toEqual(["fastq", "meta.tsv"])
    expect(run1.children[0].children[0].name).toBe("S1.fq")
  })
})

describe("ProjectFileTree — folder picker", () => {
  it("has a folder input and uploads every file with its relativePath; one failure doesn't abort", async () => {
    render(<ProjectFileTree projectId="p1" />)
    const folderInput = screen.getByTestId("project-files-folder-input") as HTMLInputElement
    expect(folderInput.hasAttribute("webkitdirectory")).toBe(true)
    failNames.add("study/b.csv")
    const files = [
      withRel(new File(["a"], "a.csv"), "study/a.csv"),
      withRel(new File(["b"], "b.csv"), "study/b.csv"),
      withRel(new File(["c"], "c.jsonl"), "study/sub/c.jsonl"),
    ]
    fireEvent.change(folderInput, { target: { files } })
    await waitFor(() => expect(screen.getByTestId("project-files-upload-summary")).toBeInTheDocument())
    expect(calls.map((c) => c.relativePath)).toEqual(["study/a.csv", "study/b.csv", "study/sub/c.jsonl"])
    expect(screen.getByTestId("project-files-upload-summary")).toHaveTextContent("2 uploaded, 1 failed")
    const failures = screen.getByTestId("project-files-upload-failures")
    expect(failures).toHaveTextContent("study/b.csv: server error (500)")
    expect(failures.textContent).not.toMatch(/Failed to fetch|Upload failed/)
  })

  it("a plain file pick sends the file name as relativePath (UTF-8 name, no folders)", async () => {
    render(<ProjectFileTree projectId="p1" />)
    fireEvent.change(screen.getByTestId("project-files-input"), { target: { files: [new File(["x"], "样本.csv")] } })
    await waitFor(() => expect(calls).toHaveLength(1))
    expect(calls[0].relativePath).toBe("样本.csv")
  })

  it("a network failure is reported as a localized reason, not a raw TypeError", async () => {
    const base = global.fetch
    global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      if (String(input).endsWith("/files/upload")) throw new TypeError("Failed to fetch")
      return (base as any)(input, init)
    }) as unknown as typeof fetch
    render(<ProjectFileTree projectId="p1" />)
    fireEvent.change(screen.getByTestId("project-files-input"), { target: { files: [new File(["x"], "a.csv")] } })
    const failures = await screen.findByTestId("project-files-upload-failures")
    expect(failures).toHaveTextContent("a.csv: network error — check your connection and try again")
  })

  it("a 409 name_conflict names the existing entry — not 'server error (409)'", async () => {
    const base = global.fetch
    global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      if (String(input).endsWith("/files/upload")) {
        return { ok: false, status: 409, json: async () => ({
          error: '"run1" conflicts with an existing file or folder in this project.', code: "name_conflict",
          conflicts: [{ name: "run1", existing: "run1/meta.tsv" }],
        }) } as Response
      }
      return (base as any)(input, init)
    }) as unknown as typeof fetch
    render(<ProjectFileTree projectId="p1" />)
    fireEvent.change(screen.getByTestId("project-files-input"), { target: { files: [new File(["x"], "run1")] } })
    const failures = await screen.findByTestId("project-files-upload-failures")
    expect(failures).toHaveTextContent("run1: “run1/meta.tsv” already uses that name in this project")
    expect(failures).not.toHaveTextContent("server error")
  })
})

// ── Drag-drop of a directory entry (FileSystemEntry API) ─────────────────────
function fileEntry(file: File): any {
  return { isFile: true, isDirectory: false, name: file.name, file: (ok: (f: File) => void) => ok(file) }
}
function dirEntry(name: string, children: any[]): any {
  return {
    isFile: false, isDirectory: true, name,
    createReader: () => {
      let done = false
      return { readEntries: (ok: (b: any[]) => void) => { const batch = done ? [] : children; done = true; ok(batch) } }
    },
  }
}
function dropEvent(entries: any[], pseudoFiles: File[]) {
  const items = entries.map((e) => ({ kind: "file", webkitGetAsEntry: () => e }))
  return { dataTransfer: { items, files: pseudoFiles } }
}

describe("ProjectFileTree — drag-drop of a folder", () => {
  it("walks the dropped folder recursively and never uploads the directory pseudo-file", async () => {
    render(<ProjectFileTree projectId="p1" />)
    const folder = dirEntry("batch_01", [
      fileEntry(new File(["1"], "x.csv")),
      dirEntry("tables", [fileEntry(new File(["2"], "y.jsonl"))]),
    ])
    // What dataTransfer.files holds for a dropped folder: one untyped, unreadable "file".
    const pseudo = new File([], "batch_01")
    fireEvent.drop(screen.getByTestId("project-file-tree"), dropEvent([folder], [pseudo]))
    await waitFor(() => expect(calls).toHaveLength(2))
    expect(calls.map((c) => c.relativePath).sort()).toEqual(["batch_01/tables/y.jsonl", "batch_01/x.csv"])
    expect(calls.some((c) => c.fileName === "batch_01")).toBe(false)
  })

  it("an empty dropped folder uploads nothing (no 'Failed to fetch')", async () => {
    render(<ProjectFileTree projectId="p1" />)
    fireEvent.drop(screen.getByTestId("project-file-tree"), dropEvent([dirEntry("empty", [])], [new File([], "empty")]))
    await new Promise((r) => setTimeout(r, 30))
    expect(calls).toHaveLength(0)
    expect(screen.queryByTestId("project-files-upload-failures")).toBeNull()
  })
})

describe("ProjectFileTree — nested folders render", () => {
  it("shows an uploaded folder as a folder row with its files inside", async () => {
    listed = [pf("f1", "study/a.csv"), pf("f2", "study/sub/c.jsonl")]
    render(<ProjectFileTree projectId="p1" />)
    const study = await screen.findByTestId("folder-inputs/study")
    expect(study).toHaveTextContent("study")
    expect(study).toHaveTextContent("2")
    fireEvent.click(study)
    expect(screen.getByTestId("folder-inputs/study/sub")).toBeInTheDocument()
    const row = screen.getByText("a.csv")
    expect(within(row.closest("div")!).queryByText("study/a.csv")).toBeNull()
  })
})
