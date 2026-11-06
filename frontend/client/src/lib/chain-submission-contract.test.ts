import { afterEach, expect, it, vi } from 'vitest'
import { pollChainStatus, submitWorkflowFromArtifact } from './chain-execution'
afterEach(() => vi.unstubAllGlobals())
it('sends coverage, concurrency and all branches in the actual request body', async () => {
  const fetcher = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ chain_run_id: 'fixture', status: 'running' }) })
  vi.stubGlobal('fetch', fetcher)
  await submitWorkflowFromArtifact({
    pipeline_steps: [{ step_key: 'a', depends_on: [], dimensions: { target: 'A' } }, { step_key: 'b', depends_on: [1] }],
    coverage_axes: { target: ['A'] }, max_parallel: 2,
  })
  const body = JSON.parse(fetcher.mock.calls[0][1].body)
  expect(body.coverage_axes).toEqual({ target: ['A'] })
  expect(body.max_parallel).toBe(2)
  expect(body.steps.map((step: any) => step.depends_on)).toEqual([[], [1]])
})
it('rejects linear approval ranges on an explicit DAG before any submission', async () => {
  const fetcher = vi.fn(); vi.stubGlobal('fetch', fetcher)
  await expect(submitWorkflowFromArtifact({ pipeline_steps: [{ depends_on: [] }] }, undefined, { endAtStep: 0 }))
    .rejects.toThrow('whole-plan submission')
  expect(fetcher).not.toHaveBeenCalled()
})
it('retains sequential step approval for legacy plans', async () => {
  const fetcher = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ chain_run_id: 'legacy' }) })
  vi.stubGlobal('fetch', fetcher)
  await submitWorkflowFromArtifact({ pipeline_steps: [{ workflow_name: 'first' }] }, undefined, { endAtStep: 0 })
  const body = JSON.parse(fetcher.mock.calls[0][1].body)
  expect(body.end_at_step).toBe(0)
  expect(body.steps[0]).not.toHaveProperty('depends_on')
})
it('stops polling when a parent is partially complete', async () => {
  const fetcher = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ status: 'partial' }) })
  vi.stubGlobal('fetch', fetcher)
  expect((await pollChainStatus('fixture', { timeoutMs: 100 })).status).toBe('partial')
  expect(fetcher).toHaveBeenCalledTimes(1)
})

it('uses whole-plan approval for explicit graphs and step approval for legacy pipelines', async () => {
  const { pipelineApprovalOptions } = await import('./chain-execution')
  const fetcher = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ chain_run_id: 'graph' }) })
  vi.stubGlobal('fetch', fetcher)
  const graph = { pipeline_steps: [{ depends_on: [] }, { depends_on: [1] }] }
  await submitWorkflowFromArtifact(graph, undefined, pipelineApprovalOptions(graph))
  expect(JSON.parse(fetcher.mock.calls[0][1].body)).not.toHaveProperty('end_at_step')
  expect(pipelineApprovalOptions({ pipeline_steps: [{ workflow_name: 'legacy' }] })).toEqual({ endAtStep: 0 })
})
