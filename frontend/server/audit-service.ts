/**
 * Audit Logging Service
 *
 * Provides persistent audit trail for all critical operations.
 * Required for regulatory compliance and debugging.
 */

import type { Request, Response, NextFunction } from 'express';
import { db } from './db';
import { auditLogs } from '../shared/schema';

export interface AuditEntry {
  userId?: string | null;
  sessionId?: string | null;
  action: string;
  resourceType?: string;
  resourceId?: string;
  details?: Record<string, any>;
  reasoning?: string;
  ipAddress?: string;
  userAgent?: string;
  status?: 'success' | 'failure' | 'error';
  errorMessage?: string;
  durationMs?: number;
}

/**
 * Audit Service - Logs actions to database for compliance
 */
export class AuditService {
  /**
   * Log an audit entry to the database
   */
  async log(entry: AuditEntry): Promise<void> {
    try {
      await db.insert(auditLogs).values({
        userId: entry.userId ?? null,
        sessionId: entry.sessionId ?? null,
        action: entry.action,
        resourceType: entry.resourceType ?? null,
        resourceId: entry.resourceId ?? null,
        details: entry.details ? JSON.stringify(entry.details) : null,
        reasoning: entry.reasoning ?? null,
        ipAddress: entry.ipAddress ?? null,
        userAgent: entry.userAgent ?? null,
        status: entry.status ?? 'success',
        errorMessage: entry.errorMessage ?? null,
        durationMs: entry.durationMs?.toString() ?? null,
      });
    } catch (error) {
      // Don't let audit failures break the main flow
      // But log to console as backup
      console.error('[AuditService] Failed to log audit entry:', error);
      console.log('[AuditService] Backup log:', JSON.stringify(entry));
    }
  }

  /**
   * Log workflow generation
   */
  async logWorkflowGeneration(
    userId: string | null,
    workflowName: string,
    toolsUsed: string[],
    reasoning: string,
    success: boolean,
    errorMessage?: string
  ): Promise<void> {
    await this.log({
      userId,
      action: 'workflow.generate',
      resourceType: 'workflow',
      resourceId: workflowName,
      details: { toolsUsed, toolCount: toolsUsed.length },
      reasoning,
      status: success ? 'success' : 'failure',
      errorMessage,
    });
  }

  /**
   * Log workflow execution start
   */
  async logWorkflowExecutionStart(
    userId: string | null,
    invocationId: string,
    workflowName: string,
    galaxyHistoryId: string
  ): Promise<void> {
    await this.log({
      userId,
      action: 'workflow.execute.start',
      resourceType: 'workflow_execution',
      resourceId: invocationId,
      details: { workflowName, galaxyHistoryId },
      status: 'success',
    });
  }

  /**
   * Log workflow execution completion
   */
  async logWorkflowExecutionComplete(
    userId: string | null,
    invocationId: string,
    status: 'ok' | 'error',
    durationMs: number,
    errorMessage?: string
  ): Promise<void> {
    await this.log({
      userId,
      action: 'workflow.execute.complete',
      resourceType: 'workflow_execution',
      resourceId: invocationId,
      status: status === 'ok' ? 'success' : 'error',
      errorMessage,
      durationMs,
    });
  }

  /**
   * Log dataset upload
   */
  async logDatasetUpload(
    userId: string | null,
    datasetId: string,
    fileName: string,
    fileSize: number
  ): Promise<void> {
    await this.log({
      userId,
      action: 'dataset.upload',
      resourceType: 'dataset',
      resourceId: datasetId,
      details: { fileName, fileSize },
      status: 'success',
    });
  }

  /**
   * Log authentication events
   */
  async logAuth(
    action: 'login' | 'logout' | 'register' | 'password_reset',
    userId: string | null,
    ipAddress: string,
    userAgent: string,
    success: boolean,
    errorMessage?: string
  ): Promise<void> {
    await this.log({
      userId,
      action: `auth.${action}`,
      resourceType: 'user',
      resourceId: userId ?? undefined,
      ipAddress,
      userAgent,
      status: success ? 'success' : 'failure',
      errorMessage,
    });
  }

  /**
   * Log SSE connection
   */
  async logSSEConnection(
    userId: string | null,
    invocationId: string,
    action: 'connect' | 'disconnect',
    ipAddress?: string
  ): Promise<void> {
    await this.log({
      userId,
      action: `sse.${action}`,
      resourceType: 'sse_connection',
      resourceId: invocationId,
      ipAddress,
      status: 'success',
    });
  }

  /**
   * Log API access denial
   */
  async logAccessDenied(
    userId: string | null,
    action: string,
    resourceType: string,
    resourceId: string,
    reason: string,
    ipAddress?: string
  ): Promise<void> {
    await this.log({
      userId,
      action,
      resourceType,
      resourceId,
      ipAddress,
      status: 'failure',
      errorMessage: `Access denied: ${reason}`,
    });
  }
}

// Export singleton instance
export const auditService = new AuditService();

/**
 * Express middleware for audit logging
 * Automatically logs all API requests with timing
 */
export function auditMiddleware(
  options: { excludePaths?: string[]; logBody?: boolean } = {}
) {
  const excludePaths = options.excludePaths ?? ['/api/health', '/api/workflow/sse'];

  return async (req: Request, res: Response, next: NextFunction) => {
    // Skip excluded paths
    if (excludePaths.some(path => req.path.startsWith(path))) {
      return next();
    }

    const startTime = Date.now();

    // Capture original end to log after response
    const originalEnd = res.end;
    res.end = function (this: Response, ...args: any[]) {
      const durationMs = Date.now() - startTime;
      const safeParams = req.params ?? {};

      // Log async to not block response
      auditService.log({
        userId: (req as any).user?.id ?? null,
        sessionId: req.sessionID,
        action: `api.${req.method.toLowerCase()}.${req.path.replace(/\//g, '.')}`,
        resourceType: 'api',
        resourceId: safeParams.id ?? safeParams.invocationId ?? req.path,
        details: options.logBody ? { body: req.body } : undefined,
        ipAddress: req.ip || req.socket.remoteAddress,
        userAgent: req.headers['user-agent'],
        status: res.statusCode < 400 ? 'success' : res.statusCode < 500 ? 'failure' : 'error',
        durationMs,
      }).catch(err => console.error('[AuditMiddleware] Log failed:', err));

      return originalEnd.apply(this, args as any);
    } as typeof res.end;

    next();
  };
}
