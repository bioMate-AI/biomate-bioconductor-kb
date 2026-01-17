/**
 * AI Assistant API Service
 *
 * Handles API calls for citations, pilot runs, and methods generation.
 */

import type {
  Citation,
  MethodsSection,
  TuningConfig,
  PilotResult,
  FullRunEstimate,
  ParameterRecommendation,
} from '@shared/schema'

const API_BASE = '/api/ai_assistant'

// ============================================================================
// Citation API
// ============================================================================

export interface BibTeXExportResponse {
  success: boolean
  bibtex: string
  total_tools: number
  tools_with_citations: number
  missing_citations: string[]
  error?: string
}

export interface MethodsSectionResponse {
  success: boolean
  methods_text: string
  style: string
  tools_cited: string[]
  tools_missing_citations: string[]
  error?: string
}

/**
 * Export workflow citations as BibTeX format
 */
export async function exportCitationsBibTeX(
  workflowGa: Record<string, any>,
  includeAll: boolean = true
): Promise<BibTeXExportResponse> {
  const response = await fetch(`${API_BASE}/citations/export`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      workflow_ga: workflowGa,
      include_all: includeAll
    })
  })

  if (!response.ok) {
    throw new Error(`Failed to export citations: ${response.statusText}`)
  }

  return response.json()
}

/**
 * Generate methods section text from workflow
 */
