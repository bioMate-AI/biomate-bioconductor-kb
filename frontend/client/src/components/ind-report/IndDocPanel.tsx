/**
 * Right-panel document viewer + inline feedback surfaces (Appendix B).
 * Port of reference/claude_design/IND_design/ind/DocPanel.jsx → TSX.
 *
 * Wires four feedback surfaces to lib/ind-report-api.ts:
 *   B2 — paragraph edit (onBlur of contentEditable)  → captureEdit
 *   B3 — audit dismissal                             → captureDismissal (in Overlays)
 *   B4 — "+" citation suggest popover                → suggestCitation
 *   B5 — regenerate-with-instruction modal           → regenerateSection
 *
 * Class names preserved verbatim from prototype.
 * CroIcon → lucide-react per the handoff mapping.
 *
 * Editing primitive: TipTap (single-paragraph schema via Document + Paragraph
 * + Text + History extensions) — see EditableParagraph.tsx. Swaps in cleanly
 * for the prototype's contentEditable because the data flow (onBlur → diff →
 * captureEdit) is preserved.
 *
 * NOT WIRED INTO PRODUCTION. Lives in frontend/sandbox/ind-port/.
 */
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Check, Download, Eye, Shield, Signature, X } from "lucide-react";
import {
  captureEdit, suggestCitation, regenerateSection, streamGenerate, sha256Hex,
} from "@/lib/ind-report-api";
import type { AuditFinding, IndDoc } from "./IndSteps";
import { EditableParagraph } from "./EditableParagraph";

// ── data shapes ────────────────────────────────────────────────
export type Region = "FDA" | "EMA" | "NMPA" | "PMDA";

export type DocSubsection = {
  id: string;        // "2.6.1.2"
  title: string;
  wait?: string;     // optional "— waiting on PBPK" placeholder text
};

export type DocSectionData = {
  id: string;                  // "2.6.1"
  title: string;               // "§2.6.1 Overview"
  subs?: DocSubsection[];      // when subdivided
  note?: string;               // inline section-level warning (e.g. "partial")
  coverage: "full" | "partial" | "none";
};

export type DocPanelDoc = IndDoc & {
  version: number;
  shaPrefix: string;
  // bodyByPid: paragraph text keyed by stable paragraph ID ("p-2.6.1.2").
  // Replaces the prototype's window.IND_SECTION_BODY global.
  bodyByPid: Record<string, string>;
  sections: (IndDoc["sections"][number] & { subs?: DocSubsection[]; note?: string })[];
};

type Props = {
  doc: DocPanelDoc;
  audit: { findings: AuditFinding[] };
  region: Region | "ALL";
  onRegionChange: (r: Region | "ALL") => void;
  onSign: () => void;
  onAudit: () => void;
  onVersionsClick: () => void;
  showVersions: boolean;
  onVersionsClose: () => void;
  onDownload: (fmt: "md" | "docx") => void;
  onChatHandoff: () => void;
  projectId: string;
  // Optional org-id for paid-tier isolation; passed through to all feedback calls.
  orgId?: string | null;
  // Header sub-line override; pages pass `${molecule} · ${sponsor} · ${indication}`
  // so the header reflects the active project (closes punch list P2-1).
  headerSub?: string;
  // Audit overlay slot — page passes its <IndAuditOverlay/> here so the overlay
  // renders inside the doc panel (the positioned ancestor for the absolute
  // inset:0 styling). Closes punch list P0-2.
  auditOverlay?: ReactNode;
};

// Helper — pull body text for a paragraph ID
const bodyOf = (doc: DocPanelDoc, pid: string): string =>
  doc.bodyByPid[pid] ?? "";

// Section order — used for the tab strip and scroll navigation.
const SECTION_ORDER = ["2.6.1", "2.6.2", "2.6.3", "2.6.4", "2.6.5", "2.6.6"];

