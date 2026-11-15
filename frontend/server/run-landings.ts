/**
 * BioMate-native pre-filled run landing links (Wave 4).
 *
 * Not Galaxy workflow_landings. Not owner-scoped /workflow/:id drafts
 * (workflow_drafts). Authenticated create → shareable /run/:token →
 * authenticate + claim → chat+panel prefilled for Confirm & Run.
 *
 * Authz: create requires auth. Preview is public (name + expiry only).
 * Claim requires auth; unknown/expired token → 404 (existence not leaked
 * via distinct foreign errors). Tokens are unguessable (32-byte base64url).
 */

import type { Express, Request, Response } from "express";
import { randomBytes, randomUUID } from "crypto";
import { authenticateToken } from "./auth-middleware";
import { pool } from "./db";

const DEFAULT_TTL_DAYS = 30;
const MAX_TTL_DAYS = 90;
const TABLE_SQL = `
  CREATE TABLE IF NOT EXISTS run_landings (
    id              TEXT        PRIMARY KEY,
    token           TEXT        NOT NULL UNIQUE,
    created_by      TEXT        NOT NULL,
    project_id      TEXT,
    workflow_id     TEXT,
    nextflow_path   TEXT,
    workflow_name   TEXT,
    domain          TEXT,
    workflow        JSONB,
    params          JSONB       NOT NULL DEFAULT '{}'::jsonb,
    dataset_refs    JSONB       NOT NULL DEFAULT '[]'::jsonb,
    response_text   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ,
    first_claimed_by TEXT,
    first_claimed_at TIMESTAMPTZ,
    claim_count     INTEGER     NOT NULL DEFAULT 0
  )
`;

let tableReady: Promise<void> | null = null;

function ensureRunLandingsTable(): Promise<void> {
  if (!tableReady) {
    tableReady = (async () => {
      await pool.query(TABLE_SQL);
      await pool.query(`CREATE INDEX IF NOT EXISTS run_landings_token_idx ON run_landings (token)`);
      await pool.query(
        `CREATE INDEX IF NOT EXISTS run_landings_created_by_idx ON run_landings (created_by, created_at DESC)`,
      );
      await pool.query(`CREATE INDEX IF NOT EXISTS run_landings_expiry_idx ON run_landings (expires_at)`);
    })().catch((e) => {
      tableReady = null;
      throw e;
    });
  }
  return tableReady;
}

function userId(req: Request): string | null {
  const u = (req as any).user;
  return u?.id ? String(u.id) : null;
}

function appBaseUrl(req?: Request): string {
  const env = (process.env.APP_URL || "").replace(/\/+$/, "");
  if (env) return env;
  if (req) {
    const proto = (req.headers["x-forwarded-proto"] as string) || req.protocol || "https";
    const host = req.headers["x-forwarded-host"] || req.headers.host;
    if (host) return `${proto}://${host}`;
  }
  return "http://localhost:5000";
}

export type RunLandingCreateBody = {
  workflowId?: string | null;
  nextflowPath?: string | null;
  workflowName?: string | null;
  domain?: string | null;
  workflow?: Record<string, unknown> | null;
  params?: Record<string, unknown> | null;
  datasetRefs?: unknown[] | null;
  projectId?: string | null;
  response?: string | null;
  expiresInDays?: number | null;
};

export type RunLandingValidationError = { error: string; status: number };

/** Pure validation — unit-tested without DB. */
export function validateCreateBody(
  body: unknown,
): { ok: true; value: Required<Pick<RunLandingCreateBody, never>> & RunLandingCreateBody & { expiresInDays: number } } | { ok: false; error: RunLandingValidationError } {
  if (!body || typeof body !== "object") {
    return { ok: false, error: { error: "body required", status: 400 } };
  }
  const b = body as RunLandingCreateBody;
  const workflowId = b.workflowId != null ? String(b.workflowId).trim() : "";
  const nextflowPath = b.nextflowPath != null ? String(b.nextflowPath).trim() : "";
  const workflowName =
    (b.workflowName != null ? String(b.workflowName).trim() : "") ||
    (b.workflow && typeof b.workflow === "object" && (b.workflow as any).name
      ? String((b.workflow as any).name).trim()
      : "");
  if (!workflowId && !nextflowPath && !workflowName && !(b.workflow && typeof b.workflow === "object")) {
    return {
      ok: false,
      error: {
        error: "workflowId, nextflowPath, workflowName, or workflow object required",
        status: 400,
      },
    };
  }
  let expiresInDays = DEFAULT_TTL_DAYS;
  if (b.expiresInDays != null) {
    const n = Number(b.expiresInDays);
    if (!Number.isFinite(n) || n <= 0) {
      return { ok: false, error: { error: "expiresInDays must be a positive number", status: 400 } };
    }
    expiresInDays = Math.min(MAX_TTL_DAYS, Math.ceil(n));
  }
  const params =
    b.params && typeof b.params === "object" && !Array.isArray(b.params) ? b.params : {};
  const datasetRefs = Array.isArray(b.datasetRefs) ? b.datasetRefs : [];
  return {
    ok: true,
    value: {
      workflowId: workflowId || null,
      nextflowPath: nextflowPath || null,
      workflowName: workflowName || null,
      domain: b.domain != null ? String(b.domain) : null,
      workflow: b.workflow && typeof b.workflow === "object" ? b.workflow : null,
      params,
      datasetRefs,
      projectId: b.projectId != null ? String(b.projectId) : null,
      response: b.response != null ? String(b.response) : null,
      expiresInDays,
    },
  };
}

