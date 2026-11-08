import { describe, expect, it } from 'vitest'
import {
  mapChainRunStatus,
  mapChainStepStatus,
  syncPipelineStepsFromChain,
} from './chain-pipeline-sync'

describe('chain-pipeline-sync', () => {
  it('maps chain step statuses to pipeline UI statuses', () => {
    expect(mapChainStepStatus('succeeded')).toBe('completed')
    expect(mapChainStepStatus('running')).toBe('running')
    expect(mapChainStepStatus('failed')).toBe('failed')
  })

  it('maps awaiting_approval to paused for run manager', () => {
    expect(mapChainRunStatus('awaiting_approval')).toBe('paused')
    expect(mapChainRunStatus('succeeded')).toBe('completed')
  })

  it('syncs pipeline steps from chain poll payload', () => {
    const synced = syncPipelineStepsFromChain(
      [
        { id: 'step-1', workflow_name: 'pocket', status: 'pending' },
        { id: 'step-2', workflow_name: 'admet', status: 'pending' },
      ],
      [
        { status: 'succeeded', run_id: 'run-a' },
        { status: 'pending' },
      ],
    )
    expect(synced[0].status).toBe('completed')
    expect(synced[0].run_id).toBe('run-a')
    expect(synced[1].status).toBe('pending')
  })
})

it('preserves blocked, submitting and partial states', () => {
  expect(mapChainStepStatus('blocked')).toBe('blocked')
  expect(mapChainStepStatus('submitting')).toBe('submitting')
  expect(mapChainRunStatus('partial')).toBe('partial')
})
it('matches reordered branches by stable key rather than array position', () => {
  const result = syncPipelineStepsFromChain(
    [{ step_key: 'a', status: 'pending' }, { step_key: 'b', status: 'pending' }],
    [{ step_key: 'b', status: 'failed', run_id: 'b-run' }, { step_key: 'a', status: 'succeeded', run_id: 'a-run' }],
  )
  expect(result.map(row => [row.status, row.run_id])).toEqual([['completed', 'a-run'], ['failed', 'b-run']])
})
it('does not assign an unmatched or ambiguous keyed result by position', () => {
  const original = [{ step_key: 'a', status: 'pending' }]
  expect(syncPipelineStepsFromChain(original, [{ step_key: 'b', status: 'failed' }])).toEqual(original)
  expect(syncPipelineStepsFromChain(original, [{ step_key: 'a', status: 'failed' }, { step_key: 'a', status: 'succeeded' }])).toEqual(original)
})
it('retains legacy unkeyed artifact sync when the server generates step keys', () => {
  expect(syncPipelineStepsFromChain([{ workflow_name: 'legacy' }], [{ step_key: 'legacy', status: 'succeeded' }])[0].status).toBe('completed')
})

it('persists parent-only transitions and stops terminal polling while keeping approval resumable', async () => {
  const { syncWorkflowFromChain, isChainTerminal } = await import('./chain-pipeline-sync')
  const workflow = { workflow_type: 'pipeline', chain_status: 'running', pipeline_steps: [] }
  const updated = syncWorkflowFromChain(workflow, { status: 'partial', steps: [] })
  expect(updated.chain_status).toBe('partial')
  expect(updated).not.toBe(workflow)
  expect(syncWorkflowFromChain(updated, { status: 'partial', steps: [] })).toBe(updated)
  expect(isChainTerminal('partial')).toBe(true)
  expect(isChainTerminal('awaiting_approval')).toBe(false)
})
