/**
 * Chinese UI: every chat surface Track D touched renders in Chinese only — no
 * missing key and no untranslated English UI words. Allowed Latin tokens are
 * proper nouns / scientific identifiers / user data (paper titles etc.).
 */
import { describe, expect, it, vi } from "vitest"
vi.mock("3dmol", () => ({ default: {}, GLViewer: class {}, createViewer: () => ({}) }))
vi.mock("@/lib/i18n", async () => {
  const { strictI18n } = await import("./i18n-strict-mock")
  const zh = (await import("@/locales/zh/common.json")).default
  return strictI18n(zh as any, "zh")
})
vi.mock("@/lib/api", () => ({ api: { request: vi.fn(async () => ({ found: true, openAccess: false, fullTextStatus: "not_open_access", sections: [], abstract: null, links: { publisher: "https://doi.org/10.1/x", europepmc: null } })) } }))
import { renderChatSurfaces, DATA_STRINGS } from "./chat-surfaces.harness"
import { COLD_DOMAINS } from "@/components/cold-start-dashboard"

// A sample dataset's `ref` is its provenance (accession, authors, journal, R dataset) shown in the
// badge tooltip — data, like DATA_STRINGS, never UI copy to translate.
const SAMPLE_REFS = COLD_DOMAINS.flatMap((d) => d.shapes.map((sh) => sh.sampleDataset?.ref).filter(Boolean)) as string[]

/** Proper nouns, product names, file names and scientific identifiers. */
const ALLOWED = new Set(`BioMate PubMed Europe PMC DOI PMID SMILES SDF ADMET hERG logP IC50 GO RNA seq DESeq2 ChIP ATAC MACS CTCF EBV VCA EA EBNA1 MiniLibCas9 Brunello LFQ Analyst Mayo
CAR CD19 Cox LFQ proteinGroups SNF CRISPR AChR PBMC PBMCs counts_matrix csv contrasts SAR FTO APA BibTeX h5ad x cryo EM airway CDR CDRs
QC FDR µM IgG IgM nf core rnaseq EPAR STAR HISAT2 Genome Biology Love MI T
GMT UTC MG IC h ad GSE EBNA CD`.split(/\s+/))

describe("chat surfaces — zh locale", () => {
  it("contain no missing keys and no untranslated English UI words", async () => {
    let text = await renderChatSurfaces("中文回答。", "按年份统计 EPAR 审批")
    expect(text).not.toMatch(/⟦MISSING:[^⟧]+⟧/)
    for (const d of [...DATA_STRINGS, ...SAMPLE_REFS]) text = text.split(d).join(" ")
    // All-caps identifiers (gene symbols LRRK2/ABL1/KRAS, mutations G12C, PD-1/PD-L1,
    // acronyms) are proper nouns in Chinese scientific text, not untranslated UI English —
    // a fixed word list cannot enumerate every gene a user or example names. Untranslated UI
    // copy ("Open", "Training runs") is mixed-case and is still caught.
    const words = (text.match(/[A-Za-z][A-Za-z0-9_]*/g) || [])
      .filter((w) => !ALLOWED.has(w) && !/^[A-Z][A-Z0-9_]*$/.test(w))
    expect([...new Set(words)]).toEqual([])
    for (const s of ["1 个来源", "检索 · 保留 4 / 24", "阅读", "运行中", "打开", "新对话", "哪里有问题？", "您想做什么？"]) {
      expect(text).toContain(s)
    }
  }, 60_000)
})
