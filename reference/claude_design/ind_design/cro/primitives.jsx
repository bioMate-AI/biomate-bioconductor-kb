// Shared primitives for CRO surfaces

const RegChip = ({ variant = 'default', children }) => (
  <span className={`reg-chip ${variant === 'indigo' ? 'indigo' : ''}`}>{children}</span>
);

const Chip = ({ tone = 'default', children, pulse = false }) => (
  <span className={`chip ${tone}`}>
    {pulse ? <span className="dot pulse"/> : tone !== 'default' ? <span className="dot"/> : null}
    {children}
  </span>
);

const Callout = ({ tone = 'info', icon, title, rows, children }) => (
  <div className={`callout ${tone}`}>
    <div className="ic">{icon || <CroIcon name="info" size={16}/>}</div>
    <div className="body">
      <div className="title">{title}</div>
      {rows && rows.length > 0 && (
        <div className="row">
          {rows.map((r, i) => <span key={i}>{r}</span>)}
        </div>
      )}
      {children}
    </div>
  </div>
);

const Collapsible = ({ title, sub, defaultOpen = false, children }) => {
  const [open, setOpen] = React.useState(defaultOpen);
  return (
    <div className="collapsible">
      <button className={`col-trigger ${open ? 'open' : ''}`} onClick={() => setOpen(!open)}>
        <CroIcon name="chevronRight" size={14} className="caret"/>
        <span className="title">{title}</span>
        {sub && <span className="sub">{sub}</span>}
      </button>
      {open && <div className="col-content">{children}</div>}
    </div>
  );
};

const ScoreBar = ({ score }) => {
  const klass = score >= 0.7 ? 'good' : score >= 0.4 ? 'mid' : 'bad';
  return (
    <div className="score-bar">
      <div className="bar"><div className={`fill ${klass}`} style={{ width: `${score * 100}%` }}/></div>
      <span className="val">{score.toFixed(2)}</span>
    </div>
  );
};

const AdCell = ({ status }) => (
  status === 'in_domain'
    ? <span className="cell-ad-in"><CroIcon name="check" size={12}/> in domain</span>
    : <span className="cell-ad-out">⚠ OOD</span>
);

const FoldCell = ({ fold }) => (
  fold <= 2.0
    ? <span className="cell-pass">{fold.toFixed(2)} <CroIcon name="check" size={12}/></span>
    : <span className="cell-fail">{fold.toFixed(2)} ✗</span>
);

const Modal = ({ title, sub, onClose, children, footer, wide = false }) => (
  <div className="modal-backdrop" onClick={onClose}>
    <div className={`modal ${wide ? 'wide' : ''}`} onClick={(e) => e.stopPropagation()}>
      <div className="head">
        <h3>{title}</h3>
        {sub && <div className="sub">{sub}</div>}
      </div>
      <div className="body">{children}</div>
      {footer && <div className="foot">{footer}</div>}
    </div>
  </div>
);

const Toast = ({ text, onDone }) => {
  React.useEffect(() => {
    const t = setTimeout(() => onDone && onDone(), 2000);
    return () => clearTimeout(t);
  }, []);
  return <div className="toast">{text}</div>;
};

// Very simple on-canvas QR render (mock — 21x21 grid of deterministic squares so it LOOKS like a QR)
const QrMock = () => {
  const N = 21;
  const cells = [];
  const seed = (i, j) => ((i * 7 + j * 13 + i * j) % 5) === 0 || ((i + j * 3) % 7) === 1;
  for (let i = 0; i < N; i++) for (let j = 0; j < N; j++) {
    const finder = (i < 7 && j < 7) || (i < 7 && j >= N-7) || (i >= N-7 && j < 7);
    const on = finder
      ? (i === 0 || i === 6 || j === 0 || j === 6 || (i >= 2 && i <= 4 && j >= 2 && j <= 4) ||
         (i === 0 || i === 6 || j === (N-7) || j === (N-1)) && (i < 7))
      : seed(i, j);
    if (on) cells.push(<rect key={`${i}-${j}`} x={j} y={i} width="1" height="1" fill="#111"/>);
  }
  // ensure the 3 finder squares are correctly drawn
  const finder = (ox, oy) => (
    <g key={`f-${ox}-${oy}`}>
      <rect x={ox} y={oy} width="7" height="7" fill="#111"/>
      <rect x={ox+1} y={oy+1} width="5" height="5" fill="#fff"/>
      <rect x={ox+2} y={oy+2} width="3" height="3" fill="#111"/>
    </g>
  );
  return (
    <div className="qr-frame">
      <svg viewBox={`0 0 ${N} ${N}`} shapeRendering="crispEdges">
        <rect x="0" y="0" width={N} height={N} fill="#fff"/>
        {cells}
        {finder(0, 0)}
        {finder(N-7, 0)}
        {finder(0, N-7)}
      </svg>
    </div>
  );
};

Object.assign(window, { RegChip, Chip, Callout, Collapsible, ScoreBar, AdCell, FoldCell, Modal, Toast, QrMock });
