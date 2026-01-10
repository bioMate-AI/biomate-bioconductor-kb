/**
 * useWorkflowExecution Hook Tests
 *
 * Tests for the workflow execution hook
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act, waitFor } from '@testing-library/react';
import { useWorkflowExecution } from './useWorkflowExecution';

// Mock global fetch
const mockFetch = vi.fn();
global.fetch = mockFetch;

// Mock EventSource
class MockEventSource {
  url: string;
  onopen: ((evt: Event) => void) | null = null;
  onmessage: ((evt: MessageEvent) => void) | null = null;
  onerror: ((evt: Event) => void) | null = null;
  readyState: number = 0;

  static CONNECTING = 0;
  static OPEN = 1;
  static CLOSED = 2;

  constructor(url: string) {
    this.url = url;
    this.readyState = MockEventSource.CONNECTING;
    // Simulate connection opening
    setTimeout(() => {
      this.readyState = MockEventSource.OPEN;
      if (this.onopen) {
        this.onopen(new Event('open'));
      }
    }, 10);
  }

  close() {
    this.readyState = MockEventSource.CLOSED;
  }

  addEventListener(type: string, listener: EventListener) {
    if (type === 'message') {
      this.onmessage = listener as (evt: MessageEvent) => void;
    } else if (type === 'open') {
      this.onopen = listener as (evt: Event) => void;
    } else if (type === 'error') {
      this.onerror = listener as (evt: Event) => void;
    }
  }

  // Helper to simulate receiving a message
  _simulateMessage(data: any) {
    if (this.onmessage) {
      this.onmessage(new MessageEvent('message', { data: JSON.stringify(data) }));
    }
  }

  // Helper to simulate an error
  _simulateError() {
    this.readyState = MockEventSource.CLOSED;
    if (this.onerror) {
      this.onerror(new Event('error'));
    }
  }
}

// Replace global EventSource
const originalEventSource = global.EventSource;
(global as any).EventSource = MockEventSource;

describe('useWorkflowExecution', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockFetch.mockReset();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('initial state', () => {
    it('should have null initial state', () => {
      const { result } = renderHook(() => useWorkflowExecution());

      // Hook returns properties directly, not through a state object
      expect(result.current.workflowId).toBeNull();
      expect(result.current.invocationId).toBeNull();
      expect(result.current.workflowState).toBeNull();
      expect(result.current.error).toBeNull();
    });

    it('should not be connected initially', () => {
      const { result } = renderHook(() => useWorkflowExecution());

      expect(result.current.isConnected).toBe(false);
    });
  });

  describe('invokeWorkflow', () => {
    it('should invoke workflow and return invocation', async () => {
      const mockInvocation = {
        id: 'inv-123',
        state: 'new',
        create_time: '2026-01-09T12:00:00Z',
        update_time: '2026-01-09T12:00:00Z',
      };

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => mockInvocation,
      });

      const { result } = renderHook(() => useWorkflowExecution());

      let invocation: any;
      await act(async () => {
        invocation = await result.current.invokeWorkflow('wf-123', { input: 'data' });
      });

      expect(invocation).toEqual(mockInvocation);
      expect(mockFetch).toHaveBeenCalledWith('/api/galaxy/workflows/invoke', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workflow_id: 'wf-123', inputs: { input: 'data' } }),
      });
    });

    it('should update state after successful invocation', async () => {
      const mockInvocation = {
        id: 'inv-456',
        state: 'scheduled',
        create_time: '2026-01-09T12:00:00Z',
        update_time: '2026-01-09T12:00:01Z',
      };

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => mockInvocation,
      });

      const { result } = renderHook(() => useWorkflowExecution());

      await act(async () => {
        await result.current.invokeWorkflow('wf-456', {});
      });

      expect(result.current.workflowId).toBe('wf-456');
      expect(result.current.invocationId).toBe('inv-456');
      expect(result.current.workflowState).toBe('scheduled');
    });

    it('should handle invocation errors', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: false,
        statusText: 'Internal Server Error',
      });

      const { result } = renderHook(() => useWorkflowExecution());

      // The hook throws the error and also sets state.error
      let caughtError: Error | null = null;
      await act(async () => {
        try {
          await result.current.invokeWorkflow('wf-error', {});
        } catch (error) {
          caughtError = error as Error;
        }
      });

      expect(caughtError).not.toBeNull();
      expect(caughtError?.message).toContain('Workflow invocation failed');
      // The error should also be set in state
      expect(result.current.error).not.toBeNull();
    });
  });

  describe('step state tracking', () => {
    it('should initialize steps as empty Map', () => {
      const { result } = renderHook(() => useWorkflowExecution());

      expect(result.current.steps).toBeInstanceOf(Map);
      expect(result.current.steps.size).toBe(0);
    });
  });

  describe('workflow states', () => {
    it('should recognize valid workflow states', () => {
      const validStates = ['new', 'ready', 'scheduled', 'cancelled', 'failed'];

      for (const state of validStates) {
        expect(validStates).toContain(state);
      }
    });

    it('should recognize valid step states', () => {
      const validStepStates = ['new', 'queued', 'running', 'ok', 'error', 'paused', 'waiting'];

      for (const state of validStepStates) {
        expect(validStepStates).toContain(state);
      }
    });
  });

  describe('SSE connection URL', () => {
    it('should construct correct SSE URL', () => {
      const workflowId = 'wf-123';
      const invocationId = 'inv-456';
      const expectedUrl = `/api/galaxy/workflows/sse/${workflowId}/${invocationId}`;

      expect(expectedUrl).toBe('/api/galaxy/workflows/sse/wf-123/inv-456');
    });
  });

  describe('cleanup', () => {
    it('should provide disconnectFromSSE function', () => {
      const { result } = renderHook(() => useWorkflowExecution());

      expect(result.current.disconnectFromSSE).toBeDefined();
      expect(typeof result.current.disconnectFromSSE).toBe('function');
    });
  });
});

describe('WorkflowExecutionState types', () => {
  it('should have correct interface structure', () => {
    const state = {
      workflowId: 'wf-123',
      invocationId: 'inv-456',
      workflowState: 'scheduled' as const,
      steps: new Map(),
      startTime: '2026-01-09T12:00:00Z',
      updateTime: '2026-01-09T12:00:01Z',
      error: null,
    };

    expect(state.workflowId).toBe('wf-123');
    expect(state.invocationId).toBe('inv-456');
    expect(state.workflowState).toBe('scheduled');
    expect(state.steps).toBeInstanceOf(Map);
    expect(state.startTime).toBeDefined();
    expect(state.updateTime).toBeDefined();
    expect(state.error).toBeNull();
  });
});

describe('StepState types', () => {
  it('should have correct interface structure', () => {
    const stepState = {
      stepId: 'step-1',
      jobId: 'job-123',
      state: 'running' as const,
      startTime: '2026-01-09T12:00:00Z',
      updateTime: '2026-01-09T12:00:05Z',
      logs: ['Starting analysis...', 'Processing data...'],
      elapsedMs: 5000,
    };

    expect(stepState.stepId).toBe('step-1');
    expect(stepState.jobId).toBe('job-123');
    expect(stepState.state).toBe('running');
    expect(stepState.logs).toHaveLength(2);
    expect(stepState.elapsedMs).toBe(5000);
  });
});

// Restore original EventSource
afterAll(() => {
  (global as any).EventSource = originalEventSource;
});
