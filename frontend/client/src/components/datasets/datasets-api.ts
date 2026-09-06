/**
 * Data-fetching hooks for the Datasets surface (Tier-1 data-centric).
 *
 * The only backend endpoint that exists today is the perception profiler:
 *
 *   POST /api/perception/profile  { datasetRef }  ->  DataProfile (+ planImpact)
 *
 * proxied to the Galaxy backend by the shared `_dlProxyHandler` in
 * server/routes.ts (same pattern as /api/models). Lineage / consumers /
 * versions have NO backend yet — the DatasetObject renders honest
 * "not available" states for those tabs rather than fabricating values.
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
