/**
 * Tests for the Models module (rebuilt 2026-11-10):
 *   - ModelsPanel: the 5 tracks render; Registry lists catalog rows (from a
 *     mocked GET /api/models) and a row opens the model object.
 *   - ModelObject: identity + the evidence gate triple (measured · threshold ·
 *     verdict) + lineage/used-by/interface/versions tabs.
 *   - InferenceResultView: the infer→viewer routing by evidence class
 *     (structure→PlddtChart+PaeHeatmap, genomic→SeqTracks, chemical→HitGrid),
 *     plus the stub badge.
 *
 * Fetch is mocked at the network boundary (react-query talks to it) — no msw,
 * no route interception of a live server; these are unit tests of the client
 * contract, matching chat-output-attachments.test.tsx conventions.
 */

import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, fireEvent, waitFor, within } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"

import { ModelsPanel, HOUSE_STYLE_HIDDEN, tabIndexFromSearch, type OptimiseData, type TrainData } from "./models-panel"
import { MOLECULAR, unavailableReasonKey } from "./training-logic"
import { ModelObject } from "./model-object"
import { RunPretrained } from "./run-pretrained"
import { InferenceResultView } from "./inference-result"
import type { ModelDetail, StructureResult, GenomicResult, ChemicalResult } from "./types"

// ── react-query wrapper ──────────────────────────────────────────────────────
function wrapper() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  )
}

// ── fixtures matching the WS1 contract ───────────────────────────────────────
const CATALOG = [
  { id: "bionemo:boltz2", name: "Boltz-2", family: "structure", version: "2.0", origin: "self_host", usedByCount: 0 },
  { id: "bionemo:evo2_7b", name: "Evo2 7B", family: "genomic", version: "7b", origin: "self_host", usedByCount: 0 },
  { id: "custom:camp1/potency-gp", name: "potency-gp", family: "python", version: "1", origin: "custom", usedByCount: 2 },
]

const MODEL_DETAIL: ModelDetail = {
  identity: { name: "Boltz-2", version: "2.0", family: "structure", confidenceBand: null, origin: "self_host" },
  evidence: { gate: { measured: "0.81", threshold: "0.75", verdict: "pass" }, calibration: "0.04", evalSetId: "assay_2026_08.csv" },
  lineage: { datasetVersion: "assay_2026_08.csv · v4", trainingRunId: "camp1", priorVersions: ["v1"] },
  consumers: ["camp1", "camp2"],
  interface: { kind: "rest" },
  versions: [{ v: "2.0", verdict: "pass" }],
}

const STRUCTURE_RESULT: StructureResult = {
  run_id: "inf-1", status: "completed", evidenceClass: "structure",
  structureFileRef: "/tmp/inference-abc.cif",
  plddt: [95, 88, 60, 45, 91],
  pae: [[0, 3], [3, 0]],
  regions: [{ label: "Core 1–2", start: 1, end: 2 }],
}
const GENOMIC_RESULT: GenomicResult = {
  run_id: "inf-2", status: "completed", evidenceClass: "genomic",
  locus: "chr7:100–200",
  tracks: [{ kind: "marks", name: "evo2_generated", intervals: [{ start: 100, end: 140 }] }],
  flagged: [{ start: 120, end: 130, context: "generated", why: "novel region" }],
}
const CHEMICAL_STUB: ChemicalResult = {
  run_id: "inf-3", status: "completed", evidenceClass: "chemical",
  stub: true, stub_reason: "custom model not loaded in-process",
  hits: [
    { id: "cmpd-1", smiles: "CCO", score: null, confidence: "low", herg: null, drugLike: null, verdict: "held" },
  ],
}

beforeEach(() => {
  vi.restoreAllMocks()
})

