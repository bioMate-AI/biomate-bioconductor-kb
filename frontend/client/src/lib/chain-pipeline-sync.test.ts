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
