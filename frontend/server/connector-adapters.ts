/**
 * Connector adapters — previously held stubs for preview_file, upload_file,
 * and get_workflow_spec that blocked the real implementations registered later
 * in routes.ts. All three stubs have been removed so Express falls through to
 * the real handlers:
 *   GET  /api/workflows/spec       → routes.ts:7698
 *   POST /api/files/preview        → routes.ts:7842
 *   POST /api/uploads/signed_url   → routes.ts:8221
 */

import type { Express, RequestHandler } from "express";

type AuthMiddleware = RequestHandler;

export function registerConnectorAdapters(app: Express, optionalAuth: AuthMiddleware) {
  // No-op: all adapter routes are now served by the canonical handlers in routes.ts.
  void app;
  void optionalAuth;
}
