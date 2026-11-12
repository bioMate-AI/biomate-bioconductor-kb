/**
 * Every code the backend profiler can emit has natural en + zh text (audit 2026-11-12):
 * a finding without a locale key renders as its raw code in the QC card. The code list is
 * extracted from the profiler source (perception-finding-codes.json — the sparse frontend
 * checkout has no backend; regenerate the JSON when the profiler adds a code). `enText` is the
 * profiler's English template table (_EN_TEXT): the en locale says exactly the same.
 */
import { describe, it, expect } from "vitest"
import codes from "./perception-finding-codes.json"
import en from "@/locales/en/common.json"
import zh from "@/locales/zh/common.json"
import { VIEW_KINDS } from "./datasets/dataset-view-model"

const PLACEHOLDER = /{{\s*(\w+)\s*}}/g
const vars = (s: string) => new Set(Array.from(s.matchAll(PLACEHOLDER), (m) => m[1]))
const msg = (l: any) => l.perception.msg as Record<string, string>

describe("perception locale coverage", () => {
  for (const [lang, loc] of [["en", en], ["zh", zh]] as const) {
    it(`${lang}: every finding code has text (and every plan code its _effect)`, () => {
      const m = msg(loc)
      const missing = codes.findings.filter((c) => !m[c])
      const missingEffects = codes.plan.filter((c) => !m[`${c}_effect`])
      expect(missing).toEqual([])
      expect(missingEffects).toEqual([])
    })
    it(`${lang}: every stat code has a label`, () => {
      const s = (loc as any).perception.stat as Record<string, string>
      expect(codes.stats.filter((c) => !s[c])).toEqual([])
    })
  }

  it("zh keeps every value the en text states (no dropped params)", () => {
    const bad = codes.findings.filter((c) => {
      const a = vars(msg(en)[c] ?? ""), b = vars(msg(zh)[c] ?? "")
      return [...a].some((v) => !b.has(v))
    })
    expect(bad).toEqual([])
  })

  it("no template uses the retired {{prefix}} (counts say 'at least' themselves)", () => {
    for (const loc of [en, zh]) {
      expect(Object.entries(msg(loc)).filter(([, v]) => v.includes("{{prefix}}")).map(([k]) => k)).toEqual([])
    }
  })

  // en wording the client deliberately leads with (the profiler's _EN_TEXT should adopt it). Each
  // entry is justified; the test below fails once an entry is no longer needed.
  const CLIENT_AHEAD_OF_PROFILER: Record<string, string> = {
    // Round-3 seams scientist wording (d71cfa7743, W7 "in plain words"): "groups are balanced, no
    // column gives the group away" instead of the profiler's "no leakage, imbalance or
    // constant-column issues" — the same plain words as the QC card's "Groups (column)" section.
  }
  const enText = (codes as any).enText as Record<string, string>

  it("en locale equals the profiler's English template table (one wording, chat + logs + card)", () => {
    const m = msg(en)
    const differ = Object.keys(enText).filter((k) => m[k] !== enText[k] && !(k in CLIENT_AHEAD_OF_PROFILER))
    expect(differ.map((k) => [k, m[k], enText[k]])).toEqual([])
  })

  it("every client-ahead exemption is still needed (and still differs)", () => {
    const m = msg(en)
    expect(Object.keys(CLIENT_AHEAD_OF_PROFILER).filter((k) => !(k in enText) || m[k] === enText[k])).toEqual([])
    // The client wording keeps every value the profiler's states.
    for (const k of Object.keys(CLIENT_AHEAD_OF_PROFILER)) {
      expect([...vars(enText[k])].filter((v) => !vars(m[k]).has(v))).toEqual([])
    }
  })

  it("en templates state every value in the profiler's template (no dropped params)", () => {
    const m = msg(en)
    const bad = Object.keys(enText).filter((k) => [...vars(enText[k])].some((v) => !vars(m[k] ?? "").has(v)))
    expect(bad).toEqual([])
  })

  it("the panel's view-kind vocabulary is exactly the profiler's", () => {
    expect([...VIEW_KINDS].sort()).toEqual([...codes.viewKinds].sort())
  })
})
