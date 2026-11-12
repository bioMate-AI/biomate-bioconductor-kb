/**
 * Round 5 (2026-11-12 walkthrough): Chinese QC sentences showed stray spaces around interpolated
 * LABELS — "数值类型为 整数", "已读取 Matrix Market 稀疏矩阵 元数据", "内容是 文本——已按 文本 显示和检查",
 * "MAGeCK sgRNA 计数表 文件". A label rendered in the UI language is a word of the sentence: no
 * space between it and the Chinese around it. Counts / file names keep the CJK–Latin space.
 */
import { describe, it, expect } from "vitest"
import zh from "@/locales/zh/common.json"
import { LABEL_PARAMS } from "./data-perception"

const CJK = "[\\u3000-\\u303f\\u4e00-\\u9fff\\uff00-\\uffef]"
const LABEL = `\\{\\{\\s*(?:${LABEL_PARAMS.join("|")})\\s*\\}\\}`
const SPACED = new RegExp(`${CJK} ${LABEL}|${LABEL} ${CJK}`)

function strings(node: unknown, path: string, out: Array<[string, string]>) {
  if (typeof node === "string") out.push([path, node])
  else if (node && typeof node === "object") for (const [k, v] of Object.entries(node)) strings(v, `${path}.${k}`, out)
  return out
}

describe("zh: no space around an interpolated label next to Chinese", () => {
  it("every zh perception string", () => {
    const bad = strings((zh as any).perception, "perception", []).filter(([, s]) => SPACED.test(s))
    expect(bad).toEqual([])
  })
  it("the dataset panel's format sentences and the folder kind badge", () => {
    const z = zh as any
    for (const s of [z.dataset_obj.image_invalid, z.dataset_obj.preview_text_under_name]) expect(s).not.toMatch(SPACED)
    expect(z.folder_profile.kind_single_format).toBe("{{label}}文件")
  })
})
