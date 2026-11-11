import { describe, it, expect } from 'vitest'
import { chatRetryDelaysMs, getChatAsyncGuidance, getExecutionAsyncGuidance, isGatewayError, isTransientChatError } from './async-guidance'

describe('getChatAsyncGuidance', () => {
  // DB / infra errors must NOT be "Connection error"
  it('DB connection terminated → Workflow generation failed (not Connection error)', () => {
    const g = getChatAsyncGuidance('Connection terminated unexpectedly')
    expect(g.title).toBe('Workflow generation failed')
    expect(g.isNetworkRelated).toBe(false)
    // Must not expose raw DB message
    expect(g.reason).not.toMatch(/terminated|connection/i)
  })

  it('connection refused → Workflow generation failed (not Connection error)', () => {
    const g = getChatAsyncGuidance('connection refused')
    expect(g.title).toBe('Workflow generation failed')
    expect(g.isNetworkRelated).toBe(false)
    expect(g.reason).not.toMatch(/refused|connection/i)
  })

  it('ECONNREFUSED → Workflow generation failed', () => {
    const g = getChatAsyncGuidance('connect ECONNREFUSED 127.0.0.1:8081')
    expect(g.title).toBe('Workflow generation failed')
    expect(g.isNetworkRelated).toBe(false)
    expect(g.reason).not.toMatch(/ECONNREFUSED|127\.0\.0/i)
  })

  it('pool is draining → Workflow generation failed, generic reason', () => {
    const g = getChatAsyncGuidance('pool is draining and will not accept work')
    expect(g.title).toBe('Workflow generation failed')
    expect(g.isNetworkRelated).toBe(false)
    expect(g.reason).not.toMatch(/pool|draining/i)
  })

  it('ECONNRESET → Workflow generation failed', () => {
    const g = getChatAsyncGuidance('ECONNRESET')
    expect(g.title).toBe('Workflow generation failed')
    expect(g.isNetworkRelated).toBe(false)
  })

  // Browser network errors must stay "Connection error"
  it('Failed to fetch → Connection error', () => {
    const g = getChatAsyncGuidance('Failed to fetch')
    expect(g.title).toBe('Connection error')
    expect(g.isNetworkRelated).toBe(true)
  })

  it('Load failed (iOS Safari) → Connection error', () => {
    const g = getChatAsyncGuidance('Load failed')
    expect(g.title).toBe('Connection error')
    expect(g.isNetworkRelated).toBe(true)
  })

  it('The network connection was lost (iOS Safari) → Connection error', () => {
    const g = getChatAsyncGuidance('The network connection was lost.')
    expect(g.title).toBe('Connection error')
    expect(g.isNetworkRelated).toBe(true)
  })

  it('NetworkError when attempting to fetch (Firefox) → Connection error', () => {
    const g = getChatAsyncGuidance('NetworkError when attempting to fetch resource')
    expect(g.title).toBe('Connection error')
    expect(g.isNetworkRelated).toBe(true)
  })

  // navigator.onLine=false alone must NOT trigger Connection error when there IS an error msg
  it('isOnline=false with actual error msg → classified by error, not navigator', () => {
    const g = getChatAsyncGuidance('Chat API error: Internal Server Error', { isOnline: false })
    expect(g.title).toBe('Workflow generation failed')
    expect(g.isNetworkRelated).toBe(false)
  })

  // isOnline=false with no error → Connection error (truly offline, empty error string)
  it('isOnline=false with no error message → Connection error', () => {
    const g = getChatAsyncGuidance('', { isOnline: false })
    expect(g.title).toBe('Connection error')
  })

  // Rate limit
  it('temporarily busy → Service temporarily busy', () => {
    const g = getChatAsyncGuidance('Chat API error: The service is temporarily busy. Please wait a moment and try again.')
    expect(g.title).toBe('Service temporarily busy')
  })

  // Timeout
  it('timeout → Response timed out', () => {
    const g = getChatAsyncGuidance('request timeout')
    expect(g.title).toBe('Response timed out')
    expect(g.isTimeout).toBe(true)
  })
})