/** Merge params + dataset refs into a panel-shaped workflow for the claim page. */
export function buildPanelWorkflow(row: {
  workflow?: any;
  workflow_id?: string | null;
  nextflow_path?: string | null;
  workflow_name?: string | null;
  domain?: string | null;
  params?: any;
  dataset_refs?: any;
}): Record<string, unknown> {
  const base =
    row.workflow && typeof row.workflow === "object" && !Array.isArray(row.workflow)
      ? { ...row.workflow }
      : {};
  const params =
    row.params && typeof row.params === "object" && !Array.isArray(row.params) ? row.params : {};
  const inline = {
    ...((base as any).inline_parameters || {}),
    ...params,
  };
  // Attach dataset refs under a stable key the panel / binding layer can read later.
  if (Array.isArray(row.dataset_refs) && row.dataset_refs.length > 0) {
    (base as any).dataset_refs = row.dataset_refs;
  }
  return {
    ...base,
    id: (base as any).id || row.workflow_id || undefined,
    name: (base as any).name || row.workflow_name || "Workflow",
    domain: (base as any).domain || row.domain || undefined,
    nextflow_path: (base as any).nextflow_path || row.nextflow_path || undefined,
    inline_parameters: inline,
  };
}

export function claimUrlForToken(token: string, req?: Request): string {
  return `${appBaseUrl(req)}/run/${encodeURIComponent(token)}`;
}

export function isExpired(expiresAt: Date | string | null | undefined, now = new Date()): boolean {
  if (!expiresAt) return false;
  const d = expiresAt instanceof Date ? expiresAt : new Date(expiresAt);
  return Number.isFinite(d.getTime()) && d.getTime() < now.getTime();
}

function mintToken(): string {
  return randomBytes(32).toString("base64url");
}

