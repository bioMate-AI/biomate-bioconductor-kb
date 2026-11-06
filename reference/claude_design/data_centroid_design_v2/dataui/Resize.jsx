/* Resizable, collapsible views. One grip drags one CSS custom property.

   The width a user chose and the width that currently fits are different
   things. The chosen value is the PREFERENCE and lives in storage; what gets
   applied is min(preference, ceiling) where the ceiling is computed from the
   container. Only a drag writes the preference — a transient narrowing must
   never overwrite it, or every window resize ratchets the pane smaller and
   widening never gives it back. */
const PANE_KEY = 'biomate.panes.v1';
function readPanes() { try { return JSON.parse(localStorage.getItem(PANE_KEY) || '{}'); } catch (e) { return {}; } }
function writePane(k, v) { try { const s = readPanes(); s[k] = v; localStorage.setItem(PANE_KEY, JSON.stringify(s)); } catch (e) {} }

function Grip({ prop, min = 180, max = 720, invert, label, measure, keep = 320 }) {
  const [drag, setDrag] = React.useState(false);
  const ref = React.useRef(null);

  const pref = () => { const v = readPanes()[prop]; return typeof v === 'number' ? v : null; };

  /* The ceiling belongs to the container, not to a constant: a pane may never
     take so much width that its sibling collapses. `keep` is the floor the
     sibling is owed. */
  const ceiling = () => {
    const g = ref.current;
    if (!g || !g.parentElement) return max;
    const box = g.parentElement.getBoundingClientRect().width;
    if (box < 240) return max;               // mid-load measurement — not a real constraint
    const gw = g.getBoundingClientRect().width || 6;
    return Math.max(min, Math.min(max, Math.round(box - gw - keep)));
  };

  /* Apply, never persist. With no preference the CSS default wins, so a
     media-query default keeps working. */
  const apply = React.useCallback(() => {
    const p = pref();
    if (p == null) { document.documentElement.style.removeProperty(prop); return; }
    document.documentElement.style.setProperty(prop, Math.max(min, Math.min(p, ceiling())) + 'px');
  }, [prop]);

  React.useEffect(() => {
    apply();
    window.addEventListener('resize', apply);
    return () => window.removeEventListener('resize', apply);
  }, [apply]);

  /* Seed from the applied property when set, otherwise from the pane as
     rendered: a default living in a var() fallback or a media query is
     invisible to getPropertyValue, and falling back to `min` would snap the
     pane to its minimum on the first drag. */
  const startWidth = () => {
    const v = parseFloat(getComputedStyle(document.documentElement).getPropertyValue(prop));
    if (!isNaN(v)) return v;
    const el = (measure && document.querySelector(measure))
      || (ref.current && (invert ? ref.current.nextElementSibling : ref.current.previousElementSibling));
    const w = el && el.getBoundingClientRect().width;
    return w ? Math.round(w) : min;
  };

  const start = e => {
    e.preventDefault();
    const x0 = e.clientX, w0 = startWidth(), hi = ceiling();
    let last = w0;
    setDrag(true);
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
    const move = ev => {
      const d = (ev.clientX - x0) * (invert ? -1 : 1);
      last = Math.max(min, Math.min(hi, Math.round(w0 + d)));
      document.documentElement.style.setProperty(prop, last + 'px');
    };
    const up = () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      setDrag(false);
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
      writePane(prop, last);                 // the only place a preference is written
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
  };

  const reset = () => { writePane(prop, null); document.documentElement.style.removeProperty(prop); };

  return <div ref={ref} className={'grip' + (drag ? ' dragging' : '')} onPointerDown={start} onDoubleClick={reset}
    role="separator" aria-orientation="vertical" aria-label={label || 'Resize'} title={(label || 'Resize') + ' — drag, or double-click to reset'}>
    <span className="griphandle"/>
  </div>;
}

/* Collapsed state, for this session only.
   Deliberately NOT persisted: an app that reopens with its sidebar gone looks
   broken, and the cost of re-hiding it is one click. Widths persist because a
   remembered width is still a visible, working layout; a remembered hide is
   not. Any previously stored hide flags are cleared here. */
(() => { const s = readPanes(); let dirty = false;
  ['sideHid', 'hubListHid'].forEach(k => { if (k in s) { delete s[k]; dirty = true; } });
  if (dirty) { try { localStorage.setItem(PANE_KEY, JSON.stringify(s)); } catch (e) {} } })();

function useCollapse(key, initial = false) {
  return React.useState(initial);
}

/* Never leave a pane hidden with no way back: a collapsed view without a
   reopen control is indistinguishable from a broken one.
   Positioned inline as well as in CSS: as a grid item this button would take
   the stage's only column and squeeze the pane it sits in to zero width, so
   it must not depend on a stylesheet having loaded. */
function Reveal({ side, label, onClick, at = 'top' }) {
  const pos = at === 'static' ? {} : { position:'absolute', zIndex:30, [side === 'left' ? 'left' : 'right']:'10px', [at]:'10px' };
  return <button className={'reveal ' + side} style={pos} onClick={onClick} title={'Show ' + label}>
    <Icon name={side === 'left' ? 'chevronRight' : 'chevronLeft'} size={13}/>
    <span>{label}</span>
  </button>;
}
Object.assign(window, { Grip, useCollapse, Reveal, readPanes, writePane });
