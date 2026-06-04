/**
 * /api/jobs router — async job-queue subsystem (Phase 0).
 *
 * See docs/20260602_ASYNC_JOB_QUEUE_DESIGN.md §7 for the API contract.
 *
 * Four endpoints:
 *   POST   /api/jobs              create-or-coalesce
 *   GET    /api/jobs/:id          poll status
 *   GET    /api/jobs/:id/artifact stream finished artifact
 *   DELETE /api/jobs/:id          cancel (or expire-if-ready)
 */

import type { Express, Request, Response } from "express";
import express from "express";
import { sql } from "drizzle-orm";
import { db } from "../db";
import { authenticateToken } from "../auth-middleware";
import {
  dispatch,
  getHandler,
  knownKinds,
  recoverOrphanRunningJobs,
  signalCancel,
} from "./executor";
import { getArtifactStore } from "./artifact-store";

const PER_USER_ACTIVE_CAP = 3;

function requireUserId(req: Request, res: Response): string | null {
  const uid = (req as any).user?.id;
  if (!uid) {
    res.status(401).json({ error: "authentication_required" });
    return null;
  }
  return String(uid);
}

interface JobRow {
  id: string;
  user_id: string;
  kind: string;
  payload: any;
  dedup_key: string;
  state: string;
  progress: number;
  eta_seconds: number | null;
  artifact_uri: string | null;
  artifact_bytes: number | string | null;
  error: string | null;
  created_at: Date;
  started_at: Date | null;
  ready_at: Date | null;
  expires_at: Date | null;
  cancelled_at: Date | null;
}

function rowToApi(row: JobRow) {
  return {
    jobId: row.id,
    kind: row.kind,
    state: row.state,
    progress: row.progress,
    etaSeconds: row.eta_seconds,
    artifactBytes: row.artifact_bytes == null ? null : Number(row.artifact_bytes),
    createdAt: row.created_at,
    readyAt: row.ready_at,
    expiresAt: row.expires_at,
    error: row.error,
    statusUrl: `/api/jobs/${row.id}`,
    artifactUrl: `/api/jobs/${row.id}/artifact`,
  };
}

async function fetchRow(jobId: string): Promise<JobRow | null> {
  const result: any = await db.execute(sql`SELECT * FROM download_jobs WHERE id = ${jobId}`);
  const rows = result.rows ?? result;
  return (rows[0] as JobRow | undefined) ?? null;
}

