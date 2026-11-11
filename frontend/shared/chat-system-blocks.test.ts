import { describe, expect, it } from "vitest"
import { stripSystemBlocks, attachedNamesFromBlocks, titleSourceText, fallbackTitle, titleHasSystemBlock } from "./chat-system-blocks"

describe("chat system blocks → user-facing text", () => {
  const msg = "Summarise the EPAR approvals by year\n[BioMate dataset: epar.jsonl (id: 1b2c-33)]\n[Uploaded datasets: epar.jsonl: dataset_id=abc]"

  it("strips every block and keeps the user's words", () => {
    expect(stripSystemBlocks(msg)).toBe("Summarise the EPAR approvals by year")
    expect(stripSystemBlocks("Q\n[Attached files: a.pdf]\n[Paper content: a.pdf]\nlong paper text…")).toBe("Q")
    expect(stripSystemBlocks("[Galaxy dataset: x]  hi")).toBe("hi")
  })

  it("strips a block truncated by an upstream slice", () => {
    expect(stripSystemBlocks("Hello [BioMate dataset: epar.jsonl (id:")).toBe("Hello")
  })

  it("names attached files for chips / attachment-only titles", () => {
    expect(attachedNamesFromBlocks(msg)).toEqual(["epar.jsonl"])
    expect(attachedNamesFromBlocks("[Attached files: a.csv, b.csv]")).toEqual(["a.csv", "b.csv"])
  })

  it("titles never contain a raw block", () => {
    expect(fallbackTitle(msg)).toBe("Summarise the EPAR approvals by year")
    expect(fallbackTitle("[BioMate dataset: epar.jsonl (id: 1)]")).toBe("epar.jsonl")
    expect(titleSourceText("[Uploaded datasets: x.csv: dataset_id=1]")).toBe("x.csv")
    expect(fallbackTitle("请分析这个数据集里的审批趋势\n[BioMate dataset: a.csv (id: 1)]")).toBe("请分析这个数据集里的审批趋势")
    for (const t of [fallbackTitle(msg), fallbackTitle("[BioMate dataset: e.jsonl (id: 1)]")]) expect(titleHasSystemBlock(t)).toBe(false)
  })

  it("detects legacy titles that still carry a block", () => {
    expect(titleHasSystemBlock("[BioMate dataset: epar.jsonl (id:")).toBe(true)
    expect(titleHasSystemBlock("EPAR approvals")).toBe(false)
  })
})
