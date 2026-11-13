/**
 * Data-fetching hooks for the Models module.
 *
 * Uses the app's react-query conventions (see lib/queryClient.ts):
 *   - queries key off the full URL path (getQueryFn joins queryKey with "/")
 *   - apiRequest() for mutating POSTs (credentials: include, throws on !ok)
 *
 * The WS1 endpoints live on the Galaxy backend and are surfaced to the browser
 * through the Node server. A model id may contain a "/" (custom models are
 * `custom:{campaign}/{name}`) so ids are always URL-encoded on the wire.
 */

import {
  useQuery,
  useMutation,
  useQueryClient,
  type UseQueryResult,
} from "@tanstack/react-query"
import { apiRequest } from "@/lib/queryClient"
import type {
  ModelSummary,
  ModelDetail,
  InferResponse,
  InferenceResult,
} from "./types"
import type { TrainData, OptimiseData } from "./models-panel"

/**
 * House-style (adaptation) shapes. The tab is hidden (models-panel
 * HOUSE_STYLE_HIDDEN) because its only data source is the IND regulatory pair
 * recorder, which is itself hidden — the read/mutate hooks and these types stay
 * so re-enabling it is one tab registration, not a rewrite.
 */
export interface AdaptPair {
  id: string
  learned: string
  scope: string
  before: string
  after: string
  source: string
  on: boolean
}
export interface AdaptData {
  pendingCount?: number
  pairs: AdaptPair[]
}

// ── GET /api/models ──────────────────────────────────────────────────────────
export function useModels(): UseQueryResult<ModelSummary[]> {
  return useQuery<ModelSummary[]>({
    queryKey: ["/api/models"],
    queryFn: async () => {
      const res = await fetch("/api/models", { credentials: "include" })
      if (!res.ok) throw new Error(`${res.status}: failed to load models`)
      const body = await res.json()
      if (!Array.isArray(body)) throw new Error("Invalid model registry response")
      return body as ModelSummary[]
    },
  })
}

// ── GET /api/models/{id} ─────────────────────────────────────────────────────
export function useModel(modelId: string | null): UseQueryResult<ModelDetail> {
  return useQuery<ModelDetail>({
    queryKey: ["/api/models", modelId],
    enabled: !!modelId,
    queryFn: async () => {
      const res = await fetch(`/api/models/${encodeURIComponent(modelId as string)}`, {
        credentials: "include",
      })
      if (!res.ok) throw new Error(`${res.status}: failed to load model ${modelId}`)
      return (await res.json()) as ModelDetail
    },
  })
}

// ── POST /api/models/{id}/infer ──────────────────────────────────────────────
export interface InferArgs {
  modelId: string
  inputs: Record<string, unknown>
}

export function useInfer() {
  return useMutation<InferResponse, Error, InferArgs>({
    mutationFn: async ({ modelId, inputs }) => {
      const res = await apiRequest(
        "POST",
        `/api/models/${encodeURIComponent(modelId)}/infer`,
        { inputs },
      )
      return (await res.json()) as InferResponse
    },
  })
}

