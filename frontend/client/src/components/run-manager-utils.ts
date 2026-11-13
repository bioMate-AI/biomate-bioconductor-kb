import { t } from "@/lib/i18n"
export interface RunListItem {
  id: string
  workflowName: string
  /** Owning chat — present on /api/workflows/runs rows; used to open the right session. */
  chatSessionId?: string
  mode?: "sandbox" | "production"
  execution?: {
    status?: string
    errorMessage?: string
    galaxyInvocationId?: string
    galaxyWorkflowId?: string
    artifactReadiness?: {
      hasOutputs?: boolean
      visualizableCount?: number
      downloadableCount?: number
      totalOutputs?: number
      meetsContract?: boolean
      completionContract?: {
        mode: "artifacts_required" | "stdout_only"
        state: "ready" | "artifact_unavailable" | "stdout_only"
        registeredOutputCount: number
        meetsContract: boolean
      }
    }
    nextflowStatus?: {
      artifactReadiness?: {
        hasOutputs?: boolean
        visualizableCount?: number
        downloadableCount?: number
        totalOutputs?: number
        meetsContract?: boolean
        completionContract?: {
          mode: "artifacts_required" | "stdout_only"
          state: "ready" | "artifact_unavailable" | "stdout_only"
          registeredOutputCount: number
          meetsContract: boolean
        }
      }
      errorMessage?: string
      outputs?: unknown[]
      results?: unknown[]
      output_files?: unknown[]
      /** AWS Batch runs record their published outputs here (Galaxy status). */
      s3_output_files?: unknown[]
    }
  }
  updatedAt?: string
  createdAt?: string
}

export type RunBucket = "needs_attention" | "running" | "queued" | "failed" | "completed"

const RESOLVE_INPUTS_PATTERN =
  /(missing input|missing inputs|missing prerequisite|prerequisite|required input|required parameter|resolve inputs|not configured)/i

function getReadiness(run: RunListItem) {
  return run.execution?.artifactReadiness || run.execution?.nextflowStatus?.artifactReadiness
}

function getOutputCount(run: RunListItem): number {
  return (
    (Array.isArray(run.execution?.nextflowStatus?.outputs) ? run.execution?.nextflowStatus?.outputs.length : 0) +
    (Array.isArray(run.execution?.nextflowStatus?.results) ? run.execution?.nextflowStatus?.results.length : 0) +
    (Array.isArray(run.execution?.nextflowStatus?.output_files) ? run.execution?.nextflowStatus?.output_files.length : 0) +
    // Batch runs: without these every completed Batch run read as "0 outputs →
    // check artifacts" and filled 需要关注 with successful runs.
    (Array.isArray(run.execution?.nextflowStatus?.s3_output_files) ? run.execution?.nextflowStatus?.s3_output_files.length : 0)
  )
}

function getErrorMessage(run: RunListItem): string {
  return `${run.execution?.errorMessage || ""} ${run.execution?.nextflowStatus?.errorMessage || ""}`.trim()
}

export function mapRunBucket(status?: string): Exclude<RunBucket, "needs_attention"> {
  switch (status) {
    case "running":
      return "running"
    case "configuring":
    case "queued":
    case "submitted":
    case "pending":
    case "initializing":
    case "paused":
      return "queued"
    case "failed":
      return "failed"
    case "completed":
    case "cancelled":
    default:
      return "completed"
  }
}

/** Output readiness as a code + numbers, for display in the UI language.
 *  `getOutputReadinessHint` (English) stays the identifier the bucket logic and
 *  tests compare against. */
export type OutputReadiness =
  | { code: "stdout_only" | "artifact_unavailable" | "not_ready" | "check_artifacts" }
  | { code: "ready"; viz: number; dl: number }
  | { code: "partial"; n: number }
  | { code: "detected"; n: number }

export function describeOutputReadiness(run: RunListItem): OutputReadiness | null {
  const readiness = getReadiness(run)
  if (readiness) {
    if (readiness.completionContract?.state === "stdout_only") return { code: "stdout_only" }
    if (readiness.completionContract?.state === "artifact_unavailable") return { code: "artifact_unavailable" }
    if (readiness.meetsContract === true) return { code: "ready", viz: readiness.visualizableCount ?? 0, dl: readiness.downloadableCount ?? 0 }
    if (readiness.hasOutputs) return { code: "partial", n: readiness.totalOutputs ?? 0 }
    if (readiness.meetsContract === false) return { code: "not_ready" }
  }
  const outputCount = getOutputCount(run)
  if (outputCount > 0) return { code: "detected", n: outputCount }
  if (run.execution?.status === "completed") return { code: "check_artifacts" }
  return null
}

/** Localized readiness line for the Run Manager card. */
export function outputReadinessLabel(run: RunListItem): string | null {
  const d = describeOutputReadiness(run)
  return d ? t(`runs_ui.readiness_${d.code}`, d as unknown as Record<string, string | number>) : null
}

/** Localized label for a primary-CTA identifier from `getRunPrimaryCta`. The
 *  whole card opens the run, so a failed run's label says what it shows (the
 *  failure), not "Retry Search", which the card never did. */
