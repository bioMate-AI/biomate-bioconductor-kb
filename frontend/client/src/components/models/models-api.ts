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

import { useQuery, useMutation, type UseQueryResult } from "@tanstack/react-query"
import { apiRequest } from "@/lib/queryClient"
import type {
  ModelSummary,
  ModelDetail,
  InferResponse,
  InferenceResult,
} from "./types"

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
