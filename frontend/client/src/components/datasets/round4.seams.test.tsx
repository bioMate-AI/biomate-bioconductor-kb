/**
 * Round-4 seams outside the dataset object (live dev walkthrough 2026-11-12), en + zh:
 *  N8  folder samples: download buttons wrap, file names break only after separators;
 *  N12 a missing-mate sample is labelled as what happens to it ("Missing mate — single-end");
 *      a single-format folder is "<label> files" (backend round 4 `single_format`), never "Mixed";
 *      tree icons tell PDF / TIFF / h5ad / BAM / PDB apart;
 *  N3  the backend's English format label in "Identified as Text" is shown in Chinese;
 *  backend round 4: an info-level near_constant (expected) is a neutral note, never a column flag.
 * The i18n locale is fixed at module load, so each language re-imports the modules.
 */
import { describe, it, expect, vi, afterEach } from "vitest"

const PAIRS = {
  path: "pairs", kind: "fastq_set", fileCount: 3,
  rollup: [{ format: "fastqsanger.gz", label: "FASTQ (gzip)", count: 3, pairs: 1 }],
  findings: [],
  fastq: {
    verdict: "mixed", patterns: ["Rs"],
    samples: [
      { sample: "S1", forward: "pairs/S1_R1.fastq.gz", reverse: "pairs/S1_R2.fastq.gz", status: "paired", dir: "pairs" },
      { sample: "S2", forward: "pairs/S2_R1.fastq.gz", reverse: null, status: "orphan", role: "forward", dir: "pairs" },
    ],
    orphans: ["pairs/S2_R1.fastq.gz"], singles: [],
  },
  samplesheet: {
    columns: ["sample", "fastq_1", "fastq_2"], filename: "samplesheet.csv", layout: "paired", pathBase: "project inputs",
    rows: [], csv: "",
    single: { columns: [], filename: "samplesheet_single_end.csv", layout: "single_end", pathBase: "project inputs", rows: [], csv: "" },
    excluded: ["pairs/S2_R1.fastq.gz"],
  },
}
const MAGECK = {
  path: "top/mageck_count", kind: "single_format", fileCount: 1,
  kindFormat: { format: "tabular", label: "MAGeCK counts", viewKind: "table" },
  rollup: [{ format: "tabular", label: "MAGeCK counts", count: 1, viewKind: "table" }], findings: [],
}

async function load(language: "english" | "chinese") {
  vi.resetModules()
  localStorage.setItem("biomate-user-settings", JSON.stringify({ language }))
  global.fetch = vi.fn(async (input: RequestInfo | URL) => {
    const p = new URL(String(input), "http://x").searchParams.get("path")
    const body = p === "pairs" ? PAIRS : MAGECK
    return { ok: true, status: 200, json: async () => body } as unknown as Response
  }) as unknown as typeof fetch
  const React = await import("react")
  const rtl = await import("@testing-library/react")
  const { QueryClient, QueryClientProvider } = await import("@tanstack/react-query")
  const { FolderProfileView } = await import("./folder-profile-view")
  const show = (path: string) => rtl.render(React.createElement(QueryClientProvider,
    { client: new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } }) },
    React.createElement(FolderProfileView, { projectId: "p1", path })))
  return { ...rtl, show }
}

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

