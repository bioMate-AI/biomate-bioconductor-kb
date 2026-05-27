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
import "@/styles/ind-report.css";
import { IndLeftNav, type IndProjectSummary } from "@/components/ind-report/IndLeftNav";
import {
  Step1ProjectSetup, Step2Admet, Step3Pbpk, Step4Leads, Step5Document,
  type IndProjectFull, type AdmetData, type PbpkData, type LeadsData,
  type IndDoc, type IndAudit,
} from "@/components/ind-report/IndSteps";
import { IndDocPanel, type DocPanelDoc, type Region } from "@/components/ind-report/IndDocPanel";
import {
  IndSignOverlay, IndAuditOverlay, IndEmptyState,
  type AuditFindingWithMeta, type ReferenceCompound,
} from "@/components/ind-report/IndOverlays";
import { NewProjectModal } from "@/components/ind-report/NewProjectModal";
import { DocPanelMobileModal } from "@/components/ind-report/DocPanelMobileModal";
import { downloadMarkdown, type DocumentSection } from "@/lib/ind-report-api";
import { useLocation } from "wouter";

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
        {/* Tutorial button — removed (stub, no tour wired)
        <button className="tut-btn" title="Replay the tutorial">
          <span style={{ fontSize: 10 }}>▶</span> Tutorial
        </button>
        */}
        {/* User avatar — removed (hardcoded jane@acme.com, replace with real auth user when wired)
        <div className="user">
          <div className="user-avatar">JS</div>
          <span>jane@acme.com</span>
        </div>
        */}
      </div>
    </header>
  );
}

