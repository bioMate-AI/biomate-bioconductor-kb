// Small icon set for CRO surfaces (scoped; separate from the main prototype)
const CroIcon = ({ name, size = 14, stroke = 1.75 }) => {
  const s = { width: size, height: size, viewBox: '0 0 24 24', fill: 'none',
    stroke: 'currentColor', strokeWidth: stroke, strokeLinecap: 'round', strokeLinejoin: 'round' };
  const P = {
    chevronRight: <polyline points="9 6 15 12 9 18"/>,
    chevronDown: <polyline points="6 9 12 15 18 9"/>,
    chevronLeft: <polyline points="15 6 9 12 15 18"/>,
    check: <polyline points="5 12 10 17 20 7"/>,
    checkCircle: <g><circle cx="12" cy="12" r="10"/><polyline points="8 12 11 15 16 9"/></g>,
    x: <g><line x1="6" y1="6" x2="18" y2="18"/><line x1="18" y1="6" x2="6" y2="18"/></g>,
    xCircle: <g><circle cx="12" cy="12" r="10"/><line x1="9" y1="9" x2="15" y2="15"/><line x1="15" y1="9" x2="9" y2="15"/></g>,
    warn: <g><path d="M12 3l10 18H2z"/><line x1="12" y1="10" x2="12" y2="14"/><line x1="12" y1="17" x2="12" y2="17.5"/></g>,
    info: <g><circle cx="12" cy="12" r="10"/><line x1="12" y1="11" x2="12" y2="16"/><line x1="12" y1="8" x2="12" y2="8.5"/></g>,
    refresh: <g><polyline points="3 12 3 6 9 6"/><path d="M3 12a9 9 0 1 0 3-6.7"/></g>,
    lock: <g><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></g>,
    unlock: <g><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0"/></g>,
    shield: <path d="M12 3l8 3v6c0 5-4 9-8 9s-8-4-8-9V6z"/>,
    beaker: <g><path d="M9 3v7L4 20a2 2 0 0 0 1.7 3h12.6A2 2 0 0 0 20 20l-5-10V3"/><line x1="8" y1="3" x2="16" y2="3"/><line x1="6.5" y1="15" x2="17.5" y2="15"/></g>,
    dna: <g><path d="M4 4c4 0 4 16 8 16s4-16 8-16"/><path d="M4 20c4 0 4-16 8-16s4 16 8 16"/></g>,
    search: <g><circle cx="11" cy="11" r="7"/><line x1="16" y1="16" x2="21" y2="21"/></g>,
    download: <g><path d="M12 4v12"/><polyline points="7 11 12 16 17 11"/><line x1="4" y1="20" x2="20" y2="20"/></g>,
    upload: <g><path d="M12 20V8"/><polyline points="7 13 12 8 17 13"/><line x1="4" y1="4" x2="20" y2="4"/></g>,
    copy: <g><rect x="8" y="8" width="12" height="12" rx="2"/><path d="M4 16V6a2 2 0 0 1 2-2h10"/></g>,
    signature: <g><path d="M4 18c4 0 6-10 10-10s2 8 6 8"/><line x1="4" y1="21" x2="20" y2="21"/></g>,
    robot: <g><rect x="5" y="8" width="14" height="11" rx="2"/><line x1="12" y1="4" x2="12" y2="8"/><circle cx="9" cy="13" r="1"/><circle cx="15" cy="13" r="1"/></g>,
    user: <g><circle cx="12" cy="8" r="4"/><path d="M4 20a8 8 0 0 1 16 0"/></g>,
    file: <g><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><polyline points="14 3 14 8 19 8"/></g>,
    play: <polygon points="6 4 20 12 6 20 6 4" fill="currentColor" stroke="none"/>,
    pause: <g><rect x="6" y="5" width="4" height="14"/><rect x="14" y="5" width="4" height="14"/></g>,
    stop: <rect x="6" y="6" width="12" height="12" rx="1" fill="currentColor" stroke="none"/>,
    plus: <g><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></g>,
    external: <g><path d="M15 3h6v6"/><line x1="10" y1="14" x2="21" y2="3"/><path d="M21 14v5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5"/></g>,
    eye: <g><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></g>,
    timer: <g><circle cx="12" cy="13" r="8"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="9" y1="3" x2="15" y2="3"/></g>,
    filter: <polygon points="3 4 21 4 14 13 14 20 10 18 10 13 3 4"/>,
    book: <path d="M4 4h12a4 4 0 0 1 4 4v12H8a4 4 0 0 1-4-4V4z"/>,
    target: <g><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.5" fill="currentColor"/></g>,
    circle: <circle cx="12" cy="12" r="4" fill="currentColor" stroke="none"/>,
    send: <path d="M4 12l16-8-6 16-3-7z"/>,
  };
  return <svg {...s}>{P[name]}</svg>;
};
window.CroIcon = CroIcon;
