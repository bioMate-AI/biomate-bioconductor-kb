import { describe, expect, it } from "vitest"
import {
  analyzeFolderChatUrl,
  filesUnderFolderPrefix,
  folderPathsFromFiles,
} from "./folder-as-input"
import {
  buildDatasetOptions,
  encodeDatasetSelection,
  parseDatasetSelection,
  resolveSelectionToFileIds,
} from "@/components/models/dataset-selection"

const FILES = [
  { id: "1", name: "pairs/S1_R1.fastq.gz", source: "upload" },
  { id: "2", name: "pairs/S1_R2.fastq.gz", source: "upload" },
  { id: "3", name: "pairs/deep/extra.txt", source: "upload" },
  { id: "4", name: "pairs_x/other.csv", source: "upload" },
  { id: "5", name: "pairs/qc.html", source: "run_output" },
  { id: "6", name: "top.csv", source: "upload" },
]

describe("folder-as-input", () => {
  it("builds an attachFolder chat URL for analysis", () => {
    expect(analyzeFolderChatUrl("proj-1", "pairs")).toBe("/?project=proj-1&attachFolder=pairs")
  })

  it("lists files under a folder prefix recursively, excluding run outputs and sibling folders", () => {
    expect(filesUnderFolderPrefix(FILES, "pairs").map((f) => f.name)).toEqual([
      "pairs/S1_R1.fastq.gz",
      "pairs/S1_R2.fastq.gz",
      "pairs/deep/extra.txt",
    ])
  })

  it("derives folder paths from file names", () => {
    expect(folderPathsFromFiles(FILES)).toEqual(["pairs", "pairs/deep", "pairs_x"])
  })
})

describe("dataset-selection (Models)", () => {
  it("encodes/parses file and folder selections", () => {
    expect(parseDatasetSelection(encodeDatasetSelection({ kind: "folder", folderPath: "train" }))).toEqual({
      kind: "folder", folderPath: "train",
    })
    expect(parseDatasetSelection(encodeDatasetSelection({ kind: "file", fileId: "abc" }))).toEqual({
      kind: "file", fileId: "abc",
    })
    expect(parseDatasetSelection("legacy-id")).toEqual({ kind: "file", fileId: "legacy-id" })
  })

  it("resolves a folder selection to every file id under the prefix", () => {
    const opts = buildDatasetOptions(FILES)
    expect(opts.some((o) => o.value === "folder:pairs" && o.label.includes("3 files"))).toBe(true)
    expect(resolveSelectionToFileIds(FILES, { kind: "folder", folderPath: "pairs" })).toEqual(["1", "2", "3"])
  })
})