export function runPrimaryCtaLabel(cta: string): string {
  const key = ({ "Resolve Inputs": "resolve_inputs", "Retry Search": "view_failure", "View Outputs": "view_outputs", "Open Logs": "open_logs" } as Record<string, string>)[cta]
  return key ? t(`runs_ui.cta_${key}`) : cta
}

export function getOutputReadinessHint(run: RunListItem): string | null {
  const readiness = getReadiness(run)
  if (readiness) {
    if (readiness.completionContract?.state === "stdout_only") {
      return "completed via stdout/log output"
    }
    if (readiness.completionContract?.state === "artifact_unavailable") {
      return "completed; result artifacts unavailable"
    }
    if (readiness.meetsContract === true) {
      return `outputs ready (${readiness.visualizableCount ?? 0} viz / ${readiness.downloadableCount ?? 0} dl)`
    }
    if (readiness.hasOutputs) {
      return `partial outputs (${readiness.totalOutputs ?? 0})`
    }
    if (readiness.meetsContract === false) {
      return "outputs not ready"
    }
  }

  const outputCount = getOutputCount(run)

  if (outputCount > 0) return `outputs detected (${outputCount})`
  if (run.execution?.status === "completed") return "completed; check artifacts"
  return null
}

export function isRunNeedsInputResolution(run: RunListItem): boolean {
  const errorMessage = getErrorMessage(run)
  if (!errorMessage) return false
  return RESOLVE_INPUTS_PATTERN.test(errorMessage)
}

export function isRunNeedsAttention(run: RunListItem): boolean {
  const status = run.execution?.status
  if (isRunNeedsInputResolution(run)) return true
  if (status === "failed" || status === "cancelled") return true

  if (status === "completed") {
    const readiness = getReadiness(run)
    if (readiness?.completionContract?.state === "artifact_unavailable") return true
    if (readiness?.meetsContract === false) return true
    const hint = getOutputReadinessHint(run)
    if (hint === "outputs not ready" || hint === "completed; check artifacts") return true
    if (hint?.startsWith("partial outputs")) return true
  }

  return false
}

export function getRunPrimaryCta(run: RunListItem): string {
  const status = run.execution?.status
  if (isRunNeedsInputResolution(run)) return "Resolve Inputs"
  if (status === "failed" || status === "cancelled") return "Retry Search"

  if (status === "completed") {
    const readiness = getReadiness(run)
    if (readiness?.completionContract?.state === "stdout_only") return "Open Logs"
    if (readiness?.completionContract?.state === "artifact_unavailable") return "Open Logs"
    const outputCount = getOutputCount(run)
    const outputsReady =
      readiness?.meetsContract === true ||
      !!readiness?.hasOutputs ||
      outputCount > 0
    return outputsReady && readiness?.meetsContract !== false ? "View Outputs" : "Open Logs"
  }

  return "Open Logs"
}

export function runUpdatedAtMs(run: RunListItem): number {
  const value = run.updatedAt || run.createdAt
  if (!value) return 0
  const ms = new Date(value).getTime()
  return Number.isFinite(ms) ? ms : 0
}

/** Active execution only; configured drafts and terminal runs belong elsewhere. */
export function isActiveJob(run: RunListItem): boolean {
  return ['running', 'queued', 'paused', 'submitted', 'pending', 'initializing'].includes(run.execution?.status ?? '')
}

/** Persisted runs retain their own project; never relabel them with the current
 * composer's project. A new unsubmitted proposal still uses composer context. */
export function workflowPanelProjectId(run: { id?: string; projectId?: string | null } | null | undefined, matchesPanel: boolean, activeProjectId?: string | null): string | undefined {
  return run?.id && matchesPanel ? run.projectId || undefined : activeProjectId || undefined;
}

/** A new unsaved chat has no run history; current-chat never falls back to all. */
/**
 * Where Run Manager should navigate when the user clicks a run.
 * Cross-chat picks must open the owning chat (left panel), not only the right workflow panel.
 */
export function runManagerSwitchHref(opts: {
  runId: string
  runChatSessionId?: string | null
  currentChatSessionId?: string | null
}): string | null {
  const owner = opts.runChatSessionId || null
  const current = opts.currentChatSessionId || null
  if (!owner || !opts.runId) return null
  if (current && owner === current) return null
  const params = new URLSearchParams()
  params.set('session', owner)
  params.set('focusRun', opts.runId)
  return `/?${params.toString()}`
}

export function runManagerListParams(scope: 'current_chat' | 'all_chats', chatSessionId?: string | null): URLSearchParams | null {
  if (scope === 'current_chat' && !chatSessionId) return null;
  const params = new URLSearchParams({ limit: '50', offset: '0' });
  if (scope === 'current_chat') params.set('chatSessionId', chatSessionId!);
  return params;
}

export function workflowPanelProjectName(projectId: string | undefined, projects: Array<{ id: string; name: string }>): string | undefined {
  return projectId ? projects.find(project => project.id === projectId)?.name : undefined;
}
