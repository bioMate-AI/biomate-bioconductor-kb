/**
 * Type contract for the Models module — mirrors the WS1 backend API in
 * backend/lib/galaxy/webapps/galaxy/api/models_inference.py EXACTLY.
 *
 *   GET  /api/models                      -> ModelSummary[]
 *   GET  /api/models/{id}                 -> ModelDetail
 *   POST /api/models/{id}/infer  {inputs} -> { run_id }
 *   GET  /api/inference/{run_id}/result   -> InferenceResult (by evidence class)
 *
 * Evidence class drives BOTH dispatch and result shape:
 *   structure -> PlddtChart + PaeHeatmap (+ 3D)
 *   genomic   -> SeqTracks
 *   chemical  -> HitGrid
 *
 * The honesty contract: a result may set `stub: true` + `stub_reason` when the
 * backend (BioNeMo NIM / an unloaded custom scorer) is unreachable. The UI must
 * render the correct SHAPE and badge it as stub — never present it as measured
 * science. No value here is fabricated on the client.
 */

export type EvidenceClass = "structure" | "genomic" | "chemical"

// ── GET /api/models ──────────────────────────────────────────────────────────
export interface ModelSummary {
  id: string
  name: string
  family: string
  version: string
  origin: string
  usedByCount: number
}

// ── GET /api/models/{id} ─────────────────────────────────────────────────────
export interface ModelGate {
  measured: string | number | null
  threshold: string | number | null
  /** "pass" | "fail" | "not_evaluated" (WS1 returns not_evaluated for the thin layer). */
  verdict: string
}

export interface ModelEvidence {
  gate: ModelGate
  calibration: string | number | null
  evalSetId: string | null
}

export interface ModelLineage {
  datasetVersion: string | null
  trainingRunId: string | null
  priorVersions: string[]
}

export interface ModelIdentity {
  name: string
  version: string
  family: string
  confidenceBand: string | null
  origin: string
}

export interface ModelInterface {
  /** "python" | "container" | "rest". */
  kind: string
}

export interface ModelVersionRow {
  v: string
  verdict: string
}

export interface ModelDetail {
  identity: ModelIdentity
  evidence: ModelEvidence
  lineage: ModelLineage
  consumers: string[]
  interface: ModelInterface
  versions: ModelVersionRow[]
}

// ── POST /api/models/{id}/infer ──────────────────────────────────────────────
export interface InferResponse {
  run_id: string
}

// ── GET /api/inference/{run_id}/result ───────────────────────────────────────
// Shared status envelope. status may be running | completed | failed.
export type InferenceStatus = "running" | "completed" | "failed"

interface InferenceBase {
  run_id: string
  status: InferenceStatus
  evidenceClass?: EvidenceClass
  error?: string
  stub?: boolean
  stub_reason?: string
}

/** structure evidence class — feeds PlddtChart + PaeHeatmap (+ 3D via structureFileRef). */
export interface StructureResult extends InferenceBase {
  evidenceClass?: "structure"
  structureFileRef: string | null
  plddt: number[]
  pae: number[][]
  regions: { label: string; start: number; end: number; note?: string }[]
}

/** genomic evidence class — feeds SeqTracks. */
export interface GenomicTrack {
  kind: "line" | "marks" | "ticks"
  name: string
  values?: number[]
  intervals?: { start: number; end: number }[]
}
export interface GenomicResult extends InferenceBase {
  evidenceClass?: "genomic"
  locus: string | null
  tracks: GenomicTrack[]
  flagged: { start: number; end: number; context: string; why: string }[]
}

/** chemical evidence class — feeds HitGrid. */
export interface ChemicalHit {
  id: string
  smiles: string
  score: number | null
  confidence: string
  herg: string | null
  drugLike: string | null
  verdict: string
}
export interface ChemicalResult extends InferenceBase {
  evidenceClass?: "chemical"
  hits: ChemicalHit[]
}

export type InferenceResult =
  | StructureResult
  | GenomicResult
  | ChemicalResult
  | (InferenceBase & Record<string, unknown>)

