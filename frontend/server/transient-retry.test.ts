import { describe, expect, it, vi } from 'vitest';
import {
  isTransientConnMessage,
  isTransientError,
  isTransientSidecarStderr,
  retryTransientRunCode,
} from './transient-retry';

describe('isTransientConnMessage', () => {
  it('classifies connection-level blips as transient', () => {
    for (const s of [
      'connect ECONNREFUSED 172.19.0.2:8080',
      'read ECONNRESET',
      'connect ETIMEDOUT',
      'getaddrinfo EAI_AGAIN biomate-galaxy-dev',
      'TypeError: fetch failed',
      'socket hang up',
      'upstream returned HTTP 503',
    ]) {
      expect(isTransientConnMessage(s), s).toBe(true);
    }
  });

  it('does NOT treat an execution timeout / abort as transient', () => {
    expect(isTransientConnMessage('This operation was aborted')).toBe(false);
    expect(isTransientConnMessage('AbortError: The operation was aborted')).toBe(false);
  });

  it('does NOT treat genuine errors as transient', () => {
    expect(isTransientConnMessage('NameError: name np is not defined')).toBe(false);
    expect(isTransientConnMessage('HTTP 400 Bad Request')).toBe(false);
    expect(isTransientConnMessage('')).toBe(false);
    expect(isTransientConnMessage(null)).toBe(false);
  });
});

describe('isTransientError', () => {
  it('matches error codes, 5xx status, and nested cause codes', () => {
    expect(isTransientError({ code: 'ECONNREFUSED' })).toBe(true);
    expect(isTransientError({ cause: { code: 'ETIMEDOUT' } })).toBe(true);
    expect(isTransientError({ status_code: 503 })).toBe(true);
    expect(isTransientError({ response: { status: 502 } })).toBe(true);
    expect(isTransientError({ message: 'fetch failed' })).toBe(true);
  });

  it('does not match 4xx or ordinary errors', () => {
    expect(isTransientError({ response: { status: 404 } })).toBe(false);
    expect(isTransientError({ message: 'validation failed' })).toBe(false);
    expect(isTransientError(null)).toBe(false);
  });
});

describe('isTransientSidecarStderr', () => {
  it('matches the code-runner sidecar connection/5xx signatures', () => {
    expect(isTransientSidecarStderr('[sidecar fetch error: fetch failed]')).toBe(true);
    expect(isTransientSidecarStderr('[sidecar fetch error: connect ECONNREFUSED 172.19.0.2:8080]')).toBe(true);
    expect(isTransientSidecarStderr('[sidecar error: HTTP 503 Service Unavailable]')).toBe(true);
  });

  it('does NOT match an execution timeout or a non-sidecar failure', () => {
    expect(isTransientSidecarStderr('[sidecar fetch error: This operation was aborted]')).toBe(false);
    expect(isTransientSidecarStderr('[sidecar error: HTTP 500 traceback: OOM]')).toBe(false);
    expect(isTransientSidecarStderr('Traceback: ZeroDivisionError')).toBe(false);
    expect(isTransientSidecarStderr('')).toBe(false);
  });
});

describe('retryTransientRunCode', () => {
  it('retries a transient sidecar blip then returns the recovered result', async () => {
    const fn = vi
      .fn()
      .mockResolvedValueOnce({ exit_code: 1, stderr: '[sidecar fetch error: fetch failed]' })
      .mockResolvedValueOnce({ exit_code: 0, stderr: '', stdout: 'ok' });
    const result = await retryTransientRunCode(fn as any, { delaysMs: [0, 0, 0] });
    expect(fn).toHaveBeenCalledTimes(2);
    expect(result).toEqual({ exit_code: 0, stderr: '', stdout: 'ok' });
  });

  it('returns immediately on success (no wasted attempts)', async () => {
    const fn = vi.fn().mockResolvedValue({ exit_code: 0, stderr: '' });
    await retryTransientRunCode(fn as any, { delaysMs: [0, 0, 0] });
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('does NOT retry a genuine code error (honest, fast failure)', async () => {
    const fn = vi.fn().mockResolvedValue({ exit_code: 1, stderr: 'NameError: np not defined' });
    const result = await retryTransientRunCode(fn as any, { delaysMs: [0, 0, 0] });
    expect(fn).toHaveBeenCalledTimes(1);
    expect(result.exit_code).toBe(1);
  });

  it('exhausts retries on a persistent outage and returns the real error unchanged', async () => {
    const fn = vi.fn().mockResolvedValue({ exit_code: 1, stderr: '[sidecar fetch error: connect ECONNREFUSED 172.19.0.2:8080]' });
    const result = await retryTransientRunCode(fn as any, { delaysMs: [0, 0, 0] });
    expect(fn).toHaveBeenCalledTimes(3);
    expect(result.stderr).toContain('ECONNREFUSED'); // honest fallback preserved
  });
});
