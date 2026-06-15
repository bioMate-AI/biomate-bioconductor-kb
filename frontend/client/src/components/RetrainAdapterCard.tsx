/**
 * Lane B3 — Settings dialog affordance for the per-org adaptation queue.
 *
 * Renders:
 *   1. Current edit-pair count for the user's org
 *   2. Recent jobs (newest first) with status badge + adaptation_mode
 *   3. "Re-train on my edits" button → POST /api/regulatory_llm/training_jobs
 *   4. Dev-only "Tick worker" button → POST /api/regulatory_llm/training_jobs/tick
 *
 * The "tick" button only appears when import.meta.env.DEV is true; production
 * runs regulatory_training_worker.run_forever as a long-lived process.
 */
import { useEffect, useState } from "react";

type AdaptationMode = "prompt_rules" | "few_shot_index" | "post_train_lora";
type JobStatus = "queued" | "running" | "succeeded" | "failed" | "cancelled";

type TrainingJob = {
  job_id: string;
  org_id: string;
  status: JobStatus;
  submitted_at: number;
  updated_at: number;
  edit_pair_count: number;
  message: string;
  adapter_path: string;
  adaptation_mode: AdaptationMode;
};

const STATUS_COLOR: Record<JobStatus, string> = {
  queued:    "oklch(0.78 0.10 250)",  // blue
  running:   "oklch(0.78 0.12 70)",   // amber
  succeeded: "oklch(0.65 0.16 145)",  // green
  failed:    "oklch(0.65 0.18 25)",   // red
  cancelled: "oklch(0.55 0.02 280)",  // grey
};

function fmtTs(unix: number): string {
  if (!unix) return "—";
  const d = new Date(unix * 1000);
  const today = new Date();
  const sameDay = d.toDateString() === today.toDateString();
  return sameDay
    ? d.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" })
    : d.toLocaleDateString();
}

