/**
 * Backend round 5 (origin/fix/ds-r5-profiler-20261112 @ 80d7235769), client side:
 *  - `sample_groups_from_names` carries `groups: [{name, n}]` — shown as "ctrl (2) · treat (2)"
 *    (zh "ctrl（2）· treat（2）"), never "[object Object]";
 *  - `group_nested` (a confounded design) reads in both languages;
 *  - BED / GTF profiles now carry columnStats (annotation / identifier roles): an intervals /
 *    annotation file still gets its own single view — no Columns / Plot / Edit because of them.
 */
import React from "react"
import { describe, it, expect, vi, afterEach } from "vitest"
import { render, screen, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { findingText, type PerceptionFinding } from "@/components/data-perception"
import { datasetViewModel } from "./dataset-view-model"
import { DatasetObject } from "./dataset-object"

const GROUPS: PerceptionFinding = {
  section: "note", code: "sample_groups_from_names", level: "info",
  params: { groups: [{ name: "ctrl", n: 2 }, { name: "treat", n: 2 }] },
}
const NESTED: PerceptionFinding = {
  section: "leakage", code: "group_nested", level: "watch", params: { column: "batch", label: "condition" },
}

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

describe("sample groups by name", () => {
  it("en: 'ctrl (2) · treat (2)', never [object Object]", () => {
    const text = findingText(GROUPS)
    expect(text).toBe("Sample columns form groups by name: ctrl (2) · treat (2).")
    expect(text).not.toContain("[object Object]")
  })
  it("group_nested reads as a confounded design", () => {
    expect(findingText(NESTED)).toBe("Each value of “batch” occurs in only one group of “condition”, so batch and condition effects cannot be separated — a confounded design; dropping the column does not fix it.")
  })
  it("zh: 'ctrl（2）· treat（2）' and the nested design in Chinese", async () => {
    vi.resetModules()
    localStorage.setItem("biomate-user-settings", JSON.stringify({ language: "chinese" }))
    const zh = await import("@/components/data-perception")
    expect(zh.findingText(GROUPS)).toBe("样本列按名称分组：ctrl（2）· treat（2）。")
    const nested = zh.findingText(NESTED)
    expect(nested).toContain("“batch”的每个取值只出现在“condition”的一个组中")
    // No English beyond the two column names.
    expect(nested.replace(/batch|condition/g, "").match(/[A-Za-z]{2,}/g)).toBeNull()
  })
})

describe("intervals / annotation with columnStats keep their own view", () => {
  it("view model: no Columns / Plot / Edit for intervals or annotation, with or without columns", () => {
    for (const kind of ["intervals", "annotation"] as const) {
      const vm = datasetViewModel(kind, { name: kind === "intervals" ? "1.bed" : "a.gtf", hasColumns: true, versionable: true, projectFile: true })
      expect(vm.views).toEqual(["content"])
      expect(vm.canEdit).toBe(false)
    }
  })

  it("a BED profile with columnStats renders no view toggles and no plot", async () => {
    const ref = "projects/p1/inputs/1.bed"
    const cols = ["chrom", "chromStart", "chromEnd", "name", "score", "strand"]
    const rows = [["chr1", "100", "200", "a", "0", "+"], ["chr1", "300", "400", "b", "0", "-"]]
    global.fetch = vi.fn(async (input: RequestInfo | URL) => {
      const url = new URL(String(input), "http://x")
      const res = (status: number, body: unknown) => ({ ok: status < 400, status, json: async () => body, text: async () => "" }) as unknown as Response
      if (url.pathname === "/api/perception/profile") {
        return res(200, {
          shape: { rows: 2, cols: 6 }, quality: "good", notes: [], viewKind: "intervals", columns: cols, sampleRows: rows,
          stats: [{ code: "regions", value: 2 }],
          columnStats: cols.map((name) => ({ name, type: "numeric", present: 2, missing: 0, distinct: 2, role: name === "name" ? "identifier" : "annotation" })),
          findings: [],
        })
      }
      if (url.pathname.endsWith("/rows")) return res(200, { columns: cols, rows, headerRow: false, version: 1, offset: 0, limit: 200, totalRows: 2 })
      return res(200, { versions: [] })
    }) as unknown as typeof fetch
    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })}>
        <DatasetObject projectId="p1" dataset={{ id: "b", name: "1.bed", ref, size: 100, source: "upload" }} onDownload={() => {}} />
      </QueryClientProvider>,
    )
    await screen.findByTestId("data-perception")
    await waitFor(() => expect(screen.getByTestId("dataset-preview").getAttribute("data-kind")).toBe("intervals"))
    expect(screen.queryByTestId("dataset-preview-toggles")).toBeNull()
    expect(screen.queryByTestId("dataset-preview-toggle-plot")).toBeNull()
    expect(screen.queryByTestId("dataset-sample-plot")).toBeNull()
  })
})
