/**
 * Left navigation for the IND Report product.
 * Ports reference/claude_design/IND_design ind/LeftNav.jsx → TSX.
 * Preserves class names verbatim so styles-ind.css applies unchanged.
 */
import { Plus } from "lucide-react";

export type IndProjectStatus = "signed" | "in_progress" | "blocked" | "not_started";

export type IndProjectSummary = {
  id: string;
  molecule: string;
  target: string;
  indication: string;
  regions: ("FDA" | "EMA" | "NMPA" | "PMDA")[];
  status: IndProjectStatus;
  statusText: string;
};

type Props = {
  projects: IndProjectSummary[];
  activeId: string | null;
  onSelect: (id: string) => void;
  onNew: () => void;
  onSettings?: () => void;
};

export function IndLeftNav({ projects, activeId, onSelect, onNew, onSettings }: Props) {
  return (
    <aside className="ind-left">
      <div className="ind-left-brand">
        <div className="mark">B</div>
        <div className="name">
          BioMate <small>IND Report</small>
        </div>
      </div>

      <button className="ind-new-project" onClick={onNew} data-tour="ind-new-project">
        <Plus size={14} /> New Project
      </button>

      <div className="ind-projects" data-tour="ind-projects">
        {projects.map((p) => (
          <button
            key={p.id}
            className={`ind-project${p.id === activeId ? " active" : ""}`}
            onClick={() => onSelect(p.id)}
          >
            <span className={`ind-project-dot ${p.status}`} aria-hidden="true" />
            <span className="ind-project-body">
              <span className="ind-project-title">
                {p.molecule} · {p.target}
              </span>
              <span className="ind-project-sub">{p.indication}</span>
              <span className="ind-project-regions">
                {p.regions.map((r) => (
                  <span key={r} className={`r-chip ${r.toLowerCase()}`}>
                    {r}
                  </span>
                ))}
              </span>
              <span className="ind-project-status">{p.statusText}</span>
            </span>
          </button>
        ))}
      </div>

      {/* Settings / Billing / Help links removed per todo (item #21):
          Billing + Help were href="#" stubs; Settings dialog says "porting
          in progress". Reinstate when each lands. */}
    </aside>
  );
}
