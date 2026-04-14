/**
 * Workflow Notification Service
 *
 * Connects GalaxyStatePoller events to email notifications.
 * Sends completion/error emails when workflows finish.
 */

import { emailService } from './email-service';
import type { GalaxyStatePoller } from './galaxy-state-poller';
import type { IStorage } from './storage';

// Notification preferences interface
export interface NotificationPreferences {
  emailOnComplete: boolean;
  emailOnError: boolean;
  // Future: webhookUrl, slackChannel, etc.
}

// Default preferences
const DEFAULT_PREFERENCES: NotificationPreferences = {
  emailOnComplete: true,
  emailOnError: true,
};

// Track active invocations with their metadata
interface InvocationMetadata {
  userId: string;
  userEmail: string;
  userName: string;
  workflowName: string;
  workflowId: string;
  startTime: Date;
}

/**
 * Workflow Notification Service
 * Manages email notifications for workflow completion events
 */
export class WorkflowNotificationService {
  private poller: GalaxyStatePoller;
  private storage: IStorage;
  private activeInvocations: Map<string, InvocationMetadata> = new Map();

  constructor(poller: GalaxyStatePoller, storage: IStorage) {
    this.poller = poller;
    this.storage = storage;

    // Register event listeners
    this.registerEventListeners();
  }

  /**
   * Register an invocation for notifications
   * Call this when a workflow is started
   */
  registerInvocation(
    invocationId: string,
    metadata: InvocationMetadata
  ): void {
    this.activeInvocations.set(invocationId, {
      ...metadata,
      startTime: new Date(),
    });
    console.log(`[WorkflowNotification] Registered invocation ${invocationId} for notifications`);
  }

  /**
   * Unregister an invocation
   */
  unregisterInvocation(invocationId: string): void {
    this.activeInvocations.delete(invocationId);
  }

  /**
   * Get user notification preferences
   * Falls back to defaults if not set
   */
  async getUserPreferences(userId: string): Promise<NotificationPreferences> {
    try {
      // Try to get user-specific preferences from storage
      // For now, return defaults - can be extended to read from database
      return DEFAULT_PREFERENCES;
    } catch (error) {
      console.error(`[WorkflowNotification] Failed to get preferences for user ${userId}:`, error);
      return DEFAULT_PREFERENCES;
    }
  }

  /**
   * Register event listeners on the poller
   */
  private registerEventListeners(): void {
    // Listen for workflow completion
    this.poller.on('workflow_completed', async (event: { invocation_id: string; state: string }) => {
      await this.handleWorkflowComplete(event.invocation_id, event.state);
    });

    // Listen for polling failures (workflow errors)
    this.poller.on('polling_failed', async (event: { invocation_id: string; error: string }) => {
      await this.handleWorkflowError(event.invocation_id, event.error);
    });
  }

  /**
   * Handle workflow completion event
   */
  private async handleWorkflowComplete(invocationId: string, state: string): Promise<void> {
    const metadata = this.activeInvocations.get(invocationId);
    if (!metadata) {
      console.log(`[WorkflowNotification] No metadata found for invocation ${invocationId}`);
      return;
    }
    // Unregister immediately to deduplicate concurrent events
    this.unregisterInvocation(invocationId);

    try {
      // Get user preferences
      const prefs = await this.getUserPreferences(metadata.userId);

      // Calculate elapsed time
      const elapsedMs = Date.now() - metadata.startTime.getTime();
      const elapsedTime = this.formatElapsedTime(elapsedMs);

      // Check final state and send appropriate email
      if (state === 'failed' || state === 'cancelled') {
        if (prefs.emailOnError) {
          await emailService.sendWorkflowErrorEmail(
            metadata.userEmail,
            metadata.userName,
            metadata.workflowName,
            invocationId,
            'Unknown step',
            `Workflow ended with state: ${state}`
          );
          console.log(`[WorkflowNotification] Sent error email to ${metadata.userEmail}`);
        }
      } else {
        // Workflow completed successfully
        if (prefs.emailOnComplete) {
          // Get step counts from poller state
          const invocationState = this.poller.getState(invocationId);
          const totalSteps = invocationState?.steps?.length || 0;
          const completedSteps = invocationState?.steps?.filter(
            (s: any) => s.state === 'ok' || s.jobs?.[0]?.state === 'ok'
          ).length || totalSteps;

          await emailService.sendWorkflowCompleteEmail(
            metadata.userEmail,
            metadata.userName,
            metadata.workflowName,
            invocationId,
            completedSteps,
            totalSteps,
            elapsedTime
          );
          console.log(`[WorkflowNotification] Sent completion email to ${metadata.userEmail}`);
        }
      }
    } catch (error) {
      console.error(`[WorkflowNotification] Failed to send notification for ${invocationId}:`, error);
    }
  }

  /**
   * Handle workflow error event
   */
  private async handleWorkflowError(invocationId: string, error: string): Promise<void> {
    const metadata = this.activeInvocations.get(invocationId);
    if (!metadata) {
      console.log(`[WorkflowNotification] No metadata found for invocation ${invocationId}`);
      return;
    }
    // Unregister immediately to deduplicate concurrent events
    this.unregisterInvocation(invocationId);

    try {
      const prefs = await this.getUserPreferences(metadata.userId);

      if (prefs.emailOnError) {
        await emailService.sendWorkflowErrorEmail(
          metadata.userEmail,
          metadata.userName,
          metadata.workflowName,
          invocationId,
          'Polling failed',
          error
        );
        console.log(`[WorkflowNotification] Sent error email to ${metadata.userEmail}`);
      }
    } catch (err) {
      console.error(`[WorkflowNotification] Failed to send error notification for ${invocationId}:`, err);
    }
  }

  /**
   * Format elapsed time as human-readable string
   */
  private formatElapsedTime(milliseconds: number): string {
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
 * Create notification service instance
 */
export function createWorkflowNotificationService(
  poller: GalaxyStatePoller,
  storage: IStorage
): WorkflowNotificationService {
  return new WorkflowNotificationService(poller, storage);
}
