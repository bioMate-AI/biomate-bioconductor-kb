// @ts-nocheck
// Surface 1 — Plan Checklist (sticky strip above the chat thread)
//
// Props:
//   items: PlanItem[]
//   editing: bool                          // whether user is in edit mode
//   collapsed: bool                        // collapsed-to-pill state
//   onToggleCollapsed: () => void
//   onEditDone: () => void                 // user clicked "Lock and run"
//   onEditCancel?: () => void
//   onRemoveItem: (id) => void
//   onAddItem: () => void
//   onReorder: (fromIdx, toIdx) => void
//   onItemAction: (id, action) => void     // 'retry' | 'skip' | 'ask_agent'
//   editLockCountdown?: { label, remaining, total }  // ticking auto-lock
//   density?: 'comfortable' | 'compact'
const { useState, useEffect, useRef } = React;

function PlanItem({ item, editing, onRemove, onAction, parallelTopOf, parallelBotOf }) {
  const stateClass = item.status; // pending|running|done|warn|failed|skipped
  const meta = item.meta || {};

  return (
    <React.Fragment>
      <div
        className={'plan-item ' + stateClass + (item.parent ? ' nested' : '') + (editing ? ' editing' : '')}
        data-plan-id={item.id}
      >
        {editing && <button className="pi-grip" title="Drag to reorder">⋮⋮</button>}
        <span className="pi-status" aria-label={item.status} />
        <span className="pi-title" title={item.title}>{item.title}</span>

        {item.parallel && (
          <span className="pi-parallel" title="Runs in parallel with grouped items">⇄</span>
        )}

        {item.status === 'running' && (
          <span className="pi-running-label">running…</span>
        )}
        {item.status === 'pending' && item.est_s && !editing && (
          <span className="pi-meta">~{fmtDur(item.est_s)}</span>
        )}
        {item.status === 'done' && item.actual_s && (
          <span className="pi-meta">{fmtDur(item.actual_s)}</span>
        )}

        {editing && (
          <button className="pi-rm" title="Remove" onClick={() => onRemove(item.id)}>
            <Icon name="x" size={11}/>
          </button>
        )}
      </div>

      {item.status === 'failed' && (
        <div className="plan-item-fail">
          <div>{item.failReason || 'Step failed.'}</div>
          <div className="pf-actions">
            <button className="btn sm" onClick={() => onAction(item.id, 'retry')}>
              <Icon name="refresh" size={11}/> Retry
            </button>
            <button className="btn sm" onClick={() => onAction(item.id, 'skip')}>
              <Icon name="skip" size={11}/> Skip
            </button>
            <button className="btn sm ghost" onClick={() => onAction(item.id, 'ask_agent')}>
              Ask DeepAgent
            </button>
          </div>
        </div>
      )}
    </React.Fragment>
  );
}

function fmtDur(seconds) {
  if (seconds < 60) return seconds + 's';
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return s ? `${m}m ${s}s` : `${m}m`;
}

function PlanChecklist({
  items, editing, collapsed,
  onToggleCollapsed, onEditDone, onEditCancel,
  onRemoveItem, onAddItem, onItemAction,
  editLockCountdown,
}) {
  if (!items || items.length === 0) return null;

  const total = items.length;
  const done  = items.filter(i => i.status === 'done').length;
  const failed = items.filter(i => i.status === 'failed').length;
  const running = items.filter(i => i.status === 'running').length;
  const skipped = items.filter(i => i.status === 'skipped').length;
  const pct = Math.round((done / total) * 100);

  // Build a render list that injects parallel-group wrappers
  const renderRows = [];
  let i = 0;
  while (i < items.length) {
    const it = items[i];
    if (it.parallel) {
      // collect contiguous run of same parallel
      const group = [];
      while (i < items.length && items[i].parallel === it.parallel) {
        group.push(items[i]); i++;
      }
      renderRows.push(
        <div key={'pg-' + it.parallel} className="plan-parallel-group">
          {group.map(g => (
            <PlanItem key={g.id} item={g} editing={editing}
              onRemove={onRemoveItem} onAction={onItemAction}/>
          ))}
        </div>
      );
    } else {
      renderRows.push(
        <PlanItem key={it.id} item={it} editing={editing}
          onRemove={onRemoveItem} onAction={onItemAction}/>
      );
      i++;
    }
  }

  const headLabel =
    collapsed
      ? `Plan · ${done} of ${total} done`
      : (running > 0 ? 'Plan · running' : `Plan · ${done} of ${total} done`);

  return (
    <div className={'plan-checklist' + (collapsed ? ' collapsed' : '') + (editing ? ' editing' : '')}
      data-tour="plan-checklist">
      <div className="plan-head">
        <button className="iconbtn" onClick={onToggleCollapsed} title={collapsed ? 'Expand plan' : 'Collapse plan'}>
          <Icon name={collapsed ? 'chevronRight' : 'chevronDown'} size={11}/>
        </button>
        <span className="label">{headLabel}</span>
        <span className="count">
          {done}/{total}
          {failed > 0 && <span style={{color:'var(--err)'}}> · {failed} failed</span>}
          {skipped > 0 && <span style={{color:'var(--text-dim)'}}> · {skipped} skipped</span>}
        </span>
        <div className="plan-progress">
          <div className="fill" style={{width: pct + '%'}}/>
        </div>
        <span className="spacer"/>
        {editing ? (
          <button className="iconbtn active" onClick={onEditDone}>
            <Icon name="check" size={12}/> Lock and run
          </button>
        ) : (
          !running && !done && (
            <button className="iconbtn" onClick={() => onEditCancel && onEditCancel()} title="Edit plan">
              edit
            </button>
          )
        )}
      </div>

      <div className="plan-body">
        {renderRows}
        {editing && (
          <button className="plan-add" onClick={onAddItem}>
            <Icon name="plus" size={11}/> Add step
          </button>
        )}
      </div>

      {editing && editLockCountdown && (
        <div className="plan-countdown">
          <span>Locking automatically in {editLockCountdown.remaining}s — edit to extend.</span>
          <div className="cd-bar">
            <div className="cd-fill" style={{width: (100 * editLockCountdown.remaining / editLockCountdown.total) + '%'}}/>
          </div>
        </div>
      )}
    </div>
  );
}

Object.assign(window, { PlanChecklist, fmtDur });
