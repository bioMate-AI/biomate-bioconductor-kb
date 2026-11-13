/**
 * CodeSandboxPath — Models power-user path via owned POST /api/code/run.
 */
import React from "react"
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { render, screen, fireEvent, waitFor, cleanup } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { CodeSandboxPath } from "./code-sandbox-path"
import { ModelsPanel } from "./models-panel"

const PROJECT = "11111111-1111-4111-8111-111111111111"
const FILE = { id: "22222222-2222-4222-8222-222222222222", name: "expr.csv", s3_key: "k/expr.csv" }

vi.mock("@/contexts/active-project-context", () => ({
  useActiveProjectSafe: () => ({
    activeProjectId: PROJECT,
    projects: [{ id: PROJECT, name: "P1" }],
    setActiveProjectId: () => {},
  }),
}))

function wrapper() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
}

beforeEach(() => {
  localStorage.setItem("biomate-user-settings", JSON.stringify({ language: "english" }))
})
afterEach(() => {
  cleanup()
  vi.restoreAllMocks()
  localStorage.clear()
})

describe("CodeSandboxPath", () => {
  it("POSTs /api/code/run with language, code, project file, and shows stdout", async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      if (url.includes("/files") && !url.includes("upload")) {
        return { ok: true, status: 200, json: async () => ({ files: [FILE] }) } as Response
      }
      if (url.includes("/api/code/run")) {
        const body = JSON.parse(String(init?.body || "{}"))
        expect(body.language).toBe("python")
        expect(body.code).toContain("INPUT_FILES")
        expect(body.project_id).toBe(PROJECT)
        expect(body.input_datasets).toEqual([FILE.id])
        return {
          ok: true,
          status: 200,
          json: async () => ({ exit_code: 0, stdout: "inputs: ['expr.csv']\n", stderr: "", output_files: [] }),
        } as Response
      }
      return { ok: true, status: 200, json: async () => ({}) } as Response
    })
    global.fetch = fetchMock as unknown as typeof fetch

    render(<CodeSandboxPath />, { wrapper: wrapper() })
    await waitFor(() =>
      expect((screen.getByTestId("code-dataset") as HTMLSelectElement).options.length).toBeGreaterThan(1),
    )
    fireEvent.change(screen.getByTestId("code-dataset"), { target: { value: `file:${FILE.id}` } })
    fireEvent.click(screen.getByTestId("code-run"))
    expect(await screen.findByTestId("code-stdout")).toHaveTextContent("expr.csv")
    expect(screen.getByTestId("code-exit")).toHaveTextContent("0")
  })

  it("selecting a folder POSTs every file id under it as input_datasets", async () => {
    const A = { id: "aaaaaaaa-0000-4000-8000-000000000001", name: "batch/a.csv", s3_key: "k/a" }
    const B = { id: "bbbbbbbb-0000-4000-8000-000000000002", name: "batch/b.csv", s3_key: "k/b" }
    let seen: unknown
    global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input)
      if (url.includes("/files") && !url.includes("upload")) {
        return { ok: true, status: 200, json: async () => ({ files: [A, B] }) } as Response
      }
      if (url.includes("/api/code/run")) {
        seen = JSON.parse(String(init?.body || "{}"))
        return {
          ok: true, status: 200,
          json: async () => ({ exit_code: 0, stdout: "ok\n", stderr: "", output_files: [] }),
        } as Response
      }
      return { ok: true, status: 200, json: async () => ({}) } as Response
    }) as unknown as typeof fetch

    render(<CodeSandboxPath />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("code-dataset").textContent).toContain("batch/"))
    fireEvent.change(screen.getByTestId("code-dataset"), { target: { value: "folder:batch" } })
    expect(await screen.findByTestId("code-folder-count")).toHaveTextContent("2")
    fireEvent.click(screen.getByTestId("code-run"))
    await waitFor(() => expect(seen).toBeTruthy())
    expect(seen).toMatchObject({
      project_id: PROJECT,
      input_datasets: [A.id, B.id],
    })
  })

  it("surfaces a server error without inventing a successful result", async () => {
    global.fetch = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input)
      if (url.includes("/files")) {
        return { ok: true, status: 200, json: async () => ({ files: [] }) } as Response
      }
      if (url.includes("/api/code/run")) {
        return { ok: false, status: 500, json: async () => ({ error: "sidecar down" }) } as Response
      }
      return { ok: true, status: 200, json: async () => ({}) } as Response
    }) as unknown as typeof fetch

    render(<CodeSandboxPath />, { wrapper: wrapper() })
    fireEvent.click(screen.getByTestId("code-run"))
    expect(await screen.findByTestId("code-error")).toHaveTextContent(/sidecar down/)
    expect(screen.queryByTestId("code-result")).toBeNull()
  })
})

describe("ModelsPanel — train path toggle", () => {
  it("defaults to no-code launcher and switches to the code sandbox", async () => {
    global.fetch = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input)
      const body =
        url.includes("/files") ? { files: [FILE] }
        : url.includes("/api/perception/profile") ? { columns: ["a"], sampleRows: [["1"]] }
        : url.includes("/api/model-tracks/train") ? { runs: [] }
        : url.includes("/api/models") ? []
        : {}
      return { ok: true, status: 200, json: async () => body } as Response
    }) as unknown as typeof fetch

    render(<ModelsPanel project="P1" tab={0} />, { wrapper: wrapper() })
    expect(await screen.findByTestId("train-path-toggle")).toBeTruthy()
    expect(screen.getByTestId("training-launcher-general")).toBeTruthy()
    expect(screen.queryByTestId("code-sandbox-path")).toBeNull()

    fireEvent.click(screen.getByTestId("train-path-code"))
    expect(await screen.findByTestId("code-sandbox-path")).toBeTruthy()
    expect(screen.queryByTestId("training-launcher-general")).toBeNull()
    // No chat-draft escape hatch.
    expect(document.querySelector('a[href*="draft="]')).toBeNull()
  })
})
