/**
 * Server-Sent Events (SSE) Endpoint for Real-Time Workflow Updates
 * Streams Galaxy workflow execution state to frontend
 *
 * Security: Requires authentication - verifies user owns the execution
 */

import type { Request, Response } from 'express';
import type { WorkflowExecutionUpdate } from '../shared/galaxy-types';
import type { GalaxyStatePoller } from './galaxy-state-poller';
import { authService } from './auth-service';
import { auditService } from './audit-service';
import { db } from './db';
import { workflowExecutions } from '../shared/schema';
import { eq } from 'drizzle-orm';
import { storage } from './storage';

export interface SSEClient {
  id: string;
  invocationId: string;
  userId: string | null;
  response: Response;
  isActive: boolean;
}

export interface SSEManagerOptions {
  strictAuth?: boolean; // If true, reject connections without valid auth (default: false for backward compatibility)
}

/**
 * SSE Manager for workflow execution updates
 */
export class WorkflowSSEManager {
  private clients: Map<string, SSEClient[]> = new Map(); // invocationId -> clients
  private poller: GalaxyStatePoller;
  private strictAuth: boolean;

  constructor(poller: GalaxyStatePoller, options: SSEManagerOptions = {}) {
    this.poller = poller;
    this.strictAuth = options.strictAuth ?? (process.env.SSE_STRICT_AUTH === 'true');
    this.setupPollerListeners();
  }

  /**
   * Setup listeners for poller events
   */
  private setupPollerListeners(): void {
    // Workflow-level state changes
    this.poller.on('workflow_state', async (update: WorkflowExecutionUpdate) => {
      this.broadcastToClients(update.invocation_id, update);

      // Update local invocation record
      try {
        const data = update.data as any;
        await storage.updateInvocation(update.invocation_id, {
          status: data.workflow_state || 'running',
          updatedAt: new Date(),
        });
      } catch (e) {
        console.warn('[SSE] Failed to update local invocation:', e);
      }
    });

    // Step-level state changes
    this.poller.on('step_state', async (update: WorkflowExecutionUpdate) => {
      this.broadcastToClients(update.invocation_id, update);

      // Update local invocation record with step progress
      try {
        const data = update.data as any;
        if (data.step_state === 'ok' || data.step_state === 'completed') {
          // Increment completed steps
          const invocation = await storage.getInvocation(update.invocation_id);
          if (invocation) {
            await storage.updateInvocation(update.invocation_id, {
              completedSteps: (invocation.completedSteps || 0) + 1,
              currentStepName: data.step_label || data.tool_id,
              updatedAt: new Date(),
            });
          }
        }
      } catch (e) {
        console.warn('[SSE] Failed to update step progress:', e);
      }
    });

    // Job logs
    this.poller.on('job_log', (update: WorkflowExecutionUpdate) => {
      this.broadcastToClients(update.invocation_id, update);
    });

    // Errors
    this.poller.on('error', (update: WorkflowExecutionUpdate) => {
      this.broadcastToClients(update.invocation_id, update);
    });

    // Progress milestones
    this.poller.on('progress_milestone', (update: WorkflowExecutionUpdate) => {
      this.broadcastToClients(update.invocation_id, update);
    });

    // Workflow completed
    this.poller.on('workflow_completed', async (data: { invocation_id: string; state: string }) => {
      const update: WorkflowExecutionUpdate = {
        type: 'workflow_state',
        invocation_id: data.invocation_id,
        timestamp: new Date().toISOString(),
        data: { workflow_state: data.state as any },
      };
      this.broadcastToClients(data.invocation_id, update);

      // Update local invocation record with completed state
      try {
        const finalStatus = (data.state === 'scheduled' ? 'ok' : data.state) as 'new' | 'queued' | 'running' | 'ok' | 'error' | 'paused' | 'deleted';
        await storage.updateInvocation(data.invocation_id, {
          status: finalStatus,
          updatedAt: new Date(),
        });
        console.log('[SSE] Workflow completed, updated local record:', data.invocation_id);
      } catch (e) {
        console.warn('[SSE] Failed to update completion status:', e);
      }

      // Close all clients after completion
      setTimeout(() => {
        this.closeClientsForInvocation(data.invocation_id);
      }, 1000);
    });

    // Polling errors
    this.poller.on('polling_error', (data: { invocation_id: string; error: string }) => {
      const update: WorkflowExecutionUpdate = {
        type: 'error',
        invocation_id: data.invocation_id,
        timestamp: new Date().toISOString(),
        data: { error: `Polling error: ${data.error}` },
      };
      this.broadcastToClients(data.invocation_id, update);
    });

    // Polling failed
    this.poller.on('polling_failed', (data: { invocation_id: string; error: string }) => {
      const update: WorkflowExecutionUpdate = {
        type: 'error',
        invocation_id: data.invocation_id,
        timestamp: new Date().toISOString(),
        data: { error: `Polling failed: ${data.error}` },
      };
      this.broadcastToClients(data.invocation_id, update);
      this.closeClientsForInvocation(data.invocation_id);
    });
  }

