/**
 * React Hook for Unified Workflow Execution
 *
 * Integrates with the unified execution API (/api/workflows/execute) which provides:
 * - Sandbox and production mode execution with same code path
 * - Tunable data scope (1% - 100%) with multiple sampling strategies
 * - Iteration linking for parameter tuning cycles
 * - Real-time progress via SSE (leverages existing GalaxyStatePoller)
 *
 * This hook bridges the ExecutionControlPanel UI component with the backend APIs.
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import type {
  ExecutionRun,
  ExecutionConfig,
  DataScope,
  ExecutionRunStatus,
  StepExecution,
  UserInteraction,
  ParameterRecommendation,
  CreateExecutionRunRequest,
} from '@shared/schema';

// ============================================================================
// Types
// ============================================================================

export interface UnifiedExecutionState {
  /** Current execution run */
  currentRun: ExecutionRun | null;
  /** All runs in the current iteration chain */
  iterations: ExecutionRun[];
  /** Loading state */
  isLoading: boolean;
  /** Error state */
  error: string | null;
  /** SSE connection state */
  isConnected: boolean;
}

export interface ExecuteWorkflowParams {
  /** Workflow definition (.ga format) */
  workflowDefinition: any;
  /** Workflow name for display */
  workflowName: string;
  /** Execution configuration */
  executionConfig: ExecutionConfig;
  /** Input datasets */
  inputs: Array<{ id: string; src: string; step_id?: number }>;
  /** Project ID for grouping */
  projectId?: string;
}

export interface UseUnifiedExecutionOptions {
  /** Auto-connect to SSE when run is active */
  autoConnectSSE?: boolean;
  /** Polling interval for status updates (ms) */
  pollInterval?: number;
  /** Initial run ID to load */
  initialRunId?: string;
}

// ============================================================================
// API Functions
// ============================================================================

async function apiExecuteWorkflow(params: ExecuteWorkflowParams): Promise<{
  runId: string;
  galaxyInvocationId: string;
  galaxyHistoryId: string;
  status: string;
  dataScopeApplied: {
    fraction: number;
    absoluteCount: number;
    sampledIds: string[];
  };
}> {
  const response = await fetch('/api/workflows/execute', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({ message: `HTTP ${response.status}: ${response.statusText}` }));
    throw new Error(error.message || error.error || 'Failed to execute workflow');
  }

  return response.json();
}

async function apiGetRun(runId: string): Promise<ExecutionRun | null> {
  const response = await fetch(`/api/workflows/runs/${runId}`);
  if (!response.ok) {
    if (response.status === 404) return null;
    throw new Error('Failed to fetch run');
  }
  return response.json();
}

async function apiGetRunStatus(runId: string): Promise<{
  runId: string;
  status: ExecutionRunStatus;
  progress: ExecutionRun['progress'];
  metrics?: ExecutionRun['metrics'];
  steps?: StepExecution[];
  errorMessage?: string;
}> {
  const response = await fetch(`/api/workflows/runs/${runId}/status?includeSteps=true`);
  if (!response.ok) {
    throw new Error('Failed to fetch run status');
  }
  return response.json();
}

async function apiGetIterations(runId: string): Promise<ExecutionRun[]> {
  const response = await fetch(`/api/workflows/runs/${runId}/iterations`);
  if (!response.ok) {
    throw new Error('Failed to fetch iterations');
  }
  return response.json();
}

async function apiPauseRun(runId: string, reason?: string): Promise<ExecutionRun> {
  const response = await fetch(`/api/workflows/runs/${runId}/pause`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ reason }),
  });
  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Failed to pause run');
  }
  return response.json();
}

async function apiResumeRun(runId: string): Promise<ExecutionRun> {
  const response = await fetch(`/api/workflows/runs/${runId}/resume`, {
    method: 'POST',
  });
  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Failed to resume run');
  }
  return response.json();
}

async function apiCancelRun(runId: string, reason?: string): Promise<ExecutionRun> {
  const response = await fetch(`/api/workflows/runs/${runId}/cancel`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ reason }),
  });
  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Failed to cancel run');
  }
  return response.json();
}

async function apiCompareRuns(
  runId: string,
  compareWithId: string
): Promise<{
  runA: ExecutionRun;
  runB: ExecutionRun;
  comparison: {
    dataScopeDelta: { fractionA: number; fractionB: number };
    parameterDifferences: Array<{
      toolId: string;
      parameter: string;
      valueA: any;
      valueB: any;
    }>;
    runtimeDelta?: number;
    qualityDelta?: Record<string, number>;
  };
}> {
  const response = await fetch(`/api/workflows/runs/${runId}/compare?with=${compareWithId}`);
  if (!response.ok) {
    throw new Error('Failed to compare runs');
  }
  return response.json();
}