describe('isTransientChatError (workflow-generation auto-retry policy)', () => {
  // ---- TRANSIENT: should retry ----
  it('browser "Failed to fetch" is transient', () => {
    expect(isTransientChatError('Failed to fetch')).toBe(true)
  })

  it('request timeout is transient', () => {
    expect(isTransientChatError('Workflow generation timed out after 120s')).toBe(true)
  })

  it('per-attempt timeout flag (via message) is transient', () => {
    expect(isTransientChatError('request timed out')).toBe(true)
  })

  it('empty / incomplete stream is transient', () => {
    expect(isTransientChatError('No final payload received from stream')).toBe(true)
    expect(isTransientChatError('Streaming response body unavailable')).toBe(true)
  })

  it('HTTP 5xx is transient', () => {
    expect(isTransientChatError('Chat API error: Internal Server Error', { httpStatus: 500 })).toBe(true)
    expect(isTransientChatError('Chat API error: Bad Gateway', { httpStatus: 502 })).toBe(true)
    expect(isTransientChatError('Chat API error: Service Unavailable', { httpStatus: 503 })).toBe(true)
  })

  it('HTTP 429 rate-limit is transient', () => {
    expect(isTransientChatError('temporarily busy', { httpStatus: 429 })).toBe(true)
    expect(isTransientChatError('The service is temporarily busy. Please wait a moment and try again.')).toBe(true)
  })

  it('upstream gateway / socket-reset messages are transient', () => {
    expect(isTransientChatError('502 Bad Gateway from upstream')).toBe(true)
    expect(isTransientChatError('socket hang up')).toBe(true)
    expect(isTransientChatError('read ECONNRESET')).toBe(true)
  })

  it('legacy __maintenance__ sentinel is treated as transient', () => {
    expect(isTransientChatError('__maintenance__')).toBe(true)
  })

  // ---- DETERMINISTIC: must NOT retry ----
  it('user abort is never retried', () => {
    expect(isTransientChatError('aborted', { aborted: true })).toBe(false)
    // even a "transient-looking" message must not retry when aborted
    expect(isTransientChatError('Failed to fetch', { aborted: true })).toBe(false)
  })

  it('HTTP 4xx client errors are NOT retried', () => {
    expect(isTransientChatError('Bad Request', { httpStatus: 400 })).toBe(false)
    expect(isTransientChatError('Unauthorized', { httpStatus: 401 })).toBe(false)
    expect(isTransientChatError('Forbidden', { httpStatus: 403 })).toBe(false)
    expect(isTransientChatError('Not Found', { httpStatus: 404 })).toBe(false)
    expect(isTransientChatError('Unprocessable Entity', { httpStatus: 422 })).toBe(false)
  })

  it('validation / clarification responses are NOT retried', () => {
    expect(isTransientChatError('parameter validation failed')).toBe(false)
    expect(isTransientChatError('needs_input: missing genome')).toBe(false)
    expect(isTransientChatError('clarification required')).toBe(false)
    expect(isTransientChatError('invalid SMILES string')).toBe(false)
  })

  it('unrecognised / empty errors are NOT retried (conservative default)', () => {
    expect(isTransientChatError('')).toBe(false)
    expect(isTransientChatError(null)).toBe(false)
    expect(isTransientChatError('some unexpected non-transient failure')).toBe(false)
  })

  it('deterministic message wins even if a 5xx-ish word appears', () => {
    // "invalid" is deterministic and takes precedence over any weak transient hint
    expect(isTransientChatError('invalid gateway parameter')).toBe(false)
  })
})

describe('getExecutionAsyncGuidance', () => {
  it('navigator.onLine=false with non-network error → Execution failed (not Connection issue)', () => {
    const g = getExecutionAsyncGuidance('Chat API error: Internal Server Error', { isOnline: false })
    expect(g.title).toBe('Execution failed')
    expect(g.isNetworkRelated).toBe(false)
  })

  it('Failed to fetch → Connection issue during execution', () => {
    const g = getExecutionAsyncGuidance('Failed to fetch')
    expect(g.title).toBe('Connection issue during execution')
    expect(g.isNetworkRelated).toBe(true)
  })

  it('Connection terminated → Execution failed (not Connection issue)', () => {
    const g = getExecutionAsyncGuidance('Connection terminated unexpectedly')
    expect(g.title).toBe('Execution failed')
    expect(g.isNetworkRelated).toBe(false)
    expect(g.reason).not.toMatch(/terminated|connection/i)
  })

  it('etimedout → Execution timed out', () => {
    const g = getExecutionAsyncGuidance('ETIMEDOUT')
    expect(g.title).toBe('Execution timed out')
    expect(g.isTimeout).toBe(true)
  })
})

// Dev 2026-11-11 04:04:19–04:04:24 UTC: the frontend container was replaced mid-request; nginx returned
// 502 for ~5 s. The client's two retries (0.8 s, 1.6 s) both landed in that window and the user saw
// "Chat API error: Bad Gateway — Rephrase the request…" for a request that would have succeeded.
describe('gateway errors (app server restarting)', () => {
  it('detects 502/503/504 by status or message', () => {
    expect(isGatewayError('Chat API error: Bad Gateway')).toBe(true)
    expect(isGatewayError('Chat API error: 502')).toBe(true)
    expect(isGatewayError('x', 504)).toBe(true)
    expect(isGatewayError('Chat API error: Not Found', 404)).toBe(false)
  })
  it('retries a gateway error across a restart window (> 5 s), others keep the short schedule', () => {
    const gw = chatRetryDelaysMs('Chat API error: Bad Gateway', 502)
    expect(gw.reduce((a, b) => a + b, 0)).toBeGreaterThan(5000)
    expect(chatRetryDelaysMs('No final payload received', null)).toEqual([800, 1600])
  })
  it('tells the user to resend unchanged, not to rephrase', () => {
    const g = getChatAsyncGuidance('Chat API error: Bad Gateway')
    expect(g.title).toBe('BioMate was briefly unavailable')
    expect(g.retry).not.toMatch(/rephrase/i)
  })
})