// ── GET /api/inference/{run_id}/result (polled until terminal) ───────────────
export function useInferenceResult(
  runId: string | null,
): UseQueryResult<InferenceResult> {
  return useQuery<InferenceResult>({
    queryKey: ["/api/inference", runId, "result"],
    enabled: !!runId,
    // Poll while running; stop once the run reaches a terminal state.
    refetchInterval: (query) => {
      const data = query.state.data as InferenceResult | undefined
      if (!data) return 1500
      return data.status === "running" ? 1500 : false
    },
    queryFn: async () => {
      const res = await fetch(
        `/api/inference/${encodeURIComponent(runId as string)}/result`,
        { credentials: "include" },
      )
      if (!res.ok) throw new Error(`${res.status}: failed to poll inference ${runId}`)
      return (await res.json()) as InferenceResult
    },
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Project-scoped track reads (Train / Adapt / Optimise).
//
// These sit under the distinct `/api/model-tracks/*` prefix so they never
// collide with the greedy `/api/models/{model_id:path}` detail route. The Galaxy
// backend maps existing stores (regulatory training jobs, the customer
// before→after DPO pair recorder, and the Bayesian-optimizer proposal rounds)
// onto the same track contract the panel renders. A project with no such work
// returns an honest-empty payload ({runs: []} / {pairs: []} / undefined), never
// fabricated rounds or scores — mirroring the models_inference honesty contract.
//
// `project` is optional: when omitted the backend reads account-scope. The hooks
// are `enabled` unconditionally so the panel can self-fetch defaults; a parent
// that passes explicit data still overrides them.
// ─────────────────────────────────────────────────────────────────────────────
function trackQuery(path: string): string {
  return path
}

/** GET /api/model-tracks/train — training-runs list for the Train track. */
export function useTrainTrack(project?: string): UseQueryResult<TrainData> {
  const qs = project ? `?project=${encodeURIComponent(project)}` : ""
  return useQuery<TrainData>({
    queryKey: ["/api/model-tracks/train", project ?? null],
    queryFn: async () => {
      const res = await fetch(trackQuery(`/api/model-tracks/train${qs}`), {
        credentials: "include",
      })
      if (!res.ok) throw new Error(`${res.status}: failed to load train track`)
      const body = await res.json()
      if (!body || !Array.isArray(body.runs)) throw new Error("Invalid training activity response")
      return { runs: body.runs }
    },
  })
}

/** GET /api/model-tracks/adapt — learned before→after pairs for the Adapt track. */
export function useAdaptTrack(project?: string): UseQueryResult<AdaptData> {
  const qs = project ? `?project=${encodeURIComponent(project)}` : ""
  return useQuery<AdaptData>({
    queryKey: ["/api/model-tracks/adapt", project ?? null],
    queryFn: async () => {
      const res = await fetch(trackQuery(`/api/model-tracks/adapt${qs}`), {
        credentials: "include",
      })
      if (!res.ok) throw new Error(`${res.status}: failed to load adapt track`)
      const body = await res.json()
      if (!body || !Array.isArray(body.pairs)) throw new Error("Invalid adaptation activity response")
      return {
        pendingCount: typeof body.pendingCount === "number" ? body.pendingCount : 0,
        pairs: Array.isArray(body.pairs) ? body.pairs : [],
      }
    },
  })
}

/**
 * GET /api/model-tracks/optimise — the DMTA loop for the Optimise track.
 * Returns `undefined` (no active loop) rather than an empty object so the panel
 * shows its honest empty state; a running loop returns the full OptimiseData.
 */
export function useOptimiseTrack(project?: string): UseQueryResult<OptimiseData | null> {
  const qs = project ? `?project=${encodeURIComponent(project)}` : ""
  return useQuery<OptimiseData | null>({
    queryKey: ["/api/model-tracks/optimise", project ?? null],
    queryFn: async () => {
      const res = await fetch(trackQuery(`/api/model-tracks/optimise${qs}`), {
        credentials: "include",
      })
      if (!res.ok) throw new Error(`${res.status}: failed to load optimise track`)
      const body = await res.json()
      // A successful explicit inactive response is the empty state.
      if (body?.active === false) return null
      if (!body || !Array.isArray(body.rounds)) throw new Error("Invalid rounds activity response")
      return body as OptimiseData
    },
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Adapt-track mutations — persist a learned-pair toggle and queue a retrain.
//
// The toggle is persisted server-side as an append-only override (it NEVER
// mutates the append-only DPO pair store); the retrain queues a real tracked
// training job. Both invalidate the adapt-track read so the UI reflects the new
// persisted state. The panel defaults its onAdaptToggle / onAdaptRetrain
// callbacks to these; a parent that passes its own still overrides.
// ─────────────────────────────────────────────────────────────────────────────
export interface ToggleAdaptPairArgs {
  pairId: string
  /** Explicit desired state; omit to flip the current one. */
  on?: boolean
  project?: string
}

export function useAdaptToggle() {
  const qc = useQueryClient()
  return useMutation<{ id: string; on: boolean }, Error, ToggleAdaptPairArgs>({
    mutationFn: async ({ pairId, on }) => {
      const res = await apiRequest(
        "POST",
        `/api/model-tracks/adapt/${encodeURIComponent(pairId)}/toggle`,
        on === undefined ? {} : { on },
      )
      return (await res.json()) as { id: string; on: boolean }
    },
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ["/api/model-tracks/adapt", vars.project ?? null] })
    },
  })
}

export interface RetrainAdaptArgs {
  project?: string
}

export function useAdaptRetrain() {
  const qc = useQueryClient()
  return useMutation<
    { job_id: string | null; status: string; edit_pair_count: number | null },
    Error,
    RetrainAdaptArgs
  >({
    mutationFn: async ({ project }) => {
      const qs = project ? `?project=${encodeURIComponent(project)}` : ""
      const res = await apiRequest("POST", `/api/model-tracks/adapt/retrain${qs}`, {})
      return (await res.json()) as {
        job_id: string | null
        status: string
        edit_pair_count: number | null
      }
    },
    onSuccess: (_data, vars) => {
      // A queued retrain becomes a training run — refresh both tracks.
      qc.invalidateQueries({ queryKey: ["/api/model-tracks/adapt", vars.project ?? null] })
      qc.invalidateQueries({ queryKey: ["/api/model-tracks/train", vars.project ?? null] })
    },
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Training launch (Models panel) — plan → ordinary workflow execution.
// POST /api/model-training/plan resolves + stages the project file server-side
// and returns a validated workflow_ga; POST /api/workflows/execute runs it like
// any workflow (run record, SSE, billing, Run Manager). No chat draft.
// ─────────────────────────────────────────────────────────────────────────────
export interface TrainingPlanRequest {
  projectId: string
  /** Single file (legacy). Prefer fileIds or folderPath for multi-file / folder inputs. */
  fileId?: string
  /** Explicit multi-file set (all staged; primary = first). */
  fileIds?: string[]
  /** Project folder path → every input file under the prefix. */
  folderPath?: string
  model_type: string
  featurizer?: string
  task_type?: string
  target_col?: string
  smiles_col?: string
  metric?: string
  gate_threshold?: number
  model_name?: string
  epochs?: number
  learning_rate?: number
  llm?: Record<string, unknown>
  sc?: Record<string, unknown>
  diffusion?: Record<string, unknown>
}

export interface TrainingPlan {
  workflow_ga: Record<string, any> & { name: string }
  nextflow_path: string
  compute_config: Record<string, unknown>
  projectId: string
  fileId: string
  fileIds?: string[]
  folderPath?: string
}

/** A launch failure: `stage` says which step failed; `detail` is the server text. */
export class TrainingLaunchError extends Error {
  constructor(public stage: "plan" | "execute", public detail: string) {
    super(detail)
  }
}

async function errorText(res: Response): Promise<string> {
  const body = await res.json().catch(() => ({}))
  const value = body?.message ?? body?.error ?? body?.detail
  return typeof value === "string" ? value : `HTTP ${res.status}`
}

export async function launchTraining(req: TrainingPlanRequest): Promise<{ runId: string; plan: TrainingPlan }> {
  const planRes = await fetch("/api/model-training/plan", {
    method: "POST", credentials: "include",
    headers: { "Content-Type": "application/json" }, body: JSON.stringify(req),
  })
  if (!planRes.ok) throw new TrainingLaunchError("plan", await errorText(planRes))
  const plan = (await planRes.json()) as TrainingPlan
  const execRes = await fetch("/api/workflows/execute", {
    method: "POST", credentials: "include",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      workflowDefinition: plan.workflow_ga,
      workflowName: plan.workflow_ga.name,
      executionConfig: { mode: "production", executionEngine: "nextflow", computeConfig: plan.compute_config },
      inputs: [],
      projectId: req.projectId,
    }),
  })
  if (!execRes.ok) throw new TrainingLaunchError("execute", await errorText(execRes))
  const body = await execRes.json()
  if (typeof body?.runId !== "string" || !body.runId) throw new TrainingLaunchError("execute", "missing runId")
  return { runId: body.runId, plan }
}

/**
 * Launch a Boltz-2 fold on OUR AWS Batch (not NVIDIA). Mirrors launchTraining:
 * POST /api/models/fold/plan stages the sequence + returns the
 * boltz_structure_prediction launch request, then POST /api/workflows/execute
 * runs it as a tracked run. Returns the runId to poll with useRunStatus.
 */
export async function launchFold(req: { sequence: string; name?: string }): Promise<{ runId: string }> {
  const planRes = await fetch("/api/models/fold/plan", {
    method: "POST", credentials: "include",
    headers: { "Content-Type": "application/json" }, body: JSON.stringify(req),
  })
  if (!planRes.ok) throw new TrainingLaunchError("plan", await errorText(planRes))
  const plan = await planRes.json()
  if (!plan?.workflow_ga?.nextflow_path) throw new TrainingLaunchError("plan", "fold plan was rejected")
  const execRes = await fetch("/api/workflows/execute", {
    method: "POST", credentials: "include",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      workflowDefinition: plan.workflow_ga,
      workflowName: plan.workflow_ga.name,
      executionConfig: { mode: "production", executionEngine: "nextflow" },
      inputs: [],
    }),
  })
  if (!execRes.ok) throw new TrainingLaunchError("execute", await errorText(execRes))
  const body = await execRes.json()
  if (typeof body?.runId !== "string" || !body.runId) throw new TrainingLaunchError("execute", "missing runId")
  return { runId: body.runId }
}

export interface RunStatus { runId: string; status: string; errorMessage?: string }

/** Poll a launched run until it reaches a terminal state. */
export function useRunStatus(runId: string | null, terminal: (s: string) => boolean): UseQueryResult<RunStatus> {
  return useQuery<RunStatus>({
    queryKey: ["/api/workflows/runs", runId, "status"],
    enabled: !!runId,
    refetchInterval: (query) => {
      const data = query.state.data as RunStatus | undefined
      return data && terminal(data.status) ? false : 5000
    },
    queryFn: async () => {
      const res = await fetch(`/api/workflows/runs/${encodeURIComponent(runId as string)}/status`, { credentials: "include" })
      if (!res.ok) throw new Error(`${res.status}`)
      return (await res.json()) as RunStatus
    },
  })
}
