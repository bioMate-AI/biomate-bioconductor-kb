/**
 * One language at a time — the Models module never mixes zh and en.
 *
 * 1. Bundle level: every models.* key exists in BOTH en and zh, en has no CJK,
 *    and zh carries no English words except proper nouns / model and format
 *    names (the allowlist below). This covers keys only reached at runtime
 *    (model types, metrics, statuses, spec fields).
 * 2. Render level: the three tabs are rendered under each locale (the locale is
 *    resolved at module load from the stored language preference, so modules are
 *    re-imported per locale) and the DOM text is checked the same way, which
 *    also catches any string hard-coded in a component instead of i18n.
 */
import React from "react"
import { describe, it, expect, vi, afterEach } from "vitest"
import { render, cleanup, waitFor, fireEvent } from "@testing-library/react"
import enCommon from "@/locales/en/common.json"
import zhCommon from "@/locales/zh/common.json"

const CJK = /[㐀-鿿豈-﫿]/

// Proper nouns, product/model/format names and technical identifiers that stay
// in Latin script in a Chinese UI. Anything else in Latin script is a leak.
const LATIN_ALLOWED = new Set([
  "scikit", "learn", "ludwig", "lora", "qlora", "dpo", "grpo", "sft", "rl", "cpu", "llm", "scdiffusion", "rfdiffusion",
  // DPO preference-pair column identifiers (data field names, kept Latin in zh UI).
  "prompt", "chosen", "rejected",
  "rdkit", "smiles", "roc", "auc", "f1", "r²", "hugging", "face", "pdb", "cif", "h5ad", "csv", "tsv",
  "jsonl", "parquet", "plddt", "pae", "contig", "kl", "beta", "obs", "gpu", "id", "a30", "a33", "ai",
  "biomate", "nvidia", "boltz", "tabddpm", "tabsyn", "smollm2",
  // Molecular / DMTA product names that stay Latin in zh UI when they appear.
  "chemprop", "sklearn", "gnn", "evo2", "reinvent",
  // Code-path labels (language names + sandbox symbols kept in Latin script).
  "python", "r", "bash", "input", "files", "run", "code", "galaxy",
])

function latinWords(text: string): string[] {
  return (text.match(/[A-Za-z][A-Za-z0-9²]*/g) ?? []).map(w => w.toLowerCase())
}

function leaks(text: string, dataTokens: Set<string> = new Set()): string[] {
  return [...new Set(latinWords(text).filter(w => !LATIN_ALLOWED.has(w) && !dataTokens.has(w)))]
}

describe("models.* bundles", () => {
  const en = (enCommon as any).models as Record<string, string>
  const zh = (zhCommon as any).models as Record<string, string>

  it("has the same keys in en and zh", () => {
    expect(Object.keys(zh).sort()).toEqual(Object.keys(en).sort())
  })

  it("has no Chinese in any English string", () => {
    expect(Object.entries(en).filter(([, v]) => CJK.test(v)).map(([k]) => k)).toEqual([])
  })

  it("has no untranslated English in any Chinese string", () => {
    // Example inputs (sequences / SMILES) are data, identical in both locales.
    // _cols keys are literal CSV header identifiers — data, identical in both locales.
    const dataKeys = Object.keys(zh).filter(k => /^domain_(example|placeholder)_|_cols$/.test(k))
    const bad = Object.entries(zh)
      .filter(([k]) => !dataKeys.includes(k))
      .map(([k, v]) => [k, leaks(v.replace(/\{\{\s*\w+\s*\}\}/g, ""))] as const)
      .filter(([, words]) => words.length)
    expect(bad).toEqual([])
  })
})

// ── render under each locale ──────────────────────────────────────────────────
const PROJECT = "11111111-1111-4111-8111-111111111111"
const FILE = { id: "22222222-2222-4222-8222-222222222222", name: "expr.jsonl", s3_key: "k/expr.jsonl" }

vi.mock("@/contexts/active-project-context", () => ({
  useActiveProjectSafe: () => ({ activeProjectId: PROJECT, projects: [{ id: PROJECT, name: "P1" }], setActiveProjectId: () => {} }),
}))

const CATALOG = [
  { id: "bionemo:boltz2", name: "Boltz-2", family: "structure", version: "2.0", origin: "self_host", usedByCount: 0,
    lastInference: { status: "failed", error: "E500" } },
]
const LOOP = {
  running: true, round: 2, surrogates: [{ id: "m1", label: "m1" }],
  rounds: [{ round: "R2", status: "R", what: "x", when: "t" }],
  proposal: [{ id: "c1", score: "7.4", confidence: "x", verdict: "accepted" }],
}

