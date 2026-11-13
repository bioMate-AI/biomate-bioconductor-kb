/**
 * Folder view (data hub): selecting an input folder in the tree opens it as ONE object —
 * FASTQ samples with paired / orphan badges + "Download samplesheet", a 10x matrix with
 * cells × genes, the format roll-up and the folder findings (i18n perception.msg.<code>),
 * in one language at a time. Network faked at fetch (our own endpoints only); the profiles
 * are the backend's shape (backend/lib/galaxy/ai/folder_profile.py, test_folder_profile.py).
 */
import { describe, it, expect, vi, afterEach } from "vitest"

vi.mock("@/contexts/active-project-context", () => ({
  useActiveProject: () => ({
    activeProjectId: "proj-1",
    activeProject: { id: "proj-1", name: "Pilot", status: "active", createdAt: "2026-08-01T10:00:00Z" },
    projects: [],
    loading: false,
    setActiveProjectId: () => {},
  }),
}))

const file = (id: string, name: string) => ({
  id, name, s3_key: `projects/proj-1/inputs/${name}`, size: 100, content_type: "application/gzip", source: "upload",
  run_id: null, workflow_name: null, step_name: null, input_context: null, created_at: "2026-11-11T09:00:00Z",
})
const FILES = [
  file("f1", "pairs/S1_R1.fastq.gz"), file("f2", "pairs/S1_R2.fastq.gz"), file("f3", "pairs/S2_R1.fastq.gz"),
  file("t1", "tenx/matrix.mtx"), file("t2", "tenx/barcodes.tsv"), file("t3", "tenx/features.tsv"),
]

const PAIRS = {
  path: "pairs", kind: "fastq_set", fileCount: 3,
  rollup: [{ format: "fastq", label: "FASTQ", count: 3, pairs: 1 }],
  findings: [
    { code: "folder_fastq_pairs", level: "info", params: { pairs: 1, pattern: "_R1/_R2" } },
    { code: "folder_fastq_orphan", level: "watch", params: { name: "S2_R1.fastq.gz", sample: "S2", missing: "R2" } },
    { code: "folder_fastq_mixed_layout", level: "watch", params: { pairs: 1, unpaired: 1 } },
    { code: "folder_samplesheet", level: "info", params: { rows: 1, layout: "paired", path_base: "project inputs" } },
    { code: "folder_samplesheet_single_end", level: "info", params: { rows: 1, filename: "samplesheet_single_end.csv", names: ["S2_R1.fastq.gz"] } },
  ],
  fastq: {
    verdict: "mixed", pattern: "Rs", patterns: ["Rs"], engine: "galaxy", pairs: 1,
    samples: [
      { sample: "S1", forward: "pairs/S1_R1.fastq.gz", reverse: "pairs/S1_R2.fastq.gz", status: "paired", dir: "pairs" },
      { sample: "S2", forward: "pairs/S2_R1.fastq.gz", reverse: null, status: "orphan", role: "forward", dir: "pairs" },
    ],
    orphans: ["pairs/S2_R1.fastq.gz"], singles: [],
  },
  // Round 3: a run takes one layout — the paired sheet holds S1 only; the orphan S2 goes to the
  // single-end sheet (folder_profile.samplesheet).
  samplesheet: {
    columns: ["sample", "fastq_1", "fastq_2"], filename: "samplesheet.csv", layout: "paired", pathBase: "project inputs",
    rows: [["S1", "pairs/S1_R1.fastq.gz", "pairs/S1_R2.fastq.gz"]],
    csv: "sample,fastq_1,fastq_2\nS1,pairs/S1_R1.fastq.gz,pairs/S1_R2.fastq.gz\n",
    single: {
      columns: ["sample", "fastq_1", "fastq_2"], filename: "samplesheet_single_end.csv", layout: "single_end", pathBase: "project inputs",
      rows: [["S2", "pairs/S2_R1.fastq.gz", ""]], csv: "sample,fastq_1,fastq_2\nS2,pairs/S2_R1.fastq.gz,\n",
    },
    excluded: ["pairs/S2_R1.fastq.gz"],
  },
}
const TENX = {
  path: "tenx", kind: "tenx_matrix", fileCount: 3,
  rollup: [{ format: "mtx", label: "Matrix Market", count: 1 }, { format: "tsv", label: "TSV", count: 2 }],
  findings: [
    { code: "folder_tenx_recognised", level: "info", params: { cells: 5, genes: 5, nnz: 8, version: "v3", dir: null } },
    { code: "folder_tenx_headerless", level: "info", params: {} },
  ],
  tenx: { sets: [{ dir: "", prefix: "", matrix: "tenx/matrix.mtx", barcodes: "tenx/barcodes.tsv", features: "tenx/features.tsv",
    version: "v3", complete: true, missing: [], genes: 5, cells: 5, nnz: 8 }] },
  tenxFiles: [],
}

const calls: string[] = []
function installFetch() {
  calls.length = 0
  global.fetch = vi.fn(async (input: RequestInfo | URL) => {
    const url = String(input)
    calls.push(url)
    const ok = (body: unknown) => ({ ok: true, status: 200, json: async () => body, text: async () => JSON.stringify(body) }) as unknown as Response
    if (url.includes("/folders/profile")) {
      const p = new URL(url, "http://x").searchParams.get("path")
      return ok(p === "pairs" ? PAIRS : p === "tenx" ? TENX : { path: p, kind: "empty", fileCount: 0, rollup: [], findings: [] })
    }
    if (url.includes("/folders/files")) {
      const p = new URL(url, "http://x").searchParams.get("path")
      const under = FILES.filter((f) => f.name.startsWith(`${p}/`))
      return ok({ path: p, files: under.map((f) => ({ id: f.id, name: f.name })) })
    }
    if (url.endsWith("/api/projects/proj-1/files")) return ok({ files: FILES })
    return ok({})
  }) as unknown as typeof fetch
}

