/**
 * Connector residency + declared-facts + scope model.
 *
 * Implements spec 00 §0.9 (Connectors: four sections, one surface):
 *   §0.9.1 Declared facts, not categories — a connector states what it NEEDS,
 *          what it PRODUCES, and WHERE IT RUNS. Those are facts, not a taxonomy.
 *   §0.9.2 Three scopes — Account (connected) / Project (on here) /
 *          Request (on for this question); one library, one state.
 *   §0.9.3 Residency is a PROPERTY of every connector, shown on every row with
 *          no exceptions: cloud / on-prem / mounted / this machine / prompt only.
 *
 * Honesty rule (§0.9.3 "No blank residency"): a row with no marker is worse than
 * a wrong one. Where a connector does not declare its residency or facts, we show
 * an explicit "unspecified" / "not declared" rather than guessing a value.
 */

// ── Residency (§0.9.3) ───────────────────────────────────────────────────────

export type Residency = 'cloud' | 'onprem' | 'mount' | 'local' | 'prompt';

/** label + the "does my data leave?" explanation, mirroring reference RESIDENCY. */
export const RESIDENCY: Record<Residency, { label: string; why: string }> = {
  cloud:  { label: 'cloud',        why: 'data leaves the estate' },
  onprem: { label: 'on-prem',      why: 'stays inside your network' },
  mount:  { label: 'mounted',      why: 'read in place, never copied' },
  local:  { label: 'this machine', why: 'never leaves the host' },
  prompt: { label: 'prompt only',  why: 'instruction text — moves no data' },
};

/** Honest fallback when a connector declares no residency (§0.9.3 no-blank rule). */
export const RESIDENCY_UNSPECIFIED = {
  label: 'residency: unspecified',
  why: 'this connector has not declared where it runs',
} as const;

// ── Scope (§0.9.2) ───────────────────────────────────────────────────────────

export type Scope = 'account' | 'project' | 'request';

export const SCOPE_META: Record<Scope, { label: string; means: string }> = {
  account: { label: 'Account', means: 'Connected — available to the whole workspace' },
  project: { label: 'Project', means: 'On here — a switch per item, per project' },
  request: { label: 'Request', means: 'On for this question — set in the composer' },
};

// ── Declared facts (§0.9.1) ──────────────────────────────────────────────────

export interface DeclaredFacts {
  /** where it runs — the residency property, on every row */
  residency?: Residency;
  /** what it needs to run (inputs / connection / entitlement) */
  needs?: string;
  /** what it produces (an artifact → runs as a step; none → recorded on the answer) */
  produces?: string;
  /** where it executes, in words (compute / host) */
  runsIn?: string;
}

/** Honest placeholder used wherever a declared fact is absent. */
export const NOT_DECLARED = 'not declared';

export function residencyDisplay(r?: Residency): { label: string; why: string; known: boolean } {
  if (r && RESIDENCY[r]) return { ...RESIDENCY[r], known: true };
  return { ...RESIDENCY_UNSPECIFIED, known: false };
}

/** A residency badge, honest "unspecified" when undeclared. */
export function ResidencyBadge({ residency }: { residency?: Residency }) {
  const d = residencyDisplay(residency);
  const palette: Record<string, { bg: string; fg: string }> = {
    cloud:  { bg: 'oklch(0.93 0.05 55)',  fg: 'oklch(0.42 0.13 55)' },   // amber — leaves the estate
    onprem: { bg: 'oklch(0.93 0.05 150)', fg: 'oklch(0.38 0.12 150)' },  // green — stays inside
    mount:  { bg: 'oklch(0.93 0.04 220)', fg: 'oklch(0.40 0.11 220)' },  // blue — read in place
    local:  { bg: 'oklch(0.93 0.04 280)', fg: 'oklch(0.40 0.12 280)' },  // violet — this host
    prompt: { bg: 'var(--muted)',         fg: 'var(--muted-foreground)' },// neutral — no data moves
  };
  const c = d.known && residency ? palette[residency] : { bg: 'oklch(0.95 0.03 30)', fg: 'oklch(0.52 0.16 30)' };
  return (
    <span
      data-testid="residency-badge"
      data-residency={residency || 'unspecified'}
      title={d.why}
      style={{
        fontSize: 10, padding: '1px 6px', borderRadius: 4, whiteSpace: 'nowrap',
        fontWeight: 600, background: c.bg, color: c.fg,
        border: d.known ? 'none' : '1px dashed oklch(0.72 0.12 30)',
      }}
    >
      {d.label}
    </span>
  );
}

/** A small scope selector — one library, one state (§0.9.2). */
export function ScopeSelector({
  scope, onChange, idBase,
}: { scope: Scope; onChange: (s: Scope) => void; idBase: string }) {
  const order: Scope[] = ['account', 'project', 'request'];
  return (
    <span
      data-testid="scope-selector"
      data-scope={scope}
      style={{ display: 'inline-flex', border: '1px solid var(--border)', borderRadius: 5, overflow: 'hidden' }}
      onClick={e => e.stopPropagation()}
    >
      {order.map(s => {
        const on = s === scope;
        return (
          <button
            key={s}
            type="button"
            data-testid={`scope-${idBase}-${s}`}
            title={SCOPE_META[s].means}
            aria-pressed={on}
            onClick={e => { e.stopPropagation(); onChange(s); }}
            style={{
              fontSize: 10, fontWeight: on ? 600 : 400, padding: '2px 7px',
              border: 'none', cursor: 'pointer', whiteSpace: 'nowrap',
              background: on ? 'oklch(0.88 0.06 260)' : 'transparent',
              color: on ? 'oklch(0.33 0.12 260)' : 'var(--muted-foreground)',
            }}
          >
            {SCOPE_META[s].label}
          </button>
        );
      })}
    </span>
  );
}
