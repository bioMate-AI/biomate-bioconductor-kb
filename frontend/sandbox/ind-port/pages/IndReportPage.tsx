/**
 * /ind-report — top-level page for the BioMate IND Report product.
 * Ports reference/claude_design/IND_design BioMate IND Report.html App component.
 *
 * Shell layout: LeftNav | Center pipeline | DocPanel — three-column grid
 * defined in styles/ind-report.css (.ind-shell). Class names preserved
 * verbatim from prototype.
 */
import { useEffect, useState } from "react";
import "@/styles/ind-report.css";
import { IndLeftNav, type IndProjectSummary } from "@/components/ind-report/IndLeftNav";

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

export function IndReportPage() {
  const [activeId, setActiveId] = useState<string | null>(DEMO_PROJECTS[0].id);
  const [showSettings, setShowSettings] = useState(false);

  // Tag body so global styles in ind-report.css that target body.ind-app apply.
  useEffect(() => {
    document.body.classList.add("ind-app");
    return () => document.body.classList.remove("ind-app");
  }, []);

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

      {/* Center — pipeline. Filled in by IndSteps in a follow-up. */}
      <main className="ind-center">
        <div style={{ padding: 24, color: "var(--ind-text-muted)", fontSize: 13 }}>
          Pipeline steps go here. (Step1ProjectSetup … Step5Document — porting in progress.)
        </div>
      </main>

      {/* Right — document viewer. Filled in by IndDocPanel in a follow-up. */}
      <aside className="ind-doc-panel">
        <div style={{ padding: 24, color: "var(--ind-text-muted)", fontSize: 13 }}>
          Document viewer goes here. (IndDocPanel — porting in progress.)
        </div>
      </aside>

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
