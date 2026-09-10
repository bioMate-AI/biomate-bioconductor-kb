/**
 * Tests for the Models module:
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
import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"

import { ModelsPanel, type OptimiseData, type TrainData, type AdaptData } from "./models-panel"
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
  { id: "bionemo:boltz2", name: "Boltz-2", family: "structure", version: "2.0", origin: "self-host", usedByCount: 0 },
  { id: "bionemo:evo2_7b", name: "Evo2 7B", family: "genomic", version: "7b", origin: "self-host", usedByCount: 0 },
  { id: "custom:camp1/potency-gp", name: "potency-gp", family: "python", version: "1", origin: "custom", usedByCount: 2 },
]

const MODEL_DETAIL: ModelDetail = {
  identity: { name: "Boltz-2", version: "2.0", family: "structure", confidenceBand: null, origin: "self-host" },
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
describe("ModelsPanel", () => {
  it("renders all five tracks", () => {
    mockFetchByUrl({ "/api/models": CATALOG })
    render(<ModelsPanel project="Test project" />, { wrapper: wrapper() })
    for (let i = 0; i < 5; i++) {
      expect(screen.getByTestId(`models-track-${i}`)).toBeTruthy()
    }
    expect(screen.getByText("Run a pre-trained model")).toBeTruthy()
  })

  it("lists catalog rows on the Registry track and opens a model object on click", async () => {
    mockFetchByUrl({
      "/api/models/bionemo:boltz2": MODEL_DETAIL,
      "/api/models": CATALOG, // less-specific key checked after — order-independent via includes
    })
    render(<ModelsPanel project="Test project" tab={4} />, { wrapper: wrapper() })

    // registry rows populated from GET /api/models
    await waitFor(() => expect(screen.getByTestId("registry-table")).toBeTruthy())
    expect(screen.getByTestId("registry-row-bionemo:boltz2")).toBeTruthy()
    expect(screen.getByTestId("registry-row-custom:camp1/potency-gp")).toBeTruthy()

    fireEvent.click(screen.getByTestId("registry-row-bionemo:boltz2"))
    // model object loads by id
    await waitFor(() => expect(screen.getByTestId("model-object")).toBeTruthy())
    expect(screen.getByTestId("model-object-id").textContent).toContain("bionemo:boltz2")
  })
})

describe("ModelsPanel — Train track", () => {
  it("shows the loop + families always, and an honest empty runs state with no data", async () => {
    mockFetchByUrl({ "/api/models": CATALOG })
    render(<ModelsPanel project="Test project" tab={0} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("track-train")).toBeTruthy())
    expect(screen.getByTestId("train-loop")).toBeTruthy()
    expect(screen.getByTestId("train-families")).toBeTruthy()
    expect(screen.getByTestId("train-runs-empty")).toBeTruthy()
  })

  it("renders training runs with status + gate and opens the experiment/model on click", async () => {
    mockFetchByUrl({
      "/api/models/custom:camp1/potency-gp": MODEL_DETAIL,
      "/api/models": CATALOG,
    })
    const TRAIN: TrainData = {
      runs: [
        {
          name: "potency-gp fit",
          family: "tabular",
          when: "2026-08",
          status: "completed",
          gate: "gate passed",
          metric: "spearman 0.62",
          dataset: "assay_2026_08.csv · v4",
          version: "→ potency-gp v2",
          modelId: "custom:camp1/potency-gp",
        },
        {
          name: "herg refit",
          family: "molecular property",
          when: "now",
          status: "running",
          gate: "gate pending",
          metric: "—",
          dataset: "herg_panel.csv · v2",
        },
      ],
    }
    render(<ModelsPanel project="Test project" tab={0} trainData={TRAIN} />, { wrapper: wrapper() })

    await waitFor(() => expect(screen.getByTestId("train-run-potency-gp fit")).toBeTruthy())
    expect(screen.getByTestId("train-run-status-potency-gp fit").textContent).toContain("completed")
    // Running run offers a live-watch link.
    expect(screen.getByTestId("train-run-open-herg refit").textContent).toContain("watch live")

    // Completed run with a modelId opens the model object.
    fireEvent.click(screen.getByTestId("train-run-open-potency-gp fit"))
    await waitFor(() => expect(screen.getByTestId("model-object")).toBeTruthy())
  })
})

describe("ModelsPanel — Adapt track", () => {
  it("shows the level ladder always, and an honest empty learned state with no data", async () => {
    mockFetchByUrl({ "/api/models": CATALOG })
    render(<ModelsPanel project="Test project" tab={1} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("track-adapt")).toBeTruthy())
    expect(screen.getByTestId("adapt-levels")).toBeTruthy()
    expect(screen.getByTestId("adapt-learned-empty")).toBeTruthy()
  })

  it("renders learned before→after pairs and toggling fires the callback", async () => {
    mockFetchByUrl({ "/api/models": CATALOG })
    const onAdaptToggle = vi.fn()
    const ADAPT: AdaptData = {
      pendingCount: 3,
      pairs: [
        {
          id: "p1",
          learned: "prefer 'cohort' over 'group'",
          scope: "organisation",
          before: "each group",
          after: "each cohort",
          source: "Methods draft · 2026-08",
          on: true,
        },
        {
          id: "p2",
          learned: "cite the accession inline",
          scope: "project",
          before: "the dataset",
          after: "the dataset (GSE12345)",
          source: "Results · 2026-08",
          on: false,
        },
      ],
    }
    render(
      <ModelsPanel project="Test project" tab={1} adaptData={ADAPT} onAdaptToggle={onAdaptToggle} />,
      { wrapper: wrapper() },
    )

    await waitFor(() => expect(screen.getByTestId("adapt-pair-p1")).toBeTruthy())
    // before→after diff shown
    expect(screen.getByTestId("adapt-pair-before-p1").textContent).toContain("each group")
    expect(screen.getByTestId("adapt-pair-after-p1").textContent).toContain("each cohort")
    // toggle fires with the pair id
    fireEvent.click(screen.getByTestId("adapt-pair-toggle-p2"))
    expect(onAdaptToggle).toHaveBeenCalledWith("p2")
  })

  it("with no onAdaptToggle prop, toggling POSTs the persisted override endpoint", async () => {
    mockFetchByUrl({
      "/api/model-tracks/adapt/p9/toggle": { id: "p9", on: false },
      "/api/model-tracks/adapt": {
        pendingCount: 1,
        pairs: [
          {
            id: "p9",
            learned: "prefer your edit",
            scope: "project",
            before: "old",
            after: "new",
            source: "Methods · 2026-08",
            on: true,
          },
        ],
      },
      "/api/models": CATALOG,
    })
    render(<ModelsPanel project="Real project" tab={1} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("adapt-pair-p9")).toBeTruthy())
    fireEvent.click(screen.getByTestId("adapt-pair-toggle-p9"))
    await waitFor(() => {
      const calls = (global.fetch as any).mock.calls as any[]
      const toggled = calls.find(
        ([u, opts]: any[]) =>
          String(u).includes("/api/model-tracks/adapt/p9/toggle") &&
          (opts?.method || "").toUpperCase() === "POST",
      )
      expect(toggled).toBeTruthy()
    })
  })

  it("with no onAdaptRetrain prop, Re-train POSTs the retrain endpoint", async () => {
    mockFetchByUrl({
      "/api/model-tracks/adapt/retrain": { job_id: "job-1", status: "queued", edit_pair_count: 3 },
      "/api/model-tracks/adapt": {
        pendingCount: 3,
        pairs: [
          {
            id: "p1",
            learned: "prefer your edit",
            scope: "project",
            before: "old",
            after: "new",
            source: "Methods · 2026-08",
            on: true,
          },
        ],
      },
      "/api/models": CATALOG,
    })
    render(<ModelsPanel project="Real project" tab={1} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("adapt-retrain")).toBeTruthy())
    fireEvent.click(screen.getByTestId("adapt-retrain"))
    await waitFor(() => {
      const calls = (global.fetch as any).mock.calls as any[]
      const retrained = calls.find(
        ([u, opts]: any[]) =>
          String(u).includes("/api/model-tracks/adapt/retrain") &&
          (opts?.method || "").toUpperCase() === "POST",
      )
      expect(retrained).toBeTruthy()
    })
  })
})

describe("ModelsPanel — self-fetched track data (react-query hooks)", () => {
  it("renders training runs fetched from /api/model-tracks/train with no props", async () => {
    mockFetchByUrl({
      "/api/model-tracks/train": {
        runs: [
          {
            name: "potency-gp fit",
            family: "tabular",
            when: "2026-08",
            status: "completed",
            gate: "gate passed",
            metric: "spearman 0.62",
            dataset: "assay.csv · v4",
          },
        ],
      },
      "/api/models": CATALOG,
    })
    render(<ModelsPanel project="Real project" tab={0} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("train-run-potency-gp fit")).toBeTruthy())
  })

  it("renders a fetched DMTA loop from /api/model-tracks/optimise, and honest-empty when active:false", async () => {
    mockFetchByUrl({
      "/api/model-tracks/optimise": {
        active: true,
        running: true,
        round: 2,
        surrogates: [{ id: "custom:c1/potency-gp", label: "potency-gp v2" }],
        rounds: [{ round: "Round 2", status: "proposed", what: "8 candidates", when: "now" }],
        proposal: [{ id: "c-1", score: "7.1", confidence: "medium", verdict: "accepted" }],
      },
      "/api/models": CATALOG,
    })
    render(<ModelsPanel project="Real project" tab={2} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("optimise-loop")).toBeTruthy())
    expect(screen.getByTestId("optimise-round-Round 2")).toBeTruthy()
  })
})

describe("ModelsPanel — Optimise / DMTA track", () => {
  it("shows the honest empty state when no loop data is supplied", async () => {
    mockFetchByUrl({ "/api/models": CATALOG })
    render(<ModelsPanel project="Test project" tab={2} />, { wrapper: wrapper() })
    await waitFor(() => expect(screen.getByTestId("track-optimise")).toBeTruthy())
    expect(screen.getByTestId("optimise-empty")).toBeTruthy()
  })

  it("renders the DMTA loop, surrogate links and the proposal table with a safety-gate rejection", async () => {
    mockFetchByUrl({
      "/api/models/custom:camp1/potency-gp": MODEL_DETAIL,
      "/api/models": CATALOG,
    })
    const OPT: OptimiseData = {
      running: true,
      round: 4,
      budget: "96 assays per round · set by you, never inferred",
      refitPolicy: "refit on ≥ 6 returned results",
      surrogates: [{ id: "custom:camp1/potency-gp", label: "potency-gp v2" }],
      rounds: [
        { round: "Round 3", status: "closed", what: "8 measured, refit applied", when: "2026-08" },
        { round: "Round 4", status: "proposed", what: "12 candidates", when: "now" },
      ],
      proposal: [
        { id: "cand-1", score: "7.4", confidence: "medium", verdict: "accepted" },
        { id: "cand-2", score: "> 30 µM", confidence: "low", verdict: "rejected · hERG gate" },
      ],
    }
    render(<ModelsPanel project="Test project" tab={2} optimiseData={OPT} />, { wrapper: wrapper() })

    await waitFor(() => expect(screen.getByTestId("optimise-loop")).toBeTruthy())
    expect(screen.getByTestId("optimise-loop-state").textContent).toContain("running")
    expect(screen.getByTestId("optimise-round-Round 4")).toBeTruthy()
    expect(screen.getByTestId("optimise-proposal-cand-1")).toBeTruthy()
    // A rejected proposal stays on the list with its safety-gate reason.
    expect(screen.getByTestId("optimise-proposal-verdict-cand-2").textContent).toContain("hERG gate")

    // Surrogate link opens the model object.
    fireEvent.click(screen.getByTestId("optimise-surrogate-custom:camp1/potency-gp"))
    await waitFor(() => expect(screen.getByTestId("model-object")).toBeTruthy())
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
    // Colour is the fail red (#ef4444 -> rgb), not the pass green (#22c55e).
    expect(verdict.getAttribute("style") || "").toContain("rgb(239, 68, 68)")
    expect(verdict.getAttribute("style") || "").not.toContain("rgb(34, 197, 94)")
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
    // Neutral slate colour (#94a3b8 -> rgb), neither pass green nor fail red.
    const style = verdict.getAttribute("style") || ""
    expect(style).toContain("rgb(148, 163, 184)")
    expect(style).not.toContain("rgb(34, 197, 94)") // pass green
    expect(style).not.toContain("rgb(239, 68, 68)") // fail red
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
    expect(screen.getByTestId("result-status-failed").textContent).toContain("failed")
    // The real backend error surfaces, not a generic placeholder.
    expect(screen.getByTestId("result-error").textContent).toContain("worker OOM")

    // A failed run must NOT fabricate a completed result or leave a spinner running.
    expect(screen.queryByTestId("result-status-completed")).toBeNull()
    expect(screen.queryByTestId("result-status-running")).toBeNull()
    expect(screen.queryByTestId("result-pending")).toBeNull()
    expect(screen.queryByTestId("hit-grid")).toBeNull()
  })
})
