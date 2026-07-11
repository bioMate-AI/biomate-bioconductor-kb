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
import { S3Client, ListObjectsV2Command, GetObjectCommand } from "@aws-sdk/client-s3";
import { registerJobKind, type ExecutorContext } from "../executor";
import { storage } from "../../storage";
import { GalaxyAPIProxy } from "../../galaxy-api-proxy";

// One shared proxy instance is fine for handler use — mirrors the
// `galaxyAPIBackend` singleton in routes.ts.
const galaxyAPIProxy = new GalaxyAPIProxy();

/**
 * A pipeline-native run (Nextflow on AWS Batch, no Galaxy invocation row).
 * Surfaced here so the executor can stream files directly from S3.
 */
interface PipelineSource {
  _pipelineSource: true;
  id: string;
  workflowName: string;
  s3Uri: string;
}

/**
 * Resolve an invocation row from any of: invocation id, galaxy invocation id,
 * or an execution-run id (which may map to an invocation via its galaxy id).
 * For runs that don't have a Galaxy invocation (the dominant case — every
 * pipeline run), fall back to a PipelineSource pointing at the S3 prefix.
 *
 * See docs/20260603_PHASE1_GAPS_NEXTFLOW_DOWNLOAD_AND_MIGRATION_RUNNER.md Gap B.
 */
async function resolveInvocation(idOrRunId: string): Promise<any | null> {
  let invocation = await storage.getInvocation(idOrRunId);
  if (invocation) return invocation;

  const byGalaxyId = await storage.getInvocationByGalaxyId(idOrRunId);
  if (byGalaxyId) return byGalaxyId;

  let executionRun: any = null;
  try {
    executionRun = await (storage as any).getExecutionRun?.(idOrRunId);
    const galaxyInvId = executionRun?.execution?.galaxyInvocationId;
    if (galaxyInvId) {
      const resolved = await storage.getInvocationByGalaxyId(galaxyInvId);
      if (resolved) return resolved;
    }
  } catch {
    /* ignore */
  }

  // Pipeline-native fallback: build a synthetic descriptor that the
  // archiver loop knows how to stream from S3.
  const s3Uri = executionRun?.execution?.nextflowOutputDir;
  if (s3Uri && typeof s3Uri === "string" && s3Uri.startsWith("s3://")) {
    return {
      _pipelineSource: true,
      id: executionRun.execution?.id ?? executionRun.id ?? idOrRunId,
      workflowName: executionRun.execution?.workflowName ?? executionRun.workflowName ?? "workflow",
      s3Uri,
    } as PipelineSource;
  }

  return null;
}

/** S3 client lazily constructed so unit tests that mock the module work. */
function makeS3Client(): S3Client {
  const accessKey = process.env.AWS_NF_ACCESS_KEY_ID;
  const secretKey = process.env.AWS_NF_SECRET_ACCESS_KEY;
  return new S3Client({
    region: "us-east-1",
    ...(accessKey && secretKey
      ? { credentials: { accessKeyId: accessKey, secretAccessKey: secretKey } }
      : {}),
  });
}