  /**
   * Handle SSE connection from client
   * Includes authentication check to verify user owns the execution
   */
  async handleConnection(req: Request, res: Response): Promise<void> {
    const { workflowId, invocationId } = req.params;
    if (!workflowId || !invocationId) {
      res.status(400).json({ error: 'Missing workflowId or invocationId parameter' });
      return;
    }

    // Authenticate user from token
    let userId: string | null = null;
    try {
      // Get token from query param (SSE can't use headers easily from EventSource)
      const token = req.query.token as string || req.cookies?.biomate_token;

      if (token) {
        const payload = authService.verifyToken(token);
        userId = payload.userId;

        // Verify user owns this execution (if we have execution records)
        try {
          const [execution] = await db
            .select()
            .from(workflowExecutions)
            .where(eq(workflowExecutions.galaxyInvocationId, invocationId))
            .limit(1);

          if (execution && execution.userId !== userId) {
            // User doesn't own this execution
            await auditService.logAccessDenied(
              userId,
              'sse.connect',
              'workflow_execution',
              invocationId,
              'User does not own this execution',
              req.ip || req.socket.remoteAddress
            );
            res.status(403).json({ error: 'Access denied - you do not own this workflow execution' });
            return;
          }
        } catch (dbError) {
          // If no execution record exists yet, allow connection (execution tracking is optional)
          console.log(`[SSE] No execution record for ${invocationId}, allowing connection`);
        }
      }

      // Log SSE connection
      await auditService.logSSEConnection(userId, invocationId, 'connect', req.ip || req.socket.remoteAddress);
    } catch (authError: any) {
      // Log failed auth attempt
      console.warn(`[SSE] Auth failed for invocation ${invocationId}:`, authError?.message || authError);

      // Audit log the failed auth attempt
      await auditService.logAccessDenied(
        null,
        'sse.connect',
        'workflow_invocation',
        invocationId,
        `Auth failed: ${authError?.message || 'Unknown error'}`,
        req.ip || req.socket.remoteAddress
      ).catch(err => console.error('[SSE] Failed to log auth failure:', err));

      // In strict mode, reject the connection
      if (this.strictAuth) {
        res.status(401).json({ error: 'Authentication required for SSE connection' });
        return;
      }
      // In permissive mode (default), allow connection but with null userId
      console.log(`[SSE] Allowing unauthenticated connection for ${invocationId} (strict auth disabled)`);
    }

    // Setup SSE headers
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no'); // Disable nginx buffering

    // Generate client ID
    const clientId = `client_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

    const client: SSEClient = {
      id: clientId,
      invocationId,
      userId,
      response: res,
      isActive: true,
    };

    // Add client to the map
    if (!this.clients.has(invocationId)) {
      this.clients.set(invocationId, []);
    }
    this.clients.get(invocationId)!.push(client);

    console.log(`SSE client ${clientId} connected for invocation ${invocationId}`);

    // Send initial connection message
    this.sendEvent(res, {
      type: 'workflow_state',
      invocation_id: invocationId,
      timestamp: new Date().toISOString(),
      data: { workflow_state: 'new' },
    });

    // Send current state if available
    const currentState = this.poller.getState(invocationId);
    if (currentState) {
      this.sendEvent(res, {
        type: 'workflow_state',
        invocation_id: invocationId,
        timestamp: new Date().toISOString(),
        data: { workflow_state: currentState.state },
      });

      // Send step states
      currentState.steps.forEach((step) => {
        this.sendEvent(res, {
          type: 'step_state',
          invocation_id: invocationId,
          timestamp: new Date().toISOString(),
          data: {
            step_id: step.id,
            step_state: step.state,
            job_id: step.job_id,
          },
        });
      });
    }

    // Start polling if not already polling
    if (!this.poller.isPolling(invocationId)) {
      console.log(`Starting polling for invocation ${invocationId} (workflow ${workflowId})`);
      this.poller.startPolling(invocationId, workflowId);
    }

    // Handle client disconnect
    req.on('close', () => {
      client.isActive = false;
      this.removeClient(invocationId, clientId);
      console.log(`SSE client ${clientId} disconnected`);

      // Log disconnect
      auditService.logSSEConnection(userId, invocationId, 'disconnect', req.ip || req.socket.remoteAddress)
        .catch(err => console.error('[SSE] Failed to log disconnect:', err));

      // Stop polling if no more clients
      const remainingClients = this.clients.get(invocationId);
      if (!remainingClients || remainingClients.length === 0) {
        console.log(`No more clients for invocation ${invocationId}, stopping polling`);
        this.poller.stopPolling(invocationId);
      }
    });

    // Keep connection alive with periodic pings
    const pingInterval = setInterval(() => {
      if (!client.isActive) {
        clearInterval(pingInterval);
        return;
      }
      res.write(': ping\n\n');
    }, 30000); // Ping every 30 seconds

    req.on('close', () => clearInterval(pingInterval));
  }

  /**
   * Send SSE event to a specific client
   */
  private sendEvent(res: Response, update: WorkflowExecutionUpdate): void {
    try {
      const eventData = JSON.stringify(update);
      res.write(`event: ${update.type}\n`);
      res.write(`data: ${eventData}\n\n`);
    } catch (error) {
      console.error('Error sending SSE event:', error);
    }
  }

  /**
   * Broadcast update to all clients listening to an invocation
   */
  private broadcastToClients(invocationId: string, update: WorkflowExecutionUpdate): void {
    const clients = this.clients.get(invocationId);
    if (!clients || clients.length === 0) return;

    console.log(`Broadcasting ${update.type} to ${clients.length} clients for invocation ${invocationId}`);

    clients.forEach((client) => {
      if (client.isActive) {
        this.sendEvent(client.response, update);
      }
    });
  }

  /**
   * Remove a specific client
   */
  private removeClient(invocationId: string, clientId: string): void {
    const clients = this.clients.get(invocationId);
    if (!clients) return;

    const index = clients.findIndex((c) => c.id === clientId);
    if (index !== -1) {
      clients.splice(index, 1);
    }

    if (clients.length === 0) {
      this.clients.delete(invocationId);
    }
  }

  /**
   * Close all clients for a specific invocation
   */
  private closeClientsForInvocation(invocationId: string): void {
    const clients = this.clients.get(invocationId);
    if (!clients) return;

    console.log(`Closing ${clients.length} SSE connections for invocation ${invocationId}`);

    clients.forEach((client) => {
      if (client.isActive) {
        client.isActive = false;
        client.response.end();
      }
    });

    this.clients.delete(invocationId);
  }

  /**
   * Handle SSE connection using only invocationId (no workflowId required).
   * Used by the QC gate SSE endpoint (/api/workflows/:invocationId/events).
   * Does NOT start Galaxy polling — events arrive via injectRawEvent().
   */
  async handleConnectionByInvocationId(req: Request, res: Response): Promise<void> {
    const { invocationId } = req.params;
    if (!invocationId) {
      res.status(400).json({ error: 'Missing invocationId parameter' });
      return;
    }

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no');

    const clientId = `qc_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const client: SSEClient = {
      id: clientId,
      invocationId,
      userId: null,
      response: res,
      isActive: true,
    };

    if (!this.clients.has(invocationId)) {
      this.clients.set(invocationId, []);
    }
    this.clients.get(invocationId)!.push(client);

    console.log(`[SSE] QC client ${clientId} connected for invocation ${invocationId}`);

    // Send initial connected acknowledgement
    res.write(`event: connected\n`);
    res.write(`data: ${JSON.stringify({ invocation_id: invocationId })}\n\n`);

    req.on('close', () => {
      client.isActive = false;
      this.removeClient(invocationId, clientId);
      console.log(`[SSE] QC client ${clientId} disconnected`);
    });

    const pingInterval = setInterval(() => {
      if (!client.isActive) {
        clearInterval(pingInterval);
        return;
      }
      res.write(': ping\n\n');
    }, 30000);

    req.on('close', () => clearInterval(pingInterval));
  }

