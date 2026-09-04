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
