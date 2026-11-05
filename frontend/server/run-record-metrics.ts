// Run-record population helpers — pure, dependency-light logic extracted from routes.ts
// so it can be unit-tested without booting the whole server (routes.ts transitively
// imports the OpenAI SDK + browser-coupled modules). These functions never throw and
// never touch the network; the wiring/persistence lives in routes.ts.
import type { ExecutionRun, ExecutionMetrics } from "../shared/schema";

/**
 * Derive a `run.metrics` patch from a COMPLETED run's data that is already in hand:
 * the output-file list (outputs.fileCount / totalSizeBytes / byType / bySize) and the
 * wall-clock runtime (runtime.totalSeconds).
 *
 * Why this exists: `storage.ts` initializes `metrics` to an all-zero block and — until
 * this helper was wired in — NOTHING ever updated it with real values, so every
 * completed run reported zero outputs and zero runtime even though it produced real
 * files over real wall-clock time. Usage/billing attribution reads those zeros.
 *
 * Best-effort boundary — `resources.*` (peakMemoryGB / avgCpuPercent / diskUsedGB) are
 * intentionally NOT populated here: they require the Nextflow per-task trace
 * (`%cpu` / `peak_rss` / `realtime` columns), and the Galaxy status payload surfaced to
 * the Node side (`getNextflowStatus` → `/api/nextflow/status`) does not carry those
 * aggregates (the backend trace parser reads only task name/status). Fabricating them
 * would corrupt billing, so they stay at their zero init. If per-task trace is ever
 * plumbed through to `nextflowStatus`, aggregate it into `resources` at this same point.
 *
 * Returns `null` when nothing is derivable (no files AND no runtime), so callers skip
 * the write entirely.
 */
export function deriveRunMetricsPatch(
  run: Pick<ExecutionRun, "execution" | "metrics">,
  nextflowStatus: any,
): Partial<ExecutionMetrics> | null {
  const patch: Partial<ExecutionMetrics> = {};

  // ── outputs — from the run's output-file list ────────────────────────────────
  // s3_output_files (AWS Batch) is the primary source; output_files (local) the
  // fallback. Each entry carries name/filename + size/s3_uri (see /output_files
  // consumers). These are trivially derivable and must never be zero for a run that
  // has outputs.
  const files: any[] =
    Array.isArray(nextflowStatus?.s3_output_files) && nextflowStatus.s3_output_files.length
      ? nextflowStatus.s3_output_files
      : (Array.isArray(nextflowStatus?.output_files) ? nextflowStatus.output_files : []);
  if (files.length > 0) {
    const byType: Record<string, number> = {}; // extension -> count
    const bySize: Record<string, number> = {}; // extension -> total bytes
    let totalSizeBytes = 0;
    for (const f of files) {
      const name = String(f?.name ?? f?.filename ?? f?.s3_uri ?? f?.path ?? "");
      const rawSize = Number(f?.size ?? f?.sizeBytes ?? f?.bytes ?? 0);
      const size = Number.isFinite(rawSize) && rawSize > 0 ? rawSize : 0;
      totalSizeBytes += size;
      const base = name.split("/").pop() || name;
      const dot = base.lastIndexOf(".");
      const ext = dot > 0 && dot < base.length - 1 ? base.slice(dot + 1).toLowerCase() : "other";
      byType[ext] = (byType[ext] || 0) + 1;
      bySize[ext] = (bySize[ext] || 0) + size;
    }
    patch.outputs = { fileCount: files.length, totalSizeBytes, byType, bySize };
  }

  // ── runtime.totalSeconds — Nextflow's own duration, else wall-clock delta ────
  let totalSeconds = 0;
  const durationS = Number(nextflowStatus?.duration_s);
  if (Number.isFinite(durationS) && durationS > 0) {
    totalSeconds = Math.round(durationS);
  } else {
    const started = run.execution?.startedAt ? new Date(run.execution.startedAt).getTime() : NaN;
    const completed = run.execution?.completedAt ? new Date(run.execution.completedAt).getTime() : NaN;
    if (Number.isFinite(started) && Number.isFinite(completed) && completed >= started) {
      totalSeconds = Math.round((completed - started) / 1000);
    }
  }
  if (totalSeconds > 0) {
    patch.runtime = {
      totalSeconds,
      perStepSeconds: run.metrics?.runtime?.perStepSeconds ?? {},
    };
  }

  return patch.outputs || patch.runtime ? patch : null;
}

/**
 * Fix #5b: resolve a run record's `inline_findings` array so it MIRRORS the run's
 * `findings_data.json` sidecar — the same structured `key_results` the UI Findings tab
 * renders (see GET /api/workflows/runs/:id/findings). Historically this field was only
 * sourced from `nextflowStatus.{findings,ai_findings,key_results}`, which nothing
 * populates, so it was always []. Resolution cascade (first non-empty wins):
 *   1. nextflowStatus-embedded findings (legacy source),
 *   2. the in-memory findings cache that backs the Findings tab for AWS Batch runs
 *      (passed in as `cacheGet` to avoid coupling to the route-closure Map),
 *   3. the local `findings_data.json` sidecar on disk (same path the /findings route reads).
 * Best-effort: never throws; `[]` is the fallback. (S3-only sidecars for AWS runs that
 * were never analyzed stay [] — reading S3 synchronously per get_run is too heavy; the
 * cache path covers AWS runs once their findings have been generated.)
 */
export async function resolveInlineFindings(
  run: Pick<ExecutionRun, "id" | "execution">,
  nextflowStatus: any,
  cacheGet?: (id: string) => Record<string, any> | undefined,
): Promise<any[]> {
  const ns = nextflowStatus || {};
  let findings: any[] =
    (Array.isArray(ns.findings) && ns.findings) ||
    (Array.isArray(ns.ai_findings) && ns.ai_findings) ||
    (Array.isArray(ns.key_results) && ns.key_results) ||
    [];
  if (findings.length === 0 && cacheGet) {
    try {
      const cached = cacheGet(run.id);
      if (cached && !cached._generating && Array.isArray(cached.key_results)) {
        findings = cached.key_results;
      }
    } catch { /* cache miss — fall through */ }
  }
  if (findings.length === 0) {
    try {
      const { readFile } = await import("fs/promises");
      const nfRunId = run.execution?.nextflowRunId || run.id;
      const sidecar = `/tmp/nextflow_runs/${nfRunId}/output/findings_data.json`;
      const parsed = JSON.parse(await readFile(sidecar, "utf8"));
      if (Array.isArray(parsed?.key_results)) findings = parsed.key_results;
    } catch { /* no local sidecar (e.g. AWS-only run not yet analyzed) — [] fallback */ }
  }
  return findings;
}