// mock fetch by URL for the panel's react-query calls
function mockFetchByUrl(map: Record<string, unknown>) {
  map = { "/api/model-tracks/train": { runs: [] }, "/api/model-tracks/optimise": { active: false },
    "/api/model-training-versions": { versions: [] }, "/api/projects": { projects: [] }, ...map }
  // Longest key first so "/api/models/bionemo:boltz2" wins over "/api/models".
  const keys = Object.keys(map).sort((a, b) => b.length - a.length)
  global.fetch = vi.fn(async (input: RequestInfo | URL) => {
    const raw = typeof input === "string" ? input : input.toString()
    // Model ids are URL-encoded on the wire (colon → %3A); decode before matching.
    const url = decodeURIComponent(raw)
    const key = keys.find((k) => url.includes(k))
    if (!key) return { ok: false, status: 404, json: async () => ({}), text: async () => "not found" } as Response
    return { ok: true, status: 200, json: async () => map[key], text: async () => JSON.stringify(map[key]) } as Response
  }) as unknown as typeof fetch
}

// ─────────────────────────────────────────────────────────────────────────────
describe("ModelsPanel — tabs", () => {
  it("renders exactly the four tabs: Train · Model library · Design loop · Adapt", () => {
    mockFetchByUrl({ "/api/models": CATALOG })
    render(<ModelsPanel project="Test project" />, { wrapper: wrapper() })
    for (let i = 0; i < 4; i++) expect(screen.getByTestId(`models-track-${i}`)).toBeTruthy()
    expect(screen.queryByTestId("models-track-4")).toBeNull()
    const tabs = screen.getByTestId("models-tabs")
    expect(within(tabs).getByText("Train")).toBeTruthy()
    expect(within(tabs).getByText("Model library")).toBeTruthy()
    expect(within(tabs).getByText("Design loop")).toBeTruthy()
    expect(within(tabs).getByText("Adapt")).toBeTruthy()
  })

  it("surfaces the Adapt track but still hides the workflow-search / DL-FM sections", async () => {
    mockFetchByUrl({ "/api/models": CATALOG })
    render(<ModelsPanel project="Test project" />, { wrapper: wrapper() })
    // Adaptation is now a first-class, surfaced track.
    expect(HOUSE_STYLE_HIDDEN).toBe(false)
    expect(within(screen.getByTestId("models-tabs")).getByText("Adapt")).toBeTruthy()
    // The sections that were removed stay gone.
    expect(screen.queryByTestId("dl-fm-tab")).toBeNull()
    expect(screen.queryByTestId("dl-section-prebuilt")).toBeNull()
    // No workflow catalog search is issued from the Models panel any more.
    await waitFor(() => expect(screen.getByTestId("models-tabs")).toBeTruthy())
    const searched = (global.fetch as any).mock.calls.some((c: any[]) => String(c[0]).includes("/api/workflows/search"))
    expect(searched).toBe(false)
  })

  it("offers no chat-draft action anywhere in the module", async () => {
    mockFetchByUrl({ "/api/models": CATALOG })
    const { container } = render(<ModelsPanel project="Test project" />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("training-launcher-general")).toBeTruthy())
    expect(screen.queryByText(/in chat/i)).toBeNull()
    expect(screen.queryByText(/在聊天中/)).toBeNull()
    expect(container.querySelector('a[href*="draft="]')).toBeNull()
  })
})