// ── IndDocPanel ────────────────────────────────────────────────
export function IndDocPanel({
  doc, audit, region, onRegionChange, onSign, onAudit,
  onVersionsClick, showVersions, onVersionsClose, onDownload, onChatHandoff,
  projectId, orgId = null, headerSub, auditOverlay,
}: Props) {
  const [editedParas, setEditedParas] = useState<Record<string, boolean>>({});
  const [showCitePop, setShowCitePop] = useState<string | null>(null);
  const [regenSection, setRegenSection] = useState<string | null>(null);
  const [regenInstr, setRegenInstr] = useState("");

  const markEdited = (pid: string) =>
    setEditedParas((prev) => ({ ...prev, [pid]: true }));

  // P2-4: compute coverage per section from bodyByPid instead of hardcoded
  // `coverage: "full"`. Section is "full" when every subsection has prose,
  // "partial" when some do, "none" when zero.
  const computedCoverage = useMemo(() => {
    const out: Record<string, "full" | "partial" | "none"> = {};
    for (const sec of doc.sections) {
      const subs = (sec as { subs?: { id: string }[] }).subs ?? [];
      if (subs.length === 0) {
        out[sec.id] = (sec as { coverage?: "full" | "partial" | "none" }).coverage ?? "none";
        continue;
      }
      const filled = subs.filter((sub) =>
        (doc.bodyByPid[`p-${sub.id}`] ?? "").trim().length > 0,
      ).length;
      out[sec.id] = filled === subs.length ? "full" : filled === 0 ? "none" : "partial";
    }
    return out;
  }, [doc.sections, doc.bodyByPid]);

  // P2-2: real SHA-256 of the canonical doc body (was hardcoded shaPrefix).
  const [docShaShort, setDocShaShort] = useState<string>(doc.shaPrefix ?? "");
  useEffect(() => {
    const canonical = JSON.stringify({
      sections: doc.sections.map((s) => ({ id: s.id, title: s.title })),
      bodyByPid: doc.bodyByPid,
      version: doc.version,
    });
    sha256Hex(canonical).then((hex) => setDocShaShort(hex.slice(0, 12))).catch(() => {});
  }, [doc.sections, doc.bodyByPid, doc.version]);

  return (
    <aside className="ind-doc-panel" data-tour="ind-doc-panel">
      <header className="ind-doc-head">
        <div className="ind-doc-title">
          CTD Module 2.6 — Nonclinical Written Summaries
          <span className="ver-chip" onClick={onVersionsClick} data-tour="ind-version-chip">
            v{doc.version}
          </span>
        </div>
        <div className="ind-doc-sub">{headerSub ?? "BM-0042 · Acme Therapeutics · NSCLC"}</div>
        <div className="ind-doc-meta">
          {doc.signed ? (
            <span className="adapter-badge" title="This document is signed and frozen">
              Signed · v{doc.version}
            </span>
          ) : (
            <span style={{ color: "var(--ind-warn)", fontWeight: 600 }}>Not yet signed</span>
          )}
          <span>·</span>
          <span>FDA · EMA · NMPA · PMDA</span>
          <span>·</span>
          <span>{doc.generatedAt}</span>
        </div>
        <div className="ind-doc-region" data-tour="ind-doc-region">
          <span>Region:</span>
          <select value={region} onChange={(e) => onRegionChange(e.target.value as Region | "ALL")}>
            <option value="FDA">FDA</option>
            <option value="EMA">EMA</option>
            <option value="NMPA">NMPA</option>
            <option value="PMDA">PMDA</option>
            <option value="ALL">All regions (combined)</option>
          </select>
          <span style={{ color: "var(--ind-text-dim)", marginLeft: 8 }}>
            {region === "NMPA"
              ? "incl. GLP declaration"
              : region === "PMDA"
              ? "incl. ethnic bridging"
              : ""}
          </span>
        </div>
      </header>

      <nav className="ind-doc-tabs" data-tour="ind-doc-tabs">
        {SECTION_ORDER.map((id) => {
          const sec = doc.sections.find((s) => s.id === id);
          return (
            <button
              key={id}
              className="ind-doc-tab"
              onClick={() => {
                const el = document.querySelector(`[data-section="${id}"]`);
                if (el) el.scrollIntoView({ block: "start" });
              }}
            >
              §{id}
              <span className={`marker ${computedCoverage[id] ?? "none"}`} />
            </button>
          );
        })}
      </nav>

      {showVersions && <VersionHistory doc={doc} onClose={onVersionsClose} />}

      <div className="ind-doc-body">
        {doc.sections.map((section) => (
          <DocSection
            key={section.id}
            section={section}
            audit={audit}
            doc={doc}
            projectId={projectId}
            orgId={orgId}
            onEdit={markEdited}
            onCiteAdd={(pid) => setShowCitePop(pid)}
            onRegenerate={(secId) => setRegenSection(secId)}
            editedParas={editedParas}
          />
        ))}

        {doc.sections.length > 0 && (
          <div
            style={{
              marginTop: 24, padding: 12,
              background: "var(--ind-bg-sub)", borderRadius: 8, fontSize: 12.5,
            }}
          >
            <b>💬 Discuss in chat →</b> Have a question about a specific result?{" "}
            <button className="ind-link" onClick={onChatHandoff}>
              Open the campaign in BioMate chat
            </button>{" "}
            — campaign context is pre-loaded so you can ask things like "Why is BM-0042 flagged for DILI?"
          </div>
        )}
      </div>

      <footer className="ind-doc-foot" data-tour="ind-doc-foot">
        <div className="row">
          <span>SHA-256: {docShaShort || doc.shaPrefix || "(computing…)"}…</span>
          <span>·</span>
          <span>Generated by BioMate v1.0 · {doc.generatedAt}</span>
          <span>·</span>
          <span>Requires human review</span>
        </div>
        <div className="row actions">
          {!doc.signed ? (
            <span className="mark-unsigned">[Not yet signed]</span>
          ) : (
            <span className="mark-signed">
              Signed by: {doc.signedBy} · Sig {doc.shaPrefix}…
            </span>
          )}
          <span style={{ flex: 1 }} />
          <button className="ind-btn sm" onClick={onAudit}>
            <Shield size={12} /> View audit
          </button>
          <button className="ind-btn sm" onClick={() => onDownload("md")}>
            <Download size={12} /> .md
          </button>
          <button className="ind-btn sm" onClick={() => onDownload("docx")}>
            <Download size={12} /> .docx
          </button>
          {!doc.signed && (
            <button className="ind-btn sm primary" onClick={onSign}>
              <Signature size={12} /> Sign
            </button>
          )}
        </div>
      </footer>

      {showCitePop && (
        <CitePopover
          pid={showCitePop}
          orgId={orgId}
          onClose={() => setShowCitePop(null)}
        />
      )}

      {regenSection && (
        <RegenerateModal
          section={regenSection}
          instruction={regenInstr}
          setInstruction={setRegenInstr}
          orgId={orgId}
          onClose={() => {
            setRegenSection(null);
            setRegenInstr("");
          }}
        />
      )}
      {/* Audit overlay slot — overlays this panel via the existing
          .ind-audit-overlay { position: absolute; inset: 0 } rule, since
          .ind-doc-panel is position:sticky (= a positioned ancestor). */}
      {auditOverlay}
    </aside>
  );
}

