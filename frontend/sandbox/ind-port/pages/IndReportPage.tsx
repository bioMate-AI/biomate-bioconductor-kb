/**
 * /ind-report — top-level page for the BioMate IND Report product.
 * Ports reference/claude_design/IND_design BioMate IND Report.html App component.
 *
 * Shell layout: LeftNav | Center pipeline | DocPanel — three-column grid
 * defined in styles/ind-report.css (.ind-shell). Class names preserved
 * verbatim from prototype.
 */
import { useEffect, useState } from "react";
import { Shield } from "lucide-react";
// Sandbox-relative imports — rewritten to @/-aliases at production integration time.
import "../styles/ind-report.css";
import { IndLeftNav, type IndProjectSummary } from "../components/IndLeftNav";
import {
  Step1ProjectSetup, Step2Admet, Step3Pbpk, Step4Leads, Step5Document,
  type IndProjectFull, type AdmetData, type PbpkData, type LeadsData,
  type IndDoc, type IndAudit,
} from "../components/IndSteps";
import { IndDocPanel, type DocPanelDoc, type Region } from "../components/IndDocPanel";
import {
  IndSignOverlay, IndAuditOverlay, IndEmptyState,
  type AuditFindingWithMeta, type ReferenceCompound,
} from "../components/IndOverlays";

// Demo seed — replace with GET /api/ind-report/projects when backend route exists.
// For now this page renders the shell so the styling can be visually verified.
const DEMO_PROJECTS: IndProjectSummary[] = [
  {
    id: "p-bm0042",
    molecule: "BM-0042",
    target: "EGFR L858R",
    indication: "NSCLC",
    regions: ["FDA", "EMA", "NMPA", "PMDA"],
    status: "in_progress",
    statusText: "Step 3 / 5 — PBPK running",
  },
  {
    id: "p-bm0038",
    molecule: "BM-0038",
    target: "KRAS G12C",
    indication: "CRC",
    regions: ["FDA", "EMA"],
    status: "signed",
    statusText: "Signed · v3 · 2026-05-09",
  },
  {
    id: "p-bm0029",
    molecule: "BM-0029",
    target: "PD-L1",
    indication: "TNBC",
    regions: ["FDA", "NMPA"],
    status: "blocked",
    statusText: "Audit blocked — 1 CRITICAL",
  },
];

// Top bar — breadcrumb + region chips + tutorial + user avatar.
// Lives in the .ind-shell grid at row 1, columns 2/-1 (see styles-ind.css).
function TopBar({ activeProject }: { activeProject: IndProjectSummary | null }) {
  if (!activeProject) return null;
  return (
    <header className="ind-topbar">
      <div className="ind-crumb">
        <span>IND Report</span>
        <span className="sep">/</span>
        <b>{activeProject.molecule}</b>
        <span className="sep">/</span>
        <span style={{ color: "var(--ind-text)" }}>§2.6 nonclinical</span>
      </div>
      <div className="ind-top-actions">
        {activeProject.regions.map((r) => (
          <span key={r} className={`r-chip ${r.toLowerCase()}`}>
            {r}
          </span>
        ))}
        <button className="tut-btn" title="Replay the tutorial">
          <span style={{ fontSize: 10 }}>▶</span> Tutorial
        </button>
        <div className="user">
          <div className="user-avatar">JS</div>
          <span>jane@acme.com</span>
        </div>
      </div>
    </header>
  );
}