/** List every object under an `s3://bucket/prefix` URI. */
async function listS3Keys(s3: S3Client, uri: string): Promise<Array<{ bucket: string; key: string; size: number }>> {
  const m = uri.replace(/^s3:\/\//, "").split("/");
  const bucket = m[0];
  const prefix = m.slice(1).join("/").replace(/\/?$/, "/");
  const keys: Array<{ bucket: string; key: string; size: number }> = [];
  let continuationToken: string | undefined;
  do {
    const resp = await s3.send(
      new ListObjectsV2Command({
        Bucket: bucket,
        Prefix: prefix,
        MaxKeys: 1000,
        ContinuationToken: continuationToken,
      }),
    );
    for (const obj of resp.Contents ?? []) {
      if (obj.Key && !obj.Key.endsWith("/")) {
        keys.push({ bucket, key: obj.Key, size: obj.Size ?? 0 });
      }
    }
    continuationToken = resp.IsTruncated ? resp.NextContinuationToken : undefined;
  } while (continuationToken);
  return keys;
}

export interface DownloadAllZipPayload {
  invocationId: string;
  runId?: string;
}

export async function estimateSize(payload: DownloadAllZipPayload): Promise<number | undefined> {
  const ref = payload.invocationId || payload.runId;
  if (!ref) return undefined;
  let invocation = await resolveInvocation(ref).catch(() => null);
  // Fallback: if invocationId resolved to nothing, try runId directly
  if (!invocation && payload.runId && payload.runId !== ref) {
    invocation = await resolveInvocation(payload.runId).catch(() => null);
  }
  if (!invocation) return undefined;
  if (invocation._pipelineSource) {
    try {
      const keys = await listS3Keys(makeS3Client(), invocation.s3Uri);
      const total = keys.reduce((acc, k) => acc + (k.size || 0), 0);
      return total > 0 ? total : undefined;
    } catch {
      return undefined;
    }
  }
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
  let invocation = await resolveInvocation(ref);
  // Fallback: if invocationId resolved to nothing, try runId directly.
  // ADMET/Nextflow runs carry a BioMate invocationId that differs from the
  // execution_run UUID stored in runId — resolveInvocation must try both.
  if (!invocation && job.payload?.runId && job.payload.runId !== ref) {
    invocation = await resolveInvocation(job.payload.runId);
  }
  if (!invocation) {
    throw new Error(`Run not found: ${ref}`);
  }

  // Pipeline-native path: stream files from S3 directly. Storage abstraction
  // is Galaxy-only so we bypass it for these runs.
  if (invocation._pipelineSource) {
    return executePipelineSource(invocation, ctx);
  }

  const outputs = await storage.getInvocationOutputs(invocation.id);
  if (!outputs || outputs.length === 0) {
    throw new Error("No outputs found for this run");
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

async function executePipelineSource(invocation: PipelineSource, ctx: ExecutorContext): Promise<void> {
  const s3 = makeS3Client();
  const keys = await listS3Keys(s3, invocation.s3Uri);
  if (keys.length === 0) {
    throw new Error("No outputs found at " + invocation.s3Uri);
  }

  // Strip the S3 prefix so archived paths are run-relative
  // (e.g. "02_motion_correction/batch_0000/motion_report.json").
  const prefixForStrip = invocation.s3Uri.replace(/^s3:\/\/[^/]+\//, "").replace(/\/?$/, "/");

  const zipName = `${invocation.workflowName || "workflow"}_outputs_${String(invocation.id).slice(0, 8)}.zip`;
  const sink = ctx.openArtifact(zipName, "application/zip");

  const archive = archiver("zip", { zlib: { level: 9 } });
  const piped = new Promise<void>((resolve, reject) => {
    archive.on("error", reject);
    archive.on("end", () => resolve());
    archive.pipe(sink.stream as any);
  });

  const total = keys.length;
  let done = 0;
  for (const { bucket, key } of keys) {
    if (ctx.checkCancelled()) {
      try { (archive as any).abort?.(); } catch { /* ignore */ }
      try {
        await new Promise<void>((resolve) => {
          (sink.stream as any).end(() => resolve());
        });
      } catch { /* ignore */ }
      return;
    }
    try {
      const resp = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
      const relName = key.startsWith(prefixForStrip) ? key.slice(prefixForStrip.length) : key;
      archive.append(resp.Body as any, { name: relName });
    } catch (err) {
      console.error(`[jobs/download_all_zip] S3 fetch failed for ${key}:`, err);
      // Continue on per-file errors — partial bundles are better than none.
    }
    done += 1;
    if (done % 5 === 0 || done === total) {
      await ctx.setProgress(Math.round((100 * done) / total));
    }
  }

  await archive.finalize();
  await piped;
  await ctx.closeArtifact();
  await ctx.setProgress(100);
}

registerJobKind("download_all_zip", { estimateSize, execute });
