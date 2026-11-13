import React from "react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { render, screen, waitFor } from "@testing-library/react"
import { MarkdownReport, resolveSiblingImage } from "./markdown-report"

const files = [
  { id: "f1", name: "ADMET QC · 2026-11-12 16.28/fig1_score.png" },
  { id: "f2", name: "ADMET QC · 2026-11-12 16.28/ADMET_QC_Report.md" },
  { id: "f3", name: "Other chat · 2026-11-11 09.00/fig1_score.png" },
]
const report = "ADMET QC · 2026-11-12 16.28/ADMET_QC_Report.md"
afterEach(() => { vi.restoreAllMocks() })

describe("Markdown report figures (founder: md report no figures)", () => {
  it("a bare relative link resolves to the figure in the SAME chat folder", () => {
    expect(resolveSiblingImage("fig1_score.png", report, files)).toBe("f1")
    expect(resolveSiblingImage("./fig1_score.png", report, files)).toBe("f1")
    expect(resolveSiblingImage("missing.png", report, files)).toBeNull()
    expect(resolveSiblingImage("https://x/y.png", report, files)).toBeNull()
    expect(resolveSiblingImage("/abs.png", report, files)).toBeNull()
  })
  it("renders the figure from the project file", async () => {
    vi.spyOn(global, "fetch").mockResolvedValue({ ok: true, json: async () => ({ files }) } as any)
    render(<MarkdownReport text={"# QC\n\n![score](fig1_score.png)\n\n![gone](nope.png)"} projectId="p1" reportName={report} />)
    const img = await screen.findByTestId("markdown-figure")
    expect(img.getAttribute("src")).toBe("/api/projects/p1/files/f1/url?redirect=1")
    await waitFor(() => expect(screen.getByTestId("markdown-figure-missing")).toBeInTheDocument())
  })
})

import { buildTree, fileRowTitle, fileTime } from "../project-file-tree"
describe("generated files: one folder per chat, with time (founder screenshot)", () => {
  it("run_code files nest under 分析结果 by chat folder", () => {
    const tree: any[] = buildTree([
      { id: "a", name: "ADMET QC · 2026-11-12 16.28/fig1.png", source: "run_code", size: 1, created_at: "2026-11-12T08:28:00Z" } as any,
      { id: "b", name: "Other · 2026-11-11 09.00/fig1.png", source: "run_code", size: 1, created_at: "2026-11-11T01:00:00Z" } as any,
    ])
    const analysis = tree.find((n) => n.path === "outputs/analysis")
    expect(analysis.children.map((c: any) => c.name)).toEqual(["ADMET QC · 2026-11-12 16.28", "Other · 2026-11-11 09.00"])
    expect(analysis.children[0].children[0].file.id).toBe("a")
  })
  it("file time is compact and local", () => {
    const d = new Date(2026, 10, 12, 16, 28)
    expect(fileTime(d, new Date(2026, 10, 13))).toBe("11-12 16:28")
    expect(fileTime(d, new Date(2027, 0, 1))).toBe("2026-11-12 16:28")
  })
  it("row hover title carries date + size (not shown inline)", () => {
    const d = new Date(2026, 10, 12, 16, 28)
    expect(fileRowTitle("umap_perturbation.png", { createdAt: d, size: 54600, now: new Date(2026, 10, 13) }))
      .toBe("umap_perturbation.png · 11-12 16:28 · 53.3 KB")
  })
})
