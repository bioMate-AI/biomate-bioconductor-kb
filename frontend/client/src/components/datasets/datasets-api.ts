/**
 * Data-fetching hooks for the Datasets surface (Tier-1 data-centric).
 *
 * Backend endpoints (all proxied to Galaxy by the shared `_dlProxyHandler` in
 * server/routes.ts, same pattern as /api/models):
 *
 *   POST /api/perception/profile        { datasetRef } -> DataProfile (+ planImpact)
 *   GET  /api/datasets/:ref/lineage     -> producing run/workflow/step
 *   GET  /api/datasets/:ref/consumers   -> runs that read it as input
 *   GET  /api/datasets/:ref/versions    -> version history (honest v1 · current)
 *
 * Lineage / consumers / versions are derived from run-output provenance and the
 * input params BioMate already tracks (backend datasets_object.py). Each
 * degrades to an honest empty result where a source genuinely has nothing — the
 * DatasetObject renders "not available yet" rather than fabricating a value.
 *
 * Uses the app's react-query conventions (see lib/queryClient.ts).
 */

import { useQuery, type UseQueryResult } from "@tanstack/react-query"
import type { DataProfile } from "@/components/data-perception"

/**
 * The profile shape the backend returns is the frontend `DataProfile` with an
 * extra `planImpact` list living alongside it (see data_perception.py
 * `to_dict()`), so we widen the type here.
 */
export interface PerceptionResponse extends DataProfile {
  planImpact?: { observed: string; effect: string }[]
}

/**
 * Profile a dataset by reference (an S3 key or a local path). Enabled only when
 * a ref is supplied. Errors surface via `isError` so the caller can render an
 * honest "quality not available" state.
 */
export function usePerceptionProfile(
  datasetRef: string | null,
  name?: string,
): UseQueryResult<PerceptionResponse> {
  return useQuery<PerceptionResponse>({
    queryKey: ["/api/perception/profile", datasetRef],
    enabled: !!datasetRef,
    // Profiling is deterministic; don't refetch aggressively.
    staleTime: 5 * 60 * 1000,
    retry: false,
    queryFn: async () => {
      const res = await fetch("/api/perception/profile", {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ datasetRef, name }),
      })
      if (!res.ok) throw new Error(`${res.status}: failed to profile dataset`)
      return (await res.json()) as PerceptionResponse
    },
  })
}

// ── Lineage / Consumers / Versions ───────────────────────────────────────────
// A run descriptor, as returned by the datasets_object backend. Every field is
// nullable because the backend only fills what it actually tracks.
export interface RunLabel {
  runId: string
  workflow?: string | null
  workflowPath?: string | null
  status?: string | null
  createdAt?: string | number | null
}

export interface LineageResponse {
  ref: string
  /** false when the dataset has no upstream run (uploaded input). */
  available: boolean
  /** "run_output" | "output_prefix" | null */
  source?: string | null
  /** The run/workflow that produced this dataset, or null. */
  producedBy?: RunLabel | null
}

export interface ConsumersResponse {
  ref: string
  /** Runs recorded as reading this dataset — empty (honest) when none. */
  consumers: RunLabel[]
}

export interface DatasetVersion {
  version: string
  label: string
  current: boolean
  ref: string
  createdAt?: string | number | null
  producedByRunId?: string | null
}

export interface VersionsResponse {
  ref: string
  versions: DatasetVersion[]
}

/** Encode a datasetRef (S3 key / path, may contain "/") for a path segment. */
function encodeRef(ref: string): string {
  return encodeURIComponent(ref)
}

async function _getJson<T>(url: string): Promise<T> {
  const res = await fetch(url, { credentials: "include" })
  if (!res.ok) throw new Error(`${res.status}: ${url}`)
  return (await res.json()) as T
}

/** Lineage — which run/workflow produced this dataset. Enabled when ref set. */
export function useDatasetLineage(
  ref: string | null,
): UseQueryResult<LineageResponse> {
  return useQuery<LineageResponse>({
    queryKey: ["/api/datasets/lineage", ref],
    enabled: !!ref,
    staleTime: 5 * 60 * 1000,
    retry: false,
    queryFn: () => _getJson<LineageResponse>(`/api/datasets/${encodeRef(ref!)}/lineage`),
  })
}

/** Consumers — which runs read this dataset as an input. */
export function useDatasetConsumers(
  ref: string | null,
): UseQueryResult<ConsumersResponse> {
  return useQuery<ConsumersResponse>({
    queryKey: ["/api/datasets/consumers", ref],
    enabled: !!ref,
    staleTime: 5 * 60 * 1000,
    retry: false,
    queryFn: () => _getJson<ConsumersResponse>(`/api/datasets/${encodeRef(ref!)}/consumers`),
  })
}

/** Versions — version history (a single honest "v1 · current" today). */
export function useDatasetVersions(
  ref: string | null,
): UseQueryResult<VersionsResponse> {
  return useQuery<VersionsResponse>({
    queryKey: ["/api/datasets/versions", ref],
    enabled: !!ref,
    staleTime: 5 * 60 * 1000,
    retry: false,
    queryFn: () => _getJson<VersionsResponse>(`/api/datasets/${encodeRef(ref!)}/versions`),
  })
}
