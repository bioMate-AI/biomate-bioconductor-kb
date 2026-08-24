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
    const out = buildRunCompletionSummary('Predict ADMET Properties', data, 5, 5)
    expect(out).toContain('**Predict ADMET Properties — complete.**')
    expect(out).toContain('1 of 2 compounds passed the hERG liability filter.')
    expect(out).toContain('**Key results:**')
    expect(out).toContain('**Aspirin hERG IC50:** 32 µM — pass')
    expect(out).toContain('**Compound-B hERG IC50:** 4 µM — flagged')
    expect(out).toContain('[Open the Findings panel](#findings)')
  })

  it('caps key results at 3', () => {
    const data = {
      status: 'ready',
      key_results: [
        { finding: 'a' }, { finding: 'b' }, { finding: 'c' }, { finding: 'd' },
      ],
    }
    const out = buildRunCompletionSummary('WF', data, 3, 3)
    expect(out).toContain('- a')
    expect(out).toContain('- c')
    expect(out).not.toContain('- d')
  })

  it('accepts camelCase keyResults and string entries', () => {
    const data = { status: 'ready', keyResults: ['first thing', 'second thing'] }
    const out = buildRunCompletionSummary('WF', data, 2, 2)
    expect(out).toContain('- first thing')
    expect(out).toContain('- second thing')
  })

  it('falls back to a generic line (no fabricated numbers) when status is pending', () => {
    const out = buildRunCompletionSummary('Predict ADMET Properties', { status: 'pending' }, 4, 6)
    expect(out).toBe(
      '**Predict ADMET Properties — complete.** 4/6 steps finished. ' +
        '[Open the Findings panel](#findings) for full results, tables, and the downloadable report.',
    )
    // No key results / summary block leaked in.
    expect(out).not.toContain('Key results')
  })

  it('falls back to generic on null data (fetch error) — never throws', () => {
    const out = buildRunCompletionSummary('WF', null, 2, 3)
    expect(out).toContain('**WF — complete.** 2/3 steps finished.')
    expect(out).not.toContain('Key results')
  })

  it('does NOT surface values when status is ready but summary/results are empty', () => {
    // ready but nothing to say → generic line, not an empty "Key results" block
    const out = buildRunCompletionSummary('WF', { status: 'ready', summary: '   ', key_results: [] }, 1, 1)
    expect(out).toContain('**WF — complete.** 1/1 steps finished.')
    expect(out).not.toContain('Key results')
  })

  it('uses "run finished" when total steps is unknown (0)', () => {
    const out = buildRunCompletionSummary('WF', null, 0, 0)
    expect(out).toContain('**WF — complete.** run finished.')
  })
})