// ── DocSection ────────────────────────────────────────────────
type SectionProps = {
  section: DocPanelDoc["sections"][number];
  audit: { findings: AuditFinding[] };
  doc: DocPanelDoc;
  projectId: string;
  orgId: string | null;
  onEdit: (pid: string) => void;
  onCiteAdd: (pid: string) => void;
  onRegenerate: (secId: string) => void;
  editedParas: Record<string, boolean>;
};

function DocSection({
  section, audit, doc, projectId, orgId,
  onEdit, onCiteAdd, onRegenerate, editedParas,
}: SectionProps) {
  const findingsForSection = audit.findings.filter(
    (f) => f.section === `§${section.id}` || f.section.startsWith(`§${section.id}.`)
  );
  const hasMinor = findingsForSection.some((f) => f.severity === "MINOR" && !f.addressed);

  // Wraps the prototype's inline onBlur. Posts the edit to the backend
  // via captureEdit only if the text actually changed.
  const onParaBlur = async (pid: string, original: string, edited: string) => {
    if (edited.trim() === original.trim()) return;
    onEdit(pid);
    try {
      await captureEdit(
        projectId,
        {
          paragraph_id: pid,
          original,
          edited,
          section_type: sectionTypeOf(section.id),
        },
        orgId,
      );
    } catch (err) {
      // Best-effort capture — never block the user's editing flow.
      console.warn("[ind] captureEdit failed:", err);
    }
  };

  return (
    <article
      className={`ind-doc-section ${hasMinor ? "has-finding" : ""}`}
      data-section={section.id}
    >
      <h3>{section.title}</h3>
      {section.subs ? (
        section.subs.map((sub) => {
          const body = bodyOf(doc, `p-${sub.id}`);
          const pid = `p-${sub.id}`;
          const subFinding = findingsForSection.find((f) => f.section === `§${sub.id}`);
          return (
            <div key={sub.id}>
              <h4>
                §{sub.id} {sub.title}
              </h4>
              {body ? (
                <EditableParagraph
                  pid={pid}
                  body={body}
                  edited={editedParas[pid]}
                  onSettled={onParaBlur}
                >
                  {subFinding && (
                    <span
                      className="finding-chip"
                      title={subFinding.desc}
                      onClick={(e) => {
                        e.stopPropagation();
                        window.dispatchEvent(new CustomEvent("ind-open-audit"));
                      }}
                    >
                      ⚠ {subFinding.severity}
                    </span>
                  )}{" "}
                  <span
                    className="cite-add"
                    title="Suggest a citation"
                    onClick={() => onCiteAdd(pid)}
                  >
                    +
                  </span>
                </EditableParagraph>
              ) : (
                <div className="skel">
                  ┄ ┄ ┄ §{sub.id} {sub.wait || "— ready"} ┄ ┄ ┄
                </div>
              )}
              <button className="regen-btn" onClick={() => onRegenerate(sub.id)}>
                ↻ Regenerate ▾
              </button>
            </div>
          );
        })
      ) : (
        <EditableParagraph
          pid={`p-${section.id}`}
          body={bodyOf(doc, `p-${section.id}`)}
          edited={editedParas[`p-${section.id}`]}
          onSettled={onParaBlur}
        >
          {" "}
          <span
            className="cite-add"
            title="Suggest a citation"
            onClick={() => onCiteAdd(`p-${section.id}`)}
          >
            +
          </span>
          {section.note && (
            <span
              className="finding-chip"
              style={{ background: "var(--ind-warn-soft)", color: "var(--ind-warn)" }}
            >
              ⚠ partial
            </span>
          )}
        </EditableParagraph>
      )}
      {section.note && (
        <div
          style={{
            fontSize: 11.5,
            color: "var(--ind-warn)",
            fontStyle: "italic",
            marginTop: 4,
          }}
        >
          ⚠ {section.note}
        </div>
      )}
    </article>
  );
}