export function registerRunLandingRoutes(app: Express): void {
  ensureRunLandingsTable().catch((e) =>
    console.error("[run_landings] table init failed:", e?.message ?? e),
  );

  // ─── POST /api/workflows/landings ───────────────────────────────────────────
  // Auth: create a shareable pre-filled run landing.
  app.post("/api/workflows/landings", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const parsed = validateCreateBody(req.body);
    if (!parsed.ok) return res.status(parsed.error.status).json({ error: parsed.error.error });

    try {
      await ensureRunLandingsTable();
      const id = randomUUID();
      const token = mintToken();
      const expiresAt = new Date(Date.now() + parsed.value.expiresInDays * 24 * 60 * 60 * 1000);
      const v = parsed.value;
      await pool.query(
        `INSERT INTO run_landings (
           id, token, created_by, project_id, workflow_id, nextflow_path,
           workflow_name, domain, workflow, params, dataset_refs, response_text, expires_at
         ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10::jsonb,$11::jsonb,$12,$13)`,
        [
          id,
          token,
          uid,
          v.projectId,
          v.workflowId,
          v.nextflowPath,
          v.workflowName,
          v.domain,
          v.workflow ? JSON.stringify(v.workflow) : null,
          JSON.stringify(v.params || {}),
          JSON.stringify(v.datasetRefs || []),
          v.response,
          expiresAt,
        ],
      );
      const url = claimUrlForToken(token, req);
      res.status(201).json({
        id,
        token,
        url,
        claim_path: `/run/${token}`,
        expires_at: expiresAt.toISOString(),
        workflow_name: v.workflowName,
      });
    } catch (e: any) {
      console.error("[run_landings] create failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to create run landing" });
    }
  });

  // ─── GET /api/workflows/landings/:token ─────────────────────────────────────
  // Public preview — name + expiry only (no params). Unknown → 404.
  app.get("/api/workflows/landings/:token", async (req: Request, res: Response) => {
    const { token } = req.params;
    if (!token) return res.status(404).json({ error: "not_found" });
    try {
      await ensureRunLandingsTable();
      const result = await pool.query(
        `SELECT workflow_name, domain, expires_at, created_at
           FROM run_landings WHERE token = $1`,
        [token],
      );
      if (!result.rowCount) return res.status(404).json({ error: "not_found" });
      const row = result.rows[0];
      if (isExpired(row.expires_at)) {
        // Match draft deep-link: 410 for expired when existence is known via token.
        return res.status(410).json({ error: "expired" });
      }
      res.json({
        workflow_name: row.workflow_name || "Workflow",
        domain: row.domain || null,
        expires_at: row.expires_at,
        created_at: row.created_at,
      });
    } catch (e: any) {
      console.error("[run_landings] preview failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to load landing" });
    }
  });

  // ─── POST /api/workflows/landings/:token/claim ──────────────────────────────
  // Auth: claim + return full payload for panel prefill. Reusable until expiry.
  app.post(
    "/api/workflows/landings/:token/claim",
    authenticateToken,
    async (req: Request, res: Response) => {
      const uid = userId(req);
      if (!uid) return res.status(401).json({ error: "Unauthorized" });
      const { token } = req.params;
      if (!token) return res.status(404).json({ error: "not_found" });
      try {
        await ensureRunLandingsTable();
        const result = await pool.query(
          `SELECT id, created_by, project_id, workflow_id, nextflow_path, workflow_name,
                  domain, workflow, params, dataset_refs, response_text, expires_at,
                  first_claimed_by, claim_count
             FROM run_landings WHERE token = $1`,
          [token],
        );
        if (!result.rowCount) return res.status(404).json({ error: "not_found" });
        const row = result.rows[0];
        if (isExpired(row.expires_at)) {
          return res.status(410).json({ error: "expired" });
        }

        await pool.query(
          `UPDATE run_landings SET
             claim_count = claim_count + 1,
             first_claimed_by = COALESCE(first_claimed_by, $2),
             first_claimed_at = COALESCE(first_claimed_at, NOW())
           WHERE id = $1`,
          [row.id, uid],
        );

        const panelWorkflow = buildPanelWorkflow(row);
        const inlineParameters =
          (panelWorkflow as any).inline_parameters &&
          typeof (panelWorkflow as any).inline_parameters === "object"
            ? (panelWorkflow as any).inline_parameters
            : {};

        res.json({
          id: row.id,
          project_id: row.project_id,
          workflow_id: row.workflow_id,
          nextflow_path: row.nextflow_path,
          workflow_name: row.workflow_name || (panelWorkflow as any).name,
          domain: row.domain,
          workflow: panelWorkflow,
          inlineParameters,
          dataset_refs: row.dataset_refs || [],
          params: row.params || {},
          response:
            row.response_text ||
            `Shared run ready: **${row.workflow_name || (panelWorkflow as any).name || "Workflow"}**. Review parameters, then click **Confirm & Run**.`,
          expires_at: row.expires_at,
          source: "run_landing",
        });
      } catch (e: any) {
        console.error("[run_landings] claim failed:", e?.message ?? e);
        res.status(500).json({ error: "Failed to claim run landing" });
      }
    },
  );

  // ─── DELETE /api/workflows/landings/:token ──────────────────────────────────
  // Auth: creator revoke only. Foreign → 404 (no existence leak).
  app.delete(
    "/api/workflows/landings/:token",
    authenticateToken,
    async (req: Request, res: Response) => {
      const uid = userId(req);
      if (!uid) return res.status(401).json({ error: "Unauthorized" });
      const { token } = req.params;
      if (!token) return res.status(404).json({ error: "not_found" });
      try {
        await ensureRunLandingsTable();
        const result = await pool.query(
          `DELETE FROM run_landings WHERE token = $1 AND created_by = $2 RETURNING id`,
          [token, uid],
        );
        if (!result.rowCount) return res.status(404).json({ error: "not_found" });
        res.json({ ok: true });
      } catch (e: any) {
        console.error("[run_landings] revoke failed:", e?.message ?? e);
        res.status(500).json({ error: "Failed to revoke run landing" });
      }
    },
  );
}
