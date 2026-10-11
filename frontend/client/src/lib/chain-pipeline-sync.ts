/**
 * Sync pipeline step statuses from chain executor polling.
 */

export type PipelineStepStatus = 'pending' | 'running' | 'completed' | 'failed' | 'skipped' | 'blocked' | 'submitting'

export function mapChainStepStatus(chainStatus: string | undefined): PipelineStepStatus {
  const s = (chainStatus || 'pending').toLowerCase()
  if (s === 'succeeded' || s === 'completed' || s === 'ok') return 'completed'
  if (s === 'running' || s === 'submitting' || s === 'blocked') return s
  if (s === 'failed' || s === 'error') return 'failed'
  if (s === 'skipped' || s === 'cancelled') return 'skipped'
  return 'pending'
}

export function mapChainRunStatus(chainStatus: string | undefined): string {
  const s = (chainStatus || 'running').toLowerCase()
  if (s === 'awaiting_approval') return 'paused'
  if (s === 'succeeded' || s === 'completed') return 'completed'
  if (s === 'partial' || s === 'blocked') return s
  if (s === 'failed') return 'failed'
  if (s === 'cancelled') return 'cancelled'
  return 'running'
}

export function syncPipelineStepsFromChain(
  pipelineSteps: Record<string, unknown>[],
  chainSteps: Record<string, unknown>[],
): Record<string, unknown>[] {
  const key = (step: Record<string, unknown>) => step.step_key || step.stepKey
  const hasKeys = pipelineSteps.some(step => key(step) != null)
  return pipelineSteps.map((ps, idx) => {
    const stepKey = key(ps)
    const matches = stepKey != null ? chainSteps.filter(step => key(step) === stepKey) : []
    // Legacy unkeyed artifacts use positional matching (the server may generate keys).
    // Missing or duplicate keyed records must not update an unrelated biological case.
    const cs = hasKeys ? (matches.length === 1 ? matches[0] : undefined) : chainSteps[idx]
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

/** Awaiting approval is resumable, so it is not a terminal parent state. */
export function isChainTerminal(status: unknown): boolean {
  return ['succeeded', 'completed', 'failed', 'error', 'cancelled', 'canceled', 'partial', 'blocked']
    .includes(String(status || '').toLowerCase())
}

/** Preserve parent-only transitions even when no child status has changed. */
export function syncWorkflowFromChain(
  workflow: Record<string, unknown>, payload: Record<string, unknown>,
): Record<string, unknown> {
  const stepsKey = workflow.workflow_type === 'pipeline' ? 'pipeline_steps' : 'chain_steps'
  const existing = (workflow[stepsKey] as Record<string, unknown>[]) || []
  const steps = Array.isArray(payload.steps)
    ? syncPipelineStepsFromChain(existing, payload.steps as Record<string, unknown>[]) : existing
  const status = String(payload.status || 'running').toLowerCase()
  if (JSON.stringify(steps) === JSON.stringify(existing) && workflow.chain_status === status) return workflow
  return { ...workflow, [stepsKey]: steps, chain_status: status }
}
