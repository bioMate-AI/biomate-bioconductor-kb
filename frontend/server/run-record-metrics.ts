// Run-record population helpers — pure, dependency-light logic extracted from routes.ts
// so it can be unit-tested without booting the whole server (routes.ts transitively
// imports the OpenAI SDK + browser-coupled modules). These functions never throw and
// never touch the network; the wiring/persistence lives in routes.ts.
import type { ExecutionRun, ExecutionMetrics, StepExecution, StepOutput } from "../shared/schema";

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

// Extensions the UI can render inline — used to tag a step output's
// `isVisualizable`. Mirrors the extension class the status endpoint's
// artifact-readiness check and StepOutputPreview already treat as viewable.
const VISUALIZABLE_EXT = new Set([
  "html", "htm", "png", "jpg", "jpeg", "svg", "pdf", "gif", "webp", "tif", "tiff",
  "csv", "tsv", "json", "txt", "bed", "vcf", "fasta", "fa", "nwk",
]);

// Run-level terminal states this finalizer acts on (never a live/paused run).
const TERMINAL_RUN_STATUSES = new Set(["completed", "failed", "cancelled"]);

function extensionOf(name: string): string {
  const base = name.split("/").pop() || name;
  const dot = base.lastIndexOf(".");
  return dot > 0 && dot < base.length - 1 ? base.slice(dot + 1).toLowerCase() : "";
}

// Normalize a name for cross-source matching (Nextflow process names vs. the
// run record's stepName/toolName/toolId/stepId): lowercase, drop every
// non-alphanumeric char so `FASTQC`, `fastqc`, `NFCORE_RNASEQ:FASTQC` and
// `fast-qc` all collapse to a comparable token. Returns "" when unusable.
function normalizeStepKey(value: unknown): string {
  return String(value ?? "").toLowerCase().replace(/[^a-z0-9]+/g, "");
}

/**
 * Fix #8: finalize a terminal run's per-step records so the step-detail panel
 * stops showing a finished run's steps as "pending" with no outputs.
 *
 * Why this exists: `storage.ts` seeds every step as `status:'pending', outputs:[]`
 * at run creation, and — for Nextflow / AWS Batch runs — NOTHING ever rewrote
 * `run.steps[]` afterward. The Galaxy-poller `workflow_completed` path finalizes
 * steps (routes.ts), and the `step_state` SSE handler only bumps aggregate
 * progress counts (never the individual step records), so a completed Nextflow
 * run's stored `steps[]` kept its creation-time pending/empty values. The root
 * cause is therefore "no step finalization on the Nextflow terminal path at
 * all", not "SSE wrote memory but not the store".
 *
 * What this derives from data already in hand (`run.execution.status` +
 * `nextflowStatus`):
 *   - status: driven by the per-process state in `nextflowStatus.processes`
 *     when present; otherwise, on a `completed` run every not-yet-terminal step
 *     ran and completed, and on a `failed`/`cancelled` run a step that produced
 *     output clearly ran → `completed`. We never fabricate a `failed` status on
 *     an arbitrary step we cannot attribute the failure to (honest empty state).
 *   - outputs: grouped from the run's output-file list by producing step
 *     (`f.step_name` / `f.process_name` → step), matched against the step's
 *     stepName/toolName/toolId/stepId. Only attached when a step currently has
 *     none, so an already-populated (e.g. Galaxy-path) record is never clobbered.
 *
 * Best-effort boundary — timing/metrics/logs/tool_version are NOT populated:
 * the Galaxy status payload surfaced to Node (`getNextflowStatus`) carries no
 * per-task trace (duration, %cpu, peak_rss) and no per-step tool version. Those
 * stay omitted (StepDetail renders its honest "duration n/a" / "version n/a").
 *
 * Returns the rewritten `steps[]` when at least one step changed, else `null`
 * (so callers skip the write and the function is idempotent across re-reads).
 */