async function renderHub(language: "chinese" | "english") {
  vi.resetModules()
  localStorage.setItem("biomate-user-settings", JSON.stringify({ language }))
  installFetch()
  const React = await import("react")
  const rtl = await import("@testing-library/react")
  const { QueryClient, QueryClientProvider } = await import("@tanstack/react-query")
  const { default: DataHubPage } = await import("@/pages/data-hub")
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  const view = rtl.render(React.createElement(QueryClientProvider, { client: qc }, React.createElement(DataHubPage)))
  await rtl.waitFor(() => expect(rtl.screen.getByTestId("folder-inputs/pairs")).toBeInTheDocument())
  return { ...rtl, view }
}

afterEach(() => {
  localStorage.clear()
  vi.restoreAllMocks()
})

describe("Folder view", () => {
  it("pairs/: S1 paired, S2_R1 orphan, samplesheet download link, roll-up + findings", async () => {
    const { screen, fireEvent, waitFor, within } = await renderHub("english")
    fireEvent.click(screen.getByTestId("folder-inputs/pairs"))
    const fp = await screen.findByTestId("folder-profile")
    await waitFor(() => expect(fp.getAttribute("data-kind")).toBe("fastq_set"))
    expect(calls.some((u) => u === "/api/projects/proj-1/folders/profile?path=pairs")).toBe(true)
    expect(screen.getByTestId("folder-sample-row-S1").getAttribute("data-status")).toBe("paired")
    expect(screen.getByTestId("folder-sample-row-S2").getAttribute("data-status")).toBe("orphan")
    expect(within(screen.getByTestId("folder-sample-row-S2")).getByTestId("folder-orphan-S2_R1.fastq.gz")).toHaveTextContent("Missing mate — single-end")
    const dl = screen.getByTestId("folder-samplesheet-download")
    expect(dl.getAttribute("href")).toBe("/api/projects/proj-1/folders/profile?path=pairs&download=samplesheet")
    // Ask in chat attaches the folder (all files), not a samplesheet-only stand-in.
    const analyze = screen.getByTestId("folder-profile-analyze")
    expect(analyze).toHaveTextContent("Ask in chat")
    expect(screen.getByTestId("folder-rollup")).toHaveTextContent("Files: 3 — 3 FASTQ · pairs: 1")
    expect(screen.getByTestId("folder-profile-verdict")).toHaveTextContent("Paired + unpaired")
    // Round 5 — S2's missing mate is said ONCE in the samples section: the row's badge and the
    // excluded note. The orphan / mixed-layout / single-end / pairs / samplesheet findings repeated it
    // (five times in all on dev) and are not listed again.
    expect(screen.queryAllByTestId("folder-finding")).toHaveLength(0)
    expect(screen.getByTestId("folder-samplesheet-excluded")).toHaveTextContent("Not in the paired samplesheet (no mate in this folder): S2_R1.fastq.gz")
    const fp2 = screen.getByTestId("folder-profile")
    expect((fp2.textContent ?? "").split("S2_R1.fastq.gz").length - 1).toBe(2) // the table cell + the excluded note
    expect(fp2.textContent).not.toContain("would run single-end")
    // The tree row shows it is the open folder; opening a file replaces the folder view.
    expect(screen.getByTestId("folder-inputs/pairs").getAttribute("aria-current")).toBe("true")
  }, 30_000)

  it("tenx/: recognised 10x matrix with cells × genes, header-less note", async () => {
    const { screen, fireEvent, waitFor } = await renderHub("english")
    fireEvent.click(screen.getByTestId("folder-inputs/tenx"))
    const fp = await screen.findByTestId("folder-profile")
    await waitFor(() => expect(fp.getAttribute("data-kind")).toBe("tenx_matrix"))
    expect(screen.getByTestId("folder-tenx-set-.")).toHaveAttribute("data-complete", "true")
    expect(screen.getByTestId("folder-tenx-dims")).toHaveTextContent("5 cells × 5 genes")
    expect(screen.getByTestId("folder-findings")).toHaveTextContent("no header row by the 10x specification")
    expect(screen.queryByTestId("folder-samplesheet-download")).toBeNull()
  }, 30_000)

  it("Chinese UI: natural Chinese, no untranslated English UI words", async () => {
    const { screen, fireEvent, waitFor } = await renderHub("chinese")
    fireEvent.click(screen.getByTestId("folder-inputs/pairs"))
    const fp = await screen.findByTestId("folder-profile")
    await waitFor(() => expect(fp.getAttribute("data-kind")).toBe("fastq_set"))
    const text = fp.textContent ?? ""
    expect(text).toContain("共 3 个文件：3 个 FASTQ（1 对）")
    expect(text).toContain("下载样本表")
    expect(text).toContain("未放入双端样本表（本文件夹中没有配对文件）：S2_R1.fastq.gz")
    expect(text).not.toContain("将按单端处理")
    const ALLOWED = ["S1_R1.fastq.gz", "S1_R2.fastq.gz", "S2_R1.fastq.gz", "pairs", "S1", "S2", "R2", "FASTQ",
      "_R1/_R2", "nf-core", "sample", "fastq_1", "fastq_2", "samplesheet_single_end.csv"]
    let rest = text
    for (const tok of [...ALLOWED].sort((a, b) => b.length - a.length)) rest = rest.split(tok).join(" ")
    expect(Array.from(new Set(rest.match(/[A-Za-z]{2,}/g) ?? []))).toEqual([])
  }, 30_000)
})
