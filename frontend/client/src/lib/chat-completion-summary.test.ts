import { describe, it, expect } from 'vitest'
import { buildRunCompletionSummary } from './chat-completion-summary'

describe('buildRunCompletionSummary', () => {
  it('surfaces REAL summary + key_results when findings are ready', () => {
    const data = {
      status: 'ready',
      summary: '1 of 2 compounds passed the hERG liability filter.',
      key_results: [
        { metric: 'Aspirin hERG IC50', value: '32 µM', interpretation: 'pass' },
        { metric: 'Compound-B hERG IC50', value: '4 µM', interpretation: 'flagged' },
      ],
    }
    const out = buildRunCompletionSummary('Predict ADMET Properties', data, 2)
    expect(out).toContain('**Predict ADMET Properties — complete.** 2 steps completed.')
    expect(out).toContain('1 of 2 compounds passed the hERG liability filter.')
    expect(out).toContain('**Key results:**')
    expect(out).toContain('**Aspirin hERG IC50:** 32 µM — pass')
    expect(out).toContain('**Compound-B hERG IC50:** 4 µM — flagged')
    expect(out).toContain('[Open the Findings panel](#findings)')
    expect(out).not.toContain('analyzing results')
  })

  it('caps key results at 3', () => {
    const data = {
      status: 'ready',
      key_results: [{ finding: 'a' }, { finding: 'b' }, { finding: 'c' }, { finding: 'd' }],
    }
    const out = buildRunCompletionSummary('WF', data, 3)
    expect(out).toContain('- a')
    expect(out).toContain('- c')
    expect(out).not.toContain('- d')
  })

  it('accepts camelCase keyResults and string entries', () => {
    const data = { status: 'ready', keyResults: ['first thing', 'second thing'] }
    const out = buildRunCompletionSummary('WF', data, 2)
    expect(out).toContain('- first thing')
    expect(out).toContain('- second thing')
  })

  it('reports the in-process "analyzing" state (no fabrication) when findings are pending', () => {
    const out = buildRunCompletionSummary('Predict ADMET Properties', { status: 'pending' }, 2)
    expect(out).toBe(
      '**Predict ADMET Properties — complete.** 2 steps completed — analyzing results… ' +
        '[Open the Findings panel](#findings) for full results, tables, and the downloadable report.',
    )
    expect(out).not.toContain('Key results')
  })

  it('reports analyzing on null data (fetch error) — never throws', () => {
    const out = buildRunCompletionSummary('WF', null, 3)
    expect(out).toContain('**WF — complete.** 3 steps completed — analyzing results…')
    expect(out).not.toContain('Key results')
  })

  it('stays in analyzing when status is ready but summary/results are empty', () => {
    const out = buildRunCompletionSummary('WF', { status: 'ready', summary: '   ', key_results: [] }, 1)
    expect(out).toContain('1 step completed — analyzing results…')
    expect(out).not.toContain('Key results')
  })

  // The "0/2 steps" bug: a completed run finished ALL its steps — never show a
  // stale live counter (which read 0 at the completion instant).
  it('reports total steps completed, never a 0/N fraction', () => {
    const out = buildRunCompletionSummary('WF', { status: 'pending' }, 2)
    expect(out).toContain('2 steps completed')
    expect(out).not.toMatch(/0\/2|0 of 2/)
  })

  it('uses singular "1 step" and "run finished" when steps are 1 / unknown', () => {
    expect(buildRunCompletionSummary('WF', null, 1)).toContain('1 step completed')
    expect(buildRunCompletionSummary('WF', null, 0)).toContain('**WF — complete.** run finished — analyzing results…')
  })
})
