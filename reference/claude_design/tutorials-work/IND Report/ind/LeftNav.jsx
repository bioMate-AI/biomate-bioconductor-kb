// LeftNav — project list + brand + footer links
const IndLeftNav = ({ projects, activeId, onSelect, onNew, onSettings }) => {
  return (
    <aside className="ind-left">
      <div className="ind-left-brand brand-full">
        <img className="brand-logo" src="images/biomate-logo.png" alt="BioMate" />
      </div>

      <button className="ind-new-project" onClick={onNew} data-tour="ind-new-project">
        <CroIcon name="plus" size={14}/> New Project
      </button>

      <div className="ind-projects" data-tour="ind-projects">
        {projects.map(p => (
          <button
            key={p.id}
            className={`ind-project${p.id === activeId ? ' active' : ''}`}
            onClick={() => onSelect(p.id)}
          >
            <span className={`ind-project-dot ${p.status}`} aria-hidden="true"/>
            <span className="ind-project-body">
              <span className="ind-project-title">
                {p.molecule} · {p.target}
              </span>
              <span className="ind-project-sub">{p.indication}</span>
              <span className="ind-project-regions">
                {p.regions.map(r => (
                  <span key={r} className={`r-chip ${r.toLowerCase()}`}>{r}</span>
                ))}
              </span>
              <span className="ind-project-status">{p.statusText}</span>
            </span>
          </button>
        ))}
      </div>

      <div className="ind-left-foot">
        <div className="ind-left-user">
          <div className="ind-left-user-avatar">JS</div>
          <div className="ind-left-user-meta">
            <span className="ind-left-user-name">Dr. Jane Smith</span>
            <span className="ind-left-user-email">jane@acme.com</span>
          </div>
        </div>
        {/* Footer links hidden for demo
        <a href="#" onClick={(e) => { e.preventDefault(); onSettings && onSettings(); }}>Settings</a>
        <a href="#">Billing</a>
        <a href="#">Help</a>
        */}
      </div>
    </aside>
  );
};

window.IndLeftNav = IndLeftNav;
