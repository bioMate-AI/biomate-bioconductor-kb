/**
 * Galaxy State Poller
 * Polls Galaxy's invocation endpoint for real-time workflow execution updates
 * Uses Galaxy's native job states - NO fake progress estimation
 */

import { EventEmitter } from 'events';
import type {
  GalaxyWorkflowInvocation,
  GalaxyJob,
  GalaxyJobState,
  WorkflowExecutionUpdate,
} from '../shared/galaxy-types';

export interface PollerOptions {
  pollInterval?: number; // milliseconds (default: 2000)
  maxRetries?: number; // Max consecutive failures before stopping (default: 5)
}

export interface InvocationPoller {
  invocationId: string;
  workflowId: string;
  lastState: GalaxyWorkflowInvocation | null;
  isActive: boolean;
  failureCount: number;
  // Progress milestone tracking
  milestonesReported: Set<number>; // Track which milestones (25, 50, 75, 100) have been reported
  stepStartTimes: Map<string, number>; // Track when each step started (for ETA)
  stepCompletionTimes: Map<string, number>; // Track how long each step took
}

/**
 * Galaxy State Poller Service
 * Manages polling for multiple workflow invocations concurrently
 */
export class GalaxyStatePoller extends EventEmitter {
  private pollers: Map<string, InvocationPoller> = new Map();
  private pollInterval: number;
  private maxRetries: number;
  private intervalId: NodeJS.Timeout | null = null;

  // API client (can be real GalaxyAPIProxy or MockGalaxyAPI)
  private api: any;

  constructor(api: any, options: PollerOptions = {}) {
    super();
    this.api = api;
    this.pollInterval = options.pollInterval || 2000; // Poll every 2 seconds
    this.maxRetries = options.maxRetries || 5;
  }

  /**
   * Start polling for a workflow invocation
   */
  startPolling(invocationId: string, workflowId: string): void {
    if (this.pollers.has(invocationId)) {
      console.log(`Already polling invocation ${invocationId}`);
      return;
    }

    const poller: InvocationPoller = {
      invocationId,
      workflowId,
      lastState: null,
      isActive: true,
      failureCount: 0,
      milestonesReported: new Set<number>(),
      stepStartTimes: new Map<string, number>(),
      stepCompletionTimes: new Map<string, number>(),
    };

    this.pollers.set(invocationId, poller);
    console.log(`Started polling for invocation ${invocationId}`);

    // Start interval if not already running
    if (!this.intervalId) {
      this.startInterval();
    }

    // Immediate first poll
    this.pollInvocation(invocationId);
  }

  /**
   * Stop polling for a specific invocation
   */
  stopPolling(invocationId: string): void {
    const poller = this.pollers.get(invocationId);
    if (poller) {
      poller.isActive = false;
      this.pollers.delete(invocationId);
      console.log(`Stopped polling for invocation ${invocationId}`);

      // Stop interval if no active pollers
      if (this.pollers.size === 0 && this.intervalId) {
        this.stopInterval();
      }
    }
  }

  /**
   * Stop all pollers
   */
  stopAll(): void {
    this.pollers.clear();
    this.stopInterval();
    console.log('Stopped all pollers');
  }

  /**
   * Get current state for an invocation
   */
  getState(invocationId: string): GalaxyWorkflowInvocation | null {
    return this.pollers.get(invocationId)?.lastState || null;
  }

  /**
   * Check if actively polling an invocation
   */
  isPolling(invocationId: string): boolean {
    return this.pollers.get(invocationId)?.isActive || false;
  }

  // ============================================================================
  // Private Methods
  // ============================================================================

  private startInterval(): void {
    this.intervalId = setInterval(() => {
      this.pollAll();
    }, this.pollInterval);
    console.log(`Started polling interval (${this.pollInterval}ms)`);
  }