export async function generateMethodsSection(
  workflowGa: Record<string, any>,
  style: 'short' | 'apa' | 'numbered' = 'short'
): Promise<MethodsSectionResponse> {
  const response = await fetch(`${API_BASE}/citations/methods?style=${style}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      workflow_ga: workflowGa,
      include_all: true
    })
  })

  if (!response.ok) {
    throw new Error(`Failed to generate methods section: ${response.statusText}`)
  }

  return response.json()
}

// ============================================================================
// Pilot Run API
// ============================================================================

export interface StartPilotResponse {
  pilot_id: string
  status: string
  pilot_size: number
  message: string
  config: TuningConfig
  galaxy_invocation_id?: string  // Galaxy invocation ID for tracking
  galaxy_history_id?: string     // Sandbox history ID
}

export interface PilotStatusResponse {
  pilot_id: string
  status: 'pending' | 'running' | 'complete' | 'failed'
  progress: number
  runtime_seconds?: number
  peak_memory_gb?: number
  quality_metrics?: Record<string, number>
  error_message?: string
}

export interface FullRunEstimateResponse {
  estimated_runtime_seconds: number
  estimated_runtime_display: string
  estimated_memory_gb: number
  estimated_cost_usd?: number
  confidence: number
  scaling_factors: Record<string, number>
}

/**
 * Start a pilot run for parameter tuning
 *
 * @param workflowIdOrDefinition - Either a Galaxy workflow ID (string) or a workflow definition object (.ga format)
 * @param totalSamples - Total number of samples in the dataset
 * @param config - Tuning configuration (pilot fraction, sampling strategy, etc.)
 * @param inputs - Input datasets for the workflow (optional, for new workflows)
 * @param sampleIds - Specific sample IDs to use (optional)
 */
export async function startPilotRun(
  workflowIdOrDefinition: string | Record<string, any>,
  totalSamples: number,
  config?: Partial<TuningConfig>,
  inputs?: Array<{ step_id?: number; src: string; id: string; name?: string }>,
  sampleIds?: string[]
): Promise<StartPilotResponse> {
  // Determine if we have a workflow ID or a definition
  const isWorkflowId = typeof workflowIdOrDefinition === 'string'

  const response = await fetch(`${API_BASE}/pilot/start`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      workflow_id: isWorkflowId ? workflowIdOrDefinition : null,
      workflow_definition: isWorkflowId ? null : workflowIdOrDefinition,
      total_samples: totalSamples,
      config: config ? {
        pilot_fraction: config.pilot_fraction ?? 0.1,
        sampling_strategy: config.sampling_strategy ?? 'stratified',
        strata_column: config.strata_column,
        min_pilot_samples: config.min_pilot_samples ?? 3,
        max_pilot_samples: config.max_pilot_samples ?? 50
      } : null,
      inputs: inputs || null,
      sample_ids: sampleIds
    })
  })

  if (!response.ok) {
    const error = await response.json().catch(() => ({ detail: response.statusText }))
    throw new Error(error.detail || 'Failed to start pilot run')
  }

  return response.json()
}

/**
 * Get pilot run status
 */
export async function getPilotStatus(pilotId: string): Promise<PilotStatusResponse> {
  const response = await fetch(`${API_BASE}/pilot/${pilotId}/status`)

  if (!response.ok) {
    throw new Error(`Failed to get pilot status: ${response.statusText}`)
  }

  return response.json()
}

/**
 * Get full run estimate from pilot results
 */
export async function getFullRunEstimate(
  pilotId: string,
  costPerHourUsd: number = 0.50
): Promise<FullRunEstimateResponse> {
  const response = await fetch(
    `${API_BASE}/pilot/${pilotId}/estimate?cost_per_hour_usd=${costPerHourUsd}`
  )

  if (!response.ok) {
    throw new Error(`Failed to get estimate: ${response.statusText}`)
  }

  return response.json()
}

/**
 * Poll pilot run status until complete or failed
 */
export async function pollPilotStatus(
  pilotId: string,
  onProgress: (status: PilotStatusResponse) => void,
  intervalMs: number = 2000,
  maxAttempts: number = 300 // 10 minutes max
): Promise<PilotStatusResponse> {
  let attempts = 0

  return new Promise((resolve, reject) => {
    const poll = async () => {
      try {
        const status = await getPilotStatus(pilotId)
        onProgress(status)

        if (status.status === 'complete' || status.status === 'failed') {
          resolve(status)
          return
        }

        attempts++
        if (attempts >= maxAttempts) {
          reject(new Error('Pilot run polling timeout'))
          return
        }

        setTimeout(poll, intervalMs)
      } catch (error) {
        reject(error)
      }
    }

    poll()
  })
}

// ============================================================================
// Benchmark API
// ============================================================================

export interface BenchmarkResult {
  scenario: string
  available: boolean
  tools_compared: string[]
  metrics: Record<string, any>
  recommendations: string[]
  last_run?: string
  message?: string
  error?: string
}

/**
 * Get benchmark results for a scenario
 */
export async function getBenchmarkResults(scenario: string): Promise<BenchmarkResult> {
  const response = await fetch(`${API_BASE}/benchmarks/${scenario}`)

  if (!response.ok) {
    throw new Error(`Failed to get benchmarks: ${response.statusText}`)
  }

  return response.json()
}

// ============================================================================
// Utility functions
// ============================================================================

/**
 * Download text content as a file
 */
export function downloadAsFile(content: string, filename: string, mimeType: string = 'text/plain') {
  const blob = new Blob([content], { type: mimeType })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

/**
 * Copy text to clipboard
 */
export async function copyToClipboard(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch (error) {
    console.error('Failed to copy to clipboard:', error)
    return false
  }
}

// ============================================================================
// Unified Execution API (routes.ts endpoints)
// Uses /api/workflows/* instead of /api/ai_assistant/*
// Provides sandbox/production mode with tunable data scope
// ============================================================================

import type {
  ExecutionRun,
  ExecutionConfig,
  DataScope,
  StepExecution,
  UserInteraction,
  ExecutionRunStatus,
} from '@shared/schema'

const EXECUTION_API_BASE = '/api/workflows'

export interface ExecuteWorkflowRequest {
  workflowDefinition: any
  workflowName?: string
  executionConfig?: Partial<ExecutionConfig>
  inputs?: Array<{ id: string; src: string; step_id?: number }>
  projectId?: string
}

export interface ExecuteWorkflowResponse {
  runId: string
  galaxyInvocationId: string
  galaxyHistoryId: string
  status: string
  dataScopeApplied: {
    fraction: number
    absoluteCount: number
    sampledIds: string[]
  }
}

export interface RunStatusResponse {
  runId: string
  status: ExecutionRunStatus
  progress: ExecutionRun['progress']
  metrics?: ExecutionRun['metrics']
  steps?: StepExecution[]
  errorMessage?: string
}

export interface RunComparisonResponse {
  runA: ExecutionRun
  runB: ExecutionRun
  comparison: {
    dataScopeDelta: { fractionA: number; fractionB: number }
    parameterDifferences: Array<{
      toolId: string
      parameter: string
      valueA: any
      valueB: any
    }>
    runtimeDelta?: number
    qualityDelta?: Record<string, number>
  }
}

export interface PromoteRunResponse {
  productionRunId: string
  sandboxRunId: string
  status: string
  message: string
}

/**
 * Execute a workflow with unified configuration (sandbox or production mode)
 */
export async function executeWorkflow(
  request: ExecuteWorkflowRequest
): Promise<ExecuteWorkflowResponse> {
  const response = await fetch(`${EXECUTION_API_BASE}/execute`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(request),
  })

  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: response.statusText }))
    throw new Error(error.error || 'Failed to execute workflow')
  }

  return response.json()
}

/**
 * Get all execution runs for the current user
 */
export async function getExecutionRuns(options?: {
  mode?: 'sandbox' | 'production'
  projectId?: string
  limit?: number
}): Promise<ExecutionRun[]> {
  const params = new URLSearchParams()
  if (options?.mode) params.set('mode', options.mode)
  if (options?.projectId) params.set('projectId', options.projectId)
  if (options?.limit) params.set('limit', options.limit.toString())

  const response = await fetch(`${EXECUTION_API_BASE}/runs?${params}`)

  if (!response.ok) {
    throw new Error('Failed to fetch execution runs')
  }

  return response.json()
}

/**
 * Get a specific execution run by ID
 */
export async function getExecutionRun(runId: string): Promise<ExecutionRun | null> {
  const response = await fetch(`${EXECUTION_API_BASE}/runs/${runId}`)

  if (!response.ok) {
    if (response.status === 404) return null
    throw new Error('Failed to fetch execution run')
  }

  return response.json()
}

/**
 * Get lightweight execution status (for polling)
 */
export async function getExecutionRunStatus(
  runId: string,
  includeSteps: boolean = false
): Promise<RunStatusResponse> {
  const params = includeSteps ? '?includeSteps=true' : ''
  const response = await fetch(`${EXECUTION_API_BASE}/runs/${runId}/status${params}`)

  if (!response.ok) {
    throw new Error('Failed to fetch run status')
  }

  return response.json()
}

/**
 * Get all runs in an iteration chain
 */
export async function getExecutionIterations(runId: string): Promise<ExecutionRun[]> {
  const response = await fetch(`${EXECUTION_API_BASE}/runs/${runId}/iterations`)

  if (!response.ok) {
    throw new Error('Failed to fetch iterations')
  }

  return response.json()
}

/**
 * Pause an execution run
 */
export async function pauseExecutionRun(runId: string, reason?: string): Promise<ExecutionRun> {
  const response = await fetch(`${EXECUTION_API_BASE}/runs/${runId}/pause`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ reason }),
  })

  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Failed to pause' }))
    throw new Error(error.error || 'Failed to pause run')
  }

  return response.json()
}

/**
 * Resume a paused execution run
 */
export async function resumeExecutionRun(runId: string): Promise<ExecutionRun> {
  const response = await fetch(`${EXECUTION_API_BASE}/runs/${runId}/resume`, {
    method: 'POST',
  })

  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Failed to resume' }))
    throw new Error(error.error || 'Failed to resume run')
  }

  return response.json()
}

/**
 * Cancel an execution run
 */
export async function cancelExecutionRun(runId: string, reason?: string): Promise<ExecutionRun> {
  const response = await fetch(`${EXECUTION_API_BASE}/runs/${runId}/cancel`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ reason }),
  })

  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Failed to cancel' }))
    throw new Error(error.error || 'Failed to cancel run')
  }

  return response.json()
}

/**
 * Record a user interaction
 */
export async function recordInteraction(
  runId: string,
  interaction: Partial<UserInteraction>
): Promise<ExecutionRun> {
  const response = await fetch(`${EXECUTION_API_BASE}/runs/${runId}/interactions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(interaction),
  })

  if (!response.ok) {
    throw new Error('Failed to record interaction')
  }

  return response.json()
}

