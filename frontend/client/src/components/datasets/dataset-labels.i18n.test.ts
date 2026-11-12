/**
 * Round-2 untranslated strings (2026-11-12 audit): format labels the profiler sends in English
 * ("Binary", "Python script", "Tar archive (gzip)" …), the file tree's root folder name, and the
 * BAM sort order inside `alignment_not_coordinate_sorted`. The i18n locale is resolved at module
 * load, so each test re-imports the modules after setting the stored language preference.
 */
import { describe, it, expect, vi, afterEach } from "vitest"

afterEach(() => { localStorage.clear(); vi.resetModules() })

async function inLocale(lang: "chinese" | "english") {
  vi.resetModules()
  localStorage.setItem("biomate-user-settings", JSON.stringify({ language: lang }))
  const presentation = await import("./dataset-presentation")
  const perception = await import("@/components/data-perception")
  const tree = await import("@/components/project-file-tree")
  return { ...presentation, ...perception, ...tree }
}

// Backend labels (data_perception.py _BIOMATE_LABELS / _BINARY_NAME_FORMATS / _table_format,
// galaxy_formats.py _LABELS / humanize_ext) as {ext, label} pairs the profile carries.
const ZH: Array<[{ ext: string; label: string }, string]> = [
  [{ ext: "binary", label: "Binary" }, "二进制文件"],
  [{ ext: "txt", label: "Text" }, "文本"],
  [{ ext: "txt", label: "Text (one value per line)" }, "文本（每行一个值）"],
  [{ ext: "py", label: "Python script" }, "Python 脚本"],
  [{ ext: "docx", label: "Word document" }, "Word 文档"],
  [{ ext: "sqlite", label: "SQLite database" }, "SQLite 数据库"],
  [{ ext: "db", label: "SQLite database" }, "SQLite 数据库"],
  [{ ext: "tgz", label: "Tar archive (gzip)" }, "Tar 归档（gzip 压缩）"],
  [{ ext: "tar", label: "Tar archive" }, "Tar 归档"],
  [{ ext: "log", label: "Log (text)" }, "日志（文本）"],
  [{ ext: "csv", label: "CSV (semicolon-separated)" }, "CSV（分号分隔）"],
  [{ ext: "fastqsanger.gz", label: "FASTQ (gzip)" }, "FASTQ（gzip 压缩）"],
  [{ ext: "fast5.tar.gz", label: "FAST5 archive (tar.gz)" }, "FAST5 归档（tar.gz）"],
  [{ ext: "xlsx", label: "Excel (xlsx)" }, "Excel 表格（xlsx）"],
  [{ ext: "unknown", label: "Unknown" }, "未知格式"],
  // Format names are not translated.
  [{ ext: "bam", label: "BAM" }, "BAM"],
  [{ ext: "pdb", label: "PDB" }, "PDB"],
  // An unknown label falls back to the backend's text.
  [{ ext: "mothur.axes", label: "Mothur axes" }, "Mothur axes"],
]

describe("format labels", () => {
  it("zh: every backend label is shown in Chinese (or kept when it is a format name)", async () => {
    const { localizedFormatLabel } = await inLocale("chinese")
    for (const [format, zh] of ZH) expect(localizedFormatLabel(format), format.label).toBe(zh)
  })
  it("en: the backend label for THIS file, never another label of the same extension", async () => {
    const { localizedFormatLabel } = await inLocale("english")
    expect(localizedFormatLabel({ ext: "txt", label: "Text" })).toBe("Text")
    expect(localizedFormatLabel({ ext: "txt", label: "Text (one value per line)" })).toBe("Text (one value per line)")
    expect(localizedFormatLabel({ ext: "csv", label: "CSV (semicolon-separated)" })).toBe("CSV (semicolon-separated)")
    expect(localizedFormatLabel({ ext: "binary", label: "Binary" })).toBe("Binary")
  })
})

