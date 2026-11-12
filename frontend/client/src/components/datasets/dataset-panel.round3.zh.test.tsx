/**
 * Round-3 Chinese copy (P8 / W6 / P6): no raw English value words in the Chinese panel —
 * a Matrix Market value type reads "整数" (not "(integer)"), a name/content mismatch names the
 * format in Chinese ("文本", not "Text"), the source reads "上传的文件" (not "upload"), and the
 * 10x heading keeps its own capitalisation (never "10X GENOMICS 矩阵").
 * The i18n locale is resolved at module load, so modules are re-imported after setting it.
 */
import { describe, it, expect, vi, afterEach } from "vitest"

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

async function zh() {
  vi.resetModules()
  localStorage.setItem("biomate-user-settings", JSON.stringify({ language: "chinese" }))
  const React = await import("react")
  const rtl = await import("@testing-library/react")
  return { React, ...rtl }
}

describe("round-3 zh copy", () => {
  it("Matrix Market value type and a format-mismatch name are in Chinese", async () => {
    const { React, render, screen } = await zh()
    const { DataPerception } = await import("../data-perception")
    render(React.createElement(DataPerception, {
      datasetName: "x",
      profile: {
        shape: { rows: 0, cols: 0 }, quality: "watch", notes: [],
        findings: [
          { section: "signal", code: "mtx_dimensions", level: "info", params: { rows: 4, cols: 5, field: "integer", nnz: 8, density: 40 } },
          { section: "note", code: "name_content_mismatch", level: "watch", params: { named: "PNG", detected: "Text" } },
        ],
      },
    }))
    const text = screen.getByTestId("data-perception").textContent ?? ""
    expect(text).toContain("数值类型为 整数")
    expect(text).not.toMatch(/integer/)
    expect(text).toContain("内容是 文本")
    expect(text).not.toMatch(/\bText\b/)
  })

  it("the source reads 上传的文件, not 'upload'", async () => {
    const { React, render, screen, fireEvent } = await zh()
    global.fetch = vi.fn(async () => ({ ok: true, status: 200, json: async () => ({ shape: { rows: 0, cols: 0 }, quality: "good", notes: [] }), text: async () => "" })) as unknown as typeof fetch
    const { QueryClient, QueryClientProvider } = await import("@tanstack/react-query")
    const { DatasetObject } = await import("./dataset-object")
    render(React.createElement(QueryClientProvider, { client: new QueryClient() },
      React.createElement(DatasetObject, { dataset: { id: "a", name: "a.csv", ref: "k/a.csv", source: "upload" } })))
    fireEvent.click(screen.getByTestId("dataset-tab-wherefrom"))
    const origin = await screen.findByTestId("dataset-origin")
    expect(origin).toHaveTextContent("上传的文件")
    expect(origin.textContent).not.toMatch(/upload/)
  })

  it("the 10x heading keeps its capitalisation (no forced all-caps)", async () => {
    const { React, render, screen } = await zh()
    const TENX = {
      path: "tenx", kind: "tenx_matrix", fileCount: 3, rollup: [], findings: [],
      tenx: { sets: [{ dir: "", prefix: "", matrix: "tenx/matrix.mtx", barcodes: "tenx/barcodes.tsv", features: "tenx/features.tsv",
        version: "v3", complete: true, missing: [], genes: 5, cells: 5, nnz: 8 }] },
      tenxFiles: [],
    }
    global.fetch = vi.fn(async () => ({ ok: true, status: 200, json: async () => TENX, text: async () => "" })) as unknown as typeof fetch
    const { QueryClient, QueryClientProvider } = await import("@tanstack/react-query")
    const { FolderProfileView } = await import("./folder-profile-view")
    render(React.createElement(QueryClientProvider, { client: new QueryClient() },
      React.createElement(FolderProfileView, { projectId: "p1", path: "tenx" })))
    const heading = await screen.findByTestId("folder-tenx-heading")
    expect(heading).toHaveTextContent("10x Genomics 矩阵")
    expect(heading.className).not.toMatch(/uppercase/)
  })
})