  /**
   * Inject a raw SSE event to all clients listening to an invocationId.
   * Called by the /internal/sse-inject route so the Python backend can push
   * QC gate events without going through the Galaxy poller.
   */
  injectRawEvent(invocationId: string, eventType: string, data: Record<string, any>): void {
    const clients = this.clients.get(invocationId);
    if (!clients || clients.length === 0) {
      console.log(`[SSE] No clients for invocation ${invocationId}, dropping ${eventType} event`);
      return;
    }

    console.log(`[SSE] Injecting ${eventType} to ${clients.length} clients for ${invocationId}`);

    clients.forEach((client) => {
      if (client.isActive) {
        try {
          client.response.write(`event: ${eventType}\n`);
          client.response.write(`data: ${JSON.stringify(data)}\n\n`);
        } catch (err) {
          console.error(`[SSE] Failed to write to client ${client.id}:`, err);
          client.isActive = false;
        }
      }
    });
  }

  /**
   * Get active client count for an invocation
   */
  getClientCount(invocationId: string): number {
    const clients = this.clients.get(invocationId);
    return clients ? clients.filter((c) => c.isActive).length : 0;
  }

  /**
   * Get total active client count
   */
  getTotalClientCount(): number {
    let total = 0;
    this.clients.forEach((clients) => {
      total += clients.filter((c) => c.isActive).length;
    });
    return total;
  }

  /**
   * Cleanup all connections
   */
  cleanup(): void {
    console.log('Cleaning up all SSE connections');
    this.clients.forEach((clients, invocationId) => {
      this.closeClientsForInvocation(invocationId);
    });
    this.poller.stopAll();
  }
}