describe("ModelsPanel — 训练 (Train) tab", () => {
  it("shows the launcher and an honest empty runs state with no data", async () => {
    mockFetchByUrl({ "/api/models": CATALOG })
    render(<ModelsPanel project="Test project" tab={0} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("training-launcher-general")).toBeTruthy())
    expect(await screen.findByTestId("train-runs-empty")).toBeTruthy()
  })

  it("renders training runs with status, a Run Manager link and the model link", async () => {
    mockFetchByUrl({ "/api/models/custom:camp1/potency-gp": MODEL_DETAIL, "/api/models": CATALOG })
    const TRAIN: TrainData = {
      runs: [
        { runId: "run-7", name: "potency-gp fit", family: "ml_training", when: "2026-08", status: "completed",
          gate: "gate passed", metric: "spearman 0.62", dataset: "assay_2026_08.csv",
          version: "→ potency-gp v2", modelId: "custom:camp1/potency-gp" },
        { runId: "run-8", name: "herg refit", family: "ml_training", when: "now", status: "running",
          gate: "Not recorded", metric: "Not recorded", dataset: "herg_panel.csv" },
      ],
    }
    render(<ModelsPanel project="Test project" tab={0} trainData={TRAIN} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("train-run-potency-gp fit")).toBeTruthy())
    expect(screen.getByTestId("train-run-status-potency-gp fit").textContent).toContain("Completed")
    expect(screen.getByTestId("train-run-status-herg refit").textContent).toContain("Running")
    // Opens the Run Manager on the all-chats scope (it has no per-run deep link).
    expect(screen.getByTestId("train-run-open-run-run-8").tagName).toBe("BUTTON")
    // "Not recorded" is localized, never leaked as the raw server token.
    expect(screen.getByTestId("train-run-herg refit").textContent).toContain("Not recorded")
    fireEvent.click(screen.getByTestId("train-run-open-potency-gp fit"))
    await waitFor(() => expect(screen.getByTestId("model-object")).toBeTruthy())
  })

  it("the model detail is not a dead end: 'Use in a run' lands on the run surface", async () => {
    mockFetchByUrl({ "/api/models/custom:camp1/potency-gp": MODEL_DETAIL, "/api/models": CATALOG })
    const TRAIN: TrainData = { runs: [
      { runId: "run-7", name: "potency-gp fit", family: "ml_training", when: "2026-08", status: "completed",
        gate: "gate passed", metric: "spearman 0.62", dataset: "assay.csv", modelId: "custom:camp1/potency-gp" },
    ] }
    // Uncontrolled tab so the handler's setTab actually switches the surface.
    render(<ModelsPanel project="Test project" trainData={TRAIN} />, { wrapper: wrapper() })
    fireEvent.click(await screen.findByTestId("train-run-open-potency-gp fit"))
    const useInRun = await screen.findByTestId("model-object-use-in-run")
    fireEvent.click(useInRun)
    // Detail closes and we land on the Library tab, where "Run a model" lives.
    await waitFor(() => expect(screen.queryByTestId("model-object")).toBeNull())
    expect(await screen.findByTestId("run-pretrained")).toBeTruthy()
  })
})

