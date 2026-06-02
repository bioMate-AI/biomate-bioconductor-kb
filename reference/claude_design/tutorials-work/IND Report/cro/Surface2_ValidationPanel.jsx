// Surface 2 — PBPK Validation Panel

const ValidationPanel = ({ emaFail = false }) => {
  const [search, setSearch] = React.useState('');
  const [filter, setFilter] = React.useState('all');
  const [shown, setShown] = React.useState(10);
  const report = VALIDATION_REPORT;
  const cmaxOk = emaFail ? false : report.criterion_met.cmax;
  const aucOk = report.criterion_met.auc;
  const overallOk = cmaxOk && aucOk;

  const cmaxPct = emaFail ? 62 : Math.round(report.metrics.cmax.within2 * 100);

  const filteredDrugs = report.drugs.filter(d => {
    if (search && !d.name.toLowerCase().includes(search.toLowerCase())) return false;
    if (filter === 'within2' && d.fold > 2.0) return false;
    if (filter === 'outside2' && d.fold <= 2.0) return false;
    if (filter === 'ood' && d.ad === 'in_domain') return false;
    return true;
  });

  return (
    <div>
      <div className="section-hd">
        <h2 className="h2">Model Validation Report</h2>
        <div className="cite-row">
          <RegChip variant="indigo">EMA/CHMP/EWP/37498/2011</RegChip>
          <RegChip>PBPK Qualification</RegChip>
        </div>
      </div>

      <div className="meta-line">
        <span>Model: <span className="mono">pbpk.v2</span></span>
        <span className="sep">·</span>
        <span>Reference set: 31 drugs</span>
        <span className="sep">·</span>
        <span>Generated {report.generated_at}</span>
        <div style={{ flex: 1 }}/>
        <button className="btn sm"><CroIcon name="refresh" size={12}/> Re-run</button>
        <button className="btn sm"><CroIcon name="download" size={12}/> Download PDF</button>
      </div>

      <div data-tour="validation-callout">
        <Callout
          tone={overallOk ? 'ok' : 'err'}
          icon={<CroIcon name={overallOk ? 'checkCircle' : 'xCircle'} size={18}/>}
          title={overallOk ? 'EMA 2-FOLD CRITERION MET' : 'EMA 2-FOLD CRITERION FAILED'}
          rows={[
            <><b>Cmax:</b> {cmaxPct}% within 2-fold {cmaxOk ? '(≥67% required ✓)' : '(< 67% required ✗)'}</>,
            <><b>AUC:</b> {Math.round(report.metrics.auc.within2 * 100)}% within 2-fold {aucOk ? '(≥67% required ✓)' : '(✗)'}</>,
          ]}
        />
      </div>

      <Collapsible title="Aggregate Metrics" sub="AFE, AAFE, R², fold distribution" defaultOpen>
        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th style={{ width: 120 }}>Metric</th>
                <th>Cmax</th>
                <th>AUC</th>
                <th style={{ width: 200, color: 'var(--text-dim)' }}>Interpretation</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>AFE</td>
                <td className="num">{report.metrics.cmax.afe.toFixed(2)}</td>
                <td className="num">{report.metrics.auc.afe.toFixed(2)}</td>
                <td style={{ color: 'var(--text-dim)', fontSize: 12 }}>Average fold error</td>
              </tr>
              <tr>
                <td>AAFE</td>
                <td className="num">{report.metrics.cmax.aafe.toFixed(2)}</td>
                <td className="num">{report.metrics.auc.aafe.toFixed(2)}</td>
                <td style={{ color: 'var(--text-dim)', fontSize: 12 }}>Absolute avg fold error</td>
              </tr>
              <tr>
                <td>R²</td>
                <td className="num">{report.metrics.cmax.r2.toFixed(2)}</td>
                <td className="num">{report.metrics.auc.r2.toFixed(2)}</td>
                <td style={{ color: 'var(--text-dim)', fontSize: 12 }}>Log-log correlation</td>
              </tr>
              <tr>
                <td>Within 2×</td>
                <td className="num" style={{ color: cmaxOk ? 'var(--ok)' : 'var(--err)' }}>{cmaxPct}%</td>
                <td className="num" style={{ color: 'var(--ok)' }}>{Math.round(report.metrics.auc.within2 * 100)}%</td>
                <td style={{ color: 'var(--text-dim)', fontSize: 12 }}>EMA threshold: ≥67%</td>
              </tr>
              <tr>
                <td>Within 3×</td>
                <td className="num">{Math.round(report.metrics.cmax.within3 * 100)}%</td>
                <td className="num">{Math.round(report.metrics.auc.within3 * 100)}%</td>
                <td style={{ color: 'var(--text-dim)', fontSize: 12 }}>Advisory only</td>
              </tr>
            </tbody>
          </table>
        </div>
      </Collapsible>

      <Collapsible title="Per-Compound Results" sub={`${report.drugs.length} drugs`} defaultOpen>
        <div className="filter-bar">
          <div className="search">
            <CroIcon name="search" size={13} className="ic" />
            <input placeholder="Search drugs…" value={search} onChange={(e) => setSearch(e.target.value)}/>
          </div>
          <div className="select">
            <select value={filter} onChange={(e) => setFilter(e.target.value)}>
              <option value="all">All results</option>
              <option value="within2">Within 2×</option>
              <option value="outside2">Outside 2×</option>
              <option value="ood">OOD only</option>
            </select>
          </div>
          <div className="spacer"/>
          <span style={{ fontSize: 12, color: 'var(--text-dim)' }}>
            Showing {Math.min(shown, filteredDrugs.length)} of {filteredDrugs.length}
          </span>
        </div>

        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th>Drug</th>
                <th style={{ width: 110, textAlign: 'right' }}>Obs Cmax</th>
                <th style={{ width: 110, textAlign: 'right' }}>Pred Cmax</th>
                <th style={{ width: 120 }}>Fold Error</th>
                <th style={{ width: 120 }}>AD</th>
              </tr>
            </thead>
            <tbody>
              {filteredDrugs.slice(0, shown).map(d => (
                <tr key={d.name}>
                  <td>{d.name}</td>
                  <td className="num">{d.obs_cmax}</td>
                  <td className="num">{d.pred_cmax}</td>
                  <td><FoldCell fold={d.fold}/></td>
                  <td><AdCell status={d.ad}/></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {shown < filteredDrugs.length && (
          <button className="btn sm" style={{ marginTop: 10 }} onClick={() => setShown(s => s + 10)}>
            Load more
          </button>
        )}

        <div style={{ fontSize: 11.5, color: 'var(--text-dim)', marginTop: 12, fontStyle: 'italic' }}>
          1 drug excluded from validation (Clopidogrel — prodrug; CL_true exceeds hepatic blood flow).
        </div>
      </Collapsible>
    </div>
  );
};

window.ValidationPanel = ValidationPanel;
