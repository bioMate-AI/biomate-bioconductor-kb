/**
 * One language at a time — the Data panel never mixes Chinese and English.
 *
 * Renders the main Data surfaces (data-hub header, project file tree incl. an upload
 * failure report, the dataset object's preview table + stat grid, and the QC card)
 * under zh and under en, and asserts:
 *   - en: no CJK character anywhere (text, title, placeholder, aria-label);
 *   - zh: no untranslated English UI words — after removing the DATA shown (file
 *     names, column names, cell values, project name) and proper nouns / units.
 *
 * The i18n locale is resolved at module load, so each locale re-imports the modules
 * (vi.resetModules) after setting the stored language preference.
 */
import { describe, it, expect, vi, afterEach } from "vitest"

vi.mock("@/contexts/active-project-context", () => ({
  useActiveProject: () => ({
    activeProjectId: "proj-1",
    activeProject: { id: "proj-1", name: "RNA pilot", status: "active", primaryDomain: "transcriptomics", createdAt: "2026-08-01T10:00:00Z" },
    projects: [],
    loading: false,
    setActiveProjectId: () => {},
  }),
}))

const FILES = [
  {
    id: "f-tbl", name: "study/counts.csv", s3_key: "projects/proj-1/inputs/study/counts.csv", size: 2048,
    content_type: "text/csv", source: "upload", run_id: null, workflow_name: null, step_name: null,
    input_context: null, created_at: "2026-11-10T09:00:00Z",
  },
  {
    id: "f-out", name: "de.tsv", s3_key: "projects/proj-1/outputs/r1/de.tsv", size: 512,
    content_type: "text/tab-separated-values", source: "run_output", run_id: "r1",
    workflow_name: "nf-core/rnaseq", step_name: null, input_context: null, created_at: "2026-11-10T09:00:00Z",
  },
]

// A backend-shaped profile (structured findings) that exercises reasons, leakage, plan,
// class balance and the Effective-N reason hint.
const PROFILE = {
  shape: { rows: 300, cols: 3 },
  quality: "watch",
  notes: ["free text the UI must not show"],
  signalSummary: ["free text the UI must not show"],
  effectiveN: 42,
  effectiveNReason: "imbalance",
  duplicateRows: 0,
  classBalance: [{ label: "ctrl", frac: 0.93 }, { label: "case", frac: 0.07 }],
  columns: ["gene", "label", "batch"],
  sampleRows: [["TP53", "ctrl", "b1"]],
  planImpact: [{ observed: "free text", effect: "free text" }],
  findings: [
    { section: "signal", code: "near_constant", level: "watch", params: { count: 1, columns: ["batch"], pct: 99 } },
    { section: "note", code: "minority_class", level: "watch", params: { label: "case", pct: 7 } },
    { section: "leakage", code: "batch_confound", level: "watch", params: { column: "batch" } },
    { section: "plan", code: "batch_covariate", level: "info", params: { column: "batch" } },
    { section: "note", code: "table_summary", level: "info", params: { rows: 300, cols: 3 } },
  ],
}

const ROWS = {
  kind: "table", offset: 0, limit: 200, totalRows: 300, columns: ["gene", "label", "batch"],
  rows: [["TP53", "ctrl", "b1"], ["EGFR", "case", "b2"]],
}

function installFetch() {
  global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input)
    const ok = (body: unknown) => ({ ok: true, status: 200, json: async () => body, text: async () => JSON.stringify(body) }) as unknown as Response
    if (url.includes("/files/upload")) {
      const rel = (init?.body as FormData).get("relativePath")
      if (rel === "big/huge.csv") return { ok: false, status: 413, json: async () => ({}) } as unknown as Response
      throw new TypeError("Failed to fetch")
    }
    if (url.includes("/rows")) return ok(ROWS)
    if (url.includes("/api/perception/profile")) return ok(PROFILE)
    if (url.endsWith("/api/projects/proj-1/files")) return ok({ files: FILES })
    return ok({})
  }) as unknown as typeof fetch
}