// Section type for the feedback API — maps the ID like "2.6.6.3" to the
// canonical section_type field stored in customer_pairs.jsonl.
function sectionTypeOf(sectionId: string): string {
  if (sectionId.startsWith("2.6.6")) return "tox_overview";
  if (sectionId.startsWith("2.6.4")) return "pk_overview";
  if (sectionId.startsWith("2.6.5")) return "pk_overview";
  if (sectionId.startsWith("2.6.2")) return "pharm_overview";
  if (sectionId.startsWith("2.6.3")) return "pharm_overview";
  return "overview";
}

// ── CitePopover (B4) ──────────────────────────────────────────
function CitePopover({
  pid, orgId, onClose,
}: {
  pid: string;
  orgId: string | null;
  onClose: () => void;
}) {
  const [gid, setGid] = useState("");
  const [why, setWhy] = useState("");
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    // Position next to the cite-add icon if findable (same logic as prototype).
    const anchor = document.querySelector(`[data-pid="${pid}"] .cite-add`);
    if (anchor && ref.current) {
      const r = anchor.getBoundingClientRect();
      const panel = anchor.closest(".ind-doc-panel");
      if (!panel) return;
      const panelRect = (panel as HTMLElement).getBoundingClientRect();
      ref.current.style.left = `${r.left - panelRect.left + 20}px`;
      ref.current.style.top = `${r.top - panelRect.top + 20}px`;
    }
  }, [pid]);

  const submit = async (documentOnly: boolean) => {
    if (!gid.trim()) {
      onClose();
      return;
    }
    try {
      await suggestCitation(
        { guideline_id: gid, rationale: why, document_only: documentOnly },
        orgId,
      );
    } catch (err) {
      console.warn("[ind] suggestCitation failed:", err);
    }
    onClose();
  };

  return (
    <>
      <div style={{ position: "absolute", inset: 0, zIndex: 25 }} onClick={onClose} />
      <div
        className="cite-popover"
        ref={ref}
        onClick={(e) => e.stopPropagation()}
        data-tour="ind-cite-popover"
      >
        <h4>Suggest a citation</h4>
        <div className="ind-field">
          <label>Guideline ID</label>
          <input
            value={gid}
            onChange={(e) => setGid(e.target.value)}
            placeholder="e.g. CDE 化学药物非临床研究技术指导原则"
          />
        </div>
        <div className="ind-field">
          <label>Why it applies</label>
          <textarea
            value={why}
            onChange={(e) => setWhy(e.target.value)}
            rows={2}
            style={{ fontFamily: "inherit" }}
          />
        </div>
        <div style={{ display: "flex", gap: 8, marginTop: 4 }}>
          <button className="ind-btn sm" onClick={() => submit(true)}>
            Add to document only
          </button>
          <button className="ind-btn sm primary" onClick={() => submit(false)}>
            Also suggest for BioMate
          </button>
        </div>
      </div>
    </>
  );
}

