/**
 * RerunParamsModal — opens when the user clicks "Re-run with new params"
 * on Step 2 (ADMET) or Step 3 (PBPK). Fetches current run params, lets
 * the user edit, POSTs to /rerun/admet or /rerun/pbpk, then signals
 * the parent to re-fetch pipeline data.
 *
 * Closes the A2/A3 tier item from
 * docs/20260603_IND_MODULE_HONEST_AUDIT.md — three "Re-run with new
 * params" buttons had no onClick. They do now.
 */
import { useEffect, useState } from "react";
import { X } from "lucide-react";
import {
  getAdmetParams, getPbpkParams, rerunAdmet, rerunPbpk,
  type AdmetRerunParams, type PbpkRerunParams,
} from "@/lib/ind-report-api";

export function RerunParamsModal({
  step, projectId, onCancel, onComplete,
}: {
  step: "admet" | "pbpk";
  projectId: string;
  onCancel: () => void;
  onComplete: () => void;
}) {
  const [admetParams, setAdmetParams] = useState<AdmetRerunParams | null>(null);
  const [pbpkParams, setPbpkParams] = useState<PbpkRerunParams | null>(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [err, setErr] = useState<string>("");

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        if (step === "admet") {
          const p = await getAdmetParams(projectId);
          if (!cancelled) setAdmetParams(p);
        } else {
          const p = await getPbpkParams(projectId);
          if (!cancelled) setPbpkParams(p);
        }
      } catch (e: any) {
        if (!cancelled) setErr(String(e?.message ?? e));
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [step, projectId]);

  // ESC closes the modal
  useEffect(() => {
    const h = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !submitting) onCancel();
    };
    document.addEventListener("keydown", h);
    return () => document.removeEventListener("keydown", h);
  }, [onCancel, submitting]);

  const submit = async () => {
    setSubmitting(true);
    setErr("");
    try {
      if (step === "admet" && admetParams) {
        await rerunAdmet(projectId, admetParams);
      } else if (step === "pbpk" && pbpkParams) {
        await rerunPbpk(projectId, pbpkParams);
      }
      onComplete();
    } catch (e: any) {
      setErr(String(e?.message ?? e));
      setSubmitting(false);
    }
  };

  return (
    <div
      className="modal-backdrop"
      onClick={submitting ? undefined : onCancel}
      style={{
        position: "fixed", inset: 0, zIndex: 60,
        background: "rgba(0,0,0,0.35)",
        display: "flex", alignItems: "center", justifyContent: "center",
      }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          background: "var(--ind-bg, white)",
          border: "1px solid var(--ind-border, #e5e7eb)",
          borderRadius: 8,
          width: "min(520px, 92vw)",
          maxHeight: "86vh", overflowY: "auto",
          padding: 20, position: "relative",
          boxShadow: "0 10px 40px rgba(0,0,0,0.18)",
        }}
      >
        <button
          onClick={onCancel}
          disabled={submitting}
          style={{
            position: "absolute", top: 12, right: 12,
            background: "none", border: "none", cursor: "pointer",
            color: "var(--ind-text-dim)",
          }}
        >
          <X size={18} />
        </button>
        <h3 style={{ marginTop: 0 }}>
          Re-run {step === "admet" ? "ADMET screening" : "PBPK qualification"} with new params
        </h3>
        <p style={{ fontSize: 13, color: "var(--ind-text-muted)", marginBottom: 14 }}>
          The pipeline will recompute with the values below. The audit chain
          captures the prior parameters + result so you can diff later.
        </p>
        {loading && <div style={{ padding: 20 }}>Loading current params…</div>}
        {err && <div style={{ color: "var(--ind-err)", marginBottom: 10, fontSize: 13 }}>{err}</div>}
        {!loading && step === "admet" && admetParams && (
          <AdmetForm params={admetParams} setParams={setAdmetParams} />
        )}
        {!loading && step === "pbpk" && pbpkParams && (
          <PbpkForm params={pbpkParams} setParams={setPbpkParams} />
        )}
        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 18 }}>
          <button className="ind-btn" onClick={onCancel} disabled={submitting}>
            Cancel
          </button>
          <button
            className="ind-btn primary"
            onClick={submit}
            disabled={submitting || loading || !!err}
          >
            {submitting ? "Re-running…" : "Re-run"}
          </button>
        </div>
      </div>
    </div>
  );
}

