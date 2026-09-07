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
import type { TrainData, AdaptData, OptimiseData } from "./models-panel"

// ── GET /api/models ──────────────────────────────────────────────────────────
export function useModels(): UseQueryResult<ModelSummary[]> {
  return useQuery<ModelSummary[]>({
    queryKey: ["/api/models"],
    queryFn: async () => {
      const res = await fetch("/api/models", { credentials: "include" })
      if (!res.ok) throw new Error(`${res.status}: failed to load models`)
      const body = await res.json().catch(() => [])
      return Array.isArray(body) ? (body as ModelSummary[]) : []
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
      const body = (await res.json().catch(() => ({}))) as Partial<TrainData>
      return { runs: Array.isArray(body.runs) ? body.runs : [] }
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
      const body = (await res.json().catch(() => ({}))) as Partial<AdaptData>
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
export function useOptimiseTrack(project?: string): UseQueryResult<OptimiseData | undefined> {
  const qs = project ? `?project=${encodeURIComponent(project)}` : ""
  return useQuery<OptimiseData | undefined>({
    queryKey: ["/api/model-tracks/optimise", project ?? null],
    queryFn: async () => {
      const res = await fetch(trackQuery(`/api/model-tracks/optimise${qs}`), {
        credentials: "include",
      })
      if (!res.ok) throw new Error(`${res.status}: failed to load optimise track`)
      const body = await res.json().catch(() => null)
      // Backend returns {active: false} when no loop exists → honest empty state.
      if (!body || body.active === false || !Array.isArray(body.rounds)) return undefined
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