// ── RegenerateModal (B5) ──────────────────────────────────────
//
// Submits BOTH:
//   1. The prompt-tuning signal (regenerateSection POST → JSONL capture)
//   2. The actual LLM generation via SSE (streamGenerate)
//
// While the stream runs the modal stays open and shows:
//   - a phase banner ("Loading regulatory adapter…" → "Drafting…" → "Validating…")
//   - the partial text accumulating in real time
//
// The customer sees structured progress instead of 30-80s of silence; on error
// the modal reports the fallback path (Gemini) was triggered.
function RegenerateModal({
  section, instruction, setInstruction, orgId, onClose,
}: {
  section: string;
  instruction: string;
  setInstruction: (s: string) => void;
  orgId: string | null;
  onClose: () => void;
}) {
  const [streaming, setStreaming] = useState(false);
  const [phaseMsg, setPhaseMsg] = useState<string>("");
  const [draftText, setDraftText] = useState<string>("");
  const [errorMsg, setErrorMsg] = useState<string>("");
  const [done, setDone] = useState(false);

  const submit = async () => {
    setStreaming(true);
    setPhaseMsg("Starting…");
    setDraftText("");
    setErrorMsg("");
    setDone(false);
    // Fire-and-forget the prompt-tuning signal capture
    if (instruction.trim()) {
      regenerateSection(section, { instruction }, orgId).catch((err) =>
        console.warn("[ind] regenerateSection signal failed:", err),
      );
    }
    try {
      await streamGenerate(
        {
          section_type: section,
          user_prompt: instruction.trim() || undefined,
          orgId,
        },
        (e) => {
          if (e.kind === "phase") {
            setPhaseMsg(e.message ?? e.phase);
            if (e.phase === "error") setErrorMsg(e.reason ?? "generation failed");
            if (e.phase === "complete") setDone(true);
          } else {
            setDraftText((d) => d + e.text);
          }
        },
      );
    } catch (err: any) {
      setErrorMsg(err?.message ?? "stream failed");
    } finally {
      setStreaming(false);
    }
  };

  const idle = !streaming && !done && !errorMsg;

  return (
    <div className="modal-backdrop" onClick={streaming ? undefined : onClose} style={{ zIndex: 50 }}>
      <div
        className="modal"
        onClick={(e) => e.stopPropagation()}
        style={{ background: "white", borderRadius: 10, padding: 18, maxWidth: 520, width: "92%" }}
        data-tour="ind-regenerate-modal"
      >
        <h3 style={{ fontSize: 14, fontWeight: 700, marginBottom: 10 }}>
          Regenerate §{section}
        </h3>
        {idle && (
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {/* P1-8: controlled radios — "as is" clears instruction, the
                other focuses the textarea. Was uncontrolled defaultChecked
                that did nothing. */}
            <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 13 }}>
              <input
                type="radio" name="regen"
                checked={!instruction}
                onChange={() => setInstruction("")}
              />
              Regenerate as is
            </label>
            <label style={{ display: "flex", gap: 8, alignItems: "flex-start", fontSize: 13 }}>
              <input
                type="radio" name="regen"
                checked={!!instruction}
                onChange={() => { if (!instruction) setInstruction(" "); }}
              />
              <span style={{ flex: 1 }}>
                Regenerate with instruction:
                <textarea
                  value={instruction}
                  onChange={(e) => setInstruction(e.target.value)}
                  placeholder="e.g. Use more conservative language about the Ames equivocal finding"
                  rows={3}
                  style={{
                    width: "100%", marginTop: 4, padding: 8,
                    border: "1px solid var(--ind-border-strong)", borderRadius: 6,
                    fontFamily: "inherit", fontSize: 12.5,
                  }}
                />
              </span>
            </label>
          </div>
        )}

        {!idle && (
          <div
            data-testid="regen-stream-area"
            style={{
              marginTop: 4, padding: 12, borderRadius: 8,
              background: errorMsg ? "#fef2f2" : "#f0fdf4",
              borderLeft: `3px solid ${errorMsg ? "#ef4444" : "#10b981"}`,
              minHeight: 80,
            }}
          >
            <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 8, display: "flex", alignItems: "center", gap: 6 }}>
              {streaming && (
                <span style={{
                  display: "inline-block", width: 12, height: 12,
                  border: "2px solid currentColor", borderRightColor: "transparent",
                  borderRadius: "50%", animation: "spin 0.8s linear infinite",
                }} />
              )}
              <span data-testid="regen-phase-msg">{phaseMsg}</span>
            </div>
            {draftText && (
              <div
                data-testid="regen-draft-text"
                style={{
                  fontSize: 12.5, lineHeight: 1.55,
                  whiteSpace: "pre-wrap",
                  color: "var(--ind-text, #111)",
                }}
              >
                {draftText}
                {streaming && <span style={{ opacity: 0.5 }}>▌</span>}
              </div>
            )}
            {errorMsg && (
              <div style={{ fontSize: 12, color: "#ef4444", marginTop: 6 }}>
                {errorMsg} — production would fall back to Gemini Flash.
              </div>
            )}
          </div>
        )}

        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 14 }}>
          {idle && (
            <>
              <button className="ind-btn" onClick={onClose}>Cancel</button>
              <button className="ind-btn primary" onClick={submit}>↻ Regenerate</button>
            </>
          )}
          {(done || errorMsg) && (
            <button className="ind-btn primary" onClick={onClose}>Close</button>
          )}
        </div>
      </div>
    </div>
  );
}