function AdmetForm({
  params, setParams,
}: {
  params: AdmetRerunParams;
  setParams: (p: AdmetRerunParams) => void;
}) {
  return (
    <div style={{ display: "grid", gap: 10 }}>
      <Field label="hERG IC50 threshold (µM)" hint="compounds with hERG IC50 below this fail the gate">
        <input
          type="number" step="0.1" min={0.1}
          value={params.herg_threshold_uM}
          onChange={(e) => setParams({ ...params, herg_threshold_uM: parseFloat(e.target.value) })}
          style={inputStyle}
        />
      </Field>
      <Field label="Max DILI score" hint="0.0 – 1.0">
        <input
          type="number" step="0.05" min={0} max={1}
          value={params.dili_score_max}
          onChange={(e) => setParams({ ...params, dili_score_max: parseFloat(e.target.value) })}
          style={inputStyle}
        />
      </Field>
      <Field label="Max Ro5 violations">
        <input
          type="number" step="1" min={0} max={4}
          value={params.ro5_max_violations}
          onChange={(e) => setParams({ ...params, ro5_max_violations: parseInt(e.target.value, 10) })}
          style={inputStyle}
        />
      </Field>
      <Field label="Ames panel" hint="strains tested in the in silico Ames panel">
        <input
          type="text"
          value={params.ames_panel.join(", ")}
          onChange={(e) => setParams({ ...params, ames_panel: e.target.value.split(",").map((s) => s.trim()).filter(Boolean) })}
          style={inputStyle}
        />
      </Field>
    </div>
  );
}

function PbpkForm({
  params, setParams,
}: {
  params: PbpkRerunParams;
  setParams: (p: PbpkRerunParams) => void;
}) {
  return (
    <div style={{ display: "grid", gap: 10 }}>
      <Field label="EMA within-2-fold threshold (%)" hint="model fails qualification if Cmax fraction within 2-fold is below this">
        <input
          type="number" step="1" min={30} max={95}
          value={params.ema_threshold_pct}
          onChange={(e) => setParams({ ...params, ema_threshold_pct: parseFloat(e.target.value) })}
          style={inputStyle}
        />
      </Field>
      <Field label="Compartments">
        <select
          value={params.n_compartments}
          onChange={(e) => setParams({ ...params, n_compartments: parseInt(e.target.value, 10) })}
          style={inputStyle}
        >
          <option value={1}>1 — central + elimination</option>
          <option value={2}>2 — central + peripheral</option>
          <option value={3}>3 — central + peripheral + deep</option>
        </select>
      </Field>
      <Field label="Include efflux (P-gp / BCRP)">
        <input
          type="checkbox"
          checked={params.include_efflux}
          onChange={(e) => setParams({ ...params, include_efflux: e.target.checked })}
          style={{ width: 16, height: 16 }}
        />
      </Field>
      <Field label="Model name" hint="appears in §2.6.2 narrative">
        <input
          type="text"
          value={params.model}
          onChange={(e) => setParams({ ...params, model: e.target.value })}
          style={inputStyle}
        />
      </Field>
    </div>
  );
}

const inputStyle: React.CSSProperties = {
  width: "100%", padding: "6px 8px", fontSize: 13,
  border: "1px solid var(--ind-border, #d1d5db)", borderRadius: 4,
};

function Field({
  label, hint, children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <label style={{ display: "block" }}>
      <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 3 }}>{label}</div>
      {hint && (
        <div style={{ fontSize: 11, color: "var(--ind-text-muted)", marginBottom: 4 }}>
          {hint}
        </div>
      )}
      {children}
    </label>
  );
}
