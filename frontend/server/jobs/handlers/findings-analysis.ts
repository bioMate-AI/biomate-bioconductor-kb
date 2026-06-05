/**
 * Phase 4 handler — findings_analysis caching via the async job system.
 *
 * The legacy endpoint at GET /api/workflows/runs/:id/findings returns one of:
 *   { status: 'ready', summary, key_results, ... }   ← cached sidecar present
 *   { status: 'pending', message: 'Analysis in progress…' }
 *   { error: '...' }
 *
 * Frontend used to poll this every 5s for up to 60s — bespoke logic, no
 * cancel button, gives up silently if Claude takes >60s. This handler
 * server-side-polls the endpoint until ready (5-minute cap), then writes
 * the final JSON as the artifact. Subsequent opens within the 24h job TTL
 * hit cached bytes.
 *
 * Payload: { runId: string }
 */

import { registerJobKind, type ExecutorContext } from "../executor";

const LOOPBACK_HOST = process.env.LOOPBACK_HOST ?? "127.0.0.1";
const LOOPBACK_PORT = process.env.PORT ?? "3000";
const POLL_INTERVAL_MS = 3000;
const MAX_DURATION_MS = 5 * 60 * 1000;

export interface FindingsAnalysisPayload {
  runId: string;
}

interface FindingsResponse {
  status?: string;
  error?: string;
  summary?: string;
  key_results?: unknown[];
  caveats?: unknown[];
  next_steps?: unknown[];
  reportMd?: string;
  reportUrl?: string;
  [k: string]: unknown;
}

export async function execute(
  job: { id: string; payload: FindingsAnalysisPayload; userId: string },
  ctx: ExecutorContext,
): Promise<void> {
  const runId = job.payload?.runId;
  if (!runId) {
    throw new Error("payload.runId is required");
  }

  const url = `http://${LOOPBACK_HOST}:${LOOPBACK_PORT}/api/workflows/runs/${encodeURIComponent(
    runId,
  )}/findings`;

  const startedAt = Date.now();
  let lastPayload: FindingsResponse | null = null;

  for (;;) {
    if (ctx.checkCancelled()) return;
    const elapsed = Date.now() - startedAt;
    if (elapsed > MAX_DURATION_MS) {
      throw new Error("Findings analysis timed out after 5 minutes");
    }

    const resp = await fetch(url, { signal: AbortSignal.timeout(30_000) }).catch((e) => {
      throw new Error(`findings endpoint unreachable: ${String(e).slice(0, 200)}`);
    });

    if (resp.status === 404) {
      throw new Error(`Run not found: ${runId}`);
    }
    if (!resp.ok) {
      const text = await resp.text().catch(() => "");
      throw new Error(`findings endpoint returned ${resp.status}: ${text.slice(0, 200)}`);
    }

    const json = (await resp.json().catch(() => ({}))) as FindingsResponse;
    lastPayload = json;

    if (json.status === "ready") {
      break;
    }
    if (json.status !== "pending") {
      // Unknown state — bail rather than poll forever.
      throw new Error(`Unexpected findings status: ${json.status ?? "(missing)"}`);
    }

    // Progress: linear 5→90% over the 5-min window so the UI feels alive
    // even though the underlying analysis doesn't expose intermediate state.
    const pct = Math.min(90, 5 + Math.round((elapsed / MAX_DURATION_MS) * 85));
    await ctx.setProgress(pct);

    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
  }

  if (!lastPayload) {
    throw new Error("findings analysis produced no payload");
  }

  await ctx.setProgress(95);

  const filename = `findings_${String(runId).slice(0, 8)}.json`;
  const sink = ctx.openArtifact(filename, "application/json; charset=utf-8");
  sink.stream.write(Buffer.from(JSON.stringify(lastPayload), "utf-8"));
  await ctx.closeArtifact();
  await ctx.setProgress(100);
}

registerJobKind("findings_analysis", { execute });
