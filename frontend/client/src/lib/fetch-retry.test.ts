import { describe, it, expect, vi, afterEach } from 'vitest'
import { fetchWithRetry, isRetryableNetworkError } from './fetch-retry'

const okResponse = () => new Response('{}', { status: 200 })
const errResponse = (status: number) => new Response('{}', { status })

afterEach(() => vi.restoreAllMocks())

describe('isRetryableNetworkError', () => {
  it('treats TypeError (Failed to fetch) as retryable', () => {
    expect(isRetryableNetworkError(new TypeError('Failed to fetch'))).toBe(true)
    expect(isRetryableNetworkError(new Error('net::ERR_FAILED'))).toBe(true)
    expect(isRetryableNetworkError(new Error('NetworkError when attempting to fetch'))).toBe(true)
  })
  it('does NOT treat HTTP-shaped errors as retryable', () => {
    expect(isRetryableNetworkError(new Error('HTTP 500'))).toBe(false)
    expect(isRetryableNetworkError(new Error('Unauthorized'))).toBe(false)
  })
})

describe('fetchWithRetry', () => {
  it('retries a GET on transient network error, then succeeds', async () => {
    const fetchMock = vi.fn()
      .mockRejectedValueOnce(new TypeError('Failed to fetch'))
      .mockResolvedValueOnce(okResponse())
    vi.stubGlobal('fetch', fetchMock)

    const res = await fetchWithRetry('/api/projects', {}, 3, [1, 1])
    expect(res.status).toBe(200)
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('does NOT retry an HTTP error response (returns it unchanged)', async () => {
    const fetchMock = vi.fn().mockResolvedValue(errResponse(500))
    vi.stubGlobal('fetch', fetchMock)

    const res = await fetchWithRetry('/api/projects', {}, 3, [1, 1])
    expect(res.status).toBe(500)
    expect(fetchMock).toHaveBeenCalledTimes(1) // no retry on 5xx
  })

  it('does NOT retry a non-idempotent POST on network error', async () => {
    const fetchMock = vi.fn().mockRejectedValue(new TypeError('Failed to fetch'))
    vi.stubGlobal('fetch', fetchMock)

    await expect(
      fetchWithRetry('/api/projects', { method: 'POST' }, 3, [1, 1])
    ).rejects.toThrow(/Failed to fetch/)
    expect(fetchMock).toHaveBeenCalledTimes(1) // never double-submit a write
  })

  it('exhausts attempts and throws if every try is a network error', async () => {
    const fetchMock = vi.fn().mockRejectedValue(new TypeError('Failed to fetch'))
    vi.stubGlobal('fetch', fetchMock)

    await expect(fetchWithRetry('/api/projects', {}, 3, [1, 1])).rejects.toThrow(/Failed to fetch/)
    expect(fetchMock).toHaveBeenCalledTimes(3)
  })
})
