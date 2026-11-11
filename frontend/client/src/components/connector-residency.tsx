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

import { ExternalLink, Folder } from "lucide-react";

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

/** The "where it runs" declared fact (§0.9.1) expressed from the residency when a
 *  connector states no free-text `runsIn`. Residency IS the where-it-runs fact, so
 *  a row with a known residency must never render "where it runs: not declared" —
 *  that would contradict its own residency badge (committee i12-1). Returns
 *  undefined only when residency is itself undeclared, which stays "not declared". */
export function runsInFromResidency(r?: Residency): string | undefined {
  if (!r || !RESIDENCY[r]) return undefined;
  const phrase: Record<Residency, string> = {
    cloud:  'remote endpoint — data leaves the estate',
    onprem: 'inside your network (on-prem)',
    mount:  'read in place (mounted)',
    local:  'this machine — never leaves the host',
    prompt: 'no data moves (prompt only)',
  };
  return phrase[r];
}

/** A residency badge, honest "unspecified" when undeclared.
 *  Styling mirrors the reference `.res` chip (data_centroid_design_v2):
 *  cloud reads as the NEUTRAL default (gray) — not a warning; the secure
 *  residencies (on-prem / mounted / this machine) are green ("data stays
 *  inside"); prompt-only is the blue accent. Pill shape + uppercase + icon. */
export function ResidencyBadge({ residency }: { residency?: Residency }) {
  const d = residencyDisplay(residency);
  const palette: Record<string, { bg: string; fg: string }> = {
    cloud:  { bg: 'var(--bm-surface-3)',   fg: 'var(--bm-text-muted)' }, // gray — leaves the estate (the common default)
    onprem: { bg: 'var(--bm-ok-soft)',     fg: 'var(--bm-ok)' },        // green — stays inside
    mount:  { bg: 'var(--bm-ok-soft)',     fg: 'var(--bm-ok)' },        // green — read in place, never copied
    local:  { bg: 'var(--bm-ok-soft)',     fg: 'var(--bm-ok)' },        // green — never leaves the host
    prompt: { bg: 'var(--bm-accent-soft)', fg: 'var(--bm-accent)' },    // blue — instruction text, moves no data
  };
  const c = d.known && residency ? palette[residency] : { bg: 'var(--bm-surface-3)', fg: 'oklch(0.52 0.16 30)' };
  const Glyph = residency === 'cloud' ? ExternalLink : Folder;
  return (
    <span
      data-testid="residency-badge"
      data-residency={residency || 'unspecified'}
      title={d.why}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 4,
        fontSize: 'var(--fs-xs)', lineHeight: 1.6, padding: '2px 8px', borderRadius: 999, whiteSpace: 'nowrap',
        fontWeight: 600, letterSpacing: '0.03em', textTransform: 'uppercase',
        background: c.bg, color: c.fg,
        border: d.known ? 'none' : '1px dashed oklch(0.72 0.12 30)',
      }}
    >
      {d.known && <Glyph size={9} style={{ flexShrink: 0 }} aria-hidden />}
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
              fontSize: 'var(--fs-xs)', fontWeight: on ? 600 : 400, padding: '2px 7px',
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
