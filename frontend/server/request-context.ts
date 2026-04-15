/**
 * Per-request AsyncLocalStorage context.
 *
 * Provides request-scoped metadata (userId, sessionId, requestId, conversationId)
 * that is automatically available anywhere within a request's async call chain —
 * including Galaxy API calls, LLM calls, and SSE streaming — without threading
 * the values through every function signature.
 *
 * Usage:
 *   import { getRequestContext, requestContextStorage } from './request-context';
 *
 *   // In any async function called during a request:
 *   const ctx = getRequestContext();
 *   logger.info({ requestId: ctx?.requestId, userId: ctx?.userId }, 'Processing...');
 */

import { AsyncLocalStorage } from 'async_hooks';
import { randomUUID } from 'crypto';

export interface RequestContext {
  /** UUID generated per HTTP request — use for log correlation */
  requestId: string;
  /** BioMate user ID (undefined for unauthenticated requests) */
  userId?: string;
  /** Frontend conversation/chat session identifier */
  sessionId?: string;
  /** memorySessionId passed in request body */
  conversationId?: string;
  /** Wall-clock timestamp when the request entered the middleware */
  startedAt: number;
}

export const requestContextStorage = new AsyncLocalStorage<RequestContext>();

/**
 * Returns the context for the current async request, or undefined when called
 * outside a request context (e.g. background tasks, startup).
 */
export function getRequestContext(): RequestContext | undefined {
  return requestContextStorage.getStore();
}

/**
 * Express middleware — must be registered before any route handlers.
 * Wraps each request in an AsyncLocalStorage context so that any code
 * downstream (including callbacks, promises, event emitters) can call
 * getRequestContext() without extra wiring.
 */
export function requestContextMiddleware(
  req: any,
  res: any,
  next: () => void
): void {
  const context: RequestContext = {
    requestId: randomUUID(),
    userId: req.user ? String((req.user as any).id) : undefined,
    sessionId: req.body?.sessionId || req.query?.sessionId || undefined,
    conversationId: req.body?.memorySessionId || req.body?.conversationId || undefined,
    startedAt: Date.now(),
  };

  // Attach requestId to response headers for client-side trace correlation
  res.setHeader('X-Request-Id', context.requestId);

  requestContextStorage.run(context, next);
}
