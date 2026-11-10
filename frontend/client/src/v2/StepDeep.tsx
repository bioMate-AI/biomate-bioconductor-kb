/**
 * StepDeep — the per-step detail panel (step deep-view).
 *
 * Implements the "previously designed" step-as-object surface (prototype
 * dataui/StepDeep.jsx): any step opens into one object —
 *   header (step N of M · phase · name · status chip)
 *   → inputs (data chips / upstream output)
 *   → output artifacts rendered from their own bytes (output tabs → preview)
 *   → the per-step LOG / TRAJECTORY tail        ← trajectory lives HERE (not a tab)
 *   → resolved parameters this step ran with (editable, origin/reason)
 *   → Re-run from this step, with the was→now diff up front + cache note
 *   → previous / next step navigation
 *
 * Opened by clicking a step (Phases tab) or a provenance claim in Summary.
 * Styled with the v2 design tokens (src/v2/tokens.css, [data-v2-ui]).
 */
import React, { useMemo, useState } from "react";
import { tOr } from "@/lib/i18n";
import { StepOutputPreview } from "@/components/step-output-preview";
import { TrajectoryView, type TrajectoryRow } from "@/components/trajectory-view";

export type StepDeepStatus =
  | "completed" | "running" | "failed" | "pending" | "waiting" | "skipped";

export interface StepDeepParam {
  label: string;
  value: string;
  /** default | from your message | from your file | recommended | project instructions | edited by you */
  origin?: string;
  /** one-line reason shown under a non-default value */
  reason?: string;
}

export interface StepDeepData {
  name: string;
  phase?: string;
  status?: StepDeepStatus;
  tool?: string;
  version?: string;
  /** 1-based position and the total step count, for the "step N of M" header + nav. */
  index: number;
  total: number;
  inputs?: Array<{ name: string; from?: string }>;
  outputs?: Array<{ name: string; path: string; extension: string }>;
  params?: StepDeepParam[];
  /** Raw per-step log lines (the tail follows while the step runs). */
  logTail?: string[];
  /** Structured per-step trajectory, preferred over logTail when present. */
  trajectory?: TrajectoryRow[];
}

export interface StepDeepProps {
  runId: string;
  step: StepDeepData;
  projectId?: string | null;
  onClose?: () => void;
  onPrev?: () => void;
  onNext?: () => void;
  /** Called with the edited parameter map when the user re-runs from this step. */
  onRerunFromHere?: (edits: Record<string, string>) => void;
}

const STATUS_TOKEN: Record<StepDeepStatus, { c: string; bg: string; label: string }> = {
  completed: { c: "var(--ok)",   bg: "var(--ok-soft)",   label: "Done" },
  running:   { c: "var(--run)",  bg: "var(--run-soft)",  label: "Running" },
  failed:    { c: "var(--err)",  bg: "var(--err-soft)",  label: "Failed" },
  pending:   { c: "var(--text-muted)", bg: "var(--neutral-badge)", label: "Queued" },
  waiting:   { c: "var(--text-muted)", bg: "var(--neutral-badge)", label: "Waiting" },
  skipped:   { c: "var(--text-muted)", bg: "var(--neutral-badge)", label: "Skipped" },
};