// ── VersionHistory ───────────────────────────────────────────
function VersionHistory({ doc, onClose }: { doc: DocPanelDoc; onClose: () => void }) {
  return (
    <>
      <div style={{ position: "absolute", inset: 0, zIndex: 25 }} onClick={onClose} />
      <div className="version-popover" data-tour="ind-version-history">
        <h4 style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 8 }}>
          Document versions — BM-0042
        </h4>
        <div className="version-row">
          <div className="head">
            <span
              style={{
                background: "var(--ind-accent)", color: "white",
                padding: "1px 7px", borderRadius: 3, fontSize: 10.5, fontWeight: 700,
              }}
            >
              v{doc.version}
            </span>
            <span>Current</span>
            <span style={{ color: "var(--ind-warn)" }}>· Not yet signed</span>
          </div>
          <div className="meta">
            SHA-256: {doc.shaPrefix}… · Sections: §2.6.1–§2.6.6 · NMPA + PMDA added
          </div>
          <div style={{ fontSize: 11.5, color: "var(--ind-text-muted)", marginTop: 2 }}>
            Generated {doc.generatedAt}
          </div>
        </div>
        <div className="version-row">
          <div className="head">
            <span
              style={{
                background: "var(--ind-text-dim)", color: "white",
                padding: "1px 7px", borderRadius: 3, fontSize: 10.5, fontWeight: 700,
              }}
            >
              v1
            </span>
            <span style={{ color: "var(--ind-text-muted)" }}>Superseded</span>
            <span style={{ color: "var(--ind-ok)" }}>· Signed</span>
          </div>
          <div className="meta">
            SHA-256: 7e3a11b2… · Sections: §2.6.1–§2.6.3 · FDA + EMA only
          </div>
          <div style={{ fontSize: 11.5, marginTop: 2 }}>
            2026-05-01 · Dr. Jane Smith · Sig 8f2a3c…
            <button className="ind-link" style={{ marginLeft: 8, fontSize: 11.5 }}>
              Download v1 DOCX
            </button>
          </div>
        </div>
        <div
          style={{
            marginTop: 10, padding: 10, fontSize: 11.5,
            color: "var(--ind-text-muted)",
            background: "var(--ind-bg-sub)", borderRadius: 6, lineHeight: 1.5,
          }}
        >
          Creating a new version supersedes the signed v1. The v1 signature record and frozen
          hash remain in the audit trail.
        </div>
      </div>
    </>
  );
}