export function finalizeRunSteps(
  run: Pick<ExecutionRun, "execution" | "steps">,
  nextflowStatus: any,
): StepExecution[] | null {
  const steps: StepExecution[] = Array.isArray(run.steps) ? run.steps : [];
  if (steps.length === 0) return null;

  const runStatus = String(run.execution?.status ?? "").toLowerCase();
  if (!TERMINAL_RUN_STATUSES.has(runStatus)) return null;

  // 1. Per-process terminal status, when the backend reports it.
  const procStatusByKey = new Map<string, string>();
  const procs: any[] = Array.isArray(nextflowStatus?.processes) ? nextflowStatus.processes : [];
  for (const p of procs) {
    const raw = String(p?.status ?? p?.state ?? "").toLowerCase();
    if (!raw) continue;
    for (const candidate of [p?.name, p?.process, p?.id]) {
      const key = normalizeStepKey(candidate);
      if (key) procStatusByKey.set(key, raw);
    }
  }

  // 2. Output files grouped by their producing step (step_name / process_name).
  const files: any[] =
    (Array.isArray(nextflowStatus?.s3_output_files) && nextflowStatus.s3_output_files.length
      ? nextflowStatus.s3_output_files
      : Array.isArray(nextflowStatus?.output_files)
      ? nextflowStatus.output_files
      : []) || [];
  const outputsByStepKey = new Map<string, StepOutput[]>();
  for (const f of files) {
    const key = normalizeStepKey(f?.step_name ?? f?.process_name);
    if (!key) continue; // a file with no producing-step tag can't be attributed
    const uri = String(f?.s3_uri ?? f?.path ?? "");
    const name = String(f?.filename ?? f?.name ?? uri.split("/").pop() ?? "");
    if (!name && !uri) continue;
    const extension = extensionOf(name || uri);
    const rawSize = Number(f?.size ?? f?.sizeBytes ?? f?.bytes ?? 0);
    const sizeBytes = Number.isFinite(rawSize) && rawSize > 0 ? rawSize : 0;
    const out: StepOutput = {
      datasetId: uri || name,
      name: name || uri.split("/").pop() || "file",
      extension,
      sizeBytes,
      isVisualizable: VISUALIZABLE_EXT.has(extension),
      previewUrl: uri || undefined,
    };
    const bucket = outputsByStepKey.get(key) || [];
    bucket.push(out);
    outputsByStepKey.set(key, bucket);
  }

  const keysFor = (s: StepExecution): string[] =>
    [s.stepName, s.toolName, s.toolId, s.stepId].map(normalizeStepKey).filter(Boolean);

  let changed = false;
  const next = steps.map((s): StepExecution => {
    const keys = keysFor(s);

    // Process status reported for this step, if any.
    let procStatus: string | undefined;
    for (const k of keys) {
      const v = procStatusByKey.get(k);
      if (v) { procStatus = v; break; }
    }

    // Outputs attributable to this step (deduped by datasetId).
    let outs: StepOutput[] = [];
    for (const k of keys) {
      const bucket = outputsByStepKey.get(k);
      if (bucket && bucket.length) outs = outs.concat(bucket);
    }
    if (outs.length > 1) {
      const seen = new Set<string>();
      outs = outs.filter((o) => (seen.has(o.datasetId) ? false : (seen.add(o.datasetId), true)));
    }

    const current = String(s.status ?? "").toLowerCase();
    const alreadyTerminalStep = current === "completed" || current === "failed" || current === "skipped";

    const procFailed =
      !!procStatus && (procStatus.includes("fail") || procStatus.includes("error") || procStatus.includes("cancel"));
    const procCompleted =
      !!procStatus && (procStatus.includes("complet") || procStatus === "succeeded" || procStatus === "ok");

    let status: StepExecution["status"] = s.status;
    if (procFailed) {
      status = "failed";
    } else if (procCompleted) {
      status = "completed";
    } else if (runStatus === "completed") {
      // The run finished OK → any step not already terminal ran and completed.
      if (!alreadyTerminalStep) status = "completed";
    } else if (runStatus === "failed" || runStatus === "cancelled") {
      // Best-effort: a step that produced output clearly ran → completed.
      // Steps with no attributable evidence keep their stored status — we do
      // NOT guess which step failed when no per-process state tells us.
      if (outs.length > 0 && !alreadyTerminalStep) status = "completed";
    }

    // Attach outputs only when the step currently has none (never clobber an
    // already-populated record, e.g. one finalized by the Galaxy path).
    const hasOutputs = Array.isArray(s.outputs) && s.outputs.length > 0;
    const nextOutputs = !hasOutputs && outs.length > 0 ? outs : s.outputs ?? [];

    if (status !== s.status || nextOutputs !== s.outputs) {
      changed = true;
      return { ...s, status, outputs: nextOutputs };
    }
    return s;
  });

  return changed ? next : null;
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