describe("ModelsPanel — 模型库 (Model library) tab", () => {
  it("lists catalog rows, opens a model, and shows WHY a model's last inference failed", async () => {
    mockFetchByUrl({
      "/api/models/bionemo:boltz2": MODEL_DETAIL,
      "/api/models": [
        ...CATALOG.slice(0, 1),
        { ...CATALOG[1], lastInference: { status: "failed", error: "BioNeMo openfold2 error 500: CUDA out of memory" } },
        { ...CATALOG[2], lastInference: { status: "completed" } },
      ],
      "/api/model-training-versions": { versions: [] },
    })
    render(<ModelsPanel project="Test project" tab={1} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("registry-table")).toBeTruthy())
    expect(screen.getByTestId("registry-row-bionemo:boltz2")).toBeTruthy()
    // The real backend reason is shown, not a bare "failed".
    const failure = screen.getByTestId("registry-row-failure-bionemo:evo2_7b")
    expect(failure.textContent).toContain("CUDA out of memory")
    expect(screen.queryByTestId("registry-row-failure-bionemo:boltz2")).toBeNull()
    expect(screen.queryByTestId("registry-row-failure-custom:camp1/potency-gp")).toBeNull()
    // Registry and "run a model" are merged into this one tab.
    expect(screen.getByTestId("run-pretrained")).toBeTruthy()
    expect(screen.getByTestId("owned-training-registry")).toBeTruthy()
    fireEvent.click(screen.getByTestId("registry-row-bionemo:boltz2"))
    await waitFor(() => expect(screen.getByTestId("model-object")).toBeTruthy())
  })

  it("a catalog row's Run preselects that model in 'Run a model'", async () => {
    mockFetchByUrl({ "/api/models": CATALOG, "/api/model-training-versions": { versions: [] } })
    render(<ModelsPanel project="Test project" tab={1} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("registry-table")).toBeTruthy())
    fireEvent.click(screen.getByTestId("registry-row-run-bionemo:boltz2"))
    await waitFor(() =>
      expect(screen.getByTestId("run-pretrained-model").textContent).toContain("Boltz-2"),
    )
  })

  it("only a registered (custom) model shows Remove, and it needs a two-step confirm", async () => {
    const posted: string[] = []
    global.fetch = vi.fn(async (url: any, init?: any) => {
      const u = String(url)
      if (init?.method === "POST" && u.includes("/disable")) { posted.push(u); return { ok: true, status: 200, json: async () => ({ removed: true }) } as any }
      const body = u.includes("/api/model-training-versions") ? { versions: [] } : u.includes("/api/models") ? CATALOG : {}
      return { ok: true, status: 200, json: async () => body, text: async () => JSON.stringify(body) } as any
    }) as unknown as typeof fetch
    render(<ModelsPanel project="Test project" tab={1} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("registry-row-remove-custom:camp1/potency-gp")).toBeTruthy())
    // A hosted (non-custom) model can't be removed.
    expect(screen.queryByTestId("registry-row-remove-bionemo:boltz2")).toBeNull()
    const btn = () => screen.getByTestId("registry-row-remove-custom:camp1/potency-gp")
    fireEvent.click(btn())                                   // arms the confirm
    expect(btn().textContent).toMatch(/Confirm/i)
    expect(posted).toHaveLength(0)                           // nothing sent on first click
    fireEvent.click(btn())                                   // confirms → POST
    await waitFor(() => expect(posted.some((u) => u.includes("/disable"))).toBe(true))
  })

  it("reports a catalog read failure instead of an empty library", async () => {
    mockFetchByUrl({ "/api/model-training-versions": { versions: [] } })
    render(<ModelsPanel project="Test project" tab={1} />, { wrapper: wrapper() })
    expect(await screen.findByTestId("registry-error")).toBeTruthy()
    expect(screen.queryByTestId("registry-empty")).toBeNull()
  })
})