// Pipeline center — wires the 5 step components against demo data.
// Replace demo data with API calls when integrated to production.
function PipelineCenter({
  activeProject, onSign, onAudit,
}: {
  activeProject: IndProjectSummary | null;
  onSign: () => void;
  onAudit: () => void;
}) {
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const toggle = (k: string) => setExpanded((e) => ({ ...e, [k]: !e[k] }));

  if (!activeProject) {
    return (
      <main className="ind-center">
        <div style={{ padding: 24, color: "var(--ind-text-muted)", fontSize: 13 }}>
          Select a project from the left to begin.
        </div>
      </main>
    );
  }

  const project: IndProjectFull = {
    id: activeProject.id,
    molecule: activeProject.molecule,
    target: activeProject.target,
    indication: activeProject.indication,
    sponsor: "Acme Therapeutics, Inc.",
    regions: activeProject.regions,
  };

  return (
    <main className="ind-center">
      <div className="ind-center-head">
        <div>
          <div className="ind-h1">{activeProject.molecule} · {activeProject.target}</div>
          <div className="ind-h1-sub">
            {activeProject.indication} · {project.sponsor} · {activeProject.regions.join(" · ")}
          </div>
        </div>
        <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
          <button className="ind-btn sm" onClick={onAudit}>
            <Shield size={12} /> Audit
          </button>
        </div>
      </div>
      <Step1ProjectSetup project={project} onEdit={() => {}} expanded={expanded.s1} onToggle={() => toggle("s1")} />
      <Step2Admet data={DEMO_ADMET} expanded={expanded.s2} onToggle={() => toggle("s2")} />
      <Step3Pbpk data={DEMO_PBPK} expanded={expanded.s3} onToggle={() => toggle("s3")} />
      <Step4Leads data={DEMO_LEADS} expanded={expanded.s4} onToggle={() => toggle("s4")} />
      <Step5Document
        doc={DEMO_DOC}
        audit={DEMO_AUDIT}
        regions={activeProject.regions}
        onSign={onSign}
        onAudit={onAudit}
        onViewDoc={() => {}}
        onDownload={() => {}}
        onRegenerate={() => {}}
        expanded={expanded.s5}
        onToggle={() => toggle("s5")}
      />
    </main>
  );
}

// Demo data — minimal versions sufficient for visual validation.
// Replace with API responses at production integration.
const DEMO_ADMET: AdmetData = {
  summary: { pass: 8, total: 12 },
  compounds: [
    { id: "BM-0042", lead: true, hergIC50: 31, hergRisk: "clear", dili: "clear", ames: "clear", logP: 3.2, mw: 412, ro5: true },
    { id: "BM-0017", hergIC50: 18, hergRisk: "clear", dili: "clear", ames: "clear", logP: 2.8, mw: 388, ro5: true },
    { id: "BM-0023", hergIC50: 4, hergRisk: "flag", dili: "flag", ames: "clear", logP: 4.7, mw: 521, ro5: false, ro5Fail: "MW" },
  ],
};
const DEMO_PBPK: PbpkData = {
  status: "pass", model: "BioMate PBPK v2.1", refSet: 30, refSource: "EMA/CHMP/EWP/37498/2011",
  metrics: { cmaxWithin2: 73.3, aucWithin2: 100, emaThreshold: 67 },
  lead: { id: "BM-0042", fu: 0.12, vd: 1.8, t12: 8.2, bioavail: 64 },
  ospRange: "70-85%",
  perDrug: [
    { name: "Aspirin", fold: 1.4, pass: true },
    { name: "Caffeine", fold: 1.1, pass: true },
    { name: "Warfarin", fold: 2.6, pass: false },
  ],
};
const DEMO_LEADS: LeadsData = {
  method: "Bayesian optimization (Acme refinements)",
  evaluated: 142, rounds: 4, inDomain: 128, outOfDomain: 14,
  ranking: [
    { rank: 1, id: "BM-0042", score: 9.21, herg: "clear", dili: "clear", ames: "clear", potency: 4, ad: "in_domain" },
    { rank: 2, id: "BM-0017", score: 8.83, herg: "clear", dili: "clear", ames: "clear", potency: 3, ad: "in_domain" },
    { rank: 3, id: "BM-0093", score: 8.12, herg: "border", dili: "clear", ames: "clear", potency: 4, ad: "in_domain" },
    { rank: 4, id: "BM-0011", score: 7.95, herg: "clear", dili: "flag", ames: "clear", potency: 3, ad: "in_domain" },
    { rank: 5, id: "BM-0067", score: 7.41, herg: "clear", dili: "clear", ames: "clear", potency: 2, ad: "out_of_domain" },
  ],
};
const DEMO_DOC: IndDoc = {
  signed: false,
  generatedAt: "2026-05-15T18:42Z",
  characters: 48732,
  shaPrefix: "9f2c4a",
  sections: [
    { id: "2.6.1", title: "§2.6.1 Overview", coverage: "full" },
    { id: "2.6.2", title: "§2.6.2 Pharmacology", coverage: "full" },
    { id: "2.6.3", title: "§2.6.3 Pharmacology tabulated", coverage: "full" },
    { id: "2.6.4", title: "§2.6.4 PK written", coverage: "full" },
    { id: "2.6.5", title: "§2.6.5 PK tabulated", coverage: "partial", note: "1 missing column" },
    { id: "2.6.6", title: "§2.6.6 Toxicology written", coverage: "full" },
  ],
};
const DEMO_AUDIT: IndAudit = {
  findings: [
    { severity: "MAJOR", section: "§2.6.1.2", desc: "PBPK interpretation lacks AFE direction comment" },
    { severity: "MINOR", section: "§2.6.6.3", desc: "Genotoxicity citation could be more specific" },
    { severity: "INFO", section: "§2.6.2", desc: "Consider mentioning secondary PD" },
  ],
};

