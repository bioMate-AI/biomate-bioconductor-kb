/**
 * Connector adapters — new endpoints required by the v2 tool manifest.
 *
 * The v2 connector surface adds three tools (`get_workflow_spec`,
 * `preview_file`, `upload_file`) that don't have a 1:1 existing route. Rather
 * than scattering ad-hoc handlers across `routes.ts`, this module concentrates
 * them so the implementation status is obvious. Tools that map to existing
 * endpoints (`get_run`, `export_report`, `recall_memory`) are not adapted here
 * — the MCP client hits the canonical paths directly.
 *
 * See docs/20260513_CONNECTOR_ARCHITECTURE_V2.md for the full plan.
 */

import type { Express, RequestHandler } from "express";

type AuthMiddleware = RequestHandler;

/**
 * Mount the v2 connector-specific adapter routes. Existing routes
 * (`/api/workflows/runs/:id`, `/api/workflows/runs/:id/findings/report`,
 * `/api/memory/relevant`) are reused as-is by the MCP client.
 */
export function registerConnectorAdapters(app: Express, optionalAuth: AuthMiddleware) {
  // ── get_workflow_spec ───────────────────────────────────────────────────────
  // Returns required + optional params, QC profile, cost estimate, license
  // requirements for a specific workflow_id. Proper implementation requires
  // a single-workflow lookup against backend/database/galaxy_ai_tools.db (the
  // existing /api/workflows/search returns the same fields but only via a
  // ranked query). Stubbed for Phase 2 — until then call search_workflow with
  // limit=1 and an exact-name query to get the same data.
  app.get("/api/workflows/spec", optionalAuth, async (req, res) => {
    const workflowId = String(req.query.workflow_id || "").trim();
    if (!workflowId) {
      return res.status(400).json({ error: "missing_workflow_id", message: "Pass ?workflow_id=…" });
    }
    res.status(501).json({
      error: "not_implemented",
      message:
        "Dedicated workflow-spec endpoint is stubbed pending Phase 2. " +
        "Workaround: call /api/workflows/search with query=<workflow_id> and limit=1 — " +
        "the first result carries the same required_params, optional_params, qc_profile, " +
        "license_requirements, estimated_cost_usd, and nextflow_path fields.",
      received: { workflow_id: workflowId },
      todo: "docs/20260513_CONNECTOR_ARCHITECTURE_V2.md — get_workflow_spec",
    });
  });

  // ── preview_file ────────────────────────────────────────────────────────────
  // Server-side preview / parse of an output file (FASTA, VCF, CSV, image,
  // PDF). For now we return 501 with a structured next-step pointer so the
  // tool fails observably rather than 404. Full implementation tracked in
  // docs/20260513_CONNECTOR_ARCHITECTURE_V2.md — Phase 2.
  app.post("/api/files/preview", optionalAuth, async (req, res) => {
    const { s3_key, run_id, max_rows } = req.body || {};
    if (!s3_key) {
      return res.status(400).json({ error: "missing_s3_key" });
    }
    res.status(501).json({
      error: "not_implemented",
      message:
        "Server-side file preview is stubbed pending Phase 2. " +
        "For now, fetch the file URL from get_run output_files and download directly.",
      received: { s3_key, run_id, max_rows },
      todo: "docs/20260513_CONNECTOR_ARCHITECTURE_V2.md — preview_file",
    });
  });

  // ── upload_file ─────────────────────────────────────────────────────────────
  // Issue a one-shot signed S3 PUT URL for direct host-to-S3 upload. Stubbed
  // pending Phase 2; until then the existing multipart `/api/datasets/upload`
  // remains the supported path for binary uploads.
  app.post("/api/uploads/signed_url", optionalAuth, async (req, res) => {
    const { filename, size_bytes, content_type } = req.body || {};
    if (!filename) {
      return res.status(400).json({ error: "missing_filename" });
    }
    res.status(501).json({
      error: "not_implemented",
      message:
        "Signed S3 PUT URLs are stubbed pending Phase 2. " +
        "For now use multipart POST /api/datasets/upload.",
      received: { filename, size_bytes, content_type },
      todo: "docs/20260513_CONNECTOR_ARCHITECTURE_V2.md — upload_file",
    });
  });
}
