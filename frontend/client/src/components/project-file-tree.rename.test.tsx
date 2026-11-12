/**
 * ProjectFileTree — rename / move of a file and of an input folder (2026-11-11).
 *
 * - file row "Rename / move" opens an inline input with the full name; Enter PATCHes
 *   {name} (folders allowed), Esc cancels without a request;
 * - a 409 keeps the editor open with the localized clash message;
 * - an input folder renames via POST /files/rename-folder {from, to} (paths without "inputs/");
 * - run outputs and read-only viewers get no rename control.
 * Network is faked at fetch (our own endpoints).
 */
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { ProjectFileTree, renameErrorReason, type ProjectFile } from "./project-file-tree"

function pf(id: string, name: string, extra: Partial<ProjectFile> = {}): ProjectFile {
  return {
    id, name, s3_key: `projects/p1/inputs/${name}`, size: 10, content_type: "text/csv",
    source: "upload", run_id: null, workflow_name: null, step_name: null, input_context: null,
    created_at: "2026-11-10T00:00:00Z", ...extra,
  }
}

type Call = { url: string; method: string; body: any }
let calls: Call[] = []
let listed: ProjectFile[] = []
let nextStatus = 200

beforeEach(() => {
  calls = []
  nextStatus = 200
  listed = [pf("f1", "x/a.csv"), pf("r1", "out.txt", { source: "run_output", run_id: "run-1" })]
  global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input)
    const method = init?.method ?? "GET"
    if (method === "PATCH" || url.endsWith("/files/rename-folder")) {
      const body = JSON.parse(String(init!.body))
      calls.push({ url, method, body })
      if (nextStatus !== 200) return { ok: false, status: nextStatus, json: async () => ({ error: "x" }) } as Response
      if (method === "PATCH") listed = listed.map((f) => (url.endsWith(`/files/${f.id}`) ? { ...f, name: body.name } : f))
      else listed = listed.map((f) => (f.name.startsWith(body.from + "/") ? { ...f, name: body.to + f.name.slice(body.from.length) } : f))
      return { ok: true, status: 200, json: async () => ({}) } as Response
    }
    if (url.endsWith("/files")) return { ok: true, status: 200, json: async () => ({ files: listed }) } as Response
    return { ok: true, status: 200, json: async () => ({}) } as Response
  }) as unknown as typeof fetch
})

async function openFolderX() {
  fireEvent.click(await screen.findByTestId("folder-inputs/x"))
  return screen.findByTestId("file-rename-f1")
}

