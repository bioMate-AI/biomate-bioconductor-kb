/**
 * Phase 2 handler — methods-report caching via the async job system.
 *
 * The legacy endpoint at GET /api/invocations/:id/methods-report does ~600 LOC
 * of work and ends with a Claude Sonnet synthesis call — cold-path latency is
 * 20–60s. The MethodsTab of AfterRunReport calls it on mount; every open
 * pays the full cost.
 *
 * This handler wraps the existing endpoint via loopback so its bytes are
 * byte-for-byte identical to what the legacy path produces — no risk of
 * divergent output. The job system gives us:
 *
 *   - Dedup: parallel clicks coalesce on the same in-flight job.
 *   - 24h artifact TTL: subsequent opens within the window hit cached bytes.
 *   - Cancellation + visible progress.
 *
 * The endpoint requires no auth (already open in routes.ts) so the loopback
 * call carries no token.
 *
 * Payload: { invocationId: string, format?: 'txt' | 'docx' }
 *   Default format is 'txt'. The format becomes part of the dedup key so
 *   txt and docx requests don't collide.
 */

import { registerJobKind, type ExecutorContext } from "../executor";

const LOOPBACK_HOST = process.env.LOOPBACK_HOST ?? "127.0.0.1";
const LOOPBACK_PORT = process.env.PORT ?? "3000";

export interface MethodsReportPayload {
  invocationId: string;
  format?: "txt" | "docx";
}

export async function execute(
  job: { id: string; payload: MethodsReportPayload; userId: string },
  ctx: ExecutorContext,
): Promise<void> {
  const invocationId = job.payload?.invocationId;
  if (!invocationId) {
    throw new Error("payload.invocationId is required");
  }
  const format = job.payload?.format === "docx" ? "docx" : "txt";

  await ctx.setProgress(5);

  // Loopback to the existing endpoint. No auth: it's a public route by design
  // (download-from-UI use case). 5-min hard cap protects the executor slot
  // from a runaway Claude call.
  const qs = format === "docx" ? "?format=docx" : "";
  const url = `http://${LOOPBACK_HOST}:${LOOPBACK_PORT}/api/invocations/${encodeURIComponent(
    invocationId,
  )}/methods-report${qs}`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5 * 60 * 1000);
  const cancelCheck = setInterval(() => {
    if (ctx.checkCancelled()) controller.abort();
  }, 1000);

  let response: Response;
  try {
    response = await fetch(url, { signal: controller.signal });
  } finally {
    clearTimeout(timer);
    clearInterval(cancelCheck);
  }

  if (ctx.checkCancelled()) {
    // Executor will tear down the artifact path.
    return;
  }

  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    throw new Error(
      `methods-report endpoint returned ${response.status}: ${detail.slice(0, 300)}`,
    );
  }

  await ctx.setProgress(80);

  const contentType =
    response.headers.get("content-type") ??
    (format === "docx"
      ? "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      : "text/plain; charset=utf-8");

  // Preserve the upstream filename so the browser's "Save as" name matches
  // what the legacy endpoint produced.
  const disposition = response.headers.get("content-disposition") ?? "";
  const filenameMatch = /filename="?([^"]+)"?/.exec(disposition);
  const ext = format === "docx" ? "docx" : "txt";
  const filename =
    filenameMatch?.[1] ?? `run_report_${String(invocationId).slice(0, 8)}.${ext}`;

  const buffer = Buffer.from(await response.arrayBuffer());
  if (buffer.length === 0) {
    throw new Error("methods-report endpoint returned empty body");
  }

  const sink = ctx.openArtifact(filename, contentType);
  sink.stream.write(buffer);
  await ctx.closeArtifact();
  await ctx.setProgress(100);
}

registerJobKind("methods_report", { execute });
