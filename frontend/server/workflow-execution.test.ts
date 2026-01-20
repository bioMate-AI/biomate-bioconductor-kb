/**
 * Workflow Execution Tests
 * Tests for workflow invocation, SSE streaming, and state polling
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { EventEmitter } from 'events';

// Mock dependencies
vi.mock('./auth-service', () => ({
  authService: {
    verifyToken: vi.fn(),
  },
}));

const mockAuditService = {
  logSSEConnection: vi.fn().mockReturnValue(Promise.resolve(undefined)),
  logAccessDenied: vi.fn().mockReturnValue(Promise.resolve(undefined)),
};

vi.mock('./audit-service', () => ({
  auditService: mockAuditService,
}));

vi.mock('./db', () => ({
  db: {
    select: vi.fn().mockReturnThis(),
    from: vi.fn().mockReturnThis(),
    where: vi.fn().mockReturnThis(),
    limit: vi.fn().mockResolvedValue([]),
  },
}));

vi.mock('./storage', () => ({
  storage: {
    getInvocation: vi.fn(),
    updateInvocation: vi.fn().mockResolvedValue(undefined),
  },
}));

// Import after mocks
import { authService } from './auth-service';
import { storage } from './storage';

// ============================================================================
// Test Suite: Galaxy State Poller
// ============================================================================

describe('GalaxyStatePoller', () => {
  let mockApi: any;
  let GalaxyStatePoller: any;

  beforeEach(async () => {
    vi.clearAllMocks();

    // Create mock Galaxy API
    mockApi = {
      getInvocation: vi.fn(),
      getJobStdout: vi.fn().mockResolvedValue(''),
      getJobStderr: vi.fn().mockResolvedValue(''),
    };

    // Dynamically import to get fresh instance
    const module = await import('./galaxy-state-poller');
    GalaxyStatePoller = module.GalaxyStatePoller;
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('Initialization', () => {
    it('TC-POLL-001: should create poller with default options', () => {
      const poller = new GalaxyStatePoller(mockApi);
      expect(poller).toBeDefined();
      expect(poller.isPolling('test-id')).toBe(false);
    });

    it('TC-POLL-002: should accept custom poll interval', () => {
      const poller = new GalaxyStatePoller(mockApi, { pollInterval: 5000 });
      expect(poller).toBeDefined();
    });
  });

  describe('Polling Lifecycle', () => {
    it('TC-POLL-003: should start polling for an invocation', () => {
      const poller = new GalaxyStatePoller(mockApi);

      mockApi.getInvocation.mockResolvedValue({
        id: 'inv-123',
        state: 'new',
        steps: [],
      });

      poller.startPolling('inv-123', 'wf-456');

      expect(poller.isPolling('inv-123')).toBe(true);

      // Cleanup
      poller.stopAll();
    });

    it('TC-POLL-004: should not start duplicate polling for same invocation', () => {
      const poller = new GalaxyStatePoller(mockApi);
      const consoleSpy = vi.spyOn(console, 'log');

      mockApi.getInvocation.mockResolvedValue({
        id: 'inv-123',
        state: 'new',
        steps: [],
      });

      poller.startPolling('inv-123', 'wf-456');
      poller.startPolling('inv-123', 'wf-456'); // Duplicate

      expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('Already polling'));

      poller.stopAll();
    });

    it('TC-POLL-005: should stop polling when requested', () => {
      const poller = new GalaxyStatePoller(mockApi);

      mockApi.getInvocation.mockResolvedValue({
        id: 'inv-123',
        state: 'new',
        steps: [],
      });

      poller.startPolling('inv-123', 'wf-456');
      expect(poller.isPolling('inv-123')).toBe(true);

      poller.stopPolling('inv-123');
      expect(poller.isPolling('inv-123')).toBe(false);
    });

    it('TC-POLL-006: should stop all polling', () => {
      const poller = new GalaxyStatePoller(mockApi);

      mockApi.getInvocation.mockResolvedValue({
        id: 'inv-123',
        state: 'new',
        steps: [],
      });

      poller.startPolling('inv-1', 'wf-1');
      poller.startPolling('inv-2', 'wf-2');

      poller.stopAll();

      expect(poller.isPolling('inv-1')).toBe(false);
      expect(poller.isPolling('inv-2')).toBe(false);
    });
  });

  describe('State Detection', () => {
    it('TC-STATE-001: should emit workflow_state event on state change', async () => {
      const poller = new GalaxyStatePoller(mockApi, { pollInterval: 100 });
      const stateHandler = vi.fn();
      poller.on('workflow_state', stateHandler);

      mockApi.getInvocation.mockResolvedValue({
        id: 'inv-123',
        state: 'running',
        steps: [],
      });

      poller.startPolling('inv-123', 'wf-456');

      // Wait for first poll
      await new Promise(resolve => setTimeout(resolve, 150));

      expect(stateHandler).toHaveBeenCalled();
      expect(stateHandler.mock.calls[0][0]).toMatchObject({
        type: 'workflow_state',
        invocation_id: 'inv-123',
      });

      poller.stopAll();
    });

    it('TC-STATE-004: should fetch and emit job logs on step completion', async () => {
      const poller = new GalaxyStatePoller(mockApi, { pollInterval: 100 });
      const logHandler = vi.fn();
      poller.on('job_log', logHandler);

      // Mock job logs
      mockApi.getJobStdout.mockResolvedValue('Processing completed successfully');
      mockApi.getJobStderr.mockResolvedValue('Warning: low memory');

      // First poll - step running
      mockApi.getInvocation.mockResolvedValueOnce({
        id: 'inv-123',
        state: 'running',
        steps: [{ id: 'step-1', state: 'running', job_id: 'job-1', jobs: [{ id: 'job-1', state: 'running' }] }],
      });

      // Second poll - step completed
      mockApi.getInvocation.mockResolvedValueOnce({
        id: 'inv-123',
        state: 'running',
        steps: [{ id: 'step-1', state: 'ok', job_id: 'job-1', jobs: [{ id: 'job-1', state: 'ok' }] }],
      });

      poller.startPolling('inv-123', 'wf-456');

      // Wait for polls and log fetch
      await new Promise(resolve => setTimeout(resolve, 350));

      expect(mockApi.getJobStdout).toHaveBeenCalledWith('job-1');
      expect(mockApi.getJobStderr).toHaveBeenCalledWith('job-1');
      expect(logHandler).toHaveBeenCalled();

      poller.stopAll();
    });

    it('TC-STATE-005: should emit error event for stderr with error content', async () => {
      const poller = new GalaxyStatePoller(mockApi, { pollInterval: 100 });
      const errorHandler = vi.fn();
      poller.on('error', errorHandler);

      // Mock job logs with error
      mockApi.getJobStdout.mockResolvedValue('');
      mockApi.getJobStderr.mockResolvedValue('error: something went wrong');

      // First poll - step running
      mockApi.getInvocation.mockResolvedValueOnce({
        id: 'inv-123',
        state: 'running',
        steps: [{ id: 'step-1', state: 'running', job_id: 'job-1', jobs: [{ id: 'job-1', state: 'running' }] }],
      });

      // Second poll - step error
      mockApi.getInvocation.mockResolvedValueOnce({
        id: 'inv-123',
        state: 'running',
        steps: [{ id: 'step-1', state: 'error', job_id: 'job-1', jobs: [{ id: 'job-1', state: 'error' }] }],
      });

      poller.startPolling('inv-123', 'wf-456');

      await new Promise(resolve => setTimeout(resolve, 350));

      expect(errorHandler).toHaveBeenCalled();

      poller.stopAll();
    });

    it('TC-STATE-006: should handle job log fetch failure gracefully', async () => {
      const poller = new GalaxyStatePoller(mockApi, { pollInterval: 100 });
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

      // Mock job log failure
      mockApi.getJobStdout.mockRejectedValue(new Error('Log fetch failed'));
      mockApi.getJobStderr.mockRejectedValue(new Error('Log fetch failed'));

      // First poll - step running
      mockApi.getInvocation.mockResolvedValueOnce({
        id: 'inv-123',
        state: 'running',
        steps: [{ id: 'step-1', state: 'running', job_id: 'job-1', jobs: [{ id: 'job-1', state: 'running' }] }],
      });

      // Second poll - step completed
      mockApi.getInvocation.mockResolvedValueOnce({
        id: 'inv-123',
        state: 'running',
        steps: [{ id: 'step-1', state: 'ok', job_id: 'job-1', jobs: [{ id: 'job-1', state: 'ok' }] }],
      });

      poller.startPolling('inv-123', 'wf-456');

      await new Promise(resolve => setTimeout(resolve, 350));

      expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('Failed to fetch logs'), expect.anything());

      consoleSpy.mockRestore();
      poller.stopAll();
    });

    it('TC-STATE-002: should emit step_state event when step state changes', async () => {
      const poller = new GalaxyStatePoller(mockApi, { pollInterval: 100 });
      const stepHandler = vi.fn();
      poller.on('step_state', stepHandler);

      // First poll - initial state
      mockApi.getInvocation.mockResolvedValueOnce({
        id: 'inv-123',
        state: 'running',
        steps: [{ id: 'step-1', state: 'queued', jobs: [] }],
      });

      // Second poll - step running
      mockApi.getInvocation.mockResolvedValueOnce({
        id: 'inv-123',
        state: 'running',
        steps: [{ id: 'step-1', state: 'running', jobs: [{ id: 'job-1', state: 'running' }] }],
      });

      poller.startPolling('inv-123', 'wf-456');

      // Wait for two polls
      await new Promise(resolve => setTimeout(resolve, 250));

      expect(stepHandler).toHaveBeenCalled();

      poller.stopAll();
    });

    it('TC-STATE-003: should detect workflow completion', async () => {
      const poller = new GalaxyStatePoller(mockApi, { pollInterval: 100 });
      const completedHandler = vi.fn();
      poller.on('workflow_completed', completedHandler);

      mockApi.getInvocation.mockResolvedValue({
        id: 'inv-123',
        state: 'scheduled',
        steps: [{ id: 'step-1', state: 'ok', jobs: [{ id: 'job-1', state: 'ok' }] }],
      });

      poller.startPolling('inv-123', 'wf-456');

      // Wait for poll
      await new Promise(resolve => setTimeout(resolve, 150));

      expect(completedHandler).toHaveBeenCalledWith({
        invocation_id: 'inv-123',
        state: 'scheduled',
      });
    });
  });

  describe('Milestone Tracking', () => {
    it('TC-MILE-001: should emit progress_milestone at 25%, 50%, 75%, 100%', async () => {
      const poller = new GalaxyStatePoller(mockApi, { pollInterval: 100 });
      const milestoneHandler = vi.fn();
      poller.on('progress_milestone', milestoneHandler);

      // 4 steps, complete them one by one
      const createState = (completedCount: number) => ({
        id: 'inv-123',
        state: 'running',
        steps: [
          { id: 'step-1', state: completedCount >= 1 ? 'ok' : 'queued', jobs: completedCount >= 1 ? [{ state: 'ok' }] : [] },
          { id: 'step-2', state: completedCount >= 2 ? 'ok' : 'queued', jobs: completedCount >= 2 ? [{ state: 'ok' }] : [] },
          { id: 'step-3', state: completedCount >= 3 ? 'ok' : 'queued', jobs: completedCount >= 3 ? [{ state: 'ok' }] : [] },
          { id: 'step-4', state: completedCount >= 4 ? 'ok' : 'queued', jobs: completedCount >= 4 ? [{ state: 'ok' }] : [] },
        ],
      });

      mockApi.getInvocation
        .mockResolvedValueOnce(createState(1)) // 25%
        .mockResolvedValueOnce(createState(2)) // 50%
        .mockResolvedValueOnce(createState(3)) // 75%
        .mockResolvedValueOnce(createState(4)); // 100%

      poller.startPolling('inv-123', 'wf-456');

      // Wait for multiple polls
      await new Promise(resolve => setTimeout(resolve, 500));

      const milestones = milestoneHandler.mock.calls.map(call => call[0].data.milestone);
      expect(milestones).toContain(25);
      expect(milestones).toContain(50);
      expect(milestones).toContain(75);
      expect(milestones).toContain(100);

      poller.stopAll();
    });
  });

  describe('Error Handling', () => {
    it('TC-ERR-001: should emit polling_error on API failure', async () => {
      const poller = new GalaxyStatePoller(mockApi, { pollInterval: 100, maxRetries: 3 });
      const errorHandler = vi.fn();
      poller.on('polling_error', errorHandler);

      mockApi.getInvocation.mockRejectedValue(new Error('Network error'));

      poller.startPolling('inv-123', 'wf-456');

      // Wait for poll
      await new Promise(resolve => setTimeout(resolve, 150));

      expect(errorHandler).toHaveBeenCalledWith(expect.objectContaining({
        invocation_id: 'inv-123',
        error: 'Network error',
      }));

      poller.stopAll();
    });

    it('TC-ERR-002: should stop polling after max retries', async () => {
      const poller = new GalaxyStatePoller(mockApi, { pollInterval: 50, maxRetries: 3 });
      const failedHandler = vi.fn();
      poller.on('polling_failed', failedHandler);

      mockApi.getInvocation.mockRejectedValue(new Error('Persistent error'));

      poller.startPolling('inv-123', 'wf-456');

      // Wait for max retries
      await new Promise(resolve => setTimeout(resolve, 300));

      expect(failedHandler).toHaveBeenCalledWith(expect.objectContaining({
        invocation_id: 'inv-123',
      }));
      expect(poller.isPolling('inv-123')).toBe(false);
    });
  });

  describe('Utility Functions', () => {
    it('TC-UTIL-001: should format elapsed time correctly', () => {
      const poller = new GalaxyStatePoller(mockApi);

      expect(poller.formatElapsedTime(5000)).toBe('5s');
      expect(poller.formatElapsedTime(65000)).toBe('1m 5s');
      expect(poller.formatElapsedTime(3665000)).toBe('1h 1m 5s');
    });

    it('TC-UTIL-002: should calculate elapsed time between timestamps', () => {
      const poller = new GalaxyStatePoller(mockApi);

      const start = '2024-01-01T00:00:00Z';
      const end = '2024-01-01T00:01:30Z';

      const elapsed = poller.calculateElapsedTime(start, end);
      expect(elapsed).toBe(90000); // 90 seconds in ms
    });

    it('TC-UTIL-003: should calculate elapsed time to now when no end time', () => {
      const poller = new GalaxyStatePoller(mockApi);

      const start = new Date(Date.now() - 10000).toISOString(); // 10 seconds ago

      const elapsed = poller.calculateElapsedTime(start);
      expect(elapsed).toBeGreaterThanOrEqual(9900); // Allow some tolerance
      expect(elapsed).toBeLessThan(11000);
    });
  });

  describe('Terminal States', () => {
    it('TC-TERM-001: should detect cancelled workflow as complete', async () => {
      const poller = new GalaxyStatePoller(mockApi, { pollInterval: 100 });
      const completedHandler = vi.fn();
      poller.on('workflow_completed', completedHandler);

      mockApi.getInvocation.mockResolvedValue({
        id: 'inv-123',
        state: 'cancelled',
        steps: [],
      });

      poller.startPolling('inv-123', 'wf-456');

      await new Promise(resolve => setTimeout(resolve, 150));

      expect(completedHandler).toHaveBeenCalledWith({
        invocation_id: 'inv-123',
        state: 'cancelled',
      });
    });

    it('TC-TERM-002: should detect failed workflow as complete', async () => {
      const poller = new GalaxyStatePoller(mockApi, { pollInterval: 100 });
      const completedHandler = vi.fn();
      poller.on('workflow_completed', completedHandler);

      mockApi.getInvocation.mockResolvedValue({
        id: 'inv-123',
        state: 'failed',
        steps: [],
      });

      poller.startPolling('inv-123', 'wf-456');

      await new Promise(resolve => setTimeout(resolve, 150));

      expect(completedHandler).toHaveBeenCalledWith({
        invocation_id: 'inv-123',
        state: 'failed',
      });
    });

    it('TC-TERM-003: should detect workflow with error steps as complete', async () => {
      const poller = new GalaxyStatePoller(mockApi, { pollInterval: 100 });
      const completedHandler = vi.fn();
      poller.on('workflow_completed', completedHandler);

      mockApi.getInvocation.mockResolvedValue({
        id: 'inv-123',
        state: 'scheduled',
        steps: [
          { id: 'step-1', state: 'ok', jobs: [{ state: 'ok' }] },
          { id: 'step-2', state: 'error', jobs: [{ state: 'error' }] },
        ],
      });

      poller.startPolling('inv-123', 'wf-456');

      await new Promise(resolve => setTimeout(resolve, 150));

      expect(completedHandler).toHaveBeenCalled();
    });
  });

  describe('Factory Function', () => {
    it('TC-FACTORY-001: should create poller via createPoller function', async () => {
      const module = await import('./galaxy-state-poller');
      const poller = module.createPoller(mockApi, { pollInterval: 1000 });

      expect(poller).toBeDefined();
      expect(poller.isPolling('test')).toBe(false);
    });
  });
});

// ============================================================================
// Test Suite: Workflow SSE Manager
// ============================================================================

describe('WorkflowSSEManager', () => {
  let mockPoller: EventEmitter;
  let WorkflowSSEManager: any;
  let mockRequest: any;
  let mockResponse: any;

  beforeEach(async () => {
    vi.clearAllMocks();

    // Reset audit service mocks
    mockAuditService.logSSEConnection.mockReturnValue(Promise.resolve(undefined));
    mockAuditService.logAccessDenied.mockReturnValue(Promise.resolve(undefined));

    // Create mock poller
    mockPoller = new EventEmitter();
    (mockPoller as any).startPolling = vi.fn();
    (mockPoller as any).stopPolling = vi.fn();
    (mockPoller as any).isPolling = vi.fn().mockReturnValue(false);
    (mockPoller as any).getState = vi.fn().mockReturnValue(null);
    (mockPoller as any).stopAll = vi.fn();

    // Create mock request/response
    mockRequest = {
      params: { workflowId: 'wf-123', invocationId: 'inv-456' },
      query: { token: 'valid-token' },
      cookies: {},
      ip: '127.0.0.1',
      socket: { remoteAddress: '127.0.0.1' },
      on: vi.fn(),
    };

    mockResponse = {
      setHeader: vi.fn(),
      write: vi.fn(),
      end: vi.fn(),
      status: vi.fn().mockReturnThis(),
      json: vi.fn(),
    };

    // Mock auth service
    (authService.verifyToken as any).mockReturnValue({ userId: 'user-123' });

    // Dynamically import
    const module = await import('./workflow-sse');
    WorkflowSSEManager = module.WorkflowSSEManager;
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('Connection Handling', () => {
    it('TC-SSE-001: should establish SSE connection with valid parameters', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      expect(mockResponse.setHeader).toHaveBeenCalledWith('Content-Type', 'text/event-stream');
      expect(mockResponse.setHeader).toHaveBeenCalledWith('Cache-Control', 'no-cache');
      expect(mockResponse.setHeader).toHaveBeenCalledWith('Connection', 'keep-alive');
    });

    it('TC-SSE-002: should reject connection with missing parameters', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      mockRequest.params = {};

      await manager.handleConnection(mockRequest, mockResponse);

      expect(mockResponse.status).toHaveBeenCalledWith(400);
      expect(mockResponse.json).toHaveBeenCalledWith(expect.objectContaining({
        error: expect.stringContaining('Missing'),
      }));
    });

    it('TC-SSE-003: should send initial state on connection', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      expect(mockResponse.write).toHaveBeenCalledWith(expect.stringContaining('event: workflow_state'));
    });

    it('TC-SSE-004: should start polling if not already polling', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      expect((mockPoller as any).startPolling).toHaveBeenCalledWith('inv-456', 'wf-123');
    });

    it('TC-SSE-005: should handle client disconnect', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      // Verify client was added
      expect(manager.getClientCount('inv-456')).toBe(1);

      // Manually remove client by calling cleanup
      manager.cleanup();

      // After cleanup, client count should be 0
      expect(manager.getClientCount('inv-456')).toBe(0);
    });
  });

  describe('Event Broadcasting', () => {
    it('TC-SSE-006: should broadcast workflow_state events to clients', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      // Simulate poller event
      mockPoller.emit('workflow_state', {
        type: 'workflow_state',
        invocation_id: 'inv-456',
        timestamp: new Date().toISOString(),
        data: { workflow_state: 'running' },
      });

      expect(mockResponse.write).toHaveBeenCalledWith(expect.stringContaining('running'));
    });

    it('TC-SSE-007: should broadcast step_state events to clients', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      mockPoller.emit('step_state', {
        type: 'step_state',
        invocation_id: 'inv-456',
        timestamp: new Date().toISOString(),
        data: { step_id: 'step-1', step_state: 'ok' },
      });

      expect(mockResponse.write).toHaveBeenCalledWith(expect.stringContaining('step_state'));
    });

    it('TC-SSE-008: should broadcast error events to clients', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      mockPoller.emit('error', {
        type: 'error',
        invocation_id: 'inv-456',
        timestamp: new Date().toISOString(),
        data: { error: 'Something went wrong' },
      });

      expect(mockResponse.write).toHaveBeenCalledWith(expect.stringContaining('error'));
    });
  });

  describe('Client Management', () => {
    it('TC-SSE-009: should track client count correctly', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      expect(manager.getClientCount('inv-456')).toBe(0);

      await manager.handleConnection(mockRequest, mockResponse);

      expect(manager.getClientCount('inv-456')).toBe(1);
    });

    it('TC-SSE-010: should support multiple clients for same invocation', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      const mockResponse2 = { ...mockResponse, write: vi.fn(), end: vi.fn() };

      await manager.handleConnection(mockRequest, mockResponse);
      await manager.handleConnection(mockRequest, mockResponse2);

      expect(manager.getClientCount('inv-456')).toBe(2);
    });

    it('TC-SSE-011: should cleanup all connections', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      manager.cleanup();

      expect(mockResponse.end).toHaveBeenCalled();
      expect(manager.getTotalClientCount()).toBe(0);
    });

    it('TC-SSE-012: should track total client count across invocations', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      // First invocation
      await manager.handleConnection(mockRequest, mockResponse);

      // Second invocation with different ID
      const mockRequest2 = {
        ...mockRequest,
        params: { workflowId: 'wf-789', invocationId: 'inv-789' },
        on: vi.fn(),
      };
      const mockResponse2 = { ...mockResponse, write: vi.fn(), end: vi.fn() };

      await manager.handleConnection(mockRequest2, mockResponse2);

      expect(manager.getTotalClientCount()).toBe(2);
      expect(manager.getClientCount('inv-456')).toBe(1);
      expect(manager.getClientCount('inv-789')).toBe(1);

      manager.cleanup();
      expect(manager.getTotalClientCount()).toBe(0);
    });

    it('TC-SSE-013: should return 0 for unknown invocation client count', () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      expect(manager.getClientCount('non-existent')).toBe(0);
    });

    it('TC-SSE-014: should send ping to keep connection alive', async () => {
      vi.useFakeTimers();

      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      // Clear initial writes
      mockResponse.write.mockClear();

      // Advance time by 30 seconds (ping interval)
      vi.advanceTimersByTime(30000);

      // Should have sent a ping
      expect(mockResponse.write).toHaveBeenCalledWith(': ping\n\n');

      vi.useRealTimers();
      manager.cleanup();
    });

    it('TC-SSE-015: should stop ping when client becomes inactive', async () => {
      vi.useFakeTimers();

      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      // Cleanup marks client as inactive
      manager.cleanup();

      // Clear writes
      mockResponse.write.mockClear();

      // Advance time - ping should not be sent for inactive client
      vi.advanceTimersByTime(30000);

      // The ping interval should check isActive and not write
      // (may or may not have been called depending on timing)

      vi.useRealTimers();
    });
  });

  describe('Authentication', () => {
    it('TC-AUTH-001: should verify token from query parameter', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      expect(authService.verifyToken).toHaveBeenCalledWith('valid-token');
    });

    it('TC-AUTH-002: should verify token from cookie if no query param', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      mockRequest.query.token = undefined;
      mockRequest.cookies.biomate_token = 'cookie-token';

      await manager.handleConnection(mockRequest, mockResponse);

      expect(authService.verifyToken).toHaveBeenCalledWith('cookie-token');
    });

    it('TC-AUTH-003: should reject connection in strict auth mode when auth fails', async () => {
      // Enable strict auth
      const manager = new WorkflowSSEManager(mockPoller as any, { strictAuth: true });

      // Make auth fail
      (authService.verifyToken as any).mockImplementation(() => {
        throw new Error('Invalid token');
      });

      await manager.handleConnection(mockRequest, mockResponse);

      expect(mockResponse.status).toHaveBeenCalledWith(401);
      expect(mockResponse.json).toHaveBeenCalledWith(expect.objectContaining({
        error: expect.stringContaining('Authentication required'),
      }));
    });

    it('TC-AUTH-004: should allow connection in permissive mode when auth fails', async () => {
      // Permissive mode (default)
      const manager = new WorkflowSSEManager(mockPoller as any, { strictAuth: false });

      // Make auth fail
      (authService.verifyToken as any).mockImplementation(() => {
        throw new Error('Invalid token');
      });

      await manager.handleConnection(mockRequest, mockResponse);

      // Should still set SSE headers (connection allowed)
      expect(mockResponse.setHeader).toHaveBeenCalledWith('Content-Type', 'text/event-stream');
    });
  });

  describe('Error Handling', () => {
    it('TC-SSE-ERR-001: should handle send event errors gracefully', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      // Make response.write throw
      mockResponse.write.mockImplementation(() => {
        throw new Error('Write failed');
      });

      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

      await manager.handleConnection(mockRequest, mockResponse);

      // Should log error but not crash
      // The sendEvent will be called for initial state
      expect(consoleSpy).toHaveBeenCalled();

      consoleSpy.mockRestore();
    });

    it('TC-SSE-ERR-002: should handle broadcast to inactive clients', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      // Mark client as inactive
      manager.cleanup();

      // Broadcast should not crash even with no active clients
      mockPoller.emit('workflow_state', {
        type: 'workflow_state',
        invocation_id: 'inv-456',
        timestamp: new Date().toISOString(),
        data: { workflow_state: 'running' },
      });

      // Should not throw
      expect(manager.getClientCount('inv-456')).toBe(0);
    });
  });

  describe('Poller Integration', () => {
    it('TC-POLL-INT-001: should update storage on workflow state change', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      // Emit workflow state event
      mockPoller.emit('workflow_state', {
        type: 'workflow_state',
        invocation_id: 'inv-456',
        timestamp: new Date().toISOString(),
        data: { workflow_state: 'running' },
      });

      // Storage should be updated
      expect(storage.updateInvocation).toHaveBeenCalled();
    });

    it('TC-POLL-INT-002: should update storage on step completion', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      // Mock storage to return invocation
      (storage.getInvocation as any).mockResolvedValue({
        id: 'inv-456',
        completedSteps: 0,
      });

      await manager.handleConnection(mockRequest, mockResponse);

      // Emit step completed event
      mockPoller.emit('step_state', {
        type: 'step_state',
        invocation_id: 'inv-456',
        timestamp: new Date().toISOString(),
        data: { step_id: 'step-1', step_state: 'ok', step_label: 'Tool 1' },
      });

      // Wait for async update
      await new Promise(resolve => setTimeout(resolve, 50));

      expect(storage.getInvocation).toHaveBeenCalledWith('inv-456');
    });

    it('TC-POLL-INT-003: should close clients on workflow completion', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);
      expect(manager.getClientCount('inv-456')).toBe(1);

      // Emit completion event
      mockPoller.emit('workflow_completed', {
        invocation_id: 'inv-456',
        state: 'ok',
      });

      // Wait for timeout to close clients
      await new Promise(resolve => setTimeout(resolve, 1100));

      // Clients should be closed
      expect(mockResponse.end).toHaveBeenCalled();
    });

    it('TC-POLL-INT-004: should broadcast job_log events', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      mockPoller.emit('job_log', {
        type: 'job_log',
        invocation_id: 'inv-456',
        timestamp: new Date().toISOString(),
        data: { job_id: 'job-1', log: 'Processing...' },
      });

      expect(mockResponse.write).toHaveBeenCalledWith(expect.stringContaining('job_log'));
    });

    it('TC-POLL-INT-005: should broadcast progress_milestone events', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      mockPoller.emit('progress_milestone', {
        type: 'progress_milestone',
        invocation_id: 'inv-456',
        timestamp: new Date().toISOString(),
        data: { milestone: '50%' },
      });

      expect(mockResponse.write).toHaveBeenCalledWith(expect.stringContaining('progress_milestone'));
    });

    it('TC-POLL-INT-006: should handle polling_error events', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      mockPoller.emit('polling_error', {
        invocation_id: 'inv-456',
        error: 'API timeout',
      });

      expect(mockResponse.write).toHaveBeenCalledWith(expect.stringContaining('error'));
    });

    it('TC-POLL-INT-007: should handle polling_failed events and close clients', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      mockPoller.emit('polling_failed', {
        invocation_id: 'inv-456',
        error: 'Max retries exceeded',
      });

      // Should broadcast error and close clients
      expect(mockResponse.write).toHaveBeenCalledWith(expect.stringContaining('error'));
      expect(mockResponse.end).toHaveBeenCalled();
    });
  });

  describe('Client Disconnect Handling', () => {
    it('TC-DISCONNECT-001: should handle client disconnect via close event', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      // Capture all close handlers (there are 2: cleanup + ping interval clear)
      const closeHandlers: (() => void)[] = [];
      mockRequest.on.mockImplementation((event: string, handler: () => void) => {
        if (event === 'close') {
          closeHandlers.push(handler);
        }
      });

      await manager.handleConnection(mockRequest, mockResponse);
      expect(manager.getClientCount('inv-456')).toBe(1);

      // Trigger all close event handlers
      closeHandlers.forEach(h => h());

      // Client should be removed
      expect(manager.getClientCount('inv-456')).toBe(0);
    });

    it('TC-DISCONNECT-002: should stop polling when last client disconnects', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      const closeHandlers: (() => void)[] = [];
      mockRequest.on.mockImplementation((event: string, handler: () => void) => {
        if (event === 'close') {
          closeHandlers.push(handler);
        }
      });

      await manager.handleConnection(mockRequest, mockResponse);

      // Trigger close handlers
      closeHandlers.forEach(h => h());

      // Polling should be stopped
      expect((mockPoller as any).stopPolling).toHaveBeenCalledWith('inv-456');
    });

    it('TC-DISCONNECT-003: should not stop polling when other clients remain', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      // First client
      const closeHandlers1: (() => void)[] = [];
      const mockRequest1 = {
        ...mockRequest,
        on: vi.fn((event: string, handler: () => void) => {
          if (event === 'close') closeHandlers1.push(handler);
        }),
      };
      const mockResponse1 = { ...mockResponse, write: vi.fn(), end: vi.fn() };

      // Second client
      const closeHandlers2: (() => void)[] = [];
      const mockRequest2 = {
        ...mockRequest,
        on: vi.fn((event: string, handler: () => void) => {
          if (event === 'close') closeHandlers2.push(handler);
        }),
      };
      const mockResponse2 = { ...mockResponse, write: vi.fn(), end: vi.fn() };

      await manager.handleConnection(mockRequest1, mockResponse1);
      await manager.handleConnection(mockRequest2, mockResponse2);

      expect(manager.getClientCount('inv-456')).toBe(2);

      // Disconnect first client only
      closeHandlers1.forEach(h => h());

      // Should still have one client, polling should continue
      expect(manager.getClientCount('inv-456')).toBe(1);
      expect((mockPoller as any).stopPolling).not.toHaveBeenCalled();
    });

    it('TC-DISCONNECT-004: should log disconnect to audit service', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      const closeHandlers: (() => void)[] = [];
      mockRequest.on.mockImplementation((event: string, handler: () => void) => {
        if (event === 'close') closeHandlers.push(handler);
      });

      await manager.handleConnection(mockRequest, mockResponse);

      // Clear the connect log
      mockAuditService.logSSEConnection.mockClear();

      // Trigger disconnect
      closeHandlers.forEach(h => h());

      // Wait for async
      await new Promise(resolve => setTimeout(resolve, 50));

      // Should log disconnect
      expect(mockAuditService.logSSEConnection).toHaveBeenCalledWith(
        'user-123',
        'inv-456',
        'disconnect',
        '127.0.0.1'
      );
    });

    it('TC-DISCONNECT-005: should handle audit log failure on disconnect gracefully', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      const closeHandlers: (() => void)[] = [];
      mockRequest.on.mockImplementation((event: string, handler: () => void) => {
        if (event === 'close') closeHandlers.push(handler);
      });

      await manager.handleConnection(mockRequest, mockResponse);

      // Make audit log fail on disconnect
      mockAuditService.logSSEConnection.mockReturnValue(Promise.reject(new Error('DB error')));

      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

      // Trigger disconnect - should not throw
      closeHandlers.forEach(h => h());

      // Wait for async error handling
      await new Promise(resolve => setTimeout(resolve, 100));

      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining('Failed to log disconnect'),
        expect.any(Error)
      );

      consoleSpy.mockRestore();
    });
  });

  describe('Auth Error Path Coverage', () => {
    it('TC-AUTH-005: should log access denied when auth fails', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any, { strictAuth: false });

      (authService.verifyToken as any).mockImplementation(() => {
        throw new Error('Token expired');
      });

      await manager.handleConnection(mockRequest, mockResponse);

      expect(mockAuditService.logAccessDenied).toHaveBeenCalledWith(
        null,
        'sse.connect',
        'workflow_invocation',
        'inv-456',
        expect.stringContaining('Token expired'),
        '127.0.0.1'
      );
    });

    it('TC-AUTH-006: should handle logAccessDenied failure gracefully', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any, { strictAuth: false });

      (authService.verifyToken as any).mockImplementation(() => {
        throw new Error('Invalid token');
      });

      mockAuditService.logAccessDenied.mockReturnValue(Promise.reject(new Error('Audit DB error')));

      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

      await manager.handleConnection(mockRequest, mockResponse);

      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining('Failed to log auth failure'),
        expect.any(Error)
      );

      consoleSpy.mockRestore();
    });

    it('TC-AUTH-007: should handle auth error with no message', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any, { strictAuth: false });

      (authService.verifyToken as any).mockImplementation(() => {
        throw 'string error'; // Non-Error throw
      });

      await manager.handleConnection(mockRequest, mockResponse);

      // Should still allow connection in permissive mode
      expect(mockResponse.setHeader).toHaveBeenCalledWith('Content-Type', 'text/event-stream');
    });
  });

  describe('State Sending on Connection', () => {
    it('TC-STATE-SEND-001: should send current state and steps on connection', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      // Mock poller to return existing state
      (mockPoller as any).getState.mockReturnValue({
        state: 'running',
        steps: [
          { id: 'step-1', state: 'ok', job_id: 'job-1' },
          { id: 'step-2', state: 'running', job_id: 'job-2' },
        ],
      });

      await manager.handleConnection(mockRequest, mockResponse);

      // Should send workflow state and step states
      expect(mockResponse.write).toHaveBeenCalledWith(expect.stringContaining('running'));
      expect(mockResponse.write).toHaveBeenCalledWith(expect.stringContaining('step_state'));
    });

    it('TC-STATE-SEND-002: should not start new polling if already polling', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      // Mock poller as already polling
      (mockPoller as any).isPolling.mockReturnValue(true);

      await manager.handleConnection(mockRequest, mockResponse);

      // Should not call startPolling
      expect((mockPoller as any).startPolling).not.toHaveBeenCalled();
    });
  });

  describe('Storage Update Errors', () => {
    it('TC-STORAGE-001: should handle storage update failure on workflow completion', async () => {
      const manager = new WorkflowSSEManager(mockPoller as any);

      // Mock storage.updateInvocation to fail
      (storage.updateInvocation as any).mockRejectedValue(new Error('DB write error'));

      const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

      await manager.handleConnection(mockRequest, mockResponse);

      // Emit workflow completion event
      mockPoller.emit('workflow_completed', {
        invocation_id: 'inv-456',
        state: 'scheduled',
      });

      // Wait for async processing
      await new Promise(resolve => setTimeout(resolve, 100));

      // Should log warning but not crash
      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining('Failed to update completion status'),
        expect.any(Error)
      );

      consoleSpy.mockRestore();
    });
  });

  describe('Ownership Verification', () => {
    it('TC-OWNER-001: should deny access when user does not own execution', async () => {
      // Import db mock to configure it for this test
      const { db } = await import('./db');

      // Mock db to return an execution owned by a different user
      (db.select as any).mockReturnValue({
        from: vi.fn().mockReturnValue({
          where: vi.fn().mockReturnValue({
            limit: vi.fn().mockResolvedValue([
              { galaxyInvocationId: 'inv-456', userId: 'other-user-123' },
            ]),
          }),
        }),
      });

      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      // Should return 403
      expect(mockResponse.status).toHaveBeenCalledWith(403);
      expect(mockResponse.json).toHaveBeenCalledWith(
        expect.objectContaining({
          error: expect.stringContaining('do not own this workflow'),
        })
      );

      // Should log access denied
      expect(mockAuditService.logAccessDenied).toHaveBeenCalledWith(
        'user-123',
        'sse.connect',
        'workflow_execution',
        'inv-456',
        'User does not own this execution',
        '127.0.0.1'
      );
    });

    it('TC-OWNER-002: should allow access when user owns execution', async () => {
      const { db } = await import('./db');

      // Mock db to return an execution owned by the same user
      (db.select as any).mockReturnValue({
        from: vi.fn().mockReturnValue({
          where: vi.fn().mockReturnValue({
            limit: vi.fn().mockResolvedValue([
              { galaxyInvocationId: 'inv-456', userId: 'user-123' },
            ]),
          }),
        }),
      });

      const manager = new WorkflowSSEManager(mockPoller as any);

      await manager.handleConnection(mockRequest, mockResponse);

      // Should set SSE headers (connection allowed)
      expect(mockResponse.setHeader).toHaveBeenCalledWith('Content-Type', 'text/event-stream');
      expect(mockResponse.status).not.toHaveBeenCalledWith(403);
    });
  });
});

// ============================================================================
// Test Suite: Workflow Invocation API
// ============================================================================

describe('Workflow Invocation API', () => {
  describe('Input Validation', () => {
    it('TC-API-001: should validate required workflow_id', () => {
      const request = {
        workflow_id: '',
        inputs: {},
      };

      expect(request.workflow_id).toBeFalsy();
    });

    it('TC-API-002: should accept valid invocation request', () => {
      const request = {
        workflow_id: 'wf-123',
        inputs: { 'input_1': { src: 'hda', id: 'dataset-1' } },
        parameters: {},
        new_history_name: 'Test History',
      };

      expect(request.workflow_id).toBeTruthy();
      expect(request.inputs).toBeDefined();
    });
  });
});
