/**
 * Sequential workflow chain submission (Phase 1 MVI + Phase 2 connections/resume).
 */

export interface ChainConnection {
  from_step: number
  from_output: string
  to_step: number
  to_input: string
}

export interface ChainStepSubmit {
  nextflow_path?: string | null
  workflow_name?: string
  role?: string
  step_key?: string
  params?: Record<string, unknown>
}

export interface ChainSubmitResult {
  chain_run_id: string
  runId?: string
  status: string
  steps?: unknown[]
  resumed_from_step?: number | null
}

export interface ChainOutputsResponse {
  chain_run_id: string
  output_files: Array<Record<string, unknown>>
  steps: Array<Record<string, unknown>>
  count: number
}

export function buildChainSubmitSteps(chainSteps: unknown[]): ChainStepSubmit[] {
  return (chainSteps || []).map((raw) => {
    const s = (raw || {}) as Record<string, unknown>
    return {
      nextflow_path:
        (s.nextflow_path as string | undefined) ||
        (s.workflow_path as string | undefined) ||
        (s.nextflowPath as string | undefined) ||
        null,
      workflow_name:
        (s.workflow_name as string | undefined) ||
        (s.name as string | undefined),
      role: (s.role as string | undefined),
      step_key:
        (s.step_key as string | undefined) ||
        (s.stepKey as string | undefined),
      params:
        (s.params_template as Record<string, unknown> | undefined) ||
        (s.params as Record<string, unknown> | undefined) ||
        (s.parameters as Record<string, unknown> | undefined) ||
        {},
    }
  })
}

export function buildChainConnections(workflow: Record<string, unknown>): ChainConnection[] {
  const raw =
    workflow.chain_connections ||
    workflow.connections ||
    []
  if (!Array.isArray(raw)) return []
  return raw.map((c: Record<string, unknown>) => ({
    from_step: Number(c.from_step),
    from_output: String(c.from_output || ''),
    to_step: Number(c.to_step),
    to_input: String(c.to_input || ''),
  }))
}

export async function submitWorkflowChain(options: {
  steps: ChainStepSubmit[]
  chainName?: string
  chatSessionId?: string
  chainRunId?: string
  connections?: ChainConnection[]
  startFromStep?: number
  endAtStep?: number
}): Promise<ChainSubmitResult> {
  const resp = await fetch('/api/workflows/chain', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      steps: options.steps,
      chain_name: options.chainName,
      chatSessionId: options.chatSessionId,
      chain_run_id: options.chainRunId,
      connections: options.connections,
      start_from_step: options.startFromStep,
      end_at_step: options.endAtStep,
    }),
  })
  const data = (await resp.json().catch(() => ({}))) as ChainSubmitResult & {
    error?: string
    detail?: string
  }
  if (!resp.ok) {
    throw new Error(data.error || data.detail || `Chain submit failed (${resp.status})`)
  }
  return data
}

export async function resumeWorkflowChain(options: {
  chainRunId: string
  steps: ChainStepSubmit[]
  connections?: ChainConnection[]
  startFromStep: number
  endAtStep?: number
  chainName?: string
  chatSessionId?: string
}): Promise<ChainSubmitResult> {
  return submitWorkflowChain({
    ...options,
    chainRunId: options.chainRunId,
    startFromStep: options.startFromStep,
    endAtStep: options.endAtStep ?? options.startFromStep,
  })
}

export async function fetchChainOutputs(chainRunId: string): Promise<ChainOutputsResponse> {
  const resp = await fetch(`/api/workflows/chain/${encodeURIComponent(chainRunId)}/outputs`)
  if (!resp.ok) {
    throw new Error(`Failed to fetch chain outputs (${resp.status})`)
  }
  return resp.json()
}

export async function fetchChainManifest(chainRunId: string): Promise<Record<string, unknown>> {
  const resp = await fetch(`/api/workflows/chain/${encodeURIComponent(chainRunId)}/manifest`)
  if (!resp.ok) {
    throw new Error(`Failed to fetch chain manifest (${resp.status})`)
  }
  return resp.json()
}

export async function pollChainStatus(
  chainRunId: string,
  options?: { intervalMs?: number; timeoutMs?: number },
): Promise<{ status: string; payload: Record<string, unknown> }> {
  const intervalMs = options?.intervalMs ?? 5000
  const timeoutMs = options?.timeoutMs ?? 20 * 60 * 1000
  const terminal = new Set(['succeeded', 'failed', 'cancelled', 'awaiting_approval'])
  const started = Date.now()

  while (Date.now() - started < timeoutMs) {
    const resp = await fetch(`/api/workflows/chain/${encodeURIComponent(chainRunId)}`)
    if (resp.ok) {
      const payload = (await resp.json()) as Record<string, unknown>
      const status = String(payload.status || 'running').toLowerCase()
      if (terminal.has(status)) {
        return { status, payload }
      }
    }
    await new Promise((r) => setTimeout(r, intervalMs))
  }
  return { status: 'timeout', payload: {} }
}

/**
 * Submit a chain or pipeline workflow artifact from chat metadata.
 */
export async function submitWorkflowFromArtifact(
  workflow: Record<string, unknown>,
  chatSessionId?: string,
  options?: { startFromStep?: number; chainRunId?: string; endAtStep?: number },
): Promise<ChainSubmitResult> {
  const steps = buildChainSubmitSteps(
    (workflow.chain_steps as unknown[]) ||
    (workflow.pipeline_steps as unknown[]) ||
    [],
  )
  const connections = buildChainConnections(workflow)
  return submitWorkflowChain({
    steps,
    connections,
    chainName:
      (workflow.chain_display_name as string) ||
      (workflow.name as string) ||
      (workflow.chain_name as string),
    chatSessionId,
    chainRunId: options?.chainRunId,
    startFromStep: options?.startFromStep,
    endAtStep: options?.endAtStep,
  })
}
