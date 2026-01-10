/**
 * React Hook for Galaxy Workflow Execution with Real-Time SSE Updates
 *
 * Manages workflow invocation and real-time state tracking via Server-Sent Events.
 * Uses Galaxy's native job states (NO fake progress estimation).
 */

import { useEffect, useRef, useState } from 'react';
import type { WorkflowExecutionUpdate } from '../../../shared/galaxy-types';

interface WorkflowExecutionState {
  workflowId: string | null;
  invocationId: string | null;
  workflowState: 'new' | 'ready' | 'scheduled' | 'cancelled' | 'failed' | null;
  steps: Map<string, StepState>;
  startTime: string | null;
  updateTime: string | null;
  error: string | null;
}

interface StepState {
  stepId: string;
  jobId?: string;
  state: 'new' | 'queued' | 'running' | 'ok' | 'error' | 'paused' | 'waiting';
  startTime?: string;
  updateTime: string;
  logs: string[];
  elapsedMs?: number;
}

interface UseWorkflowExecutionOptions {
  autoConnect?: boolean;
}

export function useWorkflowExecution(options: UseWorkflowExecutionOptions = {}) {
  const { autoConnect = false } = options;

  const [state, setState] = useState<WorkflowExecutionState>({
    workflowId: null,
    invocationId: null,
    workflowState: null,
    steps: new Map(),
    startTime: null,
    updateTime: null,
    error: null,
  });

  const [isConnected, setIsConnected] = useState(false);
  const eventSourceRef = useRef<EventSource | null>(null);

  /**
   * Start workflow execution and connect to SSE for updates
   */
  const invokeWorkflow = async (workflowId: string, inputs: Record<string, any>) => {
    try {
      // Invoke workflow via Galaxy API
      const response = await fetch('/api/galaxy/workflows/invoke', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workflow_id: workflowId, inputs }),
      });

      if (!response.ok) {
        throw new Error(`Workflow invocation failed: ${response.statusText}`);
      }

      const invocation = await response.json();

      // Update state
      setState(prev => ({
        ...prev,
        workflowId,
        invocationId: invocation.id,
        workflowState: invocation.state,
        startTime: invocation.create_time,
        updateTime: invocation.update_time,
      }));

      // Connect to SSE for real-time updates
      connectToSSE(workflowId, invocation.id);

      return invocation;
    } catch (error: any) {
      setState(prev => ({ ...prev, error: error.message }));
      throw error;
    }
  };

  /**
   * Connect to SSE endpoint for real-time updates
   */
  const connectToSSE = (workflowId: string, invocationId: string) => {
    // Close existing connection
    disconnectFromSSE();

    const eventSource = new EventSource(`/api/galaxy/workflows/sse/${workflowId}/${invocationId}`);

    eventSource.onopen = () => {
      console.log(`[SSE] Connected to invocation ${invocationId}`);
      setIsConnected(true);
    };

    eventSource.onerror = (error) => {
      console.error('[SSE] Connection error:', error);
      setIsConnected(false);
      // Auto-reconnect handled by EventSource
    };

    // Workflow-level state changes
    eventSource.addEventListener('workflow_state', (event) => {
      const update: WorkflowExecutionUpdate = JSON.parse(event.data);
      console.log('[SSE] Workflow state:', update.data.workflow_state);

      setState(prev => ({
        ...prev,
        workflowState: update.data.workflow_state || prev.workflowState,
        updateTime: update.timestamp,
      }));
    });

    // Step-level state changes
    eventSource.addEventListener('step_state', (event) => {
      const update: WorkflowExecutionUpdate = JSON.parse(event.data);
      const { step_id, step_state, job_id } = update.data;

      console.log(`[SSE] Step ${step_id}: ${step_state}`);

      setState(prev => {
        const newSteps = new Map(prev.steps);
        const existingStep = newSteps.get(step_id!) || {
          stepId: step_id!,
          state: 'new' as const,
          updateTime: update.timestamp,
          logs: [],
        };

        newSteps.set(step_id!, {
          ...existingStep,
          state: step_state!,
          jobId: job_id,
          updateTime: update.timestamp,
          startTime: existingStep.startTime || (step_state === 'running' ? update.timestamp : undefined),
          elapsedMs: existingStep.startTime
            ? new Date(update.timestamp).getTime() - new Date(existingStep.startTime).getTime()
            : undefined,
        });

        return {
          ...prev,
          steps: newSteps,
          updateTime: update.timestamp,
        };
      });
    });

    // Job logs
    eventSource.addEventListener('job_log', (event) => {
      const update: WorkflowExecutionUpdate = JSON.parse(event.data);
      const { step_id, log_message } = update.data;

      if (step_id && log_message) {
        console.log(`[SSE] Job log for ${step_id}:`, log_message.substring(0, 100));

        setState(prev => {
          const newSteps = new Map(prev.steps);
          const step = newSteps.get(step_id);
          if (step) {
            newSteps.set(step_id, {
              ...step,
              logs: [...step.logs, log_message],
            });
          }
          return { ...prev, steps: newSteps };
        });
      }
    });

    // Errors
    eventSource.addEventListener('error', (event) => {
      const update: WorkflowExecutionUpdate = JSON.parse(event.data);
      console.error('[SSE] Error:', update.data.error);

      setState(prev => ({
        ...prev,
        error: update.data.error || null,
        updateTime: update.timestamp,
      }));
    });

    eventSourceRef.current = eventSource;
  };

  /**
   * Disconnect from SSE
   */
  const disconnectFromSSE = () => {
    if (eventSourceRef.current) {
      console.log('[SSE] Disconnecting');
      eventSourceRef.current.close();
      eventSourceRef.current = null;
      setIsConnected(false);
    }
  };

  /**
   * Cancel workflow execution
   */
  const cancelWorkflow = async () => {
    if (!state.invocationId || !state.workflowId) {
      console.warn('[cancelWorkflow] Missing workflowId or invocationId');
      return;
    }

    try {
      await fetch(`/api/galaxy/workflows/${state.workflowId}/invocations/${state.invocationId}`, {
        method: 'DELETE',
      });

      setState(prev => ({
        ...prev,
        workflowState: 'cancelled',
      }));
    } catch (error: any) {
      setState(prev => ({ ...prev, error: error.message }));
    }
  };

  /**
   * Get step state by ID
   */
  const getStepState = (stepId: string): StepState | undefined => {
    return state.steps.get(stepId);
  };

  /**
   * Calculate total elapsed time
   */
  const getTotalElapsedTime = (): number | null => {
    if (!state.startTime) return null;
    const end = state.updateTime ? new Date(state.updateTime) : new Date();
    return end.getTime() - new Date(state.startTime).getTime();
  };

  /**
   * Format elapsed time for display
   */
  const formatElapsedTime = (milliseconds: number): string => {
    const seconds = Math.floor(milliseconds / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);

    if (hours > 0) {
      return `${hours}h ${minutes % 60}m ${seconds % 60}s`;
    } else if (minutes > 0) {
      return `${minutes}m ${seconds % 60}s`;
    } else {
      return `${seconds}s`;
    }
  };

  /**
   * Check if workflow is complete
   */
  const isWorkflowComplete = (): boolean => {
    if (state.workflowState === 'cancelled' || state.workflowState === 'failed') {
      return true;
    }

    // Check if all steps are done
    if (state.steps.size > 0) {
      const allStepsDone = Array.from(state.steps.values()).every(
        step => step.state === 'ok' || step.state === 'error'
      );
      return allStepsDone;
    }

    return false;
  };

  // Auto-connect on mount if invocationId exists
  useEffect(() => {
    if (autoConnect && state.workflowId && state.invocationId && !isConnected) {
      connectToSSE(state.workflowId, state.invocationId);
    }
  }, [autoConnect, state.workflowId, state.invocationId, isConnected]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      disconnectFromSSE();
    };
  }, []);

  // Auto-disconnect when workflow completes
  useEffect(() => {
    if (isWorkflowComplete() && isConnected) {
      console.log('[SSE] Workflow complete, disconnecting in 2 seconds...');
      setTimeout(() => {
        disconnectFromSSE();
      }, 2000);
    }
  }, [state.workflowState, state.steps]);

  return {
    // State
    workflowId: state.workflowId,
    invocationId: state.invocationId,
    workflowState: state.workflowState,
    steps: state.steps,
    error: state.error,
    isConnected,
    isComplete: isWorkflowComplete(),

    // Actions
    invokeWorkflow,
    cancelWorkflow,
    connectToSSE,
    disconnectFromSSE,

    // Utilities
    getStepState,
    getTotalElapsedTime,
    formatElapsedTime,
  };
}
