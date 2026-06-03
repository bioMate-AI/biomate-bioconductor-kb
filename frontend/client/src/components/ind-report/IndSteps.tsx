/**
 * 5 pipeline-step components for the IND Report.
 * Port of reference/claude_design/IND_design/ind/Steps.jsx → TSX.
 *
 * Class names preserved verbatim so styles-ind.css applies unchanged.
 * CroIcon → lucide-react per the handoff mapping.
 *
 * NOT WIRED INTO PRODUCTION. Lives in frontend/sandbox/ind-port/ until
 * the full port is validated end-to-end.
 */
import { useState, type ReactNode } from "react";
import { Check, TriangleAlert, Upload, Eye, Download, Signature } from "lucide-react";

// ── shared types ───────────────────────────────────────────────
type StepState = "pending" | "running" | "complete" | "blocked" | "failed";

type StepShellProps = {
  num: ReactNode;
  title: string;
  state: StepState;
  statusText: ReactNode;
  expanded?: boolean;
  onToggle?: () => void;
  expandedHint?: string;
  children: ReactNode;
};

// ── StatusPill ─────────────────────────────────────────────────
function StatusPill({ state, text }: { state: StepState; text: ReactNode }) {
  return (
    <span className={`ind-step-status ${state === "complete" ? "ok" : state}`}>
      {state === "running" && <span className="spinner-sm" />}
      {state === "complete" && <Check size={13} />}
      {state === "blocked" && <TriangleAlert size={13} />}
      {text}
    </span>
  );
}

// ── StepShell ──────────────────────────────────────────────────
function StepShell({ num, title, state, statusText, children, expanded, onToggle }: StepShellProps) {
  return (
    <section className={`ind-step ${state}${expanded ? " expanded" : ""}`}>
      <header className="ind-step-head" onClick={onToggle}>
        <div className="ind-step-num">{num}</div>
        <div className="ind-step-title">{title}</div>
        <StatusPill state={state} text={statusText} />
        {state === "complete" && <span className="expand-hint">{expanded ? "▴" : "▾"}</span>}
      </header>
      {(state !== "complete" || expanded) && <div className="ind-step-body">{children}</div>}
    </section>
  );
}

// ── Step 1 — Project Setup ─────────────────────────────────────
export type IndProjectFull = {
  id: string;
  molecule: string;
  target: string;
  indication: string;
  sponsor: string;
  regions: ("FDA" | "EMA" | "NMPA" | "PMDA")[];
};

export function Step1ProjectSetup({
  project,
  onEdit,
  expanded,
  onToggle,
  leadSmiles,
}: {
  project: IndProjectFull;
  onEdit: () => void;
  expanded?: boolean;
  onToggle?: () => void;
  /** Per-project lead SMILES. When undefined, falls back to the BM-0042
   * default so old call-sites keep rendering something. */
  leadSmiles?: string | null;
}) {
  const regs: ("FDA" | "EMA" | "NMPA" | "PMDA")[] = ["FDA", "EMA", "NMPA", "PMDA"];
  return (
    <StepShell num="①" title="Project Setup" state="complete" statusText="Complete" expanded={expanded} onToggle={onToggle}>
      <div className="kv-list">
        <div className="k">Molecule</div>
        <div className="v">
          <b>{project.molecule}</b>
        </div>
        <div className="k">Target</div>
        <div className="v">{project.target}</div>
        <div className="k">Indication</div>
        <div className="v">{project.indication}</div>
        <div className="k">Sponsor</div>
        <div className="v">{project.sponsor}</div>
      </div>
      <div style={{ marginTop: 12 }}>
        <div className="ind-region-row">
          <span className="label">Target regions:</span>
          {regs.map((r) => (
            <span key={r} className={`r-toggle ${project.regions.includes(r) ? "on " + r.toLowerCase() : ""}`}>
              {r}
            </span>
          ))}
        </div>
      </div>
      <div style={{ marginTop: 12 }}>
        <div className="kv-list">
          <div className="k">Compounds</div>
          <div className="v">
            12 SMILES uploaded{" "}
            <button className="ind-link" onClick={onEdit}>
              Edit
            </button>
          </div>
          <div className="k">Lead</div>
          <div className="v mono" style={{ fontSize: 11.5 }}>
            {(leadSmiles ?? "CC(=O)Nc1ccc(Oc2ncnc3[nH]ccc23)cc1") + "…"}
          </div>
        </div>
      </div>
    </StepShell>
  );
}