// Doc-panel-shaped demo data. bodyByPid replaces the prototype's
// window.IND_SECTION_BODY global.
const DEMO_DOC_FOR_PANEL: DocPanelDoc = {
  ...DEMO_DOC,
  version: 2,
  shaPrefix: DEMO_DOC.shaPrefix ?? "9f2c4a",
  sections: [
    { id: "2.6.1", title: "§2.6.1 Overview", coverage: "full" },
    { id: "2.6.2", title: "§2.6.2 Pharmacology", coverage: "full" },
    { id: "2.6.3", title: "§2.6.3 Pharmacology tabulated", coverage: "full" },
    { id: "2.6.4", title: "§2.6.4 PK written", coverage: "full" },
    { id: "2.6.5", title: "§2.6.5 PK tabulated", coverage: "partial", note: "1 missing column" },
    { id: "2.6.6", title: "§2.6.6 Toxicology written", coverage: "full" },
  ],
  bodyByPid: {
    "p-2.6.1": "[BioMate-generated draft] This nonclinical overview integrates the ADMET, PBPK, and lead-selection findings supporting BM-0042 for Phase I in NSCLC.",
    "p-2.6.2": "BM-0042 inhibits EGFR L858R with IC50 of 4.2 nM in biochemical assays. In vivo efficacy was demonstrated in HCC827 xenograft at 30 mg/kg/day PO.",
    "p-2.6.3": "Tabulated pharmacology results across 12 compounds, 41 endpoints.",
    "p-2.6.4": "Following oral administration in rat, BM-0042 showed Tmax 1.5h, Cmax 412 ng/mL, AUC₀₋₂₄ 3,840 ng·h/mL, t½ 8.2h, F 64%. PBPK qualification against 30-drug reference set met EMA Cmax within-2-fold criterion (73.3% vs ≥67% threshold).",
    "p-2.6.5": "Tabulated PK parameters across species and routes.",
    "p-2.6.6": "In the 28-day repeat-dose study, the NOAEL of 100 mg/kg/day was identified in Sprague-Dawley rats. No test-article-related findings were observed at the NOAEL dose level per ICH M3(R2).",
  },
};

// Wraps IndDocPanel — manages region + version-popover state locally so
// IndReportPage stays thin. Sign / Audit lift to the page (they're full-
// screen overlays, not panel-internal).
function DocPanelHost({
  activeProject, onSign, onAudit,
}: {
  activeProject: IndProjectSummary | null;
  onSign: () => void;
  onAudit: () => void;
}) {
  const [region, setRegion] = useState<Region | "ALL">("FDA");
  const [showVersions, setShowVersions] = useState(false);

  if (!activeProject) {
    return <aside className="ind-doc-panel" />;
  }
  return (
    <IndDocPanel
      doc={DEMO_DOC_FOR_PANEL}
      audit={DEMO_AUDIT}
      region={region}
      onRegionChange={setRegion}
      onSign={onSign}
      onAudit={onAudit}
      onVersionsClick={() => setShowVersions((v) => !v)}
      showVersions={showVersions}
      onVersionsClose={() => setShowVersions(false)}
      onDownload={(fmt) => alert(`Download .${fmt} (stub)`)}
      onChatHandoff={() => alert("Chat handoff (stub)")}
      projectId={activeProject.id}
      orgId={null}
    />
  );
}

