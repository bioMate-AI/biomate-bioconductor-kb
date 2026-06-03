/**
 * <JobButton/> — generic UI for starting + tracking an async job-queue job.
 *
 * See docs/20260602_ASYNC_JOB_QUEUE_DESIGN.md §10.
 *
 * Internal states:
 *   idle      → click → POST /api/jobs → set jobId
 *   queued    → spinner ("Queued…") + Cancel link
 *   running   → spinner + progress bar + Cancel link
 *   ready     → fires onReady(artifactUrl); shows "Download started" → idle
 *   failed    → red message + Retry button
 *   cancelled → returns to idle
 */

import { useEffect, useRef, useState } from "react";
import { useJob } from "../hooks/use-job";

export interface JobButtonProps {
  kind: string;
  payload: Record<string, any>;
  label: string;
  /** Optional override of the auto-derived dedup key. */
  dedupKey?: string;
  /** Fired exactly once per job when the job reaches `ready`. */
  onReady?: (artifactUrl: string) => void;
  /** Fired when the job fails (so callers can toast). */
  onFailed?: (error: string | null) => void;
  className?: string;
  disabled?: boolean;
}

export function JobButton(props: JobButtonProps) {
  const { kind, payload, label, dedupKey, onReady, onFailed, className, disabled } = props;
  const [jobId, setJobId] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);
  const firedReadyRef = useRef<string | null>(null);
  const firedFailedRef = useRef<string | null>(null);

  const job = useJob(jobId);

  useEffect(() => {
    if (job.state === "ready" && job.jobId && firedReadyRef.current !== job.jobId) {
      firedReadyRef.current = job.jobId;
      const url = job.artifactUrl ?? `/api/jobs/${job.jobId}/artifact`;
      onReady?.(url);
    }
    if (job.state === "failed" && job.jobId && firedFailedRef.current !== job.jobId) {
      firedFailedRef.current = job.jobId;
      onFailed?.(job.error);
    }
  }, [job.state, job.jobId, job.artifactUrl, job.error, onReady, onFailed]);

  const start = async () => {
    setCreateError(null);
    setCreating(true);
    try {
      const r = await fetch("/api/jobs", {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ kind, payload, dedupKey }),
      });
      if (!r.ok) {
        const body = await r.text();
        setCreateError(`Failed to start job (${r.status}): ${body.slice(0, 200)}`);
        return;
      }
      const j = await r.json();
      setJobId(j.jobId);
    } catch (err: any) {
      setCreateError(err?.message || "Network error");
    } finally {
      setCreating(false);
    }
  };

  const cancel = async () => {
    if (!jobId) return;
    try {
      await fetch(`/api/jobs/${jobId}`, { method: "DELETE", credentials: "include" });
    } catch { /* ignore */ }
    setJobId(null);
  };

  const reset = () => {
    setJobId(null);
    setCreateError(null);
    firedReadyRef.current = null;
    firedFailedRef.current = null;
  };

  // ---------- render ----------
  if (createError) {
    return (
      <div className={className}>
        <span className="text-red-600 text-sm" role="alert">{createError}</span>{" "}
        <button type="button" onClick={reset} className="underline text-sm">Dismiss</button>
      </div>
    );
  }

  if (!jobId) {
    return (
      <button
        type="button"
        onClick={start}
        disabled={disabled || creating}
        className={className}
        data-jobbutton-state="idle"
      >
        {creating ? "Starting…" : label}
      </button>
    );
  }

  if (job.state === "queued" || job.state === "running" || job.state === "unknown") {
    return (
      <div className={className} data-jobbutton-state={job.state}>
        <span aria-busy="true">⌛ {job.state === "queued" ? "Queued…" : "Preparing…"}</span>
        {job.state === "running" && (
          <progress value={job.progress} max={100} className="ml-2" />
        )}
        <span className="ml-2 text-xs text-muted-foreground">{job.progress}%</span>
        <button type="button" onClick={cancel} className="ml-2 underline text-xs">Cancel</button>
      </div>
    );
  }

  if (job.state === "failed") {
    return (
      <div className={className} data-jobbutton-state="failed">
        <span className="text-red-600 text-sm" role="alert">Job failed: {job.error ?? "unknown error"}</span>{" "}
        <button type="button" onClick={() => { reset(); void start(); }} className="underline text-sm">Retry</button>
      </div>
    );
  }

  if (job.state === "cancelled" || job.state === "expired") {
    reset();
    return null;
  }

  // ready — onReady fired via effect; show transient confirmation.
  return (
    <div className={className} data-jobbutton-state="ready">
      <span className="text-sm">Download started</span>{" "}
      <button type="button" onClick={reset} className="underline text-sm">OK</button>
    </div>
  );
}
