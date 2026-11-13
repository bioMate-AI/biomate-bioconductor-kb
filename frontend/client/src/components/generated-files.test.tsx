import React from "react"
import { describe, expect, it, vi } from "vitest"
import { render, screen } from "@testing-library/react"
vi.mock("wouter", () => ({ useLocation: () => ["/", vi.fn()] }))
import {
  GeneratedFiles,
  analysisFolderPath,
  chatFolderOf,
  fileDateLabel,
  groupSavedFilesByChat,
  savedFilesFromBlocks,
} from "./generated-files"
import { ancestorPaths, treeFolderOf } from "./project-file-tree"

const F = "ADMET QC · 2026-11-12 16.28"
const F2 = "Other chat · 2026-11-11 09.00"
const out = (names: string[], folder = F, createdAt?: string) => ({
  output_files: names.map((n, i) => ({
    name: n,
    size: 100 + i,
    project_file_id: `id-${n}`,
    project_id: "p1",
    project_file_name: `${folder}/${n}`,
    download_url: `/dl/${n}`,
    ...(createdAt ? { created_at: createdAt } : {}),
  })),
})
const blocks: any[] = [
  { tool_use_id: "t1", name: "run_code", result: { type: "tool_result", tool_use_id: "t1", name: "run_code", output: out(["ADMET_QC_Report.md"]) } },
  { tool_use_id: "t2", name: "run_code", result: { type: "tool_result", tool_use_id: "t2", name: "run_code", output: out(["ADMET_QC_Details.csv", "ADMET_QC_Report.md", "01_hERG.png"], F, "2026-11-12T08:28:00Z") } },
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

describe("generated files grouped under each chat with a date (founder: noTimeStamp)", () => {
  it("groups by the per-chat folder in project_file_name", () => {
    const files = [
      ...savedFilesFromBlocks([{ tool_use_id: "a", name: "run_code", result: { type: "tool_result", tool_use_id: "a", name: "run_code", output: out(["a.png"], F) } } as any]),
      ...savedFilesFromBlocks([{ tool_use_id: "b", name: "run_code", result: { type: "tool_result", tool_use_id: "b", name: "run_code", output: out(["b.png"], F2) } } as any]),
    ]
    expect(chatFolderOf(`${F}/a.png`)).toBe(F)
    expect(groupSavedFilesByChat(files).map((g) => [g.chat, g.files.map((f) => f.name)])).toEqual([
      [F, ["a.png"]],
      [F2, ["b.png"]],
    ])
  })
  it("renders a chat section header and a date beside each file name", () => {
    const mixed: any[] = [
      { tool_use_id: "t1", name: "run_code", result: { type: "tool_result", tool_use_id: "t1", name: "run_code", output: out(["fig1.png"], F, "2026-11-12T08:28:00Z") } },
      { tool_use_id: "t2", name: "run_code", result: { type: "tool_result", tool_use_id: "t2", name: "run_code", output: out(["fig2.png"], F2, "2026-11-11T01:00:00Z") } },
    ]
    render(<GeneratedFiles blocks={mixed} />)
    const titles = screen.getAllByTestId("generated-files-chat-title").map((el) => el.textContent)
    expect(titles).toEqual([F, F2])
    expect(screen.getAllByTestId("generated-file-time").length).toBe(2)
  })
  it("date prefers created_at; falls back to the chat-folder stamp", () => {
    const local = new Date(2026, 10, 12, 16, 28)
    const now = new Date(2026, 10, 13)
    const withAt = { id: "1", projectId: "p", name: "a.png", fullName: `${F}/a.png`, size: 1, createdAt: local.toISOString() }
    const noAt = { id: "2", projectId: "p", name: "b.png", fullName: `${F}/b.png`, size: 1 }
    expect(fileDateLabel(withAt, now)).toBe("11-12 16:28")
    expect(fileDateLabel(noAt, now)).toBe("11-12 16:28")
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
