/**
 * Sign-and-freeze + Audit-trail + Empty-state overlays.
 * Port of reference/claude_design/IND_design/ind/Overlays.jsx → TSX.
 *
 * Wires the audit-dismissal flow to lib/ind-report-api.ts:captureDismissal
 * (Appendix B surface B3).
 *
 * Class names preserved verbatim; CroIcon → lucide-react per the handoff.
 *
 * NOT WIRED INTO PRODUCTION. Lives in frontend/sandbox/ind-port/.
 */
import { useEffect, useRef, useState } from "react";
import { Check, ChevronRight, Download, X } from "lucide-react";
import {
  captureDismissal, signDocument, sha256Hex,
  type DismissalReason, type SignResponse,
} from "@/lib/ind-report-api";
import type { AuditFinding, IndDoc } from "./IndSteps";

// ── Sign & Freeze ──────────────────────────────────────────────
//
// Closes punch list P0-1 (sign was a stub). doSign() now:
//   1. Computes SHA-256 of the canonical document body
//   2. POSTs to /api/ind-report/projects/:id/sign with the 6-digit TOTP
//      + signer attestation + adapter-version map
//   3. Backend verifies TOTP via AuthService.verify_totp (or dev fallback)
//   4. On 401: red TOTP boxes + retry message (modal stays open)
//   5. On 200: success card shows the real signature_id + signed_at
//
// The countdown timer is a real RFC 6238 TOTP window (30s steps from
// Math.floor(Date.now()/1000) % 30), not a cosmetic loop.
export function IndSignOverlay({
  doc, projectId, onCancel, onSigned, orgId = null,
}: {
  doc: IndDoc & { shaPrefix?: string; version?: number; bodyByPid?: Record<string, string> };
  projectId: string;
  onCancel: () => void;
  onSigned?: (info: { title: string; creds: string; scope: string; sig?: SignResponse }) => void;
  orgId?: string | null;
}) {
  const [step, setStep] = useState<"sign" | "success">("sign");
  const [title, setTitle] = useState("Director, Computational Pharmacology");
  const [creds, setCreds] = useState("PhD Pharmacology · 10 years IND experience");
  const [scope, setScope] = useState("§2.6.1–§2.6.6 nonclinical pharmacology");
  const [totp, setTotp] = useState<string[]>(["", "", "", "", "", ""]);
  const [timer, setTimer] = useState(() => 30 - (Math.floor(Date.now() / 1000) % 30));
  const [submitting, setSubmitting] = useState(false);
  const [errMsg, setErrMsg] = useState<string>("");
  const [sigResp, setSigResp] = useState<SignResponse | null>(null);
  const inputRefs = useRef<(HTMLInputElement | null)[]>([]);

  // Real RFC 6238 TOTP window: refresh every second, snap to 30s boundaries.
  useEffect(() => {
    if (step !== "sign") return;
    const t = setInterval(() => {
      const sec = 30 - (Math.floor(Date.now() / 1000) % 30);
      setTimer(sec);
    }, 1000);
    return () => clearInterval(t);
  }, [step]);

  const allFilled = totp.every((t) => t.length === 1);

  const setDigit = (i: number, v: string) => {
    const next = [...totp];
    next[i] = v.slice(-1);
    setTotp(next);
    setErrMsg("");
    if (v && i < 5) inputRefs.current[i + 1]?.focus();
  };

  const doSign = async () => {
    if (!allFilled || submitting) return;
    setSubmitting(true);
    setErrMsg("");
    try {
      const canonical = JSON.stringify({
        sections: doc.sections?.map?.((s: any) => ({ id: s.id, title: s.title })) ?? [],
        bodyByPid: (doc as any).bodyByPid ?? {},
        version: doc.version ?? 0,
      });
      const docHash = await sha256Hex(canonical);
      const resp = await signDocument(
        projectId,
        {
          totp_code: totp.join(""),
          signer_title: title,
          signer_creds: creds,
          signature_scope: scope,
          document_sha256: docHash,
          adapter_versions: {},
        },
        orgId,
      );
      setSigResp(resp);
      setStep("success");
      setTimeout(() => onSigned?.({ title, creds, scope, sig: resp }), 100);
    } catch (e: any) {
      const msg = String(e?.message ?? e);
      if (msg.includes("401") || msg.toLowerCase().includes("totp")) {
        setErrMsg("Invalid TOTP code — check your authenticator and try again.");
      } else {
        setErrMsg(msg);
      }
      // Clear digits so user can retype
      setTotp(["", "", "", "", "", ""]);
      inputRefs.current[0]?.focus();
    } finally {
      setSubmitting(false);
    }
  };

  if (step === "success") {
    return (
      <div className="sign-overlay" data-tour="ind-sign-success">
        <div className="sign-card">
          <div className="sign-success">
            <div className="check">
              <Check size={28} strokeWidth={3} />
            </div>
            <h3>Signed</h3>
            <div className="summary">
              Document frozen · SHA-256 {sigResp?.document_sha256_short ?? "(local)"} · version v{doc.version ?? 2}
              <br />
              Signed by: {title}
              <br />
              Sig ID: {sigResp?.signature_id?.slice(0, 12) ?? "pending"}… · {sigResp?.signed_at ?? new Date().toISOString()}
            </div>
            <div className="actions">
              <button className="ind-btn primary">
                <Download size={13} /> Download DOCX
              </button>
              <button className="ind-btn">
                <Download size={13} /> Download Audit Trail PDF
              </button>
              <button className="ind-btn" onClick={onCancel}>
                Close
              </button>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="sign-overlay" data-tour="ind-sign-overlay" onClick={onCancel}>
      <div className="sign-card" onClick={(e) => e.stopPropagation()}>
        <div className="sign-head">
          <h2>Electronic Signature</h2>
          <div className="sub">21 CFR Part 11 §11.200</div>
        </div>
        <div className="sign-body">
          <div className="sign-section">
            <h3>Document</h3>
            <div className="sign-doc-card">
              <b>BM-0042</b> · §2.6.1–§2.6.6 · v{doc.version ?? 2} · {doc.characters.toLocaleString()} characters
              <br />
              <span className="mono">SHA-256: {doc.shaPrefix ?? ""}e8b4f72a…</span>
            </div>
          </div>

          <div className="sign-section">
            <h3>Meaning of this signature</h3>
            <div className="sign-meaning">
              I have reviewed and approve the <b>BM-0042</b> IND §2.6.1–§2.6.6 nonclinical written
              summary package for submission to FDA/EMA/NMPA/PMDA. This document represents my
              scientific judgment and was generated using validated computational methods per
              FDA/EMA AI Guidance (January 2026).
            </div>
            <div className="note">This statement is permanently recorded and cannot be changed.</div>
          </div>

          <div className="sign-section">
            <h3>
              Reviewer credentials{" "}
              <span style={{ textTransform: "none", fontWeight: 400, color: "var(--ind-text-dim)" }}>
                (recommended for IND actions)
              </span>
            </h3>
            <div className="sign-creds">
              <div className="ind-field">
                <label>Title / Role</label>
                <input value={title} onChange={(e) => setTitle(e.target.value)} />
              </div>
              <div className="ind-field">
                <label>Credentials</label>
                <input value={creds} onChange={(e) => setCreds(e.target.value)} />
              </div>
              <div className="ind-field full">
                <label>Review scope</label>
                <input value={scope} onChange={(e) => setScope(e.target.value)} />
              </div>
            </div>
            <div className="note">These are recorded in the frozen document.</div>
          </div>

          <div className="sign-section">
            <h3>6-digit authenticator code</h3>
            <div className="sign-totp">
              <div className="totp-input">
                {totp.map((d, i) => (
                  <input
                    key={i}
                    ref={(el) => {
                      inputRefs.current[i] = el;
                    }}
                    inputMode="numeric"
                    maxLength={1}
                    value={d}
                    onChange={(e) => setDigit(i, e.target.value.replace(/\D/g, ""))}
                    onKeyDown={(e) => {
                      if (e.key === "Backspace" && !d && i > 0) {
                        inputRefs.current[i - 1]?.focus();
                      }
                    }}
                  />
                ))}
              </div>
              <div className="totp-timer">refreshes in {timer}s</div>
            </div>
            {errMsg && (
              <div
                role="alert"
                data-testid="sign-totp-error"
                style={{
                  marginTop: 8, padding: "8px 10px", borderRadius: 6,
                  background: "#fef2f2", color: "#b91c1c",
                  fontSize: 12, lineHeight: 1.5,
                  border: "1px solid #fecaca",
                }}
              >
                {errMsg}
              </div>
            )}
          </div>
        </div>
        <div className="sign-foot">
          <button className="ind-btn" onClick={onCancel} disabled={submitting}>
            Cancel
          </button>
          <button
            className="ind-btn primary"
            onClick={doSign}
            disabled={!allFilled || submitting}
            data-testid="sign-submit"
          >
            {submitting ? "Verifying…" : "Sign and freeze →"}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Audit Trail Overlay ────────────────────────────────────────
export type AuditFindingWithMeta = AuditFinding & {
  id?: string;
  rule_id?: string;
  title?: string;
};

type AuditOverlayProps = {
  audit: { findings: AuditFindingWithMeta[]; chainRecords?: number; lastVerified?: string };
  onClose: () => void;
  onJumpTo: (section: string) => void;
  orgId?: string | null;
};

// Maps the prototype's 4-key reason codes to the backend's enum strings.
const REASON_MAP: Record<string, DismissalReason> = {
  na: "not_applicable",
  done: "already_addressed",
  accept: "acceptable_risk",
  disag: "disagree",
};

export function IndAuditOverlay({
  audit, onClose, onJumpTo, orgId = null,
}: AuditOverlayProps) {
  const [dismissingId, setDismissingId] = useState<number | null>(null);
  const [reason, setReason] = useState<string | null>(null);
  const [filter, setFilter] = useState<"all" | AuditFinding["severity"]>("all");
  // P1-2: optimistic dismissal — fade card + show "Dismissed" badge before
  // the POST completes; roll back on failure.
  const [dismissed, setDismissed] = useState<Set<number>>(new Set());

  const filtered =
    filter === "all" ? audit.findings : audit.findings.filter((f) => f.severity === filter);

  const sevSummary = (["CRITICAL", "MAJOR", "MINOR", "INFO"] as const).map((sev) => ({
    sev,
    count: audit.findings.filter((f, idx) =>
      f.severity === sev && !f.addressed && !dismissed.has(idx),
    ).length,
  }));

  const submitDismiss = async (i: number, finding: AuditFindingWithMeta) => {
    if (!reason) return;
    setDismissed((prev) => new Set(prev).add(i));
    setDismissingId(null);
    setReason(null);
    try {
      await captureDismissal(
        finding.id ?? `finding-${i}`,
        {
          rule_id: finding.rule_id ?? "unknown",
          section_type: sectionTypeOf(finding.section),
          reason: REASON_MAP[reason],
        },
        orgId,
      );
    } catch (err) {
      console.warn("[ind] captureDismissal failed:", err);
      setDismissed((prev) => {
        const next = new Set(prev);
        next.delete(i);
        return next;
      });
    }
  };

  return (
    <div className="ind-audit-overlay" data-tour="ind-audit-overlay">
      <header className="ind-audit-head">
        <h3>Regulatory Audit</h3>
        <button className="ind-btn sm" onClick={onClose}>
          <X size={12} /> Close
        </button>
      </header>
      <div className="ind-audit-meta">
        {sevSummary.map((s) => (
          <span
            key={s.sev}
            className={`audit-chip ${s.sev.toLowerCase()}`}
            style={{ opacity: s.count ? 1 : 0.5 }}
          >
            {s.count > 0 ? "⚠ " : "○ "}
            {s.count} {s.sev}
          </span>
        ))}
        <span style={{ flex: 1 }} />
        <select
          value={filter}
          onChange={(e) => setFilter(e.target.value as typeof filter)}
          style={{
            padding: "3px 6px", fontSize: 11.5, borderRadius: 4,
            border: "1px solid var(--ind-border)", fontFamily: "inherit", background: "white",
          }}
        >
          <option value="all">All findings</option>
          <option value="CRITICAL">CRITICAL</option>
          <option value="MAJOR">MAJOR</option>
          <option value="MINOR">MINOR</option>
          <option value="INFO">INFO</option>
        </select>
      </div>
      <div className="ind-audit-list">
        {filtered.map((f, i) => {
          const isDismissedLocal = dismissed.has(i);
          const isFaded = f.addressed || isDismissedLocal;
          return (
          <div
            key={i}
            className={`ind-audit-finding ${f.severity.toLowerCase()}${isFaded ? " addressed" : ""}`}
            data-testid={`audit-finding-${i}`}
          >
            <div className="ind-audit-finding-head">
              <span className="sec">{f.section}</span>
              <span className={`audit-chip ${f.severity.toLowerCase()}`}>{f.severity}</span>
              {f.addressed && (
                <span style={{ fontSize: 11, color: "var(--ind-ok)", fontWeight: 600 }}>
                  ✓ Addressed
                </span>
              )}
              {isDismissedLocal && !f.addressed && (
                <span
                  data-testid={`audit-dismissed-badge-${i}`}
                  style={{ fontSize: 11, color: "var(--ind-text-muted)", fontWeight: 600 }}
                >
                  ✓ Dismissed
                </span>
              )}
            </div>
            {f.title && <div className="title">{f.title}</div>}
            <div className="desc">{f.desc}</div>
            <div className="acts">
              <button className="ind-link" onClick={() => onJumpTo(f.section)}>
                → Jump to section
              </button>
              {!isFaded && (
                <button
                  className="ind-link"
                  onClick={() => {
                    setDismissingId(i);
                    setReason(null);
                  }}
                >
                  Dismiss
                </button>
              )}
            </div>
            {dismissingId === i && (
              <div className="ind-dismiss-picker" data-tour="ind-dismiss-picker">
                <h4>Dismiss this finding because…</h4>
                {(
                  [
                    ["na", "Not applicable to this product (e.g. topical → no hERG required)"],
                    ["done", "Already addressed elsewhere in the document"],
                    ["accept", "Acceptable risk — documented in Discussion"],
                    ["disag", "Disagree with the rule (regulatory judgment)"],
                  ] as const
                ).map(([k, lbl]) => (
                  <label key={k}>
                    <input
                      type="radio"
                      name="dismiss"
                      value={k}
                      checked={reason === k}
                      onChange={() => setReason(k)}
                    />
                    {lbl}
                  </label>
                ))}
                <div style={{ display: "flex", gap: 6, marginTop: 10 }}>
                  <button className="ind-btn sm" onClick={() => setDismissingId(null)}>
                    Cancel
                  </button>
                  <button
                    className="ind-btn sm primary"
                    disabled={!reason}
                    onClick={() => submitDismiss(i, f)}
                  >
                    Dismiss with reason
                  </button>
                </div>
              </div>
            )}
          </div>
          );
        })}
      </div>
      <footer className="ind-audit-foot">
        <span>
          Chain integrity: <b style={{ color: "var(--ind-ok)" }}>✓ Valid</b>
          {audit.chainRecords && audit.lastVerified
            ? ` (${audit.chainRecords} records · last verified ${audit.lastVerified})`
            : ""}
        </span>
        <span style={{ flex: 1 }} />
        <button className="ind-link">View full audit log →</button>
        <button className="ind-btn sm">
          <Download size={12} /> Export PDF
        </button>
      </footer>
    </div>
  );
}

// Reuse the section_type mapper from the DocPanel layer (kept local to
// avoid a cross-component import cycle).
function sectionTypeOf(sectionRef: string): string {
  // sectionRef like "§2.6.6.3"
  const id = sectionRef.replace("§", "");
  if (id.startsWith("2.6.6")) return "tox_overview";
  if (id.startsWith("2.6.4")) return "pk_overview";
  if (id.startsWith("2.6.5")) return "pk_overview";
  if (id.startsWith("2.6.2")) return "pharm_overview";
  if (id.startsWith("2.6.3")) return "pharm_overview";
  return "overview";
}

// ── Empty / onboarding ─────────────────────────────────────────
export type ReferenceCompound = { id: string; name: string; tag: string; desc: string };

export function IndEmptyState({
  onStart,
  onPickReference,
  referenceCompounds,
}: {
  onStart: () => void;
  onPickReference: (id: string) => void;
  referenceCompounds: ReferenceCompound[];
}) {
  return (
    <div className="ind-empty" data-tour="ind-empty">
      <div className="ind-empty-card">
        <h1>BioMate IND Report</h1>
        <p className="lede">
          Generate a complete ICH M4 CTD Module 2.6 nonclinical written summary in under 10 minutes.
        </p>
        <div className="ind-empty-bullets">
          <div className="b">
            <span className="check">✓</span>§2.6.1–§2.6.6 · FDA · EMA · NMPA · PMDA
          </div>
          <div className="b">
            <span className="check">✓</span>ADMET · PBPK · Lead ranking · Validated models
          </div>
          <div className="b">
            <span className="check">✓</span>21 CFR Part 11 eSig · SHA-256 audit trail · DOCX
          </div>
        </div>
        <button className="ind-empty-start" onClick={onStart}>
          Start with a compound <ChevronRight size={14} />
        </button>

        <div className="ind-empty-divider">
          <span>Or try a reference compound:</span>
        </div>

        <div className="ind-ref-row">
          {referenceCompounds.map((c) => (
            <button key={c.id} className="ind-ref-chip" onClick={() => onPickReference(c.id)}>
              <span className="nm">{c.name}</span>
              <span className="tag">{c.tag}</span>
              <span className="desc">{c.desc}</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
