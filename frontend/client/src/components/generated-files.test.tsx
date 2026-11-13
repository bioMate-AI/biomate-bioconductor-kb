import React from "react"
import { describe, expect, it, vi } from "vitest"
import { render, screen } from "@testing-library/react"
vi.mock("wouter", () => ({ useLocation: () => ["/", vi.fn()] }))
import { GeneratedFiles, analysisFolderPath, generatedFileTitle, savedFilesFromBlocks } from "./generated-files"
import { ancestorPaths, treeFolderOf } from "./project-file-tree"

const F = "ADMET QC · 2026-11-12 16.28"
const out = (names: string[]) => ({ output_files: names.map((n, i) => ({ name: n, size: 100 + i, project_file_id: `id-${n}`, project_id: "p1", project_file_name: `${F}/${n}`, download_url: `/dl/${n}` })) })
const blocks: any[] = [
  { tool_use_id: "t1", name: "run_code", result: { type: "tool_result", tool_use_id: "t1", name: "run_code", output: out(["ADMET_QC_Report.md"]) } },
  { tool_use_id: "t2", name: "run_code", result: { type: "tool_result", tool_use_id: "t2", name: "run_code", output: out(["ADMET_QC_Details.csv", "ADMET_QC_Report.md", "01_hERG.png"]) } },
  { tool_use_id: "t3", name: "read_file", result: { type: "tool_result", tool_use_id: "t3", name: "read_file", output: { lines: [] } } },
]

describe("generated files in chat (founder: no links, files missing from the reply)", () => {
  it("every saved file of the reply, once each (latest), in save order", () => {
    expect(savedFilesFromBlocks(blocks).map((f) => f.name)).toEqual(["ADMET_QC_Details.csv", "ADMET_QC_Report.md", "01_hERG.png"])
  })
  it("links each file to the Data page and the header to the chat's folder", () => {
    render(<GeneratedFiles blocks={blocks} />)
    expect(screen.getAllByTestId("generated-file")).toHaveLength(3)
    const open = screen.getAllByTestId("generated-file-open")[0]
    expect(open.getAttribute("href")).toBe("/files?project=p1&file=id-ADMET_QC_Details.csv")
    const folder = screen.getByTestId("generated-files-folder").getAttribute("href")!
    expect(new URLSearchParams(folder.split("?")[1]).get("folder")).toBe(`outputs/analysis/${F}`)
    expect(screen.getAllByTestId("generated-file-download")[0].getAttribute("href")).toBe("/dl/ADMET_QC_Details.csv")
  })
  it("size is muted after the name and repeated on hover/title", () => {
    render(<GeneratedFiles blocks={blocks} />)
    const opens = screen.getAllByTestId("generated-file-open")
    const rows = screen.getAllByTestId("generated-file")
    expect(opens[0].textContent?.trim()).toBe("ADMET_QC_Details.csv")
    expect(opens[0].getAttribute("title")).toBe("ADMET_QC_Details.csv · 100 B")
    expect(rows[0].getAttribute("data-file-size")).toBe("100 B")
    expect(screen.getAllByTestId("generated-file-size")[0].textContent).toBe("100 B")
    expect(rows[0].textContent).toContain("ADMET_QC_Details.csv")
    expect(rows[0].textContent).toContain("100 B")
    expect(generatedFileTitle({ id: "1", projectId: "p", name: "a.png", fullName: "a.png", size: 2048 })).toBe("a.png · 2.0 KB")
  })
  it("nothing to show → no card", () => {
    const { container } = render(<GeneratedFiles blocks={[blocks[2]]} />)
    expect(container.textContent).toBe("")
  })
  it("folder paths match the tree", () => {
    expect(analysisFolderPath(`${F}/x.png`)).toBe(`outputs/analysis/${F}`)
    expect(treeFolderOf({ name: `${F}/x.png`, source: "run_code" } as any)).toBe(`outputs/analysis/${F}`)
    expect(treeFolderOf({ name: "run1/a.fq", source: "upload" } as any)).toBe("inputs/run1")
    expect(ancestorPaths(`outputs/analysis/${F}`)).toEqual(["outputs", "outputs/analysis", `outputs/analysis/${F}`])
  })
})

import { fireEvent } from "@testing-library/react"
import { OPEN_FILE_IN_PANEL, openFileInPanel } from "@/lib/file-panel-events"
describe("a generated file opens beside the chat (founder: no switching back and forth)", () => {
  it("the chat view handles the event; the link does not navigate away", () => {
    const seen: any[] = []
    const onOpen = (e: Event) => { e.preventDefault(); seen.push((e as CustomEvent).detail) }
    window.addEventListener(OPEN_FILE_IN_PANEL, onOpen)
    render(<GeneratedFiles blocks={blocks} />)
    fireEvent.click(screen.getAllByTestId("generated-file-open")[1])
    window.removeEventListener(OPEN_FILE_IN_PANEL, onOpen)
    expect(seen).toEqual([{ projectId: "p1", fileId: "id-ADMET_QC_Report.md" }])
  })
  it("with no chat view listening, the caller falls back to the Data page", () => {
    expect(openFileInPanel({ projectId: "p", fileId: "f" })).toBe(false)
  })
})
