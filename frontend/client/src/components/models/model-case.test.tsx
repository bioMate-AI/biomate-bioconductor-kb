/**
 * Tests for ModelCase — the Spec 10 worked-case page.
 *
 *   - header renders: the case question, the model chip (name+version), lane
 *   - the four-track spine renders from props: given rows + stages, result
 *     blocks (with the honest one flagged), the floor table, the artefacts,
 *     and the next-step decisions
 *   - honest-empty states: ModelCaseEmpty ("No worked cases yet"), and per
 *     section when a case supplies no data — never a fabricated value
 *   - callbacks fire (model chip link, register decision)
 *
 * Pure presentational unit tests — no network, no react-query. Every value on
 * screen is asserted to come from the fixture, matching models.test.tsx style.
 */

import React from "react"
import { describe, it, expect, vi } from "vitest"
import { render, screen, fireEvent } from "@testing-library/react"

import { ModelCase, ModelCaseEmpty } from "./model-case"
import type { ModelCase as ModelCaseT } from "./types"

// The §10.3 "Train" case: potency-gp v3, RMSE 0.62, clears floor, not registered.
const TRAIN_CASE: ModelCaseT = {
  id: "train_potency",
  track: "train",
  question: "Train a potency predictor on our in-house assay data.",
  breadcrumb: ["Fibrosis target triage", "Models", "Train"],
  lane: "Cloud",
  origin: "From scratch, on your data",
  model: { name: "potency-gp", version: "v3", qualifier: "candidate", modelId: "custom:camp1/potency-gp" },
  given: [
    { label: "Training data", value: "assay_2026_08.csv · v4", note: "a version, not a name" },
    { label: "Split", value: "scaffold · 70/15/15", note: "random split leaks" },
    { label: "Excluded", value: "311 censored values", note: "kept as inequalities" },
  ],
  stages: [
    { label: "Featurise", status: "done" },
    { label: "Fit", status: "done" },
    { label: "Held-out evaluation", status: "done" },
    { label: "Gate", status: "done" },
    { label: "Offer", status: "waiting" },
  ],
  headline: "It clears the floor, and it is narrower than it looks.",
  confidence: "medium",
  flaggedCount: 1,
  resultBlocks: [
    { label: "Held out", body: "RMSE 0.62 log · Spearman 0.71" },
    { label: "Where it applies", body: "aminopyrimidines + 3 neighbouring series", honest: true },
  ],
  boundary:
    "Passing a gate means it cleared a floor on one held-out split — not that predictions are correct elsewhere.",
  floor: [
    { metric: "RMSE · held out", value: "0.62 log", threshold: "≤ 0.75 to gate a loop", verdict: "pass" },
    { metric: "Calibration", value: "0.78", threshold: "0.75–0.85", verdict: "pass" },
  ],
  artefacts: [
    { name: "potency-gp_v3.pkl", kind: "model" },
    { name: "train_report.md", kind: "report" },
  ],
  reportName: "train_report.md",
  nextSteps: [
    { label: "Register as v3", variant: "primary" },
    { label: "Model object", variant: "outline" },
    { label: "Fix upstream", variant: "outline" },
  ],
}

// An honest-empty case: nothing has come back yet.
const EMPTY_CASE: ModelCaseT = {
  id: "run_fold",
  track: "run_a_model",
  question: "Predict the fold of this sequence and show me where the model is unsure.",
  breadcrumb: ["Models", "Run a model"],
  lane: null,
  origin: null,
  model: { name: "fold-predict", version: "v2.3", qualifier: "pre-trained, weights pinned", modelId: null },
  given: [],
  stages: [
    { label: "Featurise", status: "waiting" },
    { label: "Held-out evaluation", status: "waiting" },
  ],
  headline: null,
  confidence: null,
  flaggedCount: 0,
  resultBlocks: [],
  boundary: null,
  floor: [],
  artefacts: [],
  reportName: null,
  nextSteps: [],
}

describe("ModelCase — header", () => {
  it("renders the case question, model chip, lane and origin", () => {
    render(<ModelCase case_={TRAIN_CASE} />)
    expect(screen.getByTestId("model-case")).toHaveAttribute("data-case-id", "train_potency")
    expect(screen.getByTestId("model-case-question")).toHaveTextContent(
      "Train a potency predictor on our in-house assay data."
    )
    const chip = screen.getByTestId("model-case-model-chip")
    expect(chip).toHaveTextContent("potency-gp")
    expect(chip).toHaveTextContent("v3")
    expect(chip).toHaveTextContent("candidate")
    expect(screen.getByTestId("model-case-lane")).toHaveTextContent("Cloud")
    expect(screen.getByTestId("model-case-origin")).toHaveTextContent("From scratch, on your data")
    // Breadcrumb is present with all crumbs.
    const crumb = screen.getByTestId("model-case-breadcrumb")
    expect(crumb).toHaveTextContent("Fibrosis target triage")
    expect(crumb).toHaveTextContent("Models")
    expect(crumb).toHaveTextContent("Train")
  })

  it("links the model chip into the model object when a modelId + handler exist", () => {
    const onOpenModel = vi.fn()
    render(<ModelCase case_={TRAIN_CASE} onOpenModel={onOpenModel} />)
    fireEvent.click(screen.getByTestId("model-case-model-chip"))
    expect(onOpenModel).toHaveBeenCalledWith("custom:camp1/potency-gp")
  })
})

