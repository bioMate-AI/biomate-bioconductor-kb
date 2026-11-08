import { useEffect, useRef, useState } from 'react';

/**
 * Live run-status polling hook (Gap 3/4 of docs/20260310_EXECUTION_TRACING_UX_GAPS.md).
 *
 * Polls the aggregate AI run-status endpoint that the Node proxy exposes at
 * `/api/workflows/<invocationId>/realtime/status` (routes.ts:4426 → Galaxy
 * `autofix3.get_workflow_realtime_status`). That endpoint reads nextflow_monitor's
 * `latest.json` analysis output plus in-memory AutoFix sessions and returns
 * detected issues + autofix state. No frontend code called it before; this hook
 * wires it into the run panel.
 *
 * Behaviour:
 *   - Polls only while `active` is true and an `invocationId` is present.
 *   - Fires once immediately, then every `intervalMs` (default 5 s).
 *   - Stops (clears the interval) the moment `active` flips false — the caller
 *     passes `active = false` on terminal states (completed/failed), so polling
 *     halts automatically.
 *   - Degrades gracefully: a 404 / network error / malformed body never throws
 *     and never clobbers previously-good data with null; the panel keeps working.
 */

export interface RealtimeIssue {
  type?: string;
  severity?: string;
  message?: string;
  suggestion?: string;
  auto_fixable?: boolean;
}

export interface RealtimeAutofix {
  enabled?: boolean;
  active?: boolean;
  fixes_applied?: number;
  sessions_count?: number;
}

export interface RealtimeRunStatus {
  workflow_id?: string;
  timestamp?: string | null;
  status?: string | null;
  issues: RealtimeIssue[];
  autofix: RealtimeAutofix | null;
  restart_info?: { new_invocation_id?: string } | null;
  /** Future-proof: backend may start tailing nextflow.out into this field. */
  recent_logs?: string[];
  has_data: boolean;
}

const EMPTY: RealtimeRunStatus = { issues: [], autofix: null, has_data: false };

function normalize(json: any): RealtimeRunStatus {
  if (!json || typeof json !== 'object') return EMPTY;
  return {
    workflow_id: typeof json.workflow_id === 'string' ? json.workflow_id : undefined,
    timestamp: json.timestamp ?? null,
    status: typeof json.status === 'string' ? json.status : null,
    issues: Array.isArray(json.issues) ? json.issues : [],
    autofix: json.autofix && typeof json.autofix === 'object' ? json.autofix : null,
    restart_info: json.restart_info && typeof json.restart_info === 'object' ? json.restart_info : null,
    recent_logs: Array.isArray(json.recent_logs)
      ? json.recent_logs.filter((l: unknown): l is string => typeof l === 'string')
      : undefined,
    has_data: Boolean(json.has_data),
  };
}

export function useRealtimeRunStatus(
  invocationId: string | undefined,
  active: boolean,
  intervalMs = 5000,
): RealtimeRunStatus | null {
  const [data, setData] = useState<RealtimeRunStatus | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    if (!invocationId || !active) {
      if (timerRef.current) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
      return;
    }

    let cancelled = false;

    const poll = async () => {
      try {
        const res = await fetch(
          `/api/workflows/${encodeURIComponent(invocationId)}/realtime/status`,
        );
        if (cancelled) return;
        if (!res.ok) {
          // Keep last-good data; only seed EMPTY if we have nothing yet.
          setData(prev => prev ?? EMPTY);
          return;
        }
        const json = await res.json().catch(() => null);
        if (cancelled) return;
        setData(normalize(json));
      } catch {
        if (!cancelled) setData(prev => prev ?? EMPTY);
      }
    };

    void poll();
    timerRef.current = setInterval(() => { void poll(); }, intervalMs);

    return () => {
      cancelled = true;
      if (timerRef.current) {
        clearInterval(timerRef.current);
        timerRef.current = null;
      }
    };
  }, [invocationId, active, intervalMs]);

  return data;
}