describe("folder view (N8 / N12)", () => {
  it("en: missing mate says single-end; names break only after separators; the button row wraps", async () => {
    const { show, screen } = await load("english")
    const view = show("pairs")
    const s2 = await screen.findByTestId("folder-sample-row-S2")
    expect(s2).toHaveTextContent("Missing mate — single-end")
    expect(s2).not.toHaveTextContent("Orphan")
    // S1_R1.<wbr>fastq.<wbr>gz — break opportunities only after _ and .
    const r1 = view.container.querySelector('[data-testid="folder-sample-row-S1"] [data-testid="folder-sample-read1"]')!
    expect(r1.querySelectorAll("wbr").length).toBe(3)
    expect(r1.className).not.toMatch(/anywhere/)
    expect(screen.getByTestId("folder-samples-head").className).toMatch(/flex-wrap/)
  })

  it("zh: the missing-mate label and a single-format folder's kind", async () => {
    const { show, screen } = await load("chinese")
    show("pairs")
    expect(await screen.findByTestId("folder-sample-row-S2")).toHaveTextContent("缺少配对——按单端")
    const { waitFor } = await import("@testing-library/react")
    show("top/mageck_count")
    await waitFor(() => expect(screen.getAllByTestId("folder-profile-kind").map((e) => e.textContent)).toContain("MAGeCK sgRNA 计数表 文件"))
    expect(screen.getAllByTestId("folder-profile-kind").map((e) => e.textContent).join(" ")).not.toContain("多种格式")
  })

  it("en: a single-format folder is '<label> files', not 'Mixed formats'", async () => {
    const { show, screen } = await load("english")
    show("top/mageck_count")
    expect(await screen.findByTestId("folder-profile-kind")).toHaveTextContent("MAGeCK counts files")
  })
})

describe("tree icons (N12)", () => {
  it("PDF, TIFF, h5ad, BAM, PDB and gzipped FASTQ each get their own icon", async () => {
    vi.resetModules()
    const { fileIcon } = await import("@/components/project-file-tree")
    const lucide = await import("lucide-react")
    expect(fileIcon("report.pdf")).toBe(lucide.FileType2)
    expect(fileIcon("scan.tiff")).toBe(lucide.FileImage)
    expect(fileIcon("pbmc.h5ad")).toBe(lucide.Grid3x3)
    expect(fileIcon("1.bam")).toBe(lucide.AlignLeft)
    expect(fileIcon("5e5z.pdb")).toBe(lucide.Atom)
    expect(fileIcon("S1_R1.fastq.gz")).toBe(lucide.Dna)
    expect(new Set(["report.pdf", "scan.tiff", "pbmc.h5ad", "1.bam", "5e5z.pdb"].map((n) => fileIcon(n))).size).toBe(5)
    expect(fileIcon("weird.xyz")).toBe(lucide.File)
  })
})

describe("finding text (N3) and expected near-constant columns (backend round 4)", () => {
  it("zh: 'Identified as Text' shows the format label in Chinese", async () => {
    vi.resetModules()
    localStorage.setItem("biomate-user-settings", JSON.stringify({ language: "chinese" }))
    const { findingText } = await import("@/components/data-perception")
    const text = findingText({ section: "note", code: "format_identified", level: "info", params: { format: "Text", size: "20 B" } })
    expect(text).toContain("文本")
    expect(text).not.toContain("Text")
  })

  it("an info-level near_constant is a neutral note with its reason, and flags no column", async () => {
    vi.resetModules()
    const React = await import("react")
    const rtl = await import("@testing-library/react")
    const { DataPerception } = await import("@/components/data-perception")
    const { computeColumnStats } = await import("./dataset-columns-view")
    const f = { section: "signal" as const, code: "near_constant", level: "info" as const, params: { count: 1, columns: ["batch"], pct: 95, expected: "few_rows" } }
    rtl.render(React.createElement(DataPerception, {
      profile: { shape: { rows: 5, cols: 2 }, quality: "good", notes: [], columns: ["id", "batch"], findings: [f] } as any,
    }))
    const line = rtl.screen.getAllByTestId("perception-finding").find((e) => e.getAttribute("data-code") === "near_constant")!
    expect(line).toHaveTextContent("Expected with this few rows — not flagged.")
    expect(rtl.screen.queryByText(/Why “Watch”/)).toBeNull()
    const stats = computeColumnStats(["id", "batch"], [["a", "x"], ["b", "x"]], [f])
    expect(stats.find((s) => s.name === "batch")!.watch).toBe(false)
    // A watch-level near_constant still flags it (control).
    const watch = computeColumnStats(["id", "batch"], [["a", "x"], ["b", "x"]], [{ ...f, level: "watch" as const }])
    expect(watch.find((s) => s.name === "batch")!.watch).toBe(true)
  })
})