describe("ModelCase — the four-track spine renders from props", () => {
  it("Track 1: WHAT THIS WAS GIVEN — given rows with notes + stage chips", () => {
    render(<ModelCase case_={TRAIN_CASE} />)
    expect(screen.getByTestId("model-case-track-1")).toBeInTheDocument()
    const given = screen.getByTestId("model-case-given")
    expect(given).toHaveTextContent("assay_2026_08.csv · v4")
    expect(given).toHaveTextContent("a version, not a name")
    expect(given).toHaveTextContent("random split leaks")
    // Five stage chips; the last reads "waiting".
    expect(screen.getAllByTestId(/^model-case-stage-\d+$/)).toHaveLength(5)
    expect(screen.getByTestId("model-case-stage-4")).toHaveAttribute("data-status", "waiting")
    expect(screen.getByTestId("model-case-stage-0")).toHaveAttribute("data-status", "done")
  })

  it("Track 2: WHAT CAME BACK — headline, result blocks, the honest block, boundary", () => {
    render(<ModelCase case_={TRAIN_CASE} />)
    expect(screen.getByTestId("model-case-track-2")).toBeInTheDocument()
    expect(screen.getByTestId("model-case-headline")).toHaveTextContent("narrower than it looks")
    expect(screen.getByTestId("model-case-confidence")).toHaveTextContent("medium confidence")
    expect(screen.getByTestId("model-case-flagged")).toHaveTextContent("1 flagged")
    // Two result blocks; the second is the honest one.
    expect(screen.getByTestId("model-case-result-block-0")).toHaveAttribute("data-honest", "false")
    expect(screen.getByTestId("model-case-result-block-1")).toHaveAttribute("data-honest", "true")
    expect(screen.getByTestId("model-case-boundary")).toHaveTextContent(
      "not that predictions are correct elsewhere"
    )
  })

  it("Track 3: MEASURED AGAINST A FLOOR — floor table rows with verdicts", () => {
    render(<ModelCase case_={TRAIN_CASE} />)
    expect(screen.getByTestId("model-case-track-3")).toBeInTheDocument()
    const rows = screen.getAllByTestId(/^model-case-floor-row-\d+$/)
    expect(rows).toHaveLength(2)
    expect(rows[0]).toHaveTextContent("RMSE · held out")
    expect(rows[0]).toHaveTextContent("0.62 log")
    expect(screen.getAllByTestId("model-case-floor-verdict")[0]).toHaveTextContent("pass")
  })

  it("Track 4: WHAT IT LEFT BEHIND — artefacts routed by kind, report name", () => {
    const onOpenArtefact = vi.fn()
    render(<ModelCase case_={TRAIN_CASE} onOpenArtefact={onOpenArtefact} />)
    expect(screen.getByTestId("model-case-track-4")).toBeInTheDocument()
    // model artefact gets "Open in Files"; report gets "Open & edit" + download.
    expect(screen.getByTestId("model-case-artefact-open-0")).toHaveTextContent("Open in Files")
    expect(screen.getByTestId("model-case-artefact-edit-1")).toHaveTextContent("Open & edit")
    expect(screen.getByTestId("model-case-artefact-download-1")).toBeInTheDocument()
    fireEvent.click(screen.getByTestId("model-case-artefact-open-0"))
    expect(onOpenArtefact).toHaveBeenCalledWith(TRAIN_CASE.artefacts[0])
    expect(screen.getByTestId("model-case-report-name")).toHaveTextContent("runs/models/train_report.md")
  })

  it("WHAT TO DO NEXT — decisions render and fire, register is primary", () => {
    const onNextStep = vi.fn()
    render(<ModelCase case_={TRAIN_CASE} onNextStep={onNextStep} />)
    const steps = screen.getAllByTestId(/^model-case-next-step-\d+$/)
    expect(steps).toHaveLength(3)
    expect(steps[0]).toHaveTextContent("Register as v3")
    fireEvent.click(steps[0])
    expect(onNextStep).toHaveBeenCalledWith(TRAIN_CASE.nextSteps[0])
  })
})

describe("ModelCase — honest-empty states (no fabricated values)", () => {
  it("ModelCaseEmpty renders 'No worked cases yet'", () => {
    render(<ModelCaseEmpty />)
    expect(screen.getByTestId("model-case-empty")).toHaveTextContent("No worked cases yet")
  })

  it("a case with no result shows honest-empty sections, not invented numbers", () => {
    render(<ModelCase case_={EMPTY_CASE} />)
    // No inputs, no result, no floor, no artefacts, no decisions.
    expect(screen.getByTestId("model-case-given-empty")).toBeInTheDocument()
    expect(screen.getByTestId("model-case-result-empty")).toHaveTextContent(
      "nothing is reported until the evaluation stage finishes"
    )
    expect(screen.getByTestId("model-case-floor-empty")).toBeInTheDocument()
    expect(screen.getByTestId("model-case-artefacts-empty")).toBeInTheDocument()
    expect(screen.getByTestId("model-case-next-empty")).toBeInTheDocument()
    // No headline, no confidence/flag badges, no boundary block are rendered.
    expect(screen.queryByTestId("model-case-headline")).toBeNull()
    expect(screen.queryByTestId("model-case-confidence")).toBeNull()
    expect(screen.queryByTestId("model-case-flagged")).toBeNull()
    expect(screen.queryByTestId("model-case-boundary")).toBeNull()
    // A pre-trained model with no modelId is plain text, not a link — chip still shows.
    expect(screen.getByTestId("model-case-model-chip")).toHaveTextContent("fold-predict")
    expect(screen.getByTestId("model-case-model-chip").tagName).toBe("SPAN")
  })
})
