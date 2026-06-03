/**
 * useJob — polls /api/jobs/:id every 2s until the job reaches a terminal state.
 *
 * See docs/20260602_ASYNC_JOB_QUEUE_DESIGN.md §10.
 */

import { useEffect, useState } from "react";

export type JobState =
  | "unknown"
  | "queued"
  | "running"
  | "ready"
  | "failed"
  | "cancelled"
  | "expired";

export interface JobSnapshot {
  jobId: string | null;
  state: JobState;
  progress: number;
  etaSeconds: number | null;
  artifactBytes: number | null;
  artifactUrl: string | null;
  error: string | null;
}

const TERMINAL: ReadonlySet<JobState> = new Set(["ready", "failed", "cancelled", "expired"]);

const EMPTY: JobSnapshot = {
  jobId: null,
  state: "unknown",
  progress: 0,
  etaSeconds: null,
  artifactBytes: null,
  artifactUrl: null,
  error: null,
};

export function useJob(jobId: string | null, pollIntervalMs = 2000): JobSnapshot {
  const [snap, setSnap] = useState<JobSnapshot>(EMPTY);

  useEffect(() => {
    if (!jobId) {
      setSnap(EMPTY);
      return;
    }
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout> | null = null;

    const tick = async () => {
      try {
        const r = await fetch(`/api/jobs/${jobId}`, { credentials: "include" });
        if (cancelled) return;
        if (!r.ok) {
          setSnap((s) => ({ ...s, jobId, state: "failed", error: `HTTP ${r.status}` }));
          return;
        }
        const j = await r.json();
        if (cancelled) return;
        const next: JobSnapshot = {
          jobId: j.jobId ?? jobId,
          state: (j.state as JobState) ?? "unknown",
          progress: typeof j.progress === "number" ? j.progress : 0,
          etaSeconds: j.etaSeconds ?? null,
          artifactBytes: j.artifactBytes ?? null,
          artifactUrl: j.artifactUrl ?? `/api/jobs/${jobId}/artifact`,
          error: j.error ?? null,
        };
        setSnap(next);
        if (!TERMINAL.has(next.state)) {
          timer = setTimeout(tick, pollIntervalMs);
        }
      } catch (err: any) {
        if (cancelled) return;
        // Transient network error — keep polling.
        timer = setTimeout(tick, pollIntervalMs);
      }
    };
    tick();
    return () => {
      cancelled = true;
      if (timer) clearTimeout(timer);
    };
  }, [jobId, pollIntervalMs]);

  return snap;
}