function mockFetch() {
  global.fetch = vi.fn(async (input: RequestInfo | URL) => {
    const url = String(input)
    const body =
      url.includes("/files") ? { files: [FILE] }
      : url.includes("/api/perception/profile") ? { columns: ["g1", "g2", "subtype"], sampleRows: [["1", "2", "A"], ["3", "4", "B"]] }
      : url.includes("/api/model-tracks/train") ? { runs: [{ runId: "r1", name: "r1", family: "ml_training", when: "Not recorded",
          status: "running", gate: "Not recorded", metric: "Not recorded", dataset: "Not recorded" }] }
      : url.includes("/api/model-tracks/optimise") ? LOOP
      : url.includes("/api/model-training-versions") ? { versions: [] }
      : url.includes("/api/models") ? CATALOG
      : {}
    return { ok: true, status: 200, json: async () => body, text: async () => JSON.stringify(body) } as Response
  }) as unknown as typeof fetch
}

async function renderTabsUnder(language: "chinese" | "english"): Promise<string[]> {
  vi.resetModules()
  localStorage.setItem("biomate-user-settings", JSON.stringify({ language }))
  const { ModelsPanel } = await import("./models-panel")
  const { QueryClient, QueryClientProvider } = await import("@tanstack/react-query")
  const texts: string[] = []
  for (const tab of [0, 1, 2]) {
    mockFetch()
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    const { container, getByTestId, unmount } = render(
      <QueryClientProvider client={qc}><ModelsPanel project="P1" tab={tab} /></QueryClientProvider>,
    )
    if (tab === 1) {
      await waitFor(() => expect(container.querySelector('[data-testid="registry-row-failure-bionemo:boltz2"]')).toBeTruthy())
    } else {
      const family = tab === 0 ? "general" : "molecular"
      await waitFor(() => expect((getByTestId("launcher-dataset") as HTMLSelectElement).options.length).toBeGreaterThan(1))
      fireEvent.change(getByTestId("launcher-dataset"), { target: { value: `file:${FILE.id}` } })
      if (family === "general") {
        await waitFor(() => expect(container.querySelector('[data-testid="launcher-target"]')).toBeTruthy())
        await waitFor(() => expect(container.querySelector('[data-testid="train-run-r1"]')).toBeTruthy())
      } else {
        await waitFor(() => expect(container.querySelector('[data-testid="launcher-no-model-types"]')).toBeTruthy())
        await waitFor(() => expect(container.querySelector('[data-testid="optimise-loop"]')).toBeTruthy())
      }
    }
    // Join every text node (incl. each <option> label) with a separator so
    // adjacent labels are never fused into one pseudo-word.
    const parts: string[] = []
    const walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT)
    for (let n = walker.nextNode(); n; n = walker.nextNode()) parts.push(n.textContent ?? "")
    texts.push(parts.join(" "))
    unmount()
  }
  return texts
}

// Data rendered verbatim from fixtures (ids, names, column names, numbers).
const DATA_TOKENS = new Set(["p1", "expr", "jsonl", "g1", "g2", "subtype", "r1", "r2", "m1", "c1", "boltz", "bionemo",
  "boltz2", "structure", "self", "host", "e500", "x", "t", "r", "accepted", "a", "b", "smollm2", "huggingfacetb",
  "instruct", "m", "huggingface", "135m", "qlora", "none", "length", "keyword", "numeric_answer", "numeric", "answer",
  "cosine", "linear", "sqrt", "mktayiakqr", "acgtacgtacgt", "cc1", "nc1ccc", "nc1"])

afterEach(() => { cleanup(); localStorage.clear() })

describe("Models panel renders in exactly one language", () => {
  it("zh: no untranslated English anywhere in the three tabs", async () => {
    const texts = await renderTabsUnder("chinese")
    texts.forEach((text, tab) => {
      expect({ tab, leaks: leaks(text, DATA_TOKENS) }).toEqual({ tab, leaks: [] })
      expect(CJK.test(text)).toBe(true)
    })
  }, 30000)

  it("en: no Chinese anywhere in the three tabs", async () => {
    const texts = await renderTabsUnder("english")
    texts.forEach((text, tab) => {
      expect({ tab, cjk: (text.match(new RegExp(CJK.source, "g")) ?? []).join("") }).toEqual({ tab, cjk: "" })
    })
  }, 30000)
})
