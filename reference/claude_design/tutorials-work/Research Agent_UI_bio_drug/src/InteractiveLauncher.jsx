// InteractiveLauncher — design-fidelity port of the production
// `interactive-launcher.tsx`. A modal that spawns an interactive computing
// environment (RStudio / Jupyter / CellxGene) against a run's outputs, so a
// scientist can poke at a .rds / .csv / .h5ad file in a live kernel without
// leaving BioMate.
//
// Entry points (both wired in this prototype):
//   • Per-output "Open in RStudio" / "Open in CellxGene" button on each
//     After-run Outputs row (.rds/.rdata → RStudio, .h5ad → CellxGene).
//   • Tour step that opens it via window.__openTourModal('launcher', {...}).
//
// NOTE FOR PORT: launch here is mocked the way the rest of the prototype
// mocks SSE — a short delay then a synthetic {entry_point_url, state}. In
// production this POSTs /api/interactive/launch → Galaxy POST /api/tools
// with tool_id ∈ {interactive_tool_jupyter_notebook, _rstudio, _cellxgene}.

(function () {
  const { useState: useStateIL, useMemo: useMemoIL } = React;

  // ── Environment catalogue ─────────────────────────────────────
  const IL_ENVS = [
    {
      id: 'rstudio', name: 'RStudio', icon: 'monitor',
      desc: 'R 4.3 statistical computing environment',
      best: 'Statistical analysis, Bioconductor', kernel: 'R',
      pkgs: ['DESeq2', 'edgeR', 'ggplot2', 'tidyverse'], more: 1,
      toolId: 'interactive_tool_rstudio', launchLabel: 'Launch RStudio',
    },
    {
      id: 'jupyter', name: 'Jupyter Notebook', icon: 'terminal',
      desc: 'Python 3.10 interactive environment',
      best: 'Custom analysis, visualization, ML', kernel: 'python',
      pkgs: ['pandas', 'numpy', 'matplotlib', 'seaborn'], more: 2,
      toolId: 'interactive_tool_jupyter_notebook', launchLabel: 'Launch Jupyter',
    },
    {
      id: 'cellxgene', name: 'CellxGene', icon: 'cells',
      desc: 'Interactive single-cell visualization',
      best: 'Single-cell RNA-seq exploration', kernel: 'python',
      pkgs: ['Scanpy', 'UMAP/t-SNE', 'Gene expression'], more: 0,
      toolId: 'interactive_tool_cellxgene', launchLabel: 'Launch CellxGene',
    },
  ];
  const IL_ENV_BY_ID = Object.fromEntries(IL_ENVS.map(e => [e.id, e]));

  const ilExt = (name) => (String(name).split('.').pop() || '').toLowerCase();

  // Routing rule for the per-output button. RStudio for R-native objects,
  // CellxGene for AnnData. (.csv/.tsv default to RStudio in these
  // Bioconductor-flavoured tutorials, so they don't get their own button.)
  function ilRowTarget(name) {
    const ext = ilExt(name);
    if (ext === 'rds' || ext === 'rdata') return 'rstudio';
    if (ext === 'h5ad') return 'cellxgene';
    return null;
  }

  // Deterministic file size so a given filename always reads the same MB.
  function ilSize(name) {
    let h = 2166136261;
    for (let i = 0; i < name.length; i++) { h ^= name.charCodeAt(i); h = Math.imul(h, 16777619); }
    const ext = ilExt(name);
    const span = ext === 'png' || ext === 'pdf' ? 6 : ext === 'csv' || ext === 'tsv' ? 18 : 56;
    const base = ext === 'png' || ext === 'pdf' ? 1 : 3;
    return base + ((h >>> 0) % span);
  }

  // Variable name from a filename: dds.rds → dds, deseq_results.rds → deseq_results
  const ilVar = (name) => String(name).replace(/\.[^.]+$/, '').replace(/[^a-zA-Z0-9_]/g, '_');

  // Icon + honest type label for an output. An .rds is a serialized R object,
  // not a table — so we label by extension and only use the grid icon for
  // genuinely tabular files (csv/tsv).
  function ilFileMeta(name, type) {
    const ext = ilExt(name);
    const hasExt = ext && ext !== String(name).toLowerCase();
    const label = hasExt ? ext : (type || 'file');
    let icon = 'file';
    if (type === 'folder') icon = 'folder';
    else if (type === 'image' || ['png', 'jpg', 'jpeg', 'svg', 'gif', 'tif', 'tiff'].includes(ext)) icon = 'image';
    else if (['csv', 'tsv', 'tab', 'txt'].includes(ext)) icon = 'table';
    else if (['rds', 'rdata', 'rda', 'h5', 'h5ad', 'hdf5', 'pkl', 'mrc', 'star', 'pdf'].includes(ext)) icon = 'file';
    else if (type === 'table') icon = 'table';
    return { icon, label, ext };
  }

  // ── Quick-start snippet, keyed on env kernel + selected files ──
  // Returns an array of {t, cls?} tokens-per-line for light syntax tint.
  function ilQuickStart(env, files) {
    const lines = [];
    const L = (parts) => lines.push(Array.isArray(parts) ? parts : [{ t: parts }]);
    if (env.kernel === 'R') {
      L([{ t: 'library', cls: 'il-fn' }, { t: '(tidyverse)' }]);
      L([{ t: '# Your data is in /data/', cls: 'il-cmt' }]);
      files.forEach(f => {
        const ext = ilExt(f);
        const v = ilVar(f);
        if (ext === 'rds' || ext === 'rdata') {
          L([{ t: `${v} <- ` }, { t: 'readRDS', cls: 'il-fn' }, { t: '(' }, { t: `'/data/${f}'`, cls: 'il-str' }, { t: ')' }]);
        } else if (ext === 'csv') {
          L([{ t: `${v} <- ` }, { t: 'read_csv', cls: 'il-fn' }, { t: '(' }, { t: `'/data/${f}'`, cls: 'il-str' }, { t: ')' }]);
        } else if (ext === 'tsv') {
          L([{ t: `${v} <- ` }, { t: 'read_tsv', cls: 'il-fn' }, { t: '(' }, { t: `'/data/${f}'`, cls: 'il-str' }, { t: ')' }]);
        } else {
          L([{ t: `# /data/${f}`, cls: 'il-cmt' }]);
        }
      });
    } else if (env.id === 'cellxgene') {
      L([{ t: 'import scanpy as sc', cls: 'il-fn' }]);
      L([{ t: '# Loaded into the CellxGene viewer:', cls: 'il-cmt' }]);
      files.forEach(f => {
        const v = ilVar(f);
        if (ilExt(f) === 'h5ad') {
          L([{ t: `${v} = ` }, { t: 'sc.read_h5ad', cls: 'il-fn' }, { t: '(' }, { t: `'/data/${f}'`, cls: 'il-str' }, { t: ')' }]);
        } else {
          L([{ t: `# /data/${f}`, cls: 'il-cmt' }]);
        }
      });
      L([{ t: '# Explore embeddings & gene expression in the web UI.', cls: 'il-cmt' }]);
    } else {
      L([{ t: 'import pandas as pd', cls: 'il-fn' }]);
      L([{ t: '# Your data is in /data/', cls: 'il-cmt' }]);
      files.forEach(f => {
        const ext = ilExt(f);
        const v = ilVar(f);
        if (ext === 'csv') {
          L([{ t: `${v} = ` }, { t: 'pd.read_csv', cls: 'il-fn' }, { t: '(' }, { t: `'/data/${f}'`, cls: 'il-str' }, { t: ')' }]);
        } else if (ext === 'tsv') {
          L([{ t: `${v} = ` }, { t: 'pd.read_csv', cls: 'il-fn' }, { t: '(' }, { t: `'/data/${f}'`, cls: 'il-str' }, { t: `, sep=` }, { t: `'\\t'`, cls: 'il-str' }, { t: ')' }]);
        } else {
          L([{ t: `# /data/${f}`, cls: 'il-cmt' }]);
        }
      });
    }
    return lines;
  }

  const ilPlainCode = (lines) => lines.map(l => l.map(tok => tok.t).join('')).join('\n');

  // ── Normalise an outputs prop into [{name, size}] ─────────────
  function ilNormalize(outputs) {
    const seen = new Set();
    const out = [];
    (outputs || []).forEach(o => {
      const name = typeof o === 'string' ? o : (o.file || o.name);
      if (!name || seen.has(name)) return;
      seen.add(name);
      out.push({ name, size: (o && o.size) || ilSize(name) });
    });
    return out;
  }

  // ── The modal ─────────────────────────────────────────────────
  function InteractiveLauncherModal({ outputs, initialEnv, initialFile, onClose }) {
    const files = useMemoIL(() => ilNormalize(outputs), [outputs]);
    const [envId, setEnvId] = useStateIL(initialEnv || (initialFile && ilRowTarget(initialFile)) || 'rstudio');
    const [selected, setSelected] = useStateIL(() => {
      if (initialFile && files.some(f => f.name === initialFile)) return [initialFile];
      return files.length ? [files[0].name] : [];
    });
    const [launching, setLaunching] = useStateIL(false);
    const [session, setSession] = useStateIL(null); // {state, url}
    const [copied, setCopied] = useStateIL(false);

    const env = IL_ENV_BY_ID[envId];
    const allOn = selected.length === files.length && files.length > 0;

    const toggleFile = (name) => setSelected(s =>
      s.includes(name) ? s.filter(n => n !== name) : [...s, name]);
    const toggleAll = () => setSelected(allOn ? [] : files.map(f => f.name));

    const launch = () => {
      setLaunching(true);
      setTimeout(() => {
        setLaunching(false);
        setSession({
          state: 'running',
          url: `https://${env.id}-7f3a.interactive.biomate.run/`,
        });
      }, 1500);
    };

    // Selected files in display order
    const selFiles = files.filter(f => selected.includes(f.name)).map(f => f.name);
    const codeLines = useMemoIL(() => ilQuickStart(env, selFiles.length ? selFiles : ['data.rds']),
      [envId, selected.join('|')]);

    const copyCode = () => {
      const text = ilPlainCode(codeLines);
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text);
      } catch (e) { /* clipboard blocked in sandbox — visual feedback only */ }
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    };

    return (
      <div className="modal-backdrop" onClick={onClose}>
        <div className="modal il-modal interactive-launcher" onClick={e => e.stopPropagation()}>
          <div className="il-head">
            <div>
              <h3>Launch a live environment</h3>
              <div className="il-sub">
                {session
                  ? 'Your environment is running — open it in a new tab or copy the quick-start code.'
                  : 'Explore your workflow outputs in a live R or Python environment.'}
              </div>
            </div>
            <button className="btn ghost sm" onClick={onClose} aria-label="Close"><Icon name="x" size={14}/></button>
          </div>

          {!session ? (
            <React.Fragment>
              <div className="il-body">
                {/* Environment picker */}
                <div className="il-section-label">Choose environment</div>
                <div className="il-tiles">
                  {IL_ENVS.map(e => (
                    <div key={e.id}
                      className={'il-tile' + (e.id === envId ? ' sel' : '')}
                      onClick={() => setEnvId(e.id)}>
                      <span className="il-radio"/>
                      <div>
                        <div className="il-tile-name">
                          <span className="il-ico"><Icon name={e.icon} size={15}/></span>{e.name}
                        </div>
                        <div className="il-tile-desc">{e.desc}</div>
                        <div className="il-tile-best">Best for: <b>{e.best}</b></div>
                        <div className="il-chips">
                          {e.pkgs.map(p => <span key={p} className="il-chip">{p}</span>)}
                          {e.more > 0 && <span className="il-chip more">+{e.more} more</span>}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>

                {/* Output picker */}
                <div className="il-section-label">
                  Data to load
                  {files.length > 0 && <button className="il-link" onClick={toggleAll}>{allOn ? 'Clear all' : 'Select all'}</button>}
                </div>
                <div className="il-picker">
                  {files.length === 0 && (
                    <div className="il-picker-foot" style={{borderTop: 'none'}}>No outputs available for this run.</div>
                  )}
                  {files.map(f => (
                    <div key={f.name}
                      className={'il-file-row' + (selected.includes(f.name) ? ' on' : '')}
                      onClick={() => toggleFile(f.name)}>
                      <span className="il-check"><Icon name="check" size={11} stroke={3}/></span>
                      <span className="il-file-name">
                        <span className="il-fico"><Icon name={ilFileMeta(f.name).icon} size={12}/></span>
                        <span>{f.name}</span>
                      </span>
                      <span className="il-file-size">{f.size} MB</span>
                    </div>
                  ))}
                  {files.length > 0 && (
                    <div className="il-picker-foot">
                      {selected.length} file{selected.length === 1 ? '' : 's'} selected
                    </div>
                  )}
                </div>

                {/* Timeout notice */}
                <div className="il-alert info">
                  <span className="il-alert-ico"><Icon name="info" size={15}/></span>
                  <div>Live environments shut down after <b>2 hours</b> of inactivity. Your work is saved back to the run history.</div>
                </div>
              </div>

              <div className="il-foot">
                <span className="il-foot-spacer"/>
                <button className="btn ghost" onClick={onClose}>Cancel</button>
                <button className="btn accent il-launch-btn"
                  disabled={launching || selected.length === 0}
                  onClick={launch}>
                  {launching
                    ? <React.Fragment><span className="il-spinner"/>Launching…</React.Fragment>
                    : <React.Fragment><Icon name={env.icon} size={14}/>{env.launchLabel}</React.Fragment>}
                </button>
              </div>
            </React.Fragment>
          ) : (
            <React.Fragment>
              <div className="il-body">
                <div className="il-alert ok">
                  <span className="il-alert-ico"><Icon name="circleCheck" size={17}/></span>
                  <div>
                    <div className="il-alert-title">{env.name} is ready</div>
                    <div className="il-alert-body">Your live environment is running.</div>
                    <div className="il-alert-state">state: {session.state}</div>
                  </div>
                </div>

                <a className="btn accent il-open-tab" href={session.url} target="_blank" rel="noopener noreferrer"
                  onClick={(e) => { /* sandbox: url won't resolve, that's expected in the demo */ }}>
                  <Icon name="external" size={15}/> Open {env.name} in new tab
                </a>

                <div className="il-code-head">
                  <span className="il-code-title">Quick-start code</span>
                  <button className={'il-copy-btn' + (copied ? ' done' : '')} onClick={copyCode}>
                    <Icon name={copied ? 'check' : 'copy'} size={12}/> {copied ? 'Copied' : 'Copy'}
                  </button>
                </div>
                <div className="il-code">
                  {codeLines.map((line, i) => (
                    <div key={i}>{line.map((tok, j) => <span key={j} className={tok.cls || ''}>{tok.t}</span>)}{'\n'}</div>
                  ))}
                </div>

                <div className="il-preload-title">Pre-loaded data</div>
                <ul className="il-preload">
                  {(selFiles.length ? selFiles : []).map(f => (
                    <li key={f}><span className="il-dot"/><span>/data/{f}</span></li>
                  ))}
                </ul>
              </div>

              <div className="il-foot">
                <span className="il-foot-spacer"/>
                <button className="btn" onClick={onClose}>Close</button>
              </div>
            </React.Fragment>
          )}
        </div>
      </div>
    );
  }

  // Small inline trigger used on each After-run Outputs row.
  function InteractiveLaunchTrigger({ file, onOpen }) {
    const target = ilRowTarget(file);
    if (!target) return null;
    const env = IL_ENV_BY_ID[target];
    return (
      <button className="il-open-link" onClick={() => onOpen(target)} title={`Spin up ${env.name} with ${file} pre-loaded`}>
        <Icon name={env.icon} size={11}/> Open in {env.name}
      </button>
    );
  }

  window.InteractiveLauncherModal = InteractiveLauncherModal;
  window.InteractiveLaunchTrigger = InteractiveLaunchTrigger;
  window.ilRowTarget = ilRowTarget;
  window.ilFileMeta = ilFileMeta;
})();