describe("ModelsPanel — 分子学习 (Molecular learning) tab", () => {
  it("shows the molecular launcher, honest empty rounds, and real DMTA controls", async () => {
    mockFetchByUrl({ "/api/models": CATALOG })
    render(<ModelsPanel project="Test project" tab={2} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("training-launcher-molecular")).toBeTruthy())
    expect(await screen.findByTestId("optimise-empty")).toBeTruthy()
    expect(screen.getByTestId("optimise-controls")).toBeTruthy()
    expect(screen.getByTestId("optimise-create-campaign")).toBeTruthy()
    expect(screen.getByTestId("optimise-start")).toBeTruthy()
    expect(screen.getByTestId("optimise-stop")).toBeTruthy()
    expect(screen.getByTestId("optimise-trigger")).toBeTruthy()
    expect(screen.getByTestId("tab-purpose-molecular")).toBeTruthy()
    // Chemprop on Molecular (same path as chat Train) — not RDKit-only.
    expect(MOLECULAR).toContain("chemprop_gnn")
  })

  it("resolves /models?tab=molecular deep-link (Optimise / CRO retarget)", () => {
    expect(tabIndexFromSearch("?tab=molecular")).toBe(2)
    expect(tabIndexFromSearch("?tab=adapt")).toBe(3)
    expect(tabIndexFromSearch("?tab=3")).toBe(3)
    expect(tabIndexFromSearch("tab=library")).toBe(1)
    expect(tabIndexFromSearch("?tab=train")).toBe(0)
    expect(tabIndexFromSearch("")).toBeUndefined()
  })

  it("blocks the backend-unavailable model types so they can't be launched (regression: offered-but-failing)", () => {
    // These were offered in the dropdown but the backend rejects them → launch
    // always failed. Each must now return a reason key (→ launcher disables submit).
    expect(unavailableReasonKey("chemprop_gnn")).toBe("unavailable_chemprop_gnn")
    expect(unavailableReasonKey("tabular_diffusion")).toBe("unavailable_tabular_diffusion")
    expect(unavailableReasonKey("protein_diffusion")).toBe("unavailable_protein_diffusion")
    // A real, launchable type is NOT blocked.
    expect(unavailableReasonKey("sklearn_tabular")).toBeNull()
  })

  it("renders the DMTA loop, surrogate links and a safety-gate rejection that stays visible", async () => {
    mockFetchByUrl({ "/api/models/custom:camp1/potency-gp": MODEL_DETAIL, "/api/models": CATALOG })
    const LOOP: OptimiseData = {
      running: true, round: 3, budget: "96 assays", refitPolicy: "refit each round",
      surrogates: [{ id: "custom:camp1/potency-gp", label: "potency-gp v2" }],
      rounds: [{ round: "R3", status: "testing", what: "24 compounds at the bench", when: "today" }],
      proposal: [
        { id: "cmpd-1", score: "7.4", confidence: "medium", verdict: "accepted" },
        { id: "cmpd-2", score: "8.1", confidence: "high", verdict: "rejected · hERG gate" },
      ],
    }
    render(<ModelsPanel project="Test project" tab={2} optimiseData={LOOP} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("optimise-loop")).toBeTruthy())
    expect(screen.getByTestId("optimise-loop-state").textContent).toContain("3")
    expect(screen.getByTestId("optimise-proposal-verdict-cmpd-2").textContent).toContain("rejected")
    fireEvent.click(screen.getByTestId("optimise-surrogate-custom:camp1/potency-gp"))
    await waitFor(() => expect(screen.getByTestId("model-object")).toBeTruthy())
  })

  it("renders a fetched loop, and honest-empty when the backend says inactive", async () => {
    mockFetchByUrl({ "/api/models": CATALOG, "/api/model-tracks/optimise": {
      running: false, round: 1, surrogates: [], rounds: [{ round: "R1", status: "done", what: "seed", when: "y" }], proposal: [],
    } })
    const { unmount } = render(<ModelsPanel project="P" tab={2} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("optimise-round-R1")).toBeTruthy())
    unmount()
    mockFetchByUrl({ "/api/models": CATALOG, "/api/model-tracks/optimise": { active: false } })
    render(<ModelsPanel project="P" tab={2} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("optimise-empty")).toBeTruthy())
  })
})