/**
 * Compare two execution runs
 */
export async function compareExecutionRuns(
  runId: string,
  compareWithId: string
): Promise<RunComparisonResponse> {
  const response = await fetch(`${EXECUTION_API_BASE}/runs/${runId}/compare?with=${compareWithId}`)

  if (!response.ok) {
    throw new Error('Failed to compare runs')
  }

  return response.json()
}

/**
 * Promote a sandbox run to production
 */
export async function promoteToProduction(
  runId: string,
  fullInputs: Array<{ id: string; src: string; step_id?: number }>
): Promise<PromoteRunResponse> {
  const response = await fetch(`${EXECUTION_API_BASE}/runs/${runId}/promote`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ inputs: fullInputs }),
  })

  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Failed to promote' }))
    throw new Error(error.error || 'Failed to promote to production')
  }

  return response.json()
}

/**
 * Delete an execution run
 */
export async function deleteExecutionRun(runId: string): Promise<boolean> {
  const response = await fetch(`${EXECUTION_API_BASE}/runs/${runId}`, {
    method: 'DELETE',
  })

  if (!response.ok && response.status !== 404) {
    throw new Error('Failed to delete run')
  }

  return response.ok
}

/**
 * Poll execution run status until complete
 */
export async function pollExecutionStatus(
  runId: string,
  onProgress: (status: RunStatusResponse) => void,
  options?: {
    intervalMs?: number
    maxAttempts?: number
    includeSteps?: boolean
  }
): Promise<RunStatusResponse> {
  const { intervalMs = 2000, maxAttempts = 600, includeSteps = true } = options || {}
  let attempts = 0

  return new Promise((resolve, reject) => {
    const poll = async () => {
      try {
        const status = await getExecutionRunStatus(runId, includeSteps)
        onProgress(status)

        if (['completed', 'failed', 'cancelled'].includes(status.status)) {
          resolve(status)
          return
        }

        attempts++
        if (attempts >= maxAttempts) {
          reject(new Error('Execution polling timeout'))
          return
        }

        setTimeout(poll, intervalMs)
      } catch (error) {
        reject(error)
      }
    }

    poll()
  })
}