async function apiPromoteToProduction(
  runId: string,
  fullInputs: Array<{ id: string; src: string; step_id?: number }>
): Promise<{
  productionRunId: string;
  sandboxRunId: string;
  status: string;
  message: string;
}> {
  const response = await fetch(`/api/workflows/runs/${runId}/promote`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ inputs: fullInputs }),
  });
  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Failed to promote to production');
  }
  return response.json();
}

async function apiRecordInteraction(
  runId: string,
  interaction: Partial<UserInteraction>
): Promise<ExecutionRun> {
  const response = await fetch(`/api/workflows/runs/${runId}/interactions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(interaction),
  });
  if (!response.ok) {
    throw new Error('Failed to record interaction');
  }
  return response.json();
}

// ============================================================================
// Hook
// ============================================================================

export function useUnifiedExecution(options: UseUnifiedExecutionOptions = {}) {
  const {
    autoConnectSSE = true,
    pollInterval = 3000,
    initialRunId,
  } = options;

  const [state, setState] = useState<UnifiedExecutionState>({
    currentRun: null,
    iterations: [],
    isLoading: false,
    error: null,
    isConnected: false,
  });

  const eventSourceRef = useRef<EventSource | null>(null);
  const pollIntervalRef = useRef<NodeJS.Timeout | null>(null);

  // ============================================================================
  // SSE Connection (leverages existing /api/galaxy/workflows/sse endpoint)
  // ============================================================================

  const connectToSSE = useCallback((workflowId: string, invocationId: string) => {
    // Close existing connection
    if (eventSourceRef.current) {
      eventSourceRef.current.close();
      eventSourceRef.current = null;
    }

    const eventSource = new EventSource(
      `/api/galaxy/workflows/sse/${workflowId}/${invocationId}`
    );

    eventSource.onopen = () => {
      console.log('[UnifiedExecution] SSE connected');
      setState((prev) => ({ ...prev, isConnected: true }));
    };

    eventSource.onerror = () => {
      console.warn('[UnifiedExecution] SSE error, will auto-reconnect');
      setState((prev) => ({ ...prev, isConnected: false }));
    };

    // Workflow state changes
    eventSource.addEventListener('workflow_state', (event) => {
      const update = JSON.parse(event.data);
      console.log('[UnifiedExecution] Workflow state:', update.data.workflow_state);

      setState((prev) => {
        if (!prev.currentRun) return prev;

        // Map Galaxy workflow state to our status
        let status: ExecutionRunStatus = prev.currentRun.execution.status;
        if (update.data.workflow_state === 'ok') {
          status = 'completed';
        } else if (update.data.workflow_state === 'error' || update.data.workflow_state === 'failed') {
          status = 'failed';
        } else if (update.data.workflow_state === 'cancelled') {
          status = 'cancelled';
        } else if (update.data.workflow_state === 'scheduled' || update.data.workflow_state === 'ready') {
          status = 'running';
        }

        return {
          ...prev,
          currentRun: {
            ...prev.currentRun,
            execution: {
              ...prev.currentRun.execution,
              status,
              completedAt: status === 'completed' || status === 'failed' || status === 'cancelled'
                ? new Date()
                : prev.currentRun.execution.completedAt,
            },
          },
        };
      });
    });

    // Step state changes
    eventSource.addEventListener('step_state', (event) => {
      const update = JSON.parse(event.data);
      const { step_id, step_state, job_id } = update.data;

      setState((prev) => {
        if (!prev.currentRun) return prev;

        const steps = [...prev.currentRun.steps];
        const stepIndex = steps.findIndex((s) => s.stepId === step_id);

        // Map Galaxy step state to our step status
        let stepStatus: StepExecution['status'] = 'pending';
        if (step_state === 'queued') stepStatus = 'queued';
        else if (step_state === 'running') stepStatus = 'running';
        else if (step_state === 'ok') stepStatus = 'completed';
        else if (step_state === 'error') stepStatus = 'failed';
        else if (step_state === 'paused' || step_state === 'waiting') stepStatus = 'pending';

        const updatedStep: StepExecution = {
          stepId: step_id,
          stepName: '',
          toolId: '',
          status: stepStatus,
          timing: {
            startedAt: step_state === 'running' ? new Date() : undefined,
            completedAt: step_state === 'ok' || step_state === 'error' ? new Date() : undefined,
          },
          metrics: {},
          logs: { stdout: [], stderr: [], truncated: false },
          outputs: [],
        };

        if (stepIndex >= 0) {
          steps[stepIndex] = { ...steps[stepIndex], ...updatedStep };
        } else {
          steps.push(updatedStep);
        }

        // Calculate progress
        const completedSteps = steps.filter((s) => s.status === 'completed').length;
        const totalSteps = prev.currentRun.progress.totalSteps || steps.length;
        const percent = totalSteps > 0 ? Math.round((completedSteps / totalSteps) * 100) : 0;

        return {
          ...prev,
          currentRun: {
            ...prev.currentRun,
            steps,
            progress: {
              ...prev.currentRun.progress,
              percent,
              currentStep: completedSteps,
              totalSteps,
            },
          },
        };
      });
    });

    // Progress milestones
    eventSource.addEventListener('progress_milestone', (event) => {
      const update = JSON.parse(event.data);
      console.log('[UnifiedExecution] Progress milestone:', update.data);
    });

    eventSourceRef.current = eventSource;
  }, []);

  const disconnectFromSSE = useCallback(() => {
    if (eventSourceRef.current) {
      eventSourceRef.current.close();
      eventSourceRef.current = null;
      setState((prev) => ({ ...prev, isConnected: false }));
    }
  }, []);

  // ============================================================================
  // Polling (fallback for status updates)
  // ============================================================================

  const startPolling = useCallback((runId: string) => {
    stopPolling();

    const poll = async () => {
      try {
        const status = await apiGetRunStatus(runId);

        setState((prev) => {
          if (!prev.currentRun || prev.currentRun.id !== runId) return prev;

          return {
            ...prev,
            currentRun: {
              ...prev.currentRun,
              execution: {
                ...prev.currentRun.execution,
                status: status.status,
                errorMessage: status.errorMessage,
              },
              progress: status.progress,
              metrics: status.metrics || prev.currentRun.metrics,
              steps: status.steps || prev.currentRun.steps,
            },
          };
        });

        // Stop polling if run is complete
        if (['completed', 'failed', 'cancelled'].includes(status.status)) {
          stopPolling();
        }
      } catch (error) {
        console.error('[UnifiedExecution] Polling error:', error);
      }
    };

    pollIntervalRef.current = setInterval(poll, pollInterval);
    poll(); // Initial fetch
  }, [pollInterval]);

  const stopPolling = useCallback(() => {
    if (pollIntervalRef.current) {
      clearInterval(pollIntervalRef.current);
      pollIntervalRef.current = null;
    }
  }, []);

  // ============================================================================
  // Actions
  // ============================================================================

  /**
   * Execute a workflow with unified configuration
   */
  const executeWorkflow = useCallback(async (params: ExecuteWorkflowParams) => {
    setState((prev) => ({ ...prev, isLoading: true, error: null }));

    try {
      const result = await apiExecuteWorkflow(params);

      // Fetch the full run details
      const run = await apiGetRun(result.runId);

      if (run) {
        setState((prev) => ({
          ...prev,
          currentRun: run,
          isLoading: false,
        }));

        // Connect to SSE for real-time updates
        if (autoConnectSSE && run.execution.galaxyWorkflowId && run.execution.galaxyInvocationId) {
          connectToSSE(run.execution.galaxyWorkflowId, run.execution.galaxyInvocationId);
        } else {
          // Fall back to polling
          startPolling(run.id);
        }

        // Fetch iterations
        const iterations = await apiGetIterations(run.id);
        setState((prev) => ({ ...prev, iterations }));

        return run;
      }

      throw new Error('Run created but could not be fetched');
    } catch (error: any) {
      setState((prev) => ({
        ...prev,
        isLoading: false,
        error: error.message,
      }));
      throw error;
    }
  }, [autoConnectSSE, connectToSSE, startPolling]);

  /**
   * Load an existing run by ID
   */
  const loadRun = useCallback(async (runId: string) => {
    setState((prev) => ({ ...prev, isLoading: true, error: null }));

    try {
      const run = await apiGetRun(runId);

      if (!run) {
        throw new Error('Run not found');
      }

      const iterations = await apiGetIterations(runId);

      setState((prev) => ({
        ...prev,
        currentRun: run,
        iterations,
        isLoading: false,
      }));

      // Connect to SSE if run is active
      if (
        autoConnectSSE &&
        run.execution.status === 'running' &&
        run.execution.galaxyWorkflowId &&
        run.execution.galaxyInvocationId
      ) {
        connectToSSE(run.execution.galaxyWorkflowId, run.execution.galaxyInvocationId);
      } else if (run.execution.status === 'running') {
        startPolling(runId);
      }

      return run;
    } catch (error: any) {
      setState((prev) => ({
        ...prev,
        isLoading: false,
        error: error.message,
      }));
      throw error;
    }
  }, [autoConnectSSE, connectToSSE, startPolling]);

  /**
   * Pause the current run
   */
  const pauseRun = useCallback(async (reason?: string) => {
    if (!state.currentRun) throw new Error('No active run');

    const updated = await apiPauseRun(state.currentRun.id, reason);
    setState((prev) => ({ ...prev, currentRun: updated }));

    return updated;
  }, [state.currentRun]);

  /**
   * Resume the current run
   */
  const resumeRun = useCallback(async () => {
    if (!state.currentRun) throw new Error('No active run');

    const updated = await apiResumeRun(state.currentRun.id);
    setState((prev) => ({ ...prev, currentRun: updated }));

    // Reconnect to SSE
    if (updated.execution.galaxyWorkflowId && updated.execution.galaxyInvocationId) {
      connectToSSE(updated.execution.galaxyWorkflowId, updated.execution.galaxyInvocationId);
    }

    return updated;
  }, [state.currentRun, connectToSSE]);

  /**
   * Cancel the current run
   */
  const cancelRun = useCallback(async (reason?: string) => {
    if (!state.currentRun) throw new Error('No active run');

    const updated = await apiCancelRun(state.currentRun.id, reason);
    setState((prev) => ({ ...prev, currentRun: updated }));

    disconnectFromSSE();
    stopPolling();

    return updated;
  }, [state.currentRun, disconnectFromSSE, stopPolling]);

  /**
   * Compare current run with another run
   */
  const compareWithRun = useCallback(async (compareWithId: string) => {
    if (!state.currentRun) throw new Error('No active run');

    return apiCompareRuns(state.currentRun.id, compareWithId);
  }, [state.currentRun]);

  /**
   * Promote sandbox run to production
   */
  const promoteToProduction = useCallback(async (
    fullInputs: Array<{ id: string; src: string; step_id?: number }>
  ) => {
    if (!state.currentRun) throw new Error('No active run');

    if (state.currentRun.mode !== 'sandbox') {
      throw new Error('Can only promote sandbox runs');
    }

    if (state.currentRun.execution.status !== 'completed') {
      throw new Error('Can only promote completed runs');
    }

    return apiPromoteToProduction(state.currentRun.id, fullInputs);
  }, [state.currentRun]);

  /**
   * Record a user interaction
   */
  const recordInteraction = useCallback(async (interaction: Partial<UserInteraction>) => {
    if (!state.currentRun) throw new Error('No active run');

    return apiRecordInteraction(state.currentRun.id, interaction);
  }, [state.currentRun]);

  /**
   * Clear current run
   */
  const clearRun = useCallback(() => {
    disconnectFromSSE();
    stopPolling();
    setState({
      currentRun: null,
      iterations: [],
      isLoading: false,
      error: null,
      isConnected: false,
    });
  }, [disconnectFromSSE, stopPolling]);

  // ============================================================================
  // Effects
  // ============================================================================

  // Load initial run if provided
  useEffect(() => {
    if (initialRunId) {
      loadRun(initialRunId);
    }
  }, [initialRunId, loadRun]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      disconnectFromSSE();
      stopPolling();
    };
  }, [disconnectFromSSE, stopPolling]);

  // ============================================================================
  // Derived State
  // ============================================================================

  const isRunning = state.currentRun?.execution.status === 'running';
  const isPaused = state.currentRun?.execution.status === 'paused';
  const isComplete = ['completed', 'failed', 'cancelled'].includes(
    state.currentRun?.execution.status || ''
  );
  const canPause = isRunning;
  const canResume = isPaused;
  const canCancel = isRunning || isPaused;
  const canPromote =
    state.currentRun?.mode === 'sandbox' &&
    state.currentRun?.execution.status === 'completed';

  return {
    // State
    currentRun: state.currentRun,
    iterations: state.iterations,
    isLoading: state.isLoading,
    error: state.error,
    isConnected: state.isConnected,

    // Derived state
    isRunning,
    isPaused,
    isComplete,
    canPause,
    canResume,
    canCancel,
    canPromote,

    // Actions
    executeWorkflow,
    loadRun,
    pauseRun,
    resumeRun,
    cancelRun,
    compareWithRun,
    promoteToProduction,
    recordInteraction,
    clearRun,

    // SSE controls
    connectToSSE,
    disconnectFromSSE,
  };
}

export default useUnifiedExecution;