describe("ModelObject", () => {
  it("renders the evidence gate triple (measured · threshold · verdict)", () => {
    render(<ModelObject detail={MODEL_DETAIL} modelId="bionemo:boltz2" />, { wrapper: wrapper() })
    expect(screen.getByTestId("model-gate-measured").textContent).toBe("0.81")
    expect(screen.getByTestId("model-gate-threshold").textContent).toBe("0.75")
    expect(screen.getByTestId("model-gate-verdict").textContent).toContain("pass")
  })

  it("shows lineage, consumers, interface kind and versions on their tabs", async () => {
    render(<ModelObject detail={MODEL_DETAIL} modelId="bionemo:boltz2" />, { wrapper: wrapper() })

    // Radix Tabs activate on mousedown (pointer), not click, in jsdom.
    fireEvent.mouseDown(screen.getByTestId("model-tab-used"))
    await waitFor(() => expect(screen.getByTestId("model-consumer-camp1")).toBeTruthy())

    fireEvent.mouseDown(screen.getByTestId("model-tab-iface"))
    await waitFor(() => expect(screen.getByTestId("model-iface-kind").textContent).toContain("rest"))

    fireEvent.mouseDown(screen.getByTestId("model-tab-versions"))
    await waitFor(() => expect(screen.getByTestId("model-version-2.0")).toBeTruthy())
  })

  it("renders a FAILING gate honestly \u2014 fail verdict, red, never a pass", () => {
    // Same shape as MODEL_DETAIL but the held-out gate did not clear.
    const FAILED: ModelDetail = {
      ...MODEL_DETAIL,
      evidence: {
        gate: { measured: "0.61", threshold: "0.75", verdict: "fail" },
        calibration: "0.12",
        evalSetId: "assay_2026_08.csv",
      },
      versions: [{ v: "2.0", verdict: "fail" }],
    }
    render(<ModelObject detail={FAILED} modelId="bionemo:boltz2" />, { wrapper: wrapper() })

    const verdict = screen.getByTestId("model-gate-verdict")
    // The verdict text is the honest word, not "pass".
    expect(verdict.textContent).toContain("fail")
    expect(verdict.textContent).not.toContain("pass")
    // Colour is the fail token (--bm-err, dark-adaptive oklch), not the pass token (--bm-ok).
    expect(verdict.getAttribute("style") || "").toContain("var(--bm-err)")
    expect(verdict.getAttribute("style") || "").not.toContain("var(--bm-ok)")
    // The measured value is below threshold \u2014 the numbers back the verdict.
    expect(screen.getByTestId("model-gate-measured").textContent).toBe("0.61")
    expect(screen.getByTestId("model-gate-threshold").textContent).toBe("0.75")
  })

  it("renders a not_evaluated gate honestly \u2014 neutral verdict, no fabricated pass", () => {
    // WS1 thin layer reports not_evaluated when there is no measured gate.
    const NOT_EVAL: ModelDetail = {
      ...MODEL_DETAIL,
      evidence: {
        gate: { measured: null, threshold: null, verdict: "not_evaluated" },
        calibration: null,
        evalSetId: null,
      },
      versions: [{ v: "2.0", verdict: "not_evaluated" }],
    }
    render(<ModelObject detail={NOT_EVAL} modelId="bionemo:boltz2" />, { wrapper: wrapper() })

    const verdict = screen.getByTestId("model-gate-verdict")
    expect(verdict.textContent).toContain("not_evaluated")
    // Crucially NOT presented as a pass.
    expect(verdict.textContent).not.toContain("pass")
    // Neutral token (--bm-text-dim), neither the pass token (--bm-ok) nor fail (--bm-err).
    const style = verdict.getAttribute("style") || ""
    expect(style).toContain("var(--bm-text-dim)")
    expect(style).not.toContain("var(--bm-ok)") // pass
    expect(style).not.toContain("var(--bm-err)") // fail
    // Un-measured gate shows the honest em-dash, not a fabricated number.
    expect(screen.getByTestId("model-gate-measured").textContent).toBe("\u2014")
    expect(screen.getByTestId("model-gate-threshold").textContent).toBe("\u2014")
  })

  it("renders lineage/consumers/versions as objects: clickable links + interface signature + header actions", async () => {
    const onOpenData = vi.fn()
    const onOpenRun = vi.fn()
    const onOpenConsumer = vi.fn()
    const onUseInRun = vi.fn()
    const onSupersede = vi.fn()
    render(
      <ModelObject
        detail={MODEL_DETAIL}
        modelId="bionemo:boltz2"
        onOpenData={onOpenData}
        onOpenRun={onOpenRun}
        onOpenConsumer={onOpenConsumer}
        onUseInRun={onUseInRun}
        onSupersede={onSupersede}
      />,
      { wrapper: wrapper() },
    )

    // Header actions
    fireEvent.click(screen.getByTestId("model-object-use-in-run"))
    expect(onUseInRun).toHaveBeenCalledWith("bionemo:boltz2")
    fireEvent.click(screen.getByTestId("model-object-supersede"))
    expect(onSupersede).toHaveBeenCalledWith("bionemo:boltz2")

    // Lineage rows are objects, not strings
    fireEvent.mouseDown(screen.getByTestId("model-tab-lineage"))
    await waitFor(() => expect(screen.getByTestId("lineage-dataset-link")).toBeTruthy())
    fireEvent.click(screen.getByTestId("lineage-dataset-link"))
    expect(onOpenData).toHaveBeenCalledWith("assay_2026_08.csv · v4")
    fireEvent.click(screen.getByTestId("lineage-run-link"))
    expect(onOpenRun).toHaveBeenCalledWith("camp1")

    // Consumer "open →" fires the callback
    fireEvent.mouseDown(screen.getByTestId("model-tab-used"))
    await waitFor(() => expect(screen.getByTestId("model-consumer-open-camp1")).toBeTruthy())
    fireEvent.click(screen.getByTestId("model-consumer-open-camp1"))
    expect(onOpenConsumer).toHaveBeenCalledWith("camp1")

    // Interface signature line is present (derived from kind: rest)
    fireEvent.mouseDown(screen.getByTestId("model-tab-iface"))
    await waitFor(() =>
      expect(screen.getByTestId("model-iface-signature").textContent).toContain("infer"),
    )
  })
})

