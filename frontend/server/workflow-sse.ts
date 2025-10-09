/**
 * Server-Sent Events (SSE) Endpoint for Real-Time Workflow Updates
 * Streams Galaxy workflow execution state to frontend
 */

import type { Request, Response } from 'express';
import type { WorkflowExecutionUpdate } from '../shared/galaxy-types';
import type { GalaxyStatePoller } from './galaxy-state-poller';

export interface SSEClient {
  id: string;
  invocationId: string;
  response: Response;
  isActive: boolean;
}

/**
 * SSE Manager for workflow execution updates
 */
export class WorkflowSSEManager {
  private clients: Map<string, SSEClient[]> = new Map(); // invocationId -> clients
  private poller: GalaxyStatePoller;

  constructor(poller: GalaxyStatePoller) {
    this.poller = poller;
    this.setupPollerListeners();
  }

  /**
   * Setup listeners for poller events
   */
  private setupPollerListeners(): void {
    // Workflow-level state changes
    this.poller.on('workflow_state', (update: WorkflowExecutionUpdate) => {
      this.broadcastToClients(update.invocation_id, update);
    });

    // Step-level state changes
    this.poller.on('step_state', (update: WorkflowExecutionUpdate) => {
      this.broadcastToClients(update.invocation_id, update);
    });

    // Job logs
    this.poller.on('job_log', (update: WorkflowExecutionUpdate) => {
      this.broadcastToClients(update.invocation_id, update);
    });

    // Errors
    this.poller.on('error', (update: WorkflowExecutionUpdate) => {
      this.broadcastToClients(update.invocation_id, update);
    });

    // Workflow completed
    this.poller.on('workflow_completed', (data: { invocation_id: string; state: string }) => {
      const update: WorkflowExecutionUpdate = {
        type: 'workflow_state',
        invocation_id: data.invocation_id,
        timestamp: new Date().toISOString(),
        data: { workflow_state: data.state as any },
      };
      this.broadcastToClients(data.invocation_id, update);

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
   */
  handleConnection(req: Request, res: Response): void {
    const invocationId = req.params.invocationId;
    if (!invocationId) {
      res.status(400).json({ error: 'Missing invocationId parameter' });
      return;
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
      console.log(`Starting polling for invocation ${invocationId}`);
      // Note: workflowId would normally come from the request or database
      // For now, using invocationId as placeholder
      this.poller.startPolling(invocationId, invocationId);
    }

    // Handle client disconnect
    req.on('close', () => {
      client.isActive = false;
      this.removeClient(invocationId, clientId);
      console.log(`SSE client ${clientId} disconnected`);

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
