/**
 * In-process executor for the async job-queue subsystem (Phase 0).
 *
 * See docs/20260602_ASYNC_JOB_QUEUE_DESIGN.md §8.
 *
 * The executor runs jobs in the same Node process as the API. Phase 0 keeps
 * everything as simple as possible:
 *   - one handler per `kind`
 *   - setImmediate dispatch, no worker dyno, no IPC
 *   - progress writes batched every 2s
 *   - on server boot, a recovery scan marks orphan `running` rows as `failed`
 *
 * Phases 1–4 register real handlers for download_all_zip / methods_report /
 * reproducibility_bundle / findings_analysis. Phase 0 ships only the
 * `download_all_zip_v0_stub` handler so the end-to-end path is testable.
 */

import { sql } from "drizzle-orm";
import { db } from "../db";
import { getArtifactStore, type ArtifactStore, type ArtifactWriteHandle } from "./artifact-store";

const PROGRESS_FLUSH_MS = 2000;
const ARTIFACT_TTL_MS = 24 * 60 * 60 * 1000; // 24h

export interface ExecutorContext {
  jobId: string;
  setProgress(p: number, etaSeconds?: number): Promise<void>;
  checkCancelled(): boolean;
  openArtifact(name: string, contentType: string): ArtifactWriteHandle;
  closeArtifact(): Promise<void>;
}

export interface JobHandler {
  estimateSize?: (payload: any) => Promise<number | undefined>;
  execute: (job: { id: string; payload: any; userId: string }, ctx: ExecutorContext) => Promise<void>;
}

const handlers = new Map<string, JobHandler>();

export function registerJobKind(kind: string, handler: JobHandler): void {
  handlers.set(kind, handler);
}

export function getHandler(kind: string): JobHandler | undefined {
  return handlers.get(kind);
}

export function knownKinds(): string[] {
  return Array.from(handlers.keys());
}

// In-process cancellation flags. Lost on restart, which is fine: cancelled
// jobs that didn't observe the flag will be reaped by the recovery scan.
const cancellationFlags = new Map<string, boolean>();

export function signalCancel(jobId: string): void {
  cancellationFlags.set(jobId, true);
}

/**
 * Kick off execution of a queued job. Returns immediately; the work happens
 * in a setImmediate task.
 */
export function dispatch(jobId: string): void {
  setImmediate(() => {
    runJob(jobId).catch((err) => {
      console.error(`[jobs] uncaught executor error for ${jobId}:`, err);
    });
  });
}

