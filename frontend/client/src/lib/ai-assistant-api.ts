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
 */
export async function startPilotRun(
  workflowId: string,
  totalSamples: number,
  config?: Partial<TuningConfig>,
  sampleIds?: string[]
): Promise<StartPilotResponse> {
  const response = await fetch(`${API_BASE}/pilot/start`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      workflow_id: workflowId,
      total_samples: totalSamples,
      config: config ? {
        pilot_fraction: config.pilot_fraction ?? 0.1,
        sampling_strategy: config.sampling_strategy ?? 'stratified',
        strata_column: config.strata_column,
        min_pilot_samples: config.min_pilot_samples ?? 3,
        max_pilot_samples: config.max_pilot_samples ?? 50
      } : null,
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
