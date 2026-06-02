/**
 * Sync pipeline step statuses from chain executor polling.
 */

export type PipelineStepStatus = 'pending' | 'running' | 'completed' | 'failed' | 'skipped'

export function mapChainStepStatus(chainStatus: string | undefined): PipelineStepStatus {
  const s = (chainStatus || 'pending').toLowerCase()
  if (s === 'succeeded' || s === 'completed' || s === 'ok') return 'completed'
  if (s === 'running') return 'running'
  if (s === 'failed' || s === 'error') return 'failed'
  if (s === 'skipped' || s === 'cancelled') return 'skipped'
  return 'pending'
}

export function mapChainRunStatus(chainStatus: string | undefined): string {
  const s = (chainStatus || 'running').toLowerCase()
  if (s === 'awaiting_approval') return 'paused'
  if (s === 'succeeded') return 'completed'
  if (s === 'failed') return 'failed'
  if (s === 'cancelled') return 'cancelled'
  return 'running'
}

export function syncPipelineStepsFromChain(
  pipelineSteps: Record<string, unknown>[],
  chainSteps: Record<string, unknown>[],
): Record<string, unknown>[] {
  return pipelineSteps.map((ps, idx) => {
    const cs = chainSteps[idx] as Record<string, unknown> | undefined
    if (!cs) return ps
    return {
      ...ps,
      status: mapChainStepStatus(String(cs.status || '')),
      errorMessage: cs.error || ps.errorMessage,
      run_id: cs.run_id || ps.run_id,
    }
  })
}

export async function fetchChainStatus(chainRunId: string): Promise<Record<string, unknown>> {
  const resp = await fetch(`/api/workflows/chain/${encodeURIComponent(chainRunId)}`)
  if (!resp.ok) {
    throw new Error(`Chain status fetch failed (${resp.status})`)
  }
  return resp.json()
}