async function runJob(jobId: string): Promise<void> {
  const rows = await db.execute(sql`SELECT id, user_id, kind, payload, state FROM download_jobs WHERE id = ${jobId}`);
  const row: any = (rows as any).rows?.[0] ?? (rows as any)[0];
  if (!row) {
    console.warn(`[jobs] runJob: row ${jobId} not found`);
    return;
  }
  if (row.state !== "queued") {
    // Already running, cancelled, or terminal — nothing to do.
    return;
  }
  const handler = handlers.get(row.kind);
  if (!handler) {
    await db.execute(sql`
      UPDATE download_jobs
      SET state = 'failed', error = ${"No handler registered for kind: " + row.kind}
      WHERE id = ${jobId}
    `);
    return;
  }

  await db.execute(sql`UPDATE download_jobs SET state = 'running', started_at = now() WHERE id = ${jobId}`);

  const store: ArtifactStore = getArtifactStore();
  // Cast `null` so TS treats this as the full union and doesn't narrow to
  // literal `null` after the closure assignments (which it can't track).
  let writeHandle = null as ArtifactWriteHandle | null;
  let lastFlushAt = 0;
  let pendingProgress: { p: number; eta?: number } | null = null;

  const flushProgress = async (force = false) => {
    if (!pendingProgress) return;
    const now = Date.now();
    if (!force && now - lastFlushAt < PROGRESS_FLUSH_MS) return;
    const { p, eta } = pendingProgress;
    pendingProgress = null;
    lastFlushAt = now;
    try {
      await db.execute(sql`
        UPDATE download_jobs
        SET progress = ${p}, eta_seconds = ${eta ?? null}
        WHERE id = ${jobId}
      `);
    } catch (err) {
      console.warn(`[jobs] progress flush failed for ${jobId}:`, err);
    }
  };

  const ctx: ExecutorContext = {
    jobId,
    setProgress: async (p, etaSeconds) => {
      pendingProgress = { p: Math.max(0, Math.min(100, Math.round(p))), eta: etaSeconds };
      await flushProgress(false);
    },
    checkCancelled: () => cancellationFlags.get(jobId) === true,
    openArtifact: (_name, contentType) => {
      writeHandle = store.open(jobId, contentType);
      return writeHandle;
    },
    closeArtifact: async () => {
      if (!writeHandle) return;
      const handle = writeHandle;
      await new Promise<void>((resolve, reject) => {
        handle.stream.end((err?: Error | null) => (err ? reject(err) : resolve()));
        handle.stream.on("error", reject);
      });
    },
  };

  try {
    await handler.execute({ id: row.id, payload: row.payload, userId: row.user_id }, ctx);
    await flushProgress(true);

    if (ctx.checkCancelled()) {
      store.delete(jobId);
      await db.execute(sql`
        UPDATE download_jobs
        SET state = 'cancelled', cancelled_at = now()
        WHERE id = ${jobId} AND state = 'running'
      `);
      cancellationFlags.delete(jobId);
      return;
    }

    const bytes = writeHandle ? writeHandle.bytesWritten() : 0;
    const uri = writeHandle ? writeHandle.uri : null;
    const expiresAtMs = Date.now() + ARTIFACT_TTL_MS;
    await db.execute(sql`
      UPDATE download_jobs
      SET state = 'ready',
          progress = 100,
          ready_at = now(),
          expires_at = ${new Date(expiresAtMs).toISOString()},
          artifact_uri = ${uri},
          artifact_bytes = ${bytes}
      WHERE id = ${jobId}
    `);
  } catch (err: any) {
    console.error(`[jobs] executor failed for ${jobId}:`, err);
    if (writeHandle) {
      try {
        (writeHandle.stream as any).destroy?.();
      } catch {
        /* ignore */
      }
      store.delete(jobId);
    }
    const message = String(err?.message || err);
    await db.execute(sql`
      UPDATE download_jobs
      SET state = 'failed', error = ${message}
      WHERE id = ${jobId}
    `);
  } finally {
    cancellationFlags.delete(jobId);
  }
}

/**
 * Recovery scan — call once at server startup.
 *
 * Marks any rows that were `running` before this process booted as `failed`.
 * Idempotent: safe to call multiple times. Returns the number of rows reaped.
 */
export async function recoverOrphanRunningJobs(): Promise<number> {
  const result: any = await db.execute(sql`
    UPDATE download_jobs
    SET state = 'failed',
        error = 'Server restarted during execution'
    WHERE state = 'running'
    RETURNING id
  `);
  const rows = result.rows ?? result;
  const count = Array.isArray(rows) ? rows.length : 0;
  if (count > 0) {
    console.log(`[jobs] recovery scan reaped ${count} orphan running job(s)`);
  }
  return count;
}

// ---------------------------------------------------------------------------
// Phase 0 stub handler — proves the end-to-end path without real archiver
// logic. Phases 1–4 add the real handlers.
// ---------------------------------------------------------------------------
registerJobKind("download_all_zip_v0_stub", {
  execute: async (job, ctx) => {
    const handle = ctx.openArtifact(`${job.id}.bin`, "application/octet-stream");
    // 100-byte placeholder.
    handle.stream.write(Buffer.alloc(100, 0x42));
    await ctx.setProgress(50);
    await ctx.closeArtifact();
    await ctx.setProgress(100);
  },
});