describe("ProjectFileTree — rename / move a file", () => {
  it("the hint gives a concrete move example built from the file's own name, inside its CURRENT folder", async () => {
    render(<ProjectFileTree projectId="p1" />)
    fireEvent.click(await openFolderX())
    const hint = screen.getByTestId("file-rename-f1-hint")
    // The example keeps the nested file in x/ (a subfolder here) — never moves it out to the top.
    expect(hint.getAttribute("data-example")).toBe("x/archive/a.csv")
    expect(hint.textContent).toMatch(/x\/archive\/a\.csv/)
    expect(hint.textContent).not.toMatch(/(^|[^/])data\//)
  })

  it("Enter saves the new name (with folders) via PATCH and the tree shows the new place", async () => {
    render(<ProjectFileTree projectId="p1" />)
    fireEvent.click(await openFolderX())
    const input = screen.getByTestId("file-rename-f1-input") as HTMLInputElement
    expect(input.value).toBe("x/a.csv")
    fireEvent.change(input, { target: { value: "y/b.csv" } })
    fireEvent.keyDown(input, { key: "Enter" })
    await waitFor(() => expect(calls).toHaveLength(1))
    expect(calls[0]).toEqual({ url: "/api/projects/p1/files/f1", method: "PATCH", body: { name: "y/b.csv" } })
    // the destination folder is open after the refresh; the old folder is gone
    expect(await screen.findByText("b.csv")).toBeInTheDocument()
    expect(screen.getByTestId("folder-inputs/y")).toBeInTheDocument()
    expect(screen.queryByTestId("folder-inputs/x")).toBeNull()
    expect(screen.queryByTestId("file-rename-f1-input")).toBeNull()
  })

  it("Esc cancels without a request", async () => {
    render(<ProjectFileTree projectId="p1" />)
    fireEvent.click(await openFolderX())
    const input = screen.getByTestId("file-rename-f1-input")
    fireEvent.change(input, { target: { value: "zzz.csv" } })
    fireEvent.keyDown(input, { key: "Escape" })
    expect(screen.queryByTestId("file-rename-f1-input")).toBeNull()
    expect(calls).toHaveLength(0)
    expect(screen.getByText("a.csv")).toBeInTheDocument()
  })

  it("a 409 clash keeps the editor open with the localized message", async () => {
    nextStatus = 409
    render(<ProjectFileTree projectId="p1" />)
    fireEvent.click(await openFolderX())
    const input = screen.getByTestId("file-rename-f1-input")
    fireEvent.change(input, { target: { value: "taken.csv" } })
    fireEvent.keyDown(input, { key: "Enter" })
    const err = await screen.findByTestId("file-rename-f1-error")
    expect(err).toHaveTextContent(renameErrorReason(409))
    expect(screen.getByTestId("file-rename-f1-input")).toBeInTheDocument()
  })

  it("run outputs and read-only viewers get no rename control", async () => {
    const { unmount } = render(<ProjectFileTree projectId="p1" />)
    await screen.findByTestId("folder-inputs/x")
    fireEvent.click(screen.getByTestId("folder-outputs/run-1"))
    expect(await screen.findByText("out.txt")).toBeInTheDocument()
    expect(screen.queryByTestId("file-rename-r1")).toBeNull()
    expect(screen.queryByTestId("folder-rename-outputs/run-1")).toBeNull()
    expect(screen.queryByTestId("folder-rename-inputs")).toBeNull()
    unmount()
    render(<ProjectFileTree projectId="p1" canEdit={false} />)
    fireEvent.click(await screen.findByTestId("folder-inputs/x"))
    await screen.findByText("a.csv")
    expect(screen.queryByTestId("file-rename-f1")).toBeNull()
    expect(screen.queryByTestId("folder-rename-inputs/x")).toBeNull()
  })
})

describe("ProjectFileTree — rename / move a folder", () => {
  it("POSTs {from, to} without the inputs/ prefix and shows the renamed folder", async () => {
    render(<ProjectFileTree projectId="p1" />)
    fireEvent.click(await screen.findByTestId("folder-rename-inputs/x"))
    const input = screen.getByTestId("folder-rename-inputs/x-input") as HTMLInputElement
    expect(input.value).toBe("x")
    fireEvent.change(input, { target: { value: "z/archive" } })
    fireEvent.keyDown(input, { key: "Enter" })
    await waitFor(() => expect(calls).toHaveLength(1))
    expect(calls[0]).toEqual({ url: "/api/projects/p1/files/rename-folder", method: "POST", body: { from: "x", to: "z/archive" } })
    expect(await screen.findByTestId("folder-inputs/z/archive")).toBeInTheDocument()
    expect(screen.getByText("a.csv")).toBeInTheDocument() // destination opened
    expect(screen.queryByTestId("folder-inputs/x")).toBeNull()
  })

  it("an unchanged name closes the editor without a request", async () => {
    render(<ProjectFileTree projectId="p1" />)
    fireEvent.click(await screen.findByTestId("folder-rename-inputs/x"))
    fireEvent.keyDown(screen.getByTestId("folder-rename-inputs/x-input"), { key: "Enter" })
    expect(screen.queryByTestId("folder-rename-inputs/x-input")).toBeNull()
    expect(calls).toHaveLength(0)
  })

  it("a 409 shows the clash message on the folder editor", async () => {
    nextStatus = 409
    render(<ProjectFileTree projectId="p1" />)
    fireEvent.click(await screen.findByTestId("folder-rename-inputs/x"))
    const input = screen.getByTestId("folder-rename-inputs/x-input")
    fireEvent.change(input, { target: { value: "taken" } })
    fireEvent.keyDown(input, { key: "Enter" })
    expect(await screen.findByTestId("folder-rename-inputs/x-error")).toHaveTextContent(renameErrorReason(409))
  })
})