describe("InferenceResultView — routing by evidence class", () => {
  it("structure → 3D slot + PlddtChart + PaeHeatmap", () => {
    render(<InferenceResultView result={STRUCTURE_RESULT} evidenceClass="structure" />, { wrapper: wrapper() })
    expect(screen.getByTestId("inference-result").getAttribute("data-evidence-class")).toBe("structure")
    expect(screen.getByTestId("inference-structure-slot")).toBeTruthy()
    expect(screen.getByTestId("plddt-chart")).toBeTruthy()
    expect(screen.getByTestId("pae-heatmap")).toBeTruthy()
  })

  it("structure → clicking a pLDDT residue centres the 3D selection (one selection, not two)", () => {
    // Spec 03 §3.8.1: chart selection and structure selection are one. The
    // inference backend returns a file ref (not a fetchable dataset) so the 3D
    // slot names the residue it would centre on rather than faking a viewer.
    render(<InferenceResultView result={STRUCTURE_RESULT} evidenceClass="structure" />, { wrapper: wrapper() })
    const slot = screen.getByTestId("inference-structure-slot")
    // Pre-selection: no residue chosen.
    expect(slot.getAttribute("data-selected-residue")).toBe("")
    expect(screen.queryByTestId("inference-structure-selection")).toBeNull()
    // Click the 3rd bar → 1-based residue 3.
    fireEvent.click(screen.getByTestId("plddt-bar-2"))
    expect(slot.getAttribute("data-selected-residue")).toBe("3")
    expect(screen.getByTestId("inference-structure-selection").textContent).toContain("residue 3")
  })

  it("genomic → SeqTracks with the flagged intervals", () => {
    render(<InferenceResultView result={GENOMIC_RESULT} evidenceClass="genomic" />, { wrapper: wrapper() })
    expect(screen.getByTestId("seq-tracks")).toBeTruthy()
    expect(screen.getByTestId("seq-flagged")).toBeTruthy()
  })

  it("chemical stub → HitGrid + a stub badge, no fabricated score", () => {
    render(<InferenceResultView result={CHEMICAL_STUB} evidenceClass="chemical" />, { wrapper: wrapper() })
    expect(screen.getByTestId("hit-grid")).toBeTruthy()
    expect(screen.getByTestId("inference-stub-badge")).toBeTruthy()
    // held hit shows "held", never a fabricated number
    expect(screen.getByTestId("hit-score-cmpd-1").textContent).toContain("held")
  })
})