// ── Step 2 — ADMET Screening ───────────────────────────────────
export type AdmetCompound = {
  id: string;
  lead?: boolean;
  hergIC50: number;
  hergRisk: "clear" | "border" | "flag";
  dili: "clear" | "flag";
  ames: "clear" | "flag";
  logP: number;
  mw: number;
  ro5: boolean;
  ro5Fail?: string;
};

export type AdmetData = {
  summary: { pass: number; total: number };
  compounds: AdmetCompound[];
};

export function Step2Admet({
  data,
  expanded,
  onToggle,
  running = false,
  progress = 100,
  importedFromChat = false,
}: {
  data: AdmetData;
  expanded?: boolean;
  onToggle?: () => void;
  running?: boolean;
  progress?: number;
  importedFromChat?: boolean;
}) {
  const [tableOpen, setTableOpen] = useState(false);
  const [wetlabOpen, setWetlabOpen] = useState(false);

  if (running) {
    return (
      <StepShell num="②" title="ADMET Screening" state="running" statusText={`Running… ${progress}%`} expanded={true} onToggle={onToggle}>
        <div style={{ fontSize: 12.5, color: "var(--ind-text-muted)" }}>
          Workflow: <span className="mono" style={{ fontFamily: "JetBrains Mono", fontSize: 11.5 }}>predict_admet_properties</span> (AWS Batch)
          <br />
          12 compounds · 41 endpoints · hERG / DILI / Ames / PPBR / Caco-2 …
        </div>
        <div className="ind-progress">
          <div className="bar">
            <div className="fill" style={{ width: `${progress}%` }} />
          </div>
          <span className="pct">{progress}%</span>
          <span className="eta">ETA: ~{Math.max(0, Math.round((100 - progress) * 0.5))}s</span>
        </div>
        <div className="ind-feeds-into">
          When complete: <b>feeds §2.6.1.3 + §2.6.4</b>
        </div>
      </StepShell>
    );
  }

  return (
    <StepShell num="②" title="ADMET Screening" state="complete" statusText={`${data.summary.pass}/${data.summary.total} pass`} expanded={expanded} onToggle={onToggle}>
      {importedFromChat && (
        <div
          style={{
            display: "flex", alignItems: "center", gap: 10,
            padding: "8px 12px", marginBottom: 10,
            background: "oklch(0.96 0.04 280)",
            border: "1px solid oklch(0.85 0.08 280)",
            borderRadius: 6, fontSize: 12.5, color: "oklch(0.32 0.10 280)",
          }}
        >
          <span style={{ fontSize: 14 }}>💬</span>
          <span style={{ flex: 1 }}>
            <b>Imported from chat</b> — ADMET ran in BioMate chat on May 4 14:22 UTC. Step 2 is using those cached results.
          </span>
          <button className="ind-btn sm">Re-run</button>
        </div>
      )}
      <div className="kv-list">
        <div className="k">Lead ({data.compounds[0].id})</div>
        <div className="v" style={{ display: "flex", gap: 10, flexWrap: "wrap", fontSize: 12 }}>
          <span className="gate clear" style={{ color: "var(--ind-ok)" }}>hERG ✓</span>
          <span className="gate clear" style={{ color: "var(--ind-ok)" }}>DILI ✓</span>
          <span className="gate clear" style={{ color: "var(--ind-ok)" }}>Ames ✓</span>
          <span className="gate clear" style={{ color: "var(--ind-ok)" }}>Ro5 ✓</span>
          <span style={{ color: "var(--ind-text-dim)" }}>all clear</span>
        </div>
        <div className="k">Campaign</div>
        <div className="v" style={{ fontSize: 12.5 }}>
          {data.summary.pass}/{data.summary.total} passed all gates&nbsp;
          <span style={{ color: "var(--ind-text-muted)" }}>· {data.summary.total - data.summary.pass} flagged</span>
        </div>
        <div className="k">Model</div>
        <div className="v" style={{ fontSize: 12, color: "var(--ind-text-muted)" }} title="hERG AUROC 0.931 · DILI 0.913 · Ames 0.934">
          ADMET-AI v2.0
          <span style={{ marginLeft: 6, fontSize: 10, padding: "1px 6px", borderRadius: 3, background: "oklch(0.92 0.04 150)", color: "oklch(0.40 0.10 150)", fontWeight: 700 }}>
            TDC AUROC 0.93
          </span>
        </div>
      </div>

      <div className="ind-expand-row">
        <button className="ind-link" onClick={() => setTableOpen((o) => !o)}>
          {tableOpen ? "▴ Hide ADMET table" : "▾ View ADMET table"}
        </button>
        <button className="ind-link" onClick={() => setWetlabOpen((o) => !o)}>
          + Add wet-lab data
        </button>
      </div>

      {tableOpen && (
        <div style={{ marginTop: 10, overflowX: "auto" }}>
          <table className="ind-table">
            <thead>
              <tr>
                <th>Compound</th>
                <th title="hERG IC50 — Redfern 2003, ICH S7B (IC50 < 10 µM = liability)">hERG IC50 (µM)</th>
                <th title="hERG risk classification">hERG</th>
                <th title="DILI risk (drug-induced liver injury)">DILI</th>
                <th title="Ames mutagenicity">Ames</th>
                <th>logP</th>
                <th>MW</th>
                <th title="Lipinski Rule of Five">Ro5</th>
              </tr>
            </thead>
            <tbody>
              {data.compounds.slice(0, 7).map((c) => (
                <tr key={c.id} className={c.lead ? "lead" : ""}>
                  <td>
                    <b>{c.id}</b>
                    {c.lead && <span style={{ marginLeft: 6, fontSize: 10, fontWeight: 700, color: "var(--ind-accent)" }}>LEAD</span>}
                  </td>
                  <td className="mono">{c.hergIC50 >= 30 ? ">30" : c.hergIC50}</td>
                  <td>
                    <span className={`gate ${c.hergRisk}`}>
                      {c.hergRisk === "clear" ? "✓ clear" : c.hergRisk === "flag" ? "✗ flag" : "~ border"}
                    </span>
                  </td>
                  <td>
                    <span className={`gate ${c.dili}`}>{c.dili === "clear" ? "✓ clear" : "✗ flag"}</span>
                  </td>
                  <td>
                    <span className={`gate ${c.ames}`}>{c.ames === "clear" ? "✓ clear" : "✗ flag"}</span>
                  </td>
                  <td className="mono">{c.logP}</td>
                  <td className="mono">{c.mw}</td>
                  <td>
                    {c.ro5 ? <span className="gate clear">✓</span> : <span className="gate flag">✗ {c.ro5Fail}</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <div style={{ fontSize: 11.5, color: "var(--ind-text-dim)", padding: "6px 0" }}>
            7 of {data.compounds.length} shown · click any cell for raw prediction + confidence + TDC benchmark context.
          </div>
        </div>
      )}

      {wetlabOpen && (
        <div className="ind-wetlab">
          <h4>
            Enrich with measured data <span style={{ fontWeight: 400, color: "var(--ind-text-dim)", fontSize: 11.5 }}>(optional)</span>
          </h4>
          <div>Upload GLP assay results to override computational predictions. Measured values always take precedence.</div>
          <ul>
            <li>NTP GLP Technical Report PDF <span style={{ color: "var(--ind-text-dim)" }}>(auto-extracted)</span></li>
            <li>FDA NDA nonclinical review PDF</li>
            <li>CSV (compound_id, assay_type, value, units, source)</li>
          </ul>
          <div className="upload-row">
            <button className="upload-btn">
              <Upload size={12} /> Upload PDF or CSV
            </button>
            <span style={{ color: "var(--ind-text-dim)" }}>or</span>
            <span title="Reference compound NDA fetch — wires to FDA NDA review search; not yet active in pilot.">
              Link NDA:
            </span>
            <input
              className="nda-input"
              placeholder="NDA # (coming soon)"
              disabled
              aria-disabled="true"
              title="NDA fetch not yet wired — upload PDF/CSV directly for now."
            />
            <button
              className="ind-btn sm"
              disabled
              title="NDA fetch not yet wired."
            >
              Fetch →
            </button>
          </div>
        </div>
      )}
    </StepShell>
  );
}

// ── Step 3 — PBPK Qualification ────────────────────────────────
export type PbpkData = {
  status: "pass" | "fail";
  model: string;
  refSet: number;
  refSource: string;
  metrics: { cmaxWithin2: number; aucWithin2: number; emaThreshold: number };
  lead: { id: string; fu: number; vd: number; t12: number; bioavail: number };
  ospRange: string;
  perDrug: { name: string; fold: number; pass: boolean }[];
};

export function Step3Pbpk({
  data,
  expanded,
  onToggle,
  failOverride = false,
}: {
  data: PbpkData;
  expanded?: boolean;
  onToggle?: () => void;
  failOverride?: boolean;
}) {
  const [tableOpen, setTableOpen] = useState(false);
  const passed = !failOverride && data.status === "pass";

  return (
    <StepShell
      num="③"
      title="PBPK Qualification"
      state={passed ? "complete" : "blocked"}
      statusText={
        passed ? (
          <>
            <span className="r-chip ema" style={{ marginRight: 4 }}>EMA ✓</span>
            <span className="r-chip fda">FDA ✓</span>
          </>
        ) : (
          <span style={{ color: "var(--ind-err)", fontWeight: 600 }}>⚠ Failed</span>
        )
      }
      expanded={expanded || !passed}
      onToggle={onToggle}
    >
      <div className="kv-list">
        <div className="k">Model</div>
        <div className="v" style={{ fontSize: 12.5 }}>{data.model}</div>
        <div className="k">Reference set</div>
        <div className="v" style={{ fontSize: 12.5 }}>
          {data.refSet} drugs · <span className="mono">{data.refSource}</span>
        </div>
      </div>

      <div
        style={{
          marginTop: 12, padding: "10px 12px",
          background: passed ? "var(--ind-ok-soft)" : "var(--ind-err-soft)",
          borderLeft: `3px solid ${passed ? "var(--ind-ok)" : "var(--ind-err)"}`,
          borderRadius: 6,
        }}
      >
        <div style={{ fontWeight: 700, fontSize: 12.5, color: passed ? "var(--ind-ok)" : "var(--ind-err)" }}>
          {passed ? "✓ EMA criterion met" : "✗ EMA criterion NOT met"}
        </div>
        <div style={{ fontSize: 12.5, marginTop: 4, lineHeight: 1.55, color: "var(--ind-text)" }}>
          <b>Cmax:</b> {passed ? data.metrics.cmaxWithin2 : 58.2}% within 2-fold{" "}
          <span style={{ color: "var(--ind-text-muted)" }}>(EMA criterion ≥{data.metrics.emaThreshold}%)</span>
          <br />
          <b>AUC:</b> {data.metrics.aucWithin2}% within 2-fold
        </div>
        {!passed && (
          <div style={{ marginTop: 8, fontSize: 12, color: "var(--ind-err)", lineHeight: 1.55 }}>
            The <b>§2.6.2 section will include a model limitation statement.</b> Consider reviewing excluded compounds or updating clearance parameters. Downstream actions (CRO export, IND assembly) are blocked until the model is re-qualified.
            <div style={{ display: "flex", gap: 6, marginTop: 8 }}>
              <button className="ind-btn sm">Review excluded compounds</button>
              <button className="ind-btn sm primary">Re-run with new params</button>
            </div>
          </div>
        )}
      </div>

      <div style={{ marginTop: 12 }}>
        <div className="kv-list">
          <div className="k">Lead ({data.lead.id})</div>
          <div className="v mono" style={{ fontFamily: "JetBrains Mono", fontSize: 11.5 }}>
            f_u = {data.lead.fu} · Vd = {data.lead.vd} L/kg · t½ = {data.lead.t12}h · F = {data.lead.bioavail}%
          </div>
        </div>
      </div>

      <div className="ind-expand-row">
        <button className="ind-link" onClick={() => setTableOpen((o) => !o)}>
          {tableOpen ? "▴ Hide qualification table" : "▾ View qualification table"}
        </button>
        {passed && <button className="ind-link">Re-run with new params</button>}
      </div>

      {tableOpen && (
        <div style={{ marginTop: 10, maxHeight: 220, overflowY: "auto" }}>
          <table className="ind-table">
            <thead>
              <tr><th>Drug</th><th>Fold (Cmax)</th><th>Result</th></tr>
            </thead>
            <tbody>
              {data.perDrug.slice(0, 10).map((d) => (
                <tr key={d.name}>
                  <td>{d.name}</td>
                  <td className="mono">{d.fold.toFixed(2)}</td>
                  <td>
                    {d.pass ? <span className="gate clear">✓ within 2×</span> : <span className="gate flag">✗ {d.fold.toFixed(2)}×</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div style={{ marginTop: 10, fontSize: 11, color: "var(--ind-text-dim)", fontStyle: "italic" }}>
        BioMate PBPK within-2-fold ({passed ? data.metrics.cmaxWithin2 : 58.2}%) is within the OSP-approved range for EMA-accepted PBPK platforms ({data.ospRange}).
      </div>
    </StepShell>
  );
}

// ── Step 4 — Lead Selection ────────────────────────────────────
export type LeadRow = {
  rank: number;
  id: string;
  score: number;
  herg: "clear" | "border" | "flag";
  dili: "clear" | "flag";
  ames: "clear" | "flag";
  potency: 1 | 2 | 3 | 4;
  ad: "in_domain" | "out_of_domain";
};

export type LeadsData = {
  method: string;
  evaluated: number;
  rounds: number;
  inDomain: number;
  outOfDomain: number;
  ranking: LeadRow[];
};

export function Step4Leads({ data, expanded, onToggle }: { data: LeadsData; expanded?: boolean; onToggle?: () => void }) {
  const [showAll, setShowAll] = useState(false);
  const rows = showAll ? data.ranking : data.ranking.slice(0, 5);

  return (
    <StepShell
      num="④"
      title="Lead Selection"
      state="complete"
      statusText={
        <>
          <Check size={13} /> Top: {data.ranking[0].id}
        </>
      }
      expanded={expanded}
      onToggle={onToggle}
    >
      <div style={{ fontSize: 12.5, color: "var(--ind-text-muted)" }}>
        <b>Method:</b> {data.method}
        <br />
        Evaluated: {data.evaluated} compounds · {data.rounds} optimization rounds
      </div>
      <div style={{ marginTop: 12, overflowX: "auto" }}>
        <table className="ind-table">
          <thead>
            <tr>
              <th>Rank</th><th>Compound</th><th>Score</th>
              <th>hERG</th><th>DILI</th><th>Ames</th>
              <th>Potency</th><th>AD</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id} className={r.rank === 1 ? "lead" : ""}>
                <td>{r.rank}</td>
                <td>
                  <b>{r.id}</b>
                  {r.rank === 1 && <span style={{ marginLeft: 6, fontSize: 10, fontWeight: 700, color: "var(--ind-accent)" }}>LEAD</span>}
                </td>
                <td className="mono">{r.score.toFixed(2)}</td>
                <td><span className={`gate ${r.herg}`}>{r.herg === "clear" ? "✓" : r.herg === "flag" ? "✗" : "~"}</span></td>
                <td><span className={`gate ${r.dili}`}>{r.dili === "clear" ? "✓" : "✗"}</span></td>
                <td><span className={`gate ${r.ames}`}>{r.ames === "clear" ? "✓" : "✗"}</span></td>
                <td>
                  <span className="potency-dots">
                    {[1, 2, 3, 4].map((i) => <span key={i} className={`d ${i <= r.potency ? "on" : ""}`} />)}
                  </span>
                </td>
                <td>
                  {r.ad === "in_domain" ? <span className="ad-cell in">in-domain</span> : <span className="ad-cell out">⚠ OOD</span>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div style={{ marginTop: 10, fontSize: 12, color: "var(--ind-text-muted)" }}>
        Applicability domain: <b>{data.inDomain}/{data.evaluated} in-domain</b> · {data.outOfDomain} OOD (flagged in §2.6.1.5)
        {!showAll && (
          <button className="ind-link" style={{ marginLeft: 10 }} onClick={() => setShowAll(true)}>
            View all {data.evaluated} →
          </button>
        )}
      </div>
    </StepShell>
  );
}

// ── Step 5 — IND Document ──────────────────────────────────────
export type AuditFinding = {
  severity: "CRITICAL" | "MAJOR" | "MINOR" | "INFO";
  section: string;
  desc: string;
  addressed?: boolean;
};

export type SectionCoverage = {
  id: string;
  title: string;
  coverage: "full" | "partial" | "none";
  note?: string;
};

export type IndDoc = {
  signed: boolean;
  generatedAt: string;
  characters: number;
  signedBy?: string | null;
  shaPrefix?: string;
  sections: SectionCoverage[];
};

export type IndAudit = { findings: AuditFinding[] };

export function Step5Document({
  doc,
  audit,
  regions,
  onSign,
  onAudit,
  onViewDoc,
  onDownload,
  onRegenerate,
  expanded,
  onToggle,
}: {
  doc: IndDoc;
  audit: IndAudit;
  regions: ("FDA" | "EMA" | "NMPA" | "PMDA")[];
  onSign: () => void;
  onAudit: () => void;
  onViewDoc: () => void;
  onDownload: () => void;
  onRegenerate: () => void;
  expanded?: boolean;
  onToggle?: () => void;
}) {
  const sevCount = (sev: AuditFinding["severity"]) =>
    audit.findings.filter((f) => f.severity === sev && !f.addressed).length;
  const crit = sevCount("CRITICAL");
  const major = sevCount("MAJOR");
  const minor = sevCount("MINOR");
  const info = sevCount("INFO");
  const hasMajor = crit > 0 || major > 0;

  return (
    <StepShell
      num="⑤"
      title="IND Document"
      state="complete"
      statusText={
        doc.signed ? (
          <><Check size={13} /> Signed</>
        ) : (
          <><Check size={13} /> Ready to sign</>
        )
      }
      expanded={true}
      onToggle={onToggle}
    >
      <div style={{ fontSize: 12.5, color: "var(--ind-text-muted)" }}>
        Sections generated: <span className="mono">§2.6.1.1–§2.6.1.6</span> · <span className="mono">§2.6.2</span> · <span className="mono">§2.6.3</span> · <span className="mono">§2.6.4</span> · <span className="mono">§2.6.5</span> · <span className="mono">§2.6.6</span>
      </div>

      <div style={{ marginTop: 10, display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
        <span style={{ fontSize: 11.5, color: "var(--ind-text-muted)", marginRight: 4 }}>Regulatory audit:</span>
        <span className={`audit-chip ${crit ? "crit" : "info"}`} style={{ opacity: crit ? 1 : 0.6 }}>
          <span className="audit-chip dot crit" /> {crit} CRITICAL
        </span>
        <span className={`audit-chip ${major ? "major" : "info"}`} style={{ opacity: major ? 1 : 0.6 }}>
          <span className="audit-chip dot major" /> {major} MAJOR
        </span>
        <span className="audit-chip minor">{minor} MINOR</span>
        <span className="audit-chip info">{info} INFO</span>
        <button className="ind-link" style={{ marginLeft: 4, fontSize: 12 }} onClick={onAudit}>
          View →
        </button>
      </div>

      <div style={{ marginTop: 10, fontSize: 12.5, color: "var(--ind-text-muted)" }}>
        Regions:{" "}
        {regions.map((r) => (
          <span key={r} className={`r-chip ${r.toLowerCase()}`} style={{ marginRight: 4, marginLeft: 4 }}>
            {r} ✓
          </span>
        ))}
      </div>

      <div style={{ marginTop: 8, fontSize: 11, color: "var(--ind-text-dim)", fontFamily: "JetBrains Mono" }}>
        Generated: {doc.generatedAt} · {doc.characters.toLocaleString()} characters · DOCX ready
      </div>

      <div
        style={{
          marginTop: 10, padding: "8px 12px",
          background: "var(--ind-bg-sub)", borderRadius: 6,
          fontSize: 12, color: "var(--ind-text-muted)",
          display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap",
        }}
      >
        <span style={{ background: "var(--ind-accent)", color: "white", padding: "1px 7px", borderRadius: 3, fontSize: 10.5, fontWeight: 700 }}>v2</span>
        <span style={{ fontWeight: 600, color: "var(--ind-text)" }}>Current</span>
        <span>· v1 signed 2026-05-01 by Dr. Jane Smith</span>
        <button className="ind-link" style={{ fontSize: 11.5, marginLeft: "auto" }}>
          View versions →
        </button>
      </div>

      <div className="coverage-list" style={{ marginTop: 12 }}>
        <div style={{ fontSize: 11, color: "var(--ind-text-muted)", fontWeight: 700, textTransform: "uppercase", letterSpacing: 0.06, marginBottom: 4 }}>
          Document completeness
        </div>
        {doc.sections.map((s) => (
          <div className="coverage-row" key={s.id}>
            <span className="num">{s.id}</span>
            <span className="title">
              {s.title.split(" ").slice(1).join(" ").replace(/§[\d.]+/, "").trim() || s.title}
              {s.note && <span className="note"> · ⚠ {s.note}</span>}
            </span>
            <span className={`badge ${s.coverage}`}>
              ● {s.coverage === "full" ? "Full" : s.coverage === "partial" ? "Partial" : "None"}
            </span>
          </div>
        ))}
      </div>

      {hasMajor && (
        <div className="ind-major-warn">
          <TriangleAlert size={16} />
          <div style={{ flex: 1 }}>
            <b>{major} MAJOR finding{major > 1 ? "s" : ""} before signing</b>
            <div style={{ fontSize: 12, color: "var(--ind-text-muted)", marginTop: 2 }}>
              §2.6.1.2: PBPK interpretation lacks AFE direction comment
            </div>
          </div>
          <button className="ind-btn sm" onClick={onAudit}>View →</button>
          <button className="ind-btn sm" onClick={onRegenerate}>Regenerate →</button>
        </div>
      )}

      <div className="ind-step-actions">
        <button className="ind-btn" onClick={onViewDoc}>
          <Eye size={13} /> View Document
        </button>
        <button className="ind-btn" onClick={onDownload}>
          <Download size={13} /> Download DOCX
        </button>
        {!doc.signed ? (
          <button className={`ind-btn ${hasMajor ? "warn" : "primary"}`} onClick={onSign}>
            <Signature size={13} /> {hasMajor ? "Sign with findings →" : "Sign & Freeze →"}
          </button>
        ) : (
          <button className="ind-btn ok" disabled>
            <Check size={13} /> Signed — View
          </button>
        )}
      </div>
    </StepShell>
  );
}