  private stopInterval(): void {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
      console.log('Stopped polling interval');
    }
  }

  private async pollAll(): Promise<void> {
    const promises = Array.from(this.pollers.keys()).map((invocationId) => this.pollInvocation(invocationId));
    await Promise.all(promises);
  }

  private async pollInvocation(invocationId: string): Promise<void> {
    const poller = this.pollers.get(invocationId);
    if (!poller || !poller.isActive) return;

    try {
      const invocation = await this.api.getInvocation(poller.workflowId, invocationId);

      // Reset failure count on successful poll
      poller.failureCount = 0;

      // Detect state changes
      this.detectStateChanges(poller, invocation);

      // Update stored state
      poller.lastState = invocation;

      // Check if workflow is complete (either terminal state or all steps done)
      if (this.isWorkflowComplete(invocation)) {
        console.log(`Invocation ${invocationId} completed with state: ${invocation.state}`);
        this.emit('workflow_completed', { invocation_id: invocationId, state: invocation.state });
        this.stopPolling(invocationId);
      }
    } catch (error: any) {
      poller.failureCount++;
      console.error(`Failed to poll invocation ${invocationId} (attempt ${poller.failureCount}/${this.maxRetries}):`, error.message);

      // Emit error event
      this.emit('polling_error', {
        invocation_id: invocationId,
        error: error.message,
        attempt: poller.failureCount,
      });

      // Stop polling after max retries
      if (poller.failureCount >= this.maxRetries) {
        console.error(`Max retries reached for invocation ${invocationId}, stopping polling`);
        this.emit('polling_failed', { invocation_id: invocationId, error: error.message });
        this.stopPolling(invocationId);
      }
    }
  }

  /**
   * Detect and emit state change events
   */
  private detectStateChanges(poller: InvocationPoller, newState: GalaxyWorkflowInvocation): void {
    const oldState = poller.lastState;

    // First poll - emit initial state
    if (!oldState) {
      this.emitUpdate({
        type: 'workflow_state',
        invocation_id: newState.id,
        timestamp: new Date().toISOString(),
        data: { workflow_state: newState.state },
      });
      return;
    }

    // Workflow-level state change
    if (oldState.state !== newState.state) {
      this.emitUpdate({
        type: 'workflow_state',
        invocation_id: newState.id,
        timestamp: new Date().toISOString(),
        data: { workflow_state: newState.state },
      });
    }

    // Step-level state changes
    // Use getEffectiveStepState to check job state instead of step state
    newState.steps.forEach((newStep: any) => {
      const oldStep = oldState.steps.find((s: any) => s.id === newStep.id);
      const newEffectiveState = this.getEffectiveStepState(newStep);
      const oldEffectiveState = oldStep ? this.getEffectiveStepState(oldStep) : null;

      // Get job_id from step or from jobs array
      const jobId = newStep.job_id || (newStep.jobs?.[0]?.id);

      if (!oldStep) {
        // New step detected
        this.emitUpdate({
          type: 'step_state',
          invocation_id: newState.id,
          timestamp: new Date().toISOString(),
          data: {
            step_id: newStep.id,
            step_state: newEffectiveState,
            job_id: jobId,
          },
        });

        // Track step start time
        if (newEffectiveState === 'running') {
          poller.stepStartTimes.set(newStep.id, Date.now());
        }
      } else if (oldEffectiveState !== newEffectiveState) {
        // Step state changed (using effective state from job)
        this.emitUpdate({
          type: 'step_state',
          invocation_id: newState.id,
          timestamp: new Date().toISOString(),
          data: {
            step_id: newStep.id,
            step_state: newEffectiveState,
            job_id: jobId,
          },
        });

        // Track step start time when it starts running
        if (newEffectiveState === 'running' && !poller.stepStartTimes.has(newStep.id)) {
          poller.stepStartTimes.set(newStep.id, Date.now());
        }

        // Track completion time when step finishes
        if ((newEffectiveState === 'ok' || newEffectiveState === 'error') && poller.stepStartTimes.has(newStep.id)) {
          const startTime = poller.stepStartTimes.get(newStep.id)!;
          const completionTime = Date.now() - startTime;
          poller.stepCompletionTimes.set(newStep.id, completionTime);
        }

        // Fetch and emit job logs for completed/error steps
        if (newEffectiveState === 'ok' || newEffectiveState === 'error') {
          this.fetchJobLogs(newState.id, newStep.id, jobId);
        }
      }
    });

    // Check for progress milestones after processing all steps
    this.detectProgressMilestones(poller, newState);
  }

  /**
   * Detect and report progress milestones (25%, 50%, 75%, 100%)
   * Proactively emits milestone notifications with ETA
   */
  private detectProgressMilestones(poller: InvocationPoller, invocation: GalaxyWorkflowInvocation): void {
    const totalSteps = invocation.steps.length;
    if (totalSteps === 0) return;

    // Count completed steps (ok or error) using effective state from jobs
    const completedSteps = invocation.steps.filter((step: any) => {
      const effectiveState = this.getEffectiveStepState(step);
      return effectiveState === 'ok' || effectiveState === 'error';
    }).length;

    // Calculate progress percentage (0-100)
    const progressPercent = Math.floor((completedSteps / totalSteps) * 100);

    // Define milestone thresholds
    const milestones = [25, 50, 75, 100];

    // Check each milestone
    for (const milestone of milestones) {
      // Only report if we've reached or passed this milestone and haven't reported it yet
      if (progressPercent >= milestone && !poller.milestonesReported.has(milestone)) {
        // Mark as reported
        poller.milestonesReported.add(milestone);

        // Calculate ETA
        const eta = this.calculateETA(poller, completedSteps, totalSteps);

        // Build milestone message
        const message = milestone === 100
          ? `✓ Workflow complete! (${completedSteps}/${totalSteps} steps)`
          : `✓ ${milestone}% complete (${completedSteps}/${totalSteps} steps)${eta ? ` - ${eta}` : ''}`;

        // Emit milestone event
        this.emitUpdate({
          type: 'progress_milestone',
          invocation_id: invocation.id,
          timestamp: new Date().toISOString(),
          data: {
            progress: milestone / 100,
            completedSteps,
            totalSteps,
            eta: eta || 'Calculating...',
            message,
            milestone,
          },
        });

        console.log(`[Milestone] Invocation ${invocation.id}: ${message}`);
      }
    }
  }

  /**
   * Calculate estimated time to completion based on historical step times
   * Returns formatted ETA string or null if cannot calculate
   */
  private calculateETA(poller: InvocationPoller, completedSteps: number, totalSteps: number): string | null {
    // Need at least 2 completed steps to calculate average
    if (poller.stepCompletionTimes.size < 2) {
      return null;
    }

    // Calculate average step completion time
    const completionTimes = Array.from(poller.stepCompletionTimes.values());
    const avgStepTime = completionTimes.reduce((sum, time) => sum + time, 0) / completionTimes.length;

    // Calculate remaining steps
    const remainingSteps = totalSteps - completedSteps;
    if (remainingSteps <= 0) {
      return 'Complete';
    }

    // Estimate remaining time
    const estimatedRemainingMs = avgStepTime * remainingSteps;

    // Format as human-readable ETA
    return `~${this.formatElapsedTime(estimatedRemainingMs)} remaining`;
  }

  /**
   * Fetch job logs and emit as events
   */
  private async fetchJobLogs(invocationId: string, stepId: string, jobId?: string): Promise<void> {
    if (!jobId) return;

    try {
      const [stdout, stderr] = await Promise.all([
        this.api.getJobStdout(jobId),
        this.api.getJobStderr(jobId),
      ]);

      if (stdout) {
        this.emitUpdate({
          type: 'job_log',
          invocation_id: invocationId,
          timestamp: new Date().toISOString(),
          data: {
            step_id: stepId,
            job_id: jobId,
            log_message: `STDOUT:\n${stdout}`,
          },
        });
      }

      if (stderr) {
        this.emitUpdate({
          type: stderr.includes('error') ? 'error' : 'job_log',
          invocation_id: invocationId,
          timestamp: new Date().toISOString(),
          data: {
            step_id: stepId,
            job_id: jobId,
            log_message: `STDERR:\n${stderr}`,
            error: stderr,
          },
        });
      }
    } catch (error: any) {
      console.error(`Failed to fetch logs for job ${jobId}:`, error.message);
    }
  }

  /**
   * Emit update event
   */
  private emitUpdate(update: WorkflowExecutionUpdate): void {
    this.emit('update', update);
    this.emit(update.type, update); // Also emit specific event type
  }

  /**
   * Check if workflow is complete (won't change anymore)
   * This checks both terminal states and completed scheduled workflows
   */
  private isTerminalState(state: GalaxyWorkflowInvocation['state']): boolean {
    return state === 'cancelled' || state === 'failed';
  }

  /**
   * Get the effective state of a step by checking its jobs
   * Galaxy step.state can be stale - use jobs[0].state for accuracy
   */
  private getEffectiveStepState(step: any): string {
    // If step has jobs array with job details, use the job state
    if (step.jobs && step.jobs.length > 0 && step.jobs[0].state) {
      return step.jobs[0].state;
    }
    // Fall back to step.state
    return step.state;
  }

  /**
   * Check if workflow invocation is actually complete
   * Galaxy workflows can stay in 'scheduled' state even when all steps are done
   * We check job state, not step state, for accuracy
   */
  private isWorkflowComplete(invocation: GalaxyWorkflowInvocation): boolean {
    // Terminal states
    if (this.isTerminalState(invocation.state)) {
      return true;
    }

    // Check if all steps are complete by looking at job state
    if (invocation.steps.length > 0) {
      const allStepsComplete = invocation.steps.every(step => {
        const effectiveState = this.getEffectiveStepState(step);
        return effectiveState === 'ok' || effectiveState === 'error';
      });
      return allStepsComplete;
    }

    return false;
  }

  /**
   * Calculate elapsed time for a job
   */
  calculateElapsedTime(createTime: string, updateTime?: string): number {
    const start = new Date(createTime).getTime();
    const end = updateTime ? new Date(updateTime).getTime() : Date.now();
    return end - start;
  }

  /**
   * Get human-readable elapsed time
   */
  formatElapsedTime(milliseconds: number): string {
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
  }
}

/**
 * Create poller instance
 */
export function createPoller(api: any, options?: PollerOptions): GalaxyStatePoller {
  return new GalaxyStatePoller(api, options);
}