export function registerJobsRouter(app: Express): void {
  // Run the recovery scan once when the router is wired up. The router is
  // registered exactly once in routes.ts, so this is the natural attach point.
  recoverOrphanRunningJobs().catch((err) => {
    console.error("[jobs] recovery scan failed at startup:", err);
  });

  // ---------------------------------------------------------------------
  // POST /api/jobs — create or coalesce
  // ---------------------------------------------------------------------
  app.post("/api/jobs", authenticateToken, express.json(), async (req, res) => {
    const userId = requireUserId(req, res);
    if (!userId) return;

    const { kind, payload, dedupKey } = req.body ?? {};
    if (typeof kind !== "string" || !kind) {
      res.status(400).json({ error: "invalid_kind" });
      return;
    }
    if (!getHandler(kind)) {
      res.status(400).json({ error: "unknown_kind", knownKinds: knownKinds() });
      return;
    }
    if (payload == null || typeof payload !== "object") {
      res.status(400).json({ error: "invalid_payload" });
      return;
    }

    // Default dedup key per §6.
    const resolvedDedupKey = typeof dedupKey === "string" && dedupKey
      ? dedupKey
      : `${kind}:${(payload as any).invocationId ?? (payload as any).runId ?? JSON.stringify(payload)}`;

    // 1) Dedup lookup — coalesce against active/ready rows.
    const existing: any = await db.execute(sql`
      SELECT * FROM download_jobs
      WHERE dedup_key = ${resolvedDedupKey}
        AND state IN ('queued', 'running', 'ready')
        AND (expires_at IS NULL OR expires_at > now())
      ORDER BY created_at DESC
      LIMIT 1
    `);
    const existingRow: JobRow | undefined = (existing.rows ?? existing)[0];
    if (existingRow) {
      // Auth scope check: only return rows belonging to the requesting user.
      if (existingRow.user_id !== userId) {
        res.status(403).json({ error: "forbidden" });
        return;
      }
      res.status(200).json(rowToApi(existingRow));
      return;
    }

    // 2) Per-user concurrency cap.
    const activeCount: any = await db.execute(sql`
      SELECT COUNT(*)::int AS n FROM download_jobs
      WHERE user_id = ${userId} AND state IN ('queued', 'running')
    `);
    const n = Number((activeCount.rows ?? activeCount)[0]?.n ?? 0);
    if (n >= PER_USER_ACTIVE_CAP) {
      res.status(429).set("Retry-After", "60").json({
        error: "per_user_concurrency_cap",
        cap: PER_USER_ACTIVE_CAP,
        active: n,
      });
      return;
    }

    // 3) Insert new row + dispatch.
    const inserted: any = await db.execute(sql`
      INSERT INTO download_jobs (user_id, kind, payload, dedup_key, state)
      VALUES (${userId}, ${kind}, ${JSON.stringify(payload)}::jsonb, ${resolvedDedupKey}, 'queued')
      RETURNING *
    `);
    const row: JobRow = (inserted.rows ?? inserted)[0];
    dispatch(row.id);
    res.status(201).json(rowToApi(row));
  });

  // ---------------------------------------------------------------------
  // GET /api/jobs/:id — poll status
  // ---------------------------------------------------------------------
  app.get("/api/jobs/:id", authenticateToken, async (req, res) => {
    const userId = requireUserId(req, res);
    if (!userId) return;
    const row = await fetchRow(req.params.id);
    if (!row) {
      res.status(404).json({ error: "not_found" });
      return;
    }
    if (row.user_id !== userId) {
      res.status(403).json({ error: "forbidden" });
      return;
    }
    res.json(rowToApi(row));
  });

  // ---------------------------------------------------------------------
  // GET /api/jobs/:id/artifact — stream finished artifact
  // ---------------------------------------------------------------------
  app.get("/api/jobs/:id/artifact", authenticateToken, async (req, res) => {
    const userId = requireUserId(req, res);
    if (!userId) return;
    const row = await fetchRow(req.params.id);
    if (!row) {
      res.status(404).json({ error: "not_found" });
      return;
    }
    if (row.user_id !== userId) {
      res.status(403).json({ error: "forbidden" });
      return;
    }
    if (row.state !== "ready") {
      res.status(409).json({ error: "not_ready", state: row.state });
      return;
    }
    const store = getArtifactStore();
    const result = store.read(row.id);
    if (!result) {
      res.status(410).json({ error: "artifact_gone" });
      return;
    }
    if ("redirect" in result) {
      res.redirect(302, result.redirect);
      return;
    }
    res.setHeader("Content-Type", result.contentType);
    res.setHeader("Content-Length", String(result.bytes));
    // Sanitize filename: forbid quote/CR/LF (header injection) and fall back
    // to the job id if the handler didn't supply one.
    const safeFilename = (result.filename ?? row.id).replace(/["\r\n]/g, "_");
    res.setHeader("Content-Disposition", `attachment; filename="${safeFilename}"`);
    result.stream.pipe(res);
  });

  // ---------------------------------------------------------------------
  // DELETE /api/jobs/:id — cancel (or expire-if-ready)
  // ---------------------------------------------------------------------
  app.delete("/api/jobs/:id", authenticateToken, async (req, res) => {
    const userId = requireUserId(req, res);
    if (!userId) return;
    const row = await fetchRow(req.params.id);
    if (!row) {
      res.status(404).json({ error: "not_found" });
      return;
    }
    if (row.user_id !== userId) {
      res.status(403).json({ error: "forbidden" });
      return;
    }

    if (row.state === "queued" || row.state === "running") {
      signalCancel(row.id);
      await db.execute(sql`
        UPDATE download_jobs
        SET state = 'cancelled', cancelled_at = now()
        WHERE id = ${row.id} AND state IN ('queued', 'running')
      `);
      // Best-effort artifact cleanup; executor will also try.
      try { getArtifactStore().delete(row.id); } catch { /* ignore */ }
      res.status(200).json({ jobId: row.id, state: "cancelled" });
      return;
    }

    if (row.state === "ready") {
      try { getArtifactStore().delete(row.id); } catch { /* ignore */ }
      await db.execute(sql`
        UPDATE download_jobs
        SET state = 'expired', artifact_uri = NULL
        WHERE id = ${row.id}
      `);
      res.status(200).json({ jobId: row.id, state: "expired" });
      return;
    }

    res.status(409).json({ error: "terminal_state", state: row.state });
  });
}