// Data, proper nouns, identifiers and units that legitimately appear in either language.
const ALLOWED = [
  "study/counts.csv", "counts.csv", "de.tsv", "study", "RNA pilot", "nf-core/rnaseq",
  "gene", "label", "batch", "TP53", "EGFR", "ctrl", "case", "b1", "b2",
  "text/csv", "RO-Crate", "Galaxy", "BioMate", "FastQC", "MultiQC", "ID", "Jupyter", "RStudio", "QC", "S3", "URL", "KB", "MB", "bp", "Phred",
  "FTP", "HTTP", // protocol labels in the add-URL / public-FTP affordance (kept as acronyms in zh)
  "big/huge.csv", "big/net.csv",
  "inputs", // the top-level folder node is a storage path segment, not UI copy
]

function surfaceText(root: HTMLElement): string {
  const parts = [root.textContent ?? ""]
  root.querySelectorAll("[title],[placeholder],[aria-label]").forEach((el) => {
    for (const a of ["title", "placeholder", "aria-label"]) {
      const v = el.getAttribute(a)
      if (v) parts.push(v)
    }
  })
  return parts.join("\n")
}

function leftoverEnglish(text: string): string[] {
  let rest = text
  for (const tok of [...ALLOWED].sort((a, b) => b.length - a.length)) rest = rest.split(tok).join(" ")
  return Array.from(new Set(rest.match(/[A-Za-z]{2,}/g) ?? []))
}

async function renderSurfaces(language: "chinese" | "english") {
  vi.resetModules()
  localStorage.setItem("biomate-user-settings", JSON.stringify({ language }))
  installFetch()
  const React = await import("react")
  const { render, screen, fireEvent, waitFor } = await import("@testing-library/react")
  const { QueryClient, QueryClientProvider } = await import("@tanstack/react-query")
  const { default: DataHubPage } = await import("@/pages/data-hub")
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
  const view = render(React.createElement(QueryClientProvider, { client: qc }, React.createElement(DataHubPage)))

  // File tree: the folder + run-output nodes, then a failing folder upload (413 + network).
  await waitFor(() => expect(screen.getByTestId("folder-inputs/study")).toBeInTheDocument())
  fireEvent.click(screen.getByTestId("folder-inputs/study"))
  const big = new File(["x"], "huge.csv")
  Object.defineProperty(big, "webkitRelativePath", { value: "big/huge.csv" })
  const net = new File(["y"], "net.csv")
  Object.defineProperty(net, "webkitRelativePath", { value: "big/net.csv" })
  fireEvent.change(screen.getByTestId("project-files-folder-input"), { target: { files: [big, net] } })
  await waitFor(() => expect(screen.getByTestId("project-files-upload-failures")).toBeInTheDocument())

  // Dataset object: preview table over the full rows, stat grid, QC card under the table.
  fireEvent.click(screen.getByTestId("file-open-f-tbl"))
  await waitFor(() => expect(screen.getByTestId("dataset-preview-table")).toBeInTheDocument())
  await waitFor(() => expect(screen.getByTestId("data-perception")).toBeInTheDocument())
  return view.container
}

afterEach(() => {
  localStorage.clear()
  vi.restoreAllMocks()
})

describe("Data panel — one language at a time", () => {
  it("English UI contains no Chinese", async () => {
    const root = await renderSurfaces("english")
    const text = surfaceText(root)
    expect(text).toContain("What we saw in your data")
    expect(text).toContain("Why “Watch”")
    expect(text.match(/[　-〿一-鿿＀-￯]/g) ?? []).toEqual([])
  }, 30_000)

  it("Chinese UI contains no untranslated English UI text", async () => {
    const root = await renderSurfaces("chinese")
    const text = surfaceText(root)
    expect(text).toContain("数据概况")
    expect(text).toContain("为何“需关注”")
    expect(text).toContain("已加载 2 / 300 行")
    expect(text).toContain("超过 500 MB 的上传上限")
    // The profiler's free-text English is never shown in place of the structured findings.
    expect(text).not.toContain("free text")
    const leftover = leftoverEnglish(text)
    if (leftover.length) console.log("LEFTOVER", leftover, text.slice(0, 4000))
    expect(leftover).toEqual([])
  }, 30_000)
})