export function isCompleted(r: InferenceResult | undefined): boolean {
  return !!r && r.status === "completed"
}
export function isStub(r: InferenceResult | undefined): boolean {
  return !!r && r.stub === true
}

// ── Spec 10 — worked-case page (ModelCase) ───────────────────────────────────
// One spine for all four tracks: what model → what it was given → what came back
// → how much to trust (floor) → what it left behind → next steps.
//
// Every field here is data the caller supplies. This module renders the SHAPE
// and honest-empty states; it never fabricates a metric, a verdict, or a
// headline. Where a section's array is empty, the page shows a "No … yet"
// empty state rather than an invented value (§10.4 honesty contract).

/** Which of the four tracks this case belongs to (§10.3 / §10.5). */
export type ModelCaseTrack =
  | "run_a_model"
  | "train"
  | "tune_on_our_data"
  | "propose_and_test_in_rounds"

/** The model chip — only registry-existing names may appear here (§10.4). */
export interface ModelCaseModel {
  /** e.g. "potency-gp". */
  name: string
  /** e.g. "v3". */
  version: string
  /** e.g. "candidate" | "pre-trained, weights pinned". Optional qualifier. */
  qualifier?: string | null
  /** Registry id this chip links into (the model object). */
  modelId?: string | null
}

/**
 * A row under WHAT THIS WAS GIVEN — an input resolved to a version, plus the
 * decision the row encodes and why (§10.4). `note` is the italic rationale
 * ("a version, not a name" / "random split leaks" / "kept as inequalities").
 */
export interface ModelCaseGivenRow {
  label: string
  value: string
  note?: string | null
}

/** A run stage chip (Featurise / Fit / Held-out evaluation / Gate / Offer). */
export interface ModelCaseStage {
  label: string
  /** done stages are filled; a not-yet-reached stage reads "waiting" (§10.4). */
  status: "done" | "waiting"
}

/**
 * A labelled block under WHAT CAME BACK. Exactly one block should carry
 * `honest: true` — the thing the model learned that you may not want, the
 * flag, or the round still in flight (§10.4). The caller marks it; this module
 * only styles it.
 */
export interface ModelCaseResultBlock {
  label: string
  body: string
  honest?: boolean
}

/** A row in the MEASURED AGAINST A FLOOR table (a floor, not a ranking). */
export interface ModelCaseFloorRow {
  metric: string
  value: string
  threshold: string
  /** "pass" | "flag" | "fail" | "not_evaluated". */
  verdict: string
}

/** An artefact left behind — every artefact is a file in the project (§10.4). */
export interface ModelCaseArtefact {
  name: string
  /** "report" gets Open & edit + download; other kinds get Open in Files. */
  kind: "report" | "model" | "table" | string
}

/** A WHAT TO DO NEXT decision — never an automatic action (§10.4). */
export interface ModelCaseNextStep {
  label: string
  /** "primary" renders the filled button (e.g. Register as v3). */
  variant?: "primary" | "outline"
}

/** The full worked-case page contract (§10.4). */
export interface ModelCase {
  /** Stable id, e.g. "train_potency" (§10.5). */
  id: string
  track: ModelCaseTrack
  /** The case question, verbatim (§10.3), e.g. "Train a potency predictor …". */
  question: string
  /** Breadcrumb: [project, "Models", track-label]. */
  breadcrumb: string[]
  /** Lane badge, e.g. "Cloud". */
  lane?: string | null
  /** One-line lane descriptor under the chip, e.g. "From scratch, on your data". */
  origin?: string | null
  model: ModelCaseModel
  given: ModelCaseGivenRow[]
  stages: ModelCaseStage[]
  /** Headline sentence for WHAT CAME BACK; null until the eval stage finishes. */
  headline: string | null
  confidence?: string | null
  flaggedCount?: number
  resultBlocks: ModelCaseResultBlock[]
  /** BOUNDARY — what the result is NOT evidence for. Present on all four cases. */
  boundary?: string | null
  floor: ModelCaseFloorRow[]
  artefacts: ModelCaseArtefact[]
  /** The report this case leaves in runs/models/ (§10.6). */
  reportName?: string | null
  nextSteps: ModelCaseNextStep[]
}
