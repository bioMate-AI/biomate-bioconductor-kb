import { describe, it, expect } from 'vitest'
import { getChatAsyncGuidance, getExecutionAsyncGuidance } from './async-guidance'

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