export function RetrainAdapterCard() {
  const [pairCount, setPairCount] = useState<number | null>(null);
  const [jobs, setJobs] = useState<TrainingJob[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string>("");
  const isDev = (typeof import.meta !== "undefined")
    && (import.meta as any).env
    && Boolean((import.meta as any).env.DEV);

  const refresh = async () => {
    setErr("");
    try {
      const [c, j] = await Promise.all([
        fetch("/api/regulatory_llm/edit_pairs/count", { credentials: "include" })
          .then((r) => (r.ok ? r.json() : { count: 0 })),
        fetch("/api/regulatory_llm/training_jobs", { credentials: "include" })
          .then((r) => (r.ok ? r.json() : [])),
      ]);
      setPairCount(typeof c?.count === "number" ? c.count : 0);
      setJobs(Array.isArray(j) ? j : []);
    } catch (e: any) {
      setErr(String(e?.message ?? e));
    }
  };

  useEffect(() => {
    refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const submit = async () => {
    setBusy(true);
    setErr("");
    try {
      const r = await fetch("/api/regulatory_llm/training_jobs", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({}),
      });
      if (!r.ok) {
        const body = await r.json().catch(() => ({}));
        throw new Error(body?.detail || body?.error || `HTTP ${r.status}`);
      }
      await refresh();
    } catch (e: any) {
      setErr(String(e?.message ?? e));
    } finally {
      setBusy(false);
    }
  };

  const tick = async () => {
    setBusy(true);
    setErr("");
    try {
      const r = await fetch("/api/regulatory_llm/training_jobs/tick", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({}),
      });
      if (!r.ok) throw new Error(`tick HTTP ${r.status}`);
      await refresh();
    } catch (e: any) {
      setErr(String(e?.message ?? e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div
      data-testid="retrain-adapter-card"
      style={{ display: "flex", flexDirection: "column", gap: 12 }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <div style={{ flex: 1 }}>
          <div style={{ fontWeight: 600 }}>Adapt regulatory LLM to your org</div>
          <div style={{ fontSize: 12, color: "var(--bm-text-muted)" }}>
            Compile your accumulated edit pairs into a per-org rule pack that
            the regulatory LLM reads on the next inference call. Zero GPU.
          </div>
        </div>
        <div
          data-testid="retrain-pair-count"
          style={{
            background: "var(--bm-surface, #f3f4f6)",
            border: "1px solid var(--bm-border, #e5e7eb)",
            borderRadius: 6, padding: "6px 10px", fontSize: 12.5,
          }}
        >
          {pairCount === null ? "…" : pairCount} edit pair{pairCount === 1 ? "" : "s"}
        </div>
      </div>

      <div style={{ display: "flex", gap: 8 }}>
        <button
          data-testid="retrain-submit-btn"
          onClick={submit}
          disabled={busy}
          className="ind-btn sm primary"
          style={{
            padding: "6px 14px", fontSize: 12.5,
            background: "oklch(0.45 0.18 280)", color: "white",
            border: "none", borderRadius: 4,
            cursor: busy ? "wait" : "pointer",
          }}
        >
          {busy ? "Submitting…" : "Re-train on my edits"}
        </button>
        {isDev && (
          <button
            data-testid="retrain-tick-btn"
            onClick={tick}
            disabled={busy}
            className="ind-btn sm"
            style={{
              padding: "6px 14px", fontSize: 12.5,
              background: "transparent", color: "var(--bm-text-muted)",
              border: "1px solid var(--bm-border, #e5e7eb)", borderRadius: 4,
              cursor: busy ? "wait" : "pointer",
            }}
            title="Dev only — drive the stub worker once"
          >
            Tick worker
          </button>
        )}
        <button
          data-testid="retrain-refresh-btn"
          onClick={refresh}
          disabled={busy}
          className="ind-btn sm"
          style={{
            padding: "6px 14px", fontSize: 12.5,
            background: "transparent", color: "var(--bm-text-muted)",
            border: "1px solid var(--bm-border, #e5e7eb)", borderRadius: 4,
            cursor: busy ? "wait" : "pointer",
          }}
        >
          Refresh
        </button>
      </div>

      {err && (
        <div
          data-testid="retrain-error"
          style={{
            color: "var(--ind-err, #b91c1c)", fontSize: 12,
            background: "var(--ind-err-soft, #fef2f2)",
            border: "1px solid var(--ind-err, #fecaca)",
            borderRadius: 4, padding: "6px 10px",
          }}
        >
          {err}
        </div>
      )}

      {jobs !== null && (
        <div data-testid="retrain-job-history">
          <div style={{ fontSize: 11, textTransform: "uppercase", letterSpacing: "0.06em", color: "var(--bm-text-muted)", marginBottom: 6 }}>
            Recent jobs
          </div>
          {jobs.length === 0 ? (
            <div style={{ fontSize: 12.5, color: "var(--bm-text-muted)" }}>
              No retrain jobs yet — click <b>Re-train on my edits</b> to queue one.
            </div>
          ) : (
            <ul style={{ listStyle: "none", padding: 0, margin: 0, display: "flex", flexDirection: "column", gap: 6 }}>
              {jobs.slice(0, 8).map((j) => (
                <li
                  key={j.job_id}
                  data-testid={`retrain-job-${j.job_id}`}
                  style={{
                    display: "flex", alignItems: "center", gap: 10,
                    padding: "6px 10px",
                    border: "1px solid var(--bm-border, #e5e7eb)",
                    borderRadius: 4, fontSize: 12,
                  }}
                >
                  <span
                    style={{
                      display: "inline-block", width: 8, height: 8, borderRadius: 4,
                      background: STATUS_COLOR[j.status] ?? "#9ca3af",
                    }}
                  />
                  <span style={{ flex: 1 }}>
                    <span style={{ fontFamily: "JetBrains Mono", fontSize: 11 }}>{j.job_id.slice(0, 8)}</span>
                    {" · "}
                    <span>{j.adaptation_mode}</span>
                    {j.message ? <span style={{ color: "var(--bm-text-muted)" }}> · {j.message.slice(0, 80)}</span> : null}
                  </span>
                  <span style={{ color: "var(--bm-text-muted)", fontSize: 11 }}>{fmtTs(j.updated_at)}</span>
                  <span style={{
                    fontSize: 10.5, fontWeight: 600, textTransform: "uppercase",
                    color: STATUS_COLOR[j.status] ?? "#374151",
                  }}>
                    {j.status}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