describe("RunPretrained — full infer→poll→viewer flow", () => {
  it("submits chemical inference and renders HitGrid when the run completes", async () => {
    // The whole flow through the WS1 endpoints: catalog → POST infer → poll result.
    mockFetchByUrl({
      "/api/inference/inf-9/result": {
        run_id: "inf-9",
        status: "completed",
        evidenceClass: "chemical",
        hits: [
          { id: "cmpd-1", smiles: "CCO", score: 7.4, confidence: "medium", herg: "—", drugLike: "—", verdict: "held" },
        ],
      },
      "/api/models/custom:camp1/potency-gp/infer": { run_id: "inf-9" },
      "/api/models": CATALOG,
    })

    render(<RunPretrained />, { wrapper: wrapper() })

    // Pick the chemical domain (plain shadcn Button — click works in jsdom).
    fireEvent.click(screen.getByTestId("domain-chemical"))
    // Wait for the catalog to resolve so a concrete model id is chosen (the
    // submit button is disabled until a model is picked).
    await waitFor(() =>
      expect(screen.getByTestId("run-pretrained-model").textContent).toContain("potency-gp"),
    )
    fireEvent.change(screen.getByTestId("run-pretrained-input"), { target: { value: "CCO" } })
    fireEvent.click(screen.getByTestId("run-pretrained-submit"))

    // Poll resolves to completed → HitGrid routes in.
    await waitFor(() => expect(screen.getByTestId("result-status-completed")).toBeTruthy())
    expect(screen.getByTestId("hit-grid")).toBeTruthy()
    expect(screen.getByTestId("inference-chemical")).toBeTruthy()
  })

  it("shows a failed status + error when the inference run fails \u2014 not a stuck spinner or fake success", async () => {
    // The poll resolves to a terminal FAILED run carrying an error message.
    mockFetchByUrl({
      "/api/inference/inf-err/result": {
        run_id: "inf-err",
        status: "failed",
        evidenceClass: "chemical",
        error: "worker OOM: model process exited 137",
      },
      "/api/models/custom:camp1/potency-gp/infer": { run_id: "inf-err" },
      "/api/models": CATALOG,
    })

    render(<RunPretrained />, { wrapper: wrapper() })

    fireEvent.click(screen.getByTestId("domain-chemical"))
    await waitFor(() =>
      expect(screen.getByTestId("run-pretrained-model").textContent).toContain("potency-gp"),
    )
    fireEvent.change(screen.getByTestId("run-pretrained-input"), { target: { value: "CCO" } })
    fireEvent.click(screen.getByTestId("run-pretrained-submit"))

    // The failed badge appears \u2014 honest terminal state.
    await waitFor(() => expect(screen.getByTestId("result-status-failed")).toBeTruthy())
    expect(screen.getByTestId("result-status-failed").textContent).toContain("Failed")
    // The real backend error surfaces, not a generic placeholder.
    expect(screen.getByTestId("result-error").textContent).toContain("worker OOM")

    // A failed run must NOT fabricate a completed result or leave a spinner running.
    expect(screen.queryByTestId("result-status-completed")).toBeNull()
    expect(screen.queryByTestId("result-status-running")).toBeNull()
    expect(screen.queryByTestId("result-pending")).toBeNull()
    expect(screen.queryByTestId("hit-grid")).toBeNull()
  })
})

describe("Models activity failures", () => {
  it("shows an actionable error instead of an empty success on the Train tab", async () => {
    mockFetchByUrl({ "/api/models": CATALOG })
    const fetcher = global.fetch
    global.fetch = vi.fn(async (...args: Parameters<typeof fetch>) => {
      if (String(args[0]).includes("/api/model-tracks/")) return { ok: false, status: 503 } as Response
      return fetcher(...args)
    }) as typeof fetch
    render(<ModelsPanel tab={0} />, { wrapper: wrapper() })
    expect((await screen.findByRole("alert")).textContent).toContain("Could not load")
    expect(screen.getByRole("button", { name: "Retry" })).toBeTruthy()
    expect(screen.queryByTestId("train-runs-empty")).toBeNull()
  })

  it("rejects malformed successful responses instead of hiding saved work", async () => {
    mockFetchByUrl({ "/api/models": CATALOG, "/api/model-tracks/train": { unexpected: true } })
    render(<ModelsPanel tab={0} />, { wrapper: wrapper() })
    expect(await screen.findByRole("alert")).toBeTruthy()
  })

  it("does not offer a no-op model link for a run without a model", async () => {
    mockFetchByUrl({ "/api/models": CATALOG })
    render(<ModelsPanel tab={0} trainData={{ runs: [{ name: "job", family: "ml_training", when: "now",
      status: "running", gate: "Not recorded", metric: "Not recorded", dataset: "counts" }] }} />, { wrapper: wrapper() })
    expect(screen.queryByTestId("train-run-open-job")).toBeNull()
  })
})