// URL-query knobs for QA / stakeholder demo. Documented as test fixtures,
// not production behavior. Used by IND-9/10/12 E2E tests.
function readKnobs(): {
  step2State: "complete" | "running";
  step2Progress: number;
  importedFromChat: boolean;
  pbpkFail: boolean;
  auditHasCritical: boolean;
} {
  if (typeof window === "undefined") {
    return { step2State: "complete", step2Progress: 100, importedFromChat: false, pbpkFail: false, auditHasCritical: false };
  }
  const q = new URLSearchParams(window.location.search);
  return {
    step2State: q.get("state") === "running" ? "running" : "complete",
    step2Progress: parseInt(q.get("progress") ?? "55", 10),
    importedFromChat: q.get("imported") === "1",
    pbpkFail: q.get("state") === "pbpk-fail" || q.get("pbpk") === "fail",
    auditHasCritical: q.get("audit") === "critical",
  };
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
  const knobs = readKnobs();

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
      <Step2Admet
        data={DEMO_ADMET}
        expanded={expanded.s2}
        onToggle={() => toggle("s2")}
        running={knobs.step2State === "running"}
        progress={knobs.step2Progress}
        importedFromChat={knobs.importedFromChat}
      />
      <Step3Pbpk
        data={DEMO_PBPK}
        expanded={expanded.s3}
        onToggle={() => toggle("s3")}
        failOverride={knobs.pbpkFail}
      />
      <Step4Leads data={DEMO_LEADS} expanded={expanded.s4} onToggle={() => toggle("s4")} />
      <Step5Document
        doc={DEMO_DOC}
        audit={knobs.auditHasCritical ? DEMO_AUDIT_CRITICAL : DEMO_AUDIT}
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

// Activated by ?audit=critical for IND-24 (CRITICAL blocks signing).
const DEMO_AUDIT_CRITICAL: IndAudit = {
  findings: [
    { severity: "CRITICAL", section: "§2.6.6.3", desc: "Genotoxicity Ames result missing in §2.6.6.3 — sponsor must address before submission" },
    ...DEMO_AUDIT.findings,
  ],
};

// Doc-panel-shaped demo data. Sections now carry `subs` so the prototype's
// inline-audit-chip code path activates: audit findings with section like
// "§2.6.1.2" match a sub's full id and render a ⚠ MAJOR/MINOR chip in line.
// bodyByPid replaces the prototype's window.IND_SECTION_BODY global, keyed
// by the sub id (or the section id when no subs).
const DEMO_DOC_FOR_PANEL: DocPanelDoc = {
  ...DEMO_DOC,
  version: 2,
  shaPrefix: DEMO_DOC.shaPrefix ?? "9f2c4a",
  sections: [
    {
      id: "2.6.1", title: "§2.6.1 Overview", coverage: "full",
      subs: [
        { id: "2.6.1.1", title: "Brief summary" },
        { id: "2.6.1.2", title: "Primary pharmacodynamics" },
        { id: "2.6.1.3", title: "Safety pharmacology" },
      ],
    },
    {
      id: "2.6.2", title: "§2.6.2 Pharmacology", coverage: "full",
      subs: [
        { id: "2.6.2.1", title: "Brief summary" },
        { id: "2.6.2.2", title: "Primary pharmacodynamics" },
      ],
    },
    { id: "2.6.3", title: "§2.6.3 Pharmacology tabulated", coverage: "full" },
    { id: "2.6.4", title: "§2.6.4 PK written", coverage: "full" },
    { id: "2.6.5", title: "§2.6.5 PK tabulated", coverage: "partial", note: "1 missing column" },
    {
      id: "2.6.6", title: "§2.6.6 Toxicology written", coverage: "full",
      subs: [
        { id: "2.6.6.1", title: "Brief summary" },
        { id: "2.6.6.2", title: "Single-dose toxicity" },
        { id: "2.6.6.3", title: "Repeat-dose toxicity" },
      ],
    },
  ],
  bodyByPid: {
    "p-2.6.1.1": "This nonclinical overview integrates the ADMET, PBPK, and lead-selection findings supporting BM-0042 for Phase I in NSCLC. [BioMate-generated draft — MUST NOT be submitted without human regulatory affairs review and 21 CFR Part 11 electronic signature.]",
    "p-2.6.1.2": "BM-0042 demonstrates EGFR L858R inhibitory activity with IC50 of 4.2 nM in biochemical assay (n=3, CV<15%). The PBPK Cmax-within-2-fold result of 73.3% exceeds the EMA criterion of ≥67% per CHMP/EWP/37498/2011.",
    "p-2.6.1.3": "Safety pharmacology assessment per ICH S7B identified hERG IC50 of 31 µM in HEK293 cell line assay, yielding a 75-fold margin over anticipated Cmax (412 ng/mL ≈ 0.41 µM).",
    "p-2.6.2.1": "Mechanism of action: BM-0042 is a selective, reversible inhibitor of EGFR L858R + T790M with >100-fold selectivity over wild-type EGFR. Off-target panel (Eurofins Cerep, 68 receptors) clean at 1 µM.",
    "p-2.6.2.2": "In vivo efficacy demonstrated in HCC827 xenograft model at 30 mg/kg/day PO; tumor regression 78% (95% CI 68-87%) at day 21. Plasma exposure linear up to 100 mg/kg.",
    "p-2.6.3": "Tabulated pharmacology results across 12 compounds, 41 endpoints — see §2.6.3 attached table.",
    "p-2.6.4": "Following oral administration in Sprague-Dawley rat (n=4/sex), BM-0042 showed Tmax 1.5h, Cmax 412 ng/mL, AUC₀₋₂₄ 3,840 ng·h/mL, t½ 8.2h, F 64%. PBPK qualification against 30-drug reference set (EMA/CHMP/EWP/37498/2011) met Cmax within-2-fold criterion of ≥67% (observed 73.3%) and AUC criterion (observed 100%).",
    "p-2.6.5": "Tabulated PK parameters across species (rat, dog, monkey) and routes (PO, IV) — see §2.6.5 attached table.",
    "p-2.6.6.1": "Toxicology brief: NOAEL identified at 100 mg/kg/day in 28-day GLP rat study (RTX-101). Safety margin ≥10× over anticipated human Cmax.",
    "p-2.6.6.2": "Single-dose toxicity (rat, oral, RTX-100): no mortality at 2000 mg/kg. MTD not reached. Reversible body-weight effects at ≥1000 mg/kg.",
    "p-2.6.6.3": "Repeat-dose toxicity (28-day, rat + dog, RTX-101/102): NOAEL 100 mg/kg/day in rat, 30 mg/kg/day in dog. No test-article-related findings at NOAEL per ICH M3(R2). Mild hepatic enzyme elevation at the high dose was reversible after 14-day recovery.",
  },
};

// Wraps IndDocPanel — manages region + version-popover state locally so
// IndReportPage stays thin. Sign / Audit lift to the page (they're full-
// screen overlays, not panel-internal).
function DocPanelHost({
  activeProject, onSign, onAudit, showAudit, onAuditClose,
}: {
  activeProject: IndProjectSummary | null;
  onSign: () => void;
  onAudit: () => void;
  showAudit: boolean;
  onAuditClose: () => void;
}) {
  const [region, setRegion] = useState<Region | "ALL">("FDA");
  const [showVersions, setShowVersions] = useState(false);
  const [, setLocation] = useLocation();
  const knobs = readKnobs();

  if (!activeProject) {
    return <aside className="ind-doc-panel" />;
  }

  // Replaces `alert("Download .md (stub)")` (closes P0-4). Walks the doc
  // body, ships it to the backend markdown renderer, triggers a real file
  // download. DOCX is greyed-out / disabled until python-docx is wired.
  const handleDownload = (fmt: "md" | "docx") => {
    if (fmt === "docx") {
      // P0-4 honest stance: don't pretend DOCX works. Tell the user.
      window.alert("DOCX export ships next sprint. Use the Markdown download for now.");
      return;
    }
    const sections: DocumentSection[] = DEMO_DOC_FOR_PANEL.sections.map((s) => ({
      id: s.id,
      title: s.title,
      body: (s.subs ?? [])
        .map((sub) => DEMO_DOC_FOR_PANEL.bodyByPid[`p-${sub.id}`] ?? "")
        .filter(Boolean)
        .join("\n\n"),
    }));
    downloadMarkdown(activeProject.id, sections).catch((e) =>
      console.error("[ind] markdown download failed:", e),
    );
  };

  // Replaces `alert("Chat handoff (stub)")` (closes P0-5).
  // Routes to /chat with project context so BioMate chat opens pre-loaded
  // with the active campaign.
  const handleChatHandoff = () => {
    const url = `/chat?context=ind-report&project=${encodeURIComponent(activeProject.id)}&molecule=${encodeURIComponent(activeProject.molecule)}`;
    setLocation(url);
  };

  return (
    <IndDocPanel
      doc={DEMO_DOC_FOR_PANEL}
      audit={knobs.auditHasCritical ? DEMO_AUDIT_CRITICAL : DEMO_AUDIT}
      region={region}
      onRegionChange={setRegion}
      onSign={onSign}
      onAudit={onAudit}
      onVersionsClick={() => setShowVersions((v) => !v)}
      showVersions={showVersions}
      onVersionsClose={() => setShowVersions(false)}
      onDownload={handleDownload}
      onChatHandoff={handleChatHandoff}
      projectId={activeProject.id}
      orgId={null}
      // P2-1: real header from active project, not hardcoded BM-0042 string
      headerSub={`${activeProject.molecule} · ${activeProject.sponsor ?? "Acme Therapeutics"} · ${activeProject.indication}`}
      // P0-2: audit overlay rendered as a SLOT inside the doc panel — the
      // .ind-audit-overlay { position: absolute; inset: 0 } CSS overlays the
      // panel (the positioned ancestor) instead of floating at the page root.
      auditOverlay={
        showAudit ? (
          <IndAuditOverlay
            audit={{
              findings: (knobs.auditHasCritical ? DEMO_AUDIT_CRITICAL : DEMO_AUDIT).findings as AuditFindingWithMeta[],
              chainRecords: 142,
              lastVerified: "2026-05-16 14:22",
            }}
            onClose={onAuditClose}
            onJumpTo={(section) => {
              const id = section.replace("§", "").split(".").slice(0, 3).join(".");
              const el = document.querySelector(`[data-section="${id}"]`);
              if (el) el.scrollIntoView({ block: "start", behavior: "smooth" });
              onAuditClose();
            }}
          />
        ) : undefined
      }
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
  const [projects, setProjects] = useState<IndProjectSummary[]>(DEMO_PROJECTS);
  const [activeId, setActiveId] = useState<string | null>(DEMO_PROJECTS[0].id);
  const [showSettings, setShowSettings] = useState(false);
  const [showSign, setShowSign] = useState(false);
  const [showAudit, setShowAudit] = useState(false);
  // Closes punch list P0-3: + New project opens this modal instead of TODO no-op
  const [showNewProject, setShowNewProject] = useState(false);
  // Closes punch list P0-6: mobile FAB opens the doc panel as a full-screen modal
  const [showDocModal, setShowDocModal] = useState(false);
  const activeProject = projects.find((p) => p.id === activeId) ?? null;

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
        projects={projects}
        activeId={activeId}
        onSelect={setActiveId}
        onNew={() => setShowNewProject(true)}
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
          /* Don't dismiss the overlay on signed — the success card with
             Download DOCX / Audit Trail buttons must stay until the user
             clicks Close. */
          onSigned={() => {}}
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