export function StepDeep({ runId, step, projectId, onClose, onPrev, onNext, onRerunFromHere }: StepDeepProps) {
  const params = step.params ?? [];
  const outputs = step.outputs ?? [];
  const [sel, setSel] = useState(0);
  const [edits, setEdits] = useState<Record<string, string>>({});

  const status = (step.status ?? "pending") as StepDeepStatus;
  const st = STATUS_TOKEN[status] ?? STATUS_TOKEN.pending;

  // was → now diff: params the user changed in place.
  const diff = useMemo(
    () => params.filter(p => edits[p.label] !== undefined && edits[p.label] !== p.value)
      .map(p => ({ label: p.label, was: p.value, now: edits[p.label] })),
    [params, edits],
  );
  const dirty = diff.length > 0;

  const selFile = outputs[Math.min(sel, Math.max(0, outputs.length - 1))];

  return (
    <div data-testid="step-deep" data-v2-ui style={{
      display: "flex", flexDirection: "column", gap: 14,
      fontFamily: "var(--font-ui)", color: "var(--text)", fontSize: 'var(--fs-meta)',
    }}>
      {/* Header */}
      <div style={{ display: "flex", alignItems: "flex-start", gap: 10 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 'var(--fs-micro)', color: "var(--text-muted)" }}>
            {tOr("stepdeep.pos", "step {{i}} of {{n}}", { i: step.index, n: step.total })}
            {step.phase ? ` · ${step.phase}` : ""}
            {status === "skipped" ? " · not run" : ""}
          </div>
          <div style={{ fontWeight: 600, fontSize: 'var(--fs-body)', marginTop: 2 }}>{step.name}</div>
          {(step.tool || step.version) && (
            <div style={{ fontFamily: "var(--font-mono)", fontSize: 'var(--fs-micro)', color: "var(--text-muted)", marginTop: 2 }}>
              {step.tool}{step.version ? ` · ${step.version}` : ""}
            </div>
          )}
        </div>
        <span data-testid="step-deep-status" style={{
          display: "inline-flex", alignItems: "center", gap: 6, flexShrink: 0,
          padding: "3px 9px", borderRadius: 999, fontSize: 'var(--fs-micro)', fontWeight: 500,
          color: st.c, background: st.bg,
        }}>
          <span style={{ width: 6, height: 6, borderRadius: 999, background: "currentColor" }} />
          {st.label}
        </span>
        {onClose && (
          <button onClick={onClose} aria-label="Close" style={ghostBtn}>✕</button>
        )}
      </div>

      {/* Inputs */}
      <section>
        <div style={sectionLabel}>{tOr("stepdeep.inputs", "Inputs")}</div>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
          {step.inputs && step.inputs.length > 0 ? (
            step.inputs.map((inp, i) => (
              <span key={i} style={chip} title={inp.from || undefined}>
                <span style={{ fontFamily: "var(--font-mono)" }}>{inp.name}</span>
                {inp.from && <span style={{ color: "var(--text-dim)" }}>· {inp.from}</span>}
              </span>
            ))
          ) : (
            <span style={chip}>{tOr("stepdeep.upstream", "upstream step output")}</span>
          )}
        </div>
      </section>

      {/* Output artifacts — rendered from their own bytes */}
      {outputs.length > 0 && (
        <section>
          <div style={sectionLabel}>{tOr("stepdeep.outputs", "Outputs")}</div>
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginBottom: 8 }}>
            {outputs.map((o, i) => (
              <button key={o.path || i} onClick={() => setSel(i)} data-testid="step-deep-outtab" style={{
                ...pillBtn, ...(i === sel ? pillBtnOn : null),
              }}>{o.name}</button>
            ))}
          </div>
          {selFile && (
            <StepOutputPreview
              runId={runId}
              file={{ name: selFile.name, path: selFile.path, extension: selFile.extension }}
              onClose={() => { /* inline — no-op */ }}
              projectId={projectId ?? undefined}
            />
          )}
        </section>
      )}

      {/* Trajectory section commented out 2026-10-28 (user request): the agent
          trajectory has no real backend endpoint and duplicates the Record / per-step
          log; re-enable when a real agent-trajectory endpoint ships. Original below.
      <section>
        <div style={sectionLabel}>{tOr("stepdeep.trajectory", "Trajectory")}</div>
        {step.trajectory && step.trajectory.length > 0 ? (
          <TrajectoryView rows={step.trajectory} />
        ) : step.logTail && step.logTail.length > 0 ? (
          <pre data-testid="step-deep-log" style={{
            margin: 0, padding: "10px 12px", borderRadius: 8, maxHeight: 220, overflow: "auto",
            background: "var(--surface-2)", border: "1px solid var(--border)",
            fontFamily: "var(--font-mono)", fontSize: 'var(--fs-micro)', lineHeight: 1.5, color: "var(--text)",
          }}>{step.logTail.join("\n")}</pre>
        ) : (
          <div style={{ fontSize: 'var(--fs-meta)', color: "var(--text-muted)" }}>
            {status === "running"
              ? tOr("stepdeep.log_follow", "Follows the tail while the step runs.")
              : tOr("stepdeep.log_none", "No step log recorded.")}
          </div>
        )}
      </section>
      */}

      {/* Resolved parameters — editable in place */}
      {params.length > 0 && (
        <section>
          <div style={{ ...sectionLabel, display: "flex", alignItems: "center", gap: 8 }}>
            <span style={{ flex: 1 }}>{tOr("stepdeep.params", "Parameters this step actually ran with")}</span>
          </div>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 'var(--fs-meta)' }}>
            <tbody>
              {params.map((p, i) => {
                const v = edits[p.label] ?? p.value;
                const changed = edits[p.label] !== undefined && edits[p.label] !== p.value;
                return (
                  <tr key={i} style={{ borderTop: i ? "1px solid var(--border)" : "none" }}>
                    <td style={{ padding: "7px 10px 7px 0", color: "var(--text-muted)", whiteSpace: "nowrap" }}>{p.label}</td>
                    <td style={{ padding: "7px 10px 7px 0" }}>
                      <input
                        value={v}
                        onChange={e => setEdits(prev => ({ ...prev, [p.label]: e.target.value }))}
                        style={{
                          width: "100%", fontSize: 'var(--fs-meta)', fontFamily: "var(--font-mono)",
                          padding: "3px 7px", borderRadius: 6,
                          border: `1px solid ${changed ? "var(--accent)" : "var(--border)"}`,
                          background: "var(--bg-elev, #fff)", color: "var(--text)",
                        }}
                      />
                      {p.reason && <div style={{ fontSize: 10.5, color: "var(--text-dim)", marginTop: 2 }}>{p.reason}</div>}
                    </td>
                    <td style={{ padding: "7px 0", textAlign: "right", whiteSpace: "nowrap" }}>
                      {p.origin && (
                        <span style={{
                          fontSize: 10, fontWeight: 600, letterSpacing: ".04em", textTransform: "uppercase",
                          padding: "2px 7px", borderRadius: 6,
                          color: p.origin === "default" ? "var(--text-muted)" : "var(--accent-ink)",
                          background: p.origin === "default" ? "var(--neutral-badge)" : "var(--accent-soft)",
                        }}>{p.origin}</span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          <div style={{ fontSize: 10.5, color: "var(--text-dim)", marginTop: 6 }}>
            {tOr("stepdeep.params_hint", "Defaults are muted; anything the project or you changed carries its reason. Edit a value here and the step re-runs from this point.")}
          </div>
        </section>
      )}

      {/* Re-run from this step — was → now diff up front + cache note */}
      {onRerunFromHere && (
        <section style={{ borderTop: "1px solid var(--border)", paddingTop: 12 }}>
          <div style={sectionLabel}>{tOr("stepdeep.rerun", "Re-run from this step")}</div>
          {dirty && (
            <div data-testid="step-deep-diff" style={{ marginBottom: 8 }}>
              {diff.map(d => (
                <div key={d.label} style={{ fontSize: 'var(--fs-meta)', fontFamily: "var(--font-mono)" }}>
                  <span style={{ color: "var(--text-muted)" }}>{d.label}: </span>
                  <span style={{ color: "var(--err)", textDecoration: "line-through" }}>{d.was}</span>
                  <span style={{ color: "var(--text-dim)" }}> → </span>
                  <span style={{ color: "var(--ok)", fontWeight: 600 }}>{d.now}</span>
                </div>
              ))}
            </div>
          )}
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <button
              disabled={!dirty}
              onClick={() => onRerunFromHere(edits)}
              style={{ ...primaryBtn, opacity: dirty ? 1 : 0.5, cursor: dirty ? "pointer" : "not-allowed" }}
            >{tOr("stepdeep.apply_rerun", "Apply & re-run from here")}</button>
            <span style={{ fontSize: 'var(--fs-micro)', color: "var(--text-dim)" }}>
              {tOr("stepdeep.cache_note", "Upstream is reused from cache — only this step and what depends on it run again.")}
            </span>
          </div>
        </section>
      )}

      {/* Prev / next step navigation */}
      <div style={{ display: "flex", gap: 8, borderTop: "1px solid var(--border)", paddingTop: 10 }}>
        <button disabled={step.index <= 1 || !onPrev} onClick={onPrev} style={{ ...ghostNavBtn, opacity: step.index <= 1 || !onPrev ? 0.4 : 1 }}>
          ‹ {tOr("stepdeep.prev", "previous step")}
        </button>
        <span style={{ flex: 1 }} />
        <button disabled={step.index >= step.total || !onNext} onClick={onNext} style={{ ...ghostNavBtn, opacity: step.index >= step.total || !onNext ? 0.4 : 1 }}>
          {tOr("stepdeep.next", "next step")} ›
        </button>
      </div>
    </div>
  );
}

const sectionLabel: React.CSSProperties = {
  fontSize: 'var(--fs-micro)', fontWeight: 600, letterSpacing: ".06em", textTransform: "uppercase",
  color: "var(--text-muted)", marginBottom: 6,
};
const chip: React.CSSProperties = {
  display: "inline-flex", alignItems: "center", gap: 6, padding: "3px 9px",
  borderRadius: 999, fontSize: 'var(--fs-micro)', background: "var(--neutral-badge)", color: "var(--text-muted)",
};
const pillBtn: React.CSSProperties = {
  padding: "4px 11px", borderRadius: 999, fontSize: 'var(--fs-meta)', border: "1px solid var(--border)",
  background: "var(--bg-elev, #fff)", color: "var(--text)", cursor: "pointer",
};
const pillBtnOn: React.CSSProperties = {
  background: "var(--text)", color: "var(--bg-elev, #fff)", borderColor: "var(--text)",
};
const primaryBtn: React.CSSProperties = {
  height: 30, padding: "0 14px", borderRadius: 6, border: "1px solid var(--accent)",
  background: "var(--accent)", color: "#fff", fontSize: 'var(--fs-meta)', fontWeight: 500,
};
const ghostBtn: React.CSSProperties = {
  border: "none", background: "transparent", color: "var(--text-muted)", fontSize: 'var(--fs-body)', cursor: "pointer", padding: 4,
};
const ghostNavBtn: React.CSSProperties = {
  height: 28, padding: "0 10px", borderRadius: 6, border: "1px solid var(--border)",
  background: "transparent", color: "var(--text)", fontSize: 'var(--fs-meta)', cursor: "pointer",
};