describe("file tree root", () => {
  it("zh: the inputs root is named 输入; its path (test ids, expand state) stays 'inputs'", async () => {
    const { buildTree } = await inLocale("chinese")
    const root = buildTree([{
      id: "1", name: "a.csv", s3_key: "projects/p1/inputs/a.csv", size: 1, content_type: "text/csv",
      source: "upload", run_id: null, workflow_name: null, step_name: null, input_context: null, created_at: null,
    } as any])[0] as any
    expect(root.name).toBe("输入")
    expect(root.path).toBe("inputs")
  })
})

describe("upload name conflict", () => {
  it("zh: names the existing entry", async () => {
    const { uploadErrorReason } = await inLocale("chinese")
    expect(uploadErrorReason(409, { code: "name_conflict", conflicts: [{ name: "a", existing: "a/b.csv" }] })).toBe("项目中的“a/b.csv”已使用该名称 — 请重命名其中之一后重试")
    expect(uploadErrorReason(409, null)).toBe("项目中已有同名的文件或文件夹")
  })
})

describe("alignment sort order", () => {
  // Backend (round 2): params {order (raw SO:), order_key ∈ unknown|unsorted|queryname|coordinate,
  // order_words (English)}; the client translates from order_key.
  const finding = (params: Record<string, unknown>) => ({
    section: "note" as const, code: "alignment_not_coordinate_sorted", level: "watch" as const, params,
  })
  it("en: the order_key's words, not the raw SO: value", async () => {
    const { findingText } = await inLocale("english")
    expect(findingText(finding({ order: "queryname", order_key: "queryname", order_words: "by read name" })))
      .toBe("Sort order is by read name, not by coordinate: sort the file before indexing or variant calling.")
    expect(findingText(finding({ order: "unknown", order_key: "unknown", order_words: "not stated in the header" })))
      .toContain("Sort order is not stated in the header,")
    // A value outside the vocabulary (or an older backend without order_key): quoted raw.
    expect(findingText(finding({ order: "weird", order_words: "“weird”" }))).toContain("Sort order is “weird”,")
    expect(findingText(finding({ order: "weird" }))).toContain("Sort order is “weird”,")
  })
  it("zh: every order_key reads in Chinese, never the English order_words", async () => {
    const { findingText } = await inLocale("chinese")
    expect(findingText(finding({ order: "queryname", order_key: "queryname", order_words: "by read name" })))
      .toBe("文件未按坐标排序（当前排序方式：按读段名）：建立索引或变异检测前请先按坐标排序。")
    expect(findingText(finding({ order: "unknown", order_key: "unknown", order_words: "not stated in the header" }))).toContain("文件头未注明")
    expect(findingText(finding({ order: "unsorted", order_key: "unsorted", order_words: "unsorted" }))).toContain("未排序")
    expect(findingText(finding({ order: "coordinate", order_key: "coordinate" }))).toContain("按坐标）")
    for (const k of ["unknown", "unsorted", "queryname"]) {
      expect(findingText(finding({ order: k, order_key: k, order_words: "by read name" }))).not.toMatch(/[A-Za-z]{3,}/)
    }
  })
})

describe("structure findings", () => {
  it("zh: the experimental method family is translated; the predictor name is kept", async () => {
    const { findingText } = await inLocale("chinese")
    expect(findingText({ section: "note", code: "structure_experimental", level: "info",
      params: { method: "X-RAY DIFFRACTION", method_key: "xray" } })).toBe("实验测定的结构（X 射线衍射）：B 因子列记录的是原子位移，而非预测置信度。")
    expect(findingText({ section: "note", code: "structure_predicted", level: "info",
      params: { predictor: "AlphaFold" } })).toContain("预测模型（AlphaFold）")
  })
  it("en: an 'other' method keeps the file's own wording", async () => {
    const { findingText } = await inLocale("english")
    expect(findingText({ section: "note", code: "structure_experimental", level: "info",
      params: { method: "SOLID-STATE NMR", method_key: "other" } })).toContain("Experimental structure (SOLID-STATE NMR)")
  })
})