// Reference compounds for the EmptyState onboarding card.
const DEMO_REFERENCE_COMPOUNDS: ReferenceCompound[] = [
  { id: "ref-pembro", name: "Pembrolizumab", tag: "mAb", desc: "PD-1 inhibitor — biologics path" },
  { id: "ref-osim",   name: "Osimertinib",   tag: "small mol", desc: "EGFR T790M — oncology M3(R2)" },
  { id: "ref-sema",   name: "Semaglutide",   tag: "peptide", desc: "GLP-1 agonist — PK-heavy" },
];

export function IndReportPage() {
  // Allow ?onboarding=1 in the URL to force the EmptyState (for QA/screenshots).
  const initialOnboarding =
    typeof window !== "undefined" &&
    new URLSearchParams(window.location.search).get("onboarding") === "1";
  const [showOnboarding, setShowOnboarding] = useState(initialOnboarding);
  const [activeId, setActiveId] = useState<string | null>(DEMO_PROJECTS[0].id);
  const [showSettings, setShowSettings] = useState(false);
  const [showSign, setShowSign] = useState(false);
  const [showAudit, setShowAudit] = useState(false);
  const activeProject = DEMO_PROJECTS.find((p) => p.id === activeId) ?? null;

  // Tag body so global styles in ind-report.css that target body.ind-app apply.
  useEffect(() => {
    document.body.classList.add("ind-app");
    return () => document.body.classList.remove("ind-app");
  }, []);

  // Onboarding mode — show EmptyState in place of the main pipeline.
  if (showOnboarding) {
    return (
      <div className="ind-shell">
        <IndLeftNav
          projects={[]}
          activeId={null}
          onSelect={() => {}}
          onNew={() => setShowOnboarding(false)}
        />
        <IndEmptyState
          onStart={() => setShowOnboarding(false)}
          onPickReference={() => setShowOnboarding(false)}
          referenceCompounds={DEMO_REFERENCE_COMPOUNDS}
        />
      </div>
    );
  }

  return (
    <div className="ind-shell">
      <IndLeftNav
        projects={DEMO_PROJECTS}
        activeId={activeId}
        onSelect={setActiveId}
        onNew={() => {
          /* TODO: wire new-project dialog */
        }}
        onSettings={() => setShowSettings(true)}
      />

      <TopBar activeProject={activeProject} />

      <PipelineCenter
        activeProject={activeProject}
        onSign={() => setShowSign(true)}
        onAudit={() => setShowAudit(true)}
      />

      {/* Floating action button — CSS makes this display:flex only at
          viewport ≤1024px (where .ind-doc-panel is hidden). Opens the
          panel as a modal. Stub click for now. */}
      <button
        className="ind-doc-fab"
        onClick={() => alert("Open document panel (narrow viewport stub)")}
      >
        📄 View document
      </button>

      <DocPanelHost
        activeProject={activeProject}
        onSign={() => setShowSign(true)}
        onAudit={() => setShowAudit(true)}
      />

      {showSign && (
        <IndSignOverlay
          doc={{ ...DEMO_DOC_FOR_PANEL }}
          onCancel={() => setShowSign(false)}
          onSigned={() => setShowSign(false)}
        />
      )}
      {showAudit && (
        <IndAuditOverlay
          audit={{
            findings: DEMO_AUDIT.findings as AuditFindingWithMeta[],
            chainRecords: 142,
            lastVerified: "2026-05-16 14:22",
          }}
          onClose={() => setShowAudit(false)}
          onJumpTo={(section) => {
            const id = section.replace("§", "").split(".").slice(0, 3).join(".");
            const el = document.querySelector(`[data-section="${id}"]`);
            if (el) el.scrollIntoView({ block: "start" });
            setShowAudit(false);
          }}
        />
      )}

      {showSettings && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            background: "rgba(0,0,0,0.4)",
            display: "grid",
            placeItems: "center",
            zIndex: 30,
          }}
          onClick={() => setShowSettings(false)}
        >
          <div
            style={{
              background: "var(--ind-bg)",
              padding: 24,
              borderRadius: 12,
              maxWidth: 400,
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <h3>Settings</h3>
            <p style={{ fontSize: 12.5, color: "var(--ind-text-muted)" }}>
              Settings panel — porting in progress.
            </p>
            <button className="ind-btn sm" onClick={() => setShowSettings(false)}>
              Close
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

export default IndReportPage;
