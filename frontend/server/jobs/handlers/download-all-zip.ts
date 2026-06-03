/**
 * Phase 1 handler — async migration of GET /api/invocations/:id/download-all.
 *
 * Reuses the same archiver + galaxy/local fetch logic as the legacy sync
 * endpoint in routes.ts (~line 7546), but executes through the async job
 * subsystem so the HTTP connection is no longer held for the lifetime of
 * the ZIP stream.
 *
 * Payload: { invocationId: string, runId?: string }
 *
 * See docs/20260602_ASYNC_JOB_QUEUE_DESIGN.md §11.
 */

import archiver from "archiver";
import { createReadStream } from "fs";
import { registerJobKind, type ExecutorContext } from "../executor";
import { storage } from "../../storage";
import { GalaxyAPIProxy } from "../../galaxy-api-proxy";

// One shared proxy instance is fine for handler use — mirrors the
// `galaxyAPIBackend` singleton in routes.ts.
const galaxyAPIProxy = new GalaxyAPIProxy();

/**
 * Resolve an invocation row from any of: invocation id, galaxy invocation id,
 * or an execution-run id (which may map to an invocation via its galaxy id).
 * Mirrors the resolution chain in routes.ts /api/invocations/:id/download-all.
 */
async function resolveInvocation(idOrRunId: string): Promise<any | null> {
  let invocation = await storage.getInvocation(idOrRunId);
  if (invocation) return invocation;

  const byGalaxyId = await storage.getInvocationByGalaxyId(idOrRunId);
  if (byGalaxyId) return byGalaxyId;

  try {
    const executionRun = await (storage as any).getExecutionRun?.(idOrRunId);
    const galaxyInvId = executionRun?.execution?.galaxyInvocationId;
    if (galaxyInvId) {
      const resolved = await storage.getInvocationByGalaxyId(galaxyInvId);
      if (resolved) return resolved;
    }
  } catch {
    /* ignore */
  }
  return null;
}

export interface DownloadAllZipPayload {
  invocationId: string;
  runId?: string;
}

export async function estimateSize(payload: DownloadAllZipPayload): Promise<number | undefined> {
  const ref = payload.invocationId || payload.runId;
  if (!ref) return undefined;
  const invocation = await resolveInvocation(ref).catch(() => null);
  if (!invocation) return undefined;
  const outputs = await storage.getInvocationOutputs(invocation.id).catch(() => []);
  if (!outputs || outputs.length === 0) return undefined;
  let total = 0;
  for (const o of outputs as any[]) {
    if (typeof o.size === "number" && o.size > 0) total += o.size;
  }
  return total > 0 ? total : undefined;
}

export async function execute(
  job: { id: string; payload: DownloadAllZipPayload; userId: string },
  ctx: ExecutorContext,
): Promise<void> {
  const ref = job.payload?.invocationId || job.payload?.runId;
  if (!ref) {
    throw new Error("payload.invocationId is required");
  }
  const invocation = await resolveInvocation(ref);
  if (!invocation) {
    throw new Error(`Invocation not found: ${ref}`);
  }

  const outputs = await storage.getInvocationOutputs(invocation.id);
  if (!outputs || outputs.length === 0) {
    throw new Error("No outputs found for this invocation");
  }

  const zipName = `${invocation.workflowName || "workflow"}_outputs_${String(invocation.id).slice(0, 8)}.zip`;
  const sink = ctx.openArtifact(zipName, "application/zip");

  const archive = archiver("zip", { zlib: { level: 9 } });
  // Promise that resolves when piping completes or rejects on archive error.
  const piped = new Promise<void>((resolve, reject) => {
    archive.on("error", reject);
    archive.on("end", () => resolve());
    archive.pipe(sink.stream as any);
  });

  const total = outputs.length;
  let done = 0;

  for (const output of outputs as any[]) {
    if (ctx.checkCancelled()) {
      try { (archive as any).abort?.(); } catch { /* ignore */ }
      // Close the underlying write stream so the executor's store.delete()
      // call can fully reclaim the artifact path (otherwise the still-open
      // fd races with unlink and recreates the file).
      try {
        await new Promise<void>((resolve) => {
          (sink.stream as any).end(() => resolve());
        });
      } catch { /* ignore */ }
      return;
    }
    try {
      const localPath = String(output?.metadata?.localPath || "");
      const fileStream = output.galaxyDatasetId
        ? await galaxyAPIProxy.downloadDataset(output.galaxyDatasetId)
        : localPath
          ? createReadStream(localPath)
          : null;
      if (!fileStream) {
        done += 1;
        continue;
      }
      const filename = output.extension ? `${output.name}.${output.extension}` : output.name;
      archive.append(fileStream as any, { name: filename });
    } catch (err) {
      console.error(`[jobs/download_all_zip] failed to add ${output?.name}:`, err);
      // Continue with remaining files — mirrors legacy endpoint behavior.
    }
    done += 1;
    await ctx.setProgress(Math.round((100 * done) / total));
  }

  await archive.finalize();
  await piped;
  await ctx.closeArtifact();
  await ctx.setProgress(100);
}

registerJobKind("download_all_zip", { estimateSize, execute });
