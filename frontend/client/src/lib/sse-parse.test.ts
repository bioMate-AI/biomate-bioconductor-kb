import { describe, it, expect, vi } from 'vitest'
import { parseSSEData } from './sse-parse'

describe('parseSSEData', () => {
  it('parses a valid JSON frame', () => {
    expect(parseSSEData('{"data":{"workflow_state":"ok"}}')).toEqual({ data: { workflow_state: 'ok' } })
  })

  it('returns null (not throw) on a truncated/malformed frame', () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    expect(parseSSEData('{"data":{"step_id":')).toBeNull()
    expect(parseSSEData('not json')).toBeNull()
    expect(warn).toHaveBeenCalled()
    warn.mockRestore()
  })

  it('returns null on empty / non-string input', () => {
    expect(parseSSEData('')).toBeNull()
    expect(parseSSEData(undefined)).toBeNull()
    expect(parseSSEData(null)).toBeNull()
    expect(parseSSEData(42 as any)).toBeNull()
  })
})
