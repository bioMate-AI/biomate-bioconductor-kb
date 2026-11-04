import { describe, it, expect } from 'vitest'
import { shouldAppendRerunCard, isTerminalStatus, type RerunCardArgs } from './rerun-card'

const base: RerunCardArgs = {
  sourceMessageId: null,
  panelWorkflowMessageId: 'msg-A',
  prevPanelRunId: 'run-old',
  prevPanelStatus: 'completed',
  ownerRunId: 'run-old',
  newRunId: 'run-new',
}

describe('isTerminalStatus', () => {
  it('matches terminal statuses case-insensitively', () => {
    for (const s of ['completed', 'OK', 'Succeeded', 'failed', 'cancelled', 'error']) {
      expect(isTerminalStatus(s)).toBe(true)
    }
  })
  it('rejects non-terminal / empty', () => {
    for (const s of ['running', 'queued', 'idle', 'paused', '', null, undefined]) {
      expect(isTerminalStatus(s)).toBe(false)
    }
  })
})

describe('shouldAppendRerunCard', () => {
  it('appends a new card when re-running the finished run the card points at', () => {
    expect(shouldAppendRerunCard(base)).toBe(true)
    expect(shouldAppendRerunCard({ ...base, prevPanelStatus: 'failed' })).toBe(true)
  })

  it('does NOT append on a first run (previous run still running / idle)', () => {
    expect(shouldAppendRerunCard({ ...base, prevPanelStatus: 'running' })).toBe(false)
    expect(shouldAppendRerunCard({ ...base, prevPanelStatus: 'idle' })).toBe(false)
  })

  it('does NOT append when there is no previous run at all', () => {
    expect(shouldAppendRerunCard({ ...base, prevPanelRunId: null })).toBe(false)
  })

  it('does NOT append when a programmatic sourceMessageId owns the run', () => {
    expect(shouldAppendRerunCard({ ...base, sourceMessageId: 'msg-explicit' })).toBe(false)
  })

  it('does NOT append when no card is bound to the panel', () => {
    expect(shouldAppendRerunCard({ ...base, panelWorkflowMessageId: null })).toBe(false)
  })

  it('does NOT append for a DIFFERENT workflow whose card does not point at the finished run', () => {
    // A finished run is on-screen, but the user launches another card's first run.
    expect(shouldAppendRerunCard({ ...base, ownerRunId: null })).toBe(false)
    expect(shouldAppendRerunCard({ ...base, ownerRunId: 'run-unrelated' })).toBe(false)
  })

  it('does NOT append when the "new" run id equals the previous (resume/in-place, not a new run)', () => {
    expect(shouldAppendRerunCard({ ...base, newRunId: 'run-old' })).toBe(false)
  })

  it('accepts the invocationId as the owner run id', () => {
    expect(shouldAppendRerunCard({ ...base, ownerRunId: 'run-old' })).toBe(true)
  })
})
