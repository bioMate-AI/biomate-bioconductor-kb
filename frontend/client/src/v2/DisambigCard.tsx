/**
 * v2 DisambigCard — Bioconductor handoff §3.5 + ChatCards.jsx reference port.
 *
 * Rendered when the backend returns workflow_type='disambiguation' (two or more
 * KB matches scored close enough that BioMate cannot confidently auto-route).
 *
 * Design fidelity gaps over the existing v1 WorkflowDisambiguationCard:
 *   - Score column (numeric KB-match score, monospace right-aligned)
 *   - Recommended pill / "top match" badge on the highest scorer
 *   - Optional detail line ("DESeq2 → apeglm → clusterProfiler")
 *   - Optional countdown ring with auto-select after N seconds
 *
 * This is a strict-TS component (the v2 ChatCards.tsx demo is @ts-nocheck
 * with React globals). Lives in v2/ for now; will replace the v1 component
 * once user approves the upgrade.
 */
import { useEffect, useRef, useState } from "react";

export interface DisambigOption {
  /** Stable id used as the key + as the action id ("disambig_select_a") */
  id: string;
  /** User-facing workflow name */
  label: string;
  /** Sub-line under the name — e.g. "6 steps · starts from a count matrix" */
  sub?: string;
  /** Optional one-line tool-chain summary — e.g. "DESeq2 → apeglm → …" */
  detail?: string;
  /** Numeric KB-match score, formatted by the caller (e.g. "0.71") */
  score: string;
  /** Short badge — e.g. "top match", "fuller run" */
  badge?: string;
  /** Marks the recommended option (visual accent + default for auto-select) */
  recommended?: boolean;
}

export interface DisambigCardProps {
  /** Prompt copy shown at the top of the card */
  prompt?: string;
  /** Ranked options — highest-score first (caller's responsibility to sort) */
  options: DisambigOption[];
  /** Called when the user clicks Select on an option, or when countdown fires */
  onSelect: (option: DisambigOption) => void;
  /** Seconds for auto-select countdown; omit/0 → no countdown */
  countdownSeconds?: number;
  /** Optional className for the outer container */
  className?: string;
}

const STYLES = {
  card: {
    border: "1px solid oklch(0.92 0.008 260)",
    borderRadius: 8,
    background: "white",
    boxShadow: "0 1px 2px oklch(0.95 0.005 260 / 0.5)",
  } as React.CSSProperties,
  header: {
    padding: "10px 14px",
    borderBottom: "1px solid oklch(0.94 0.008 260)",
    display: "flex",
    alignItems: "center",
    gap: 8,
    fontSize: 13,
    color: "oklch(0.22 0.012 260)",
  } as React.CSSProperties,
  optionRow: {
    display: "grid",
    gridTemplateColumns: "1fr auto auto",
    alignItems: "center",
    gap: 12,
    padding: "10px 14px",
    borderTop: "1px solid oklch(0.96 0.005 260)",
  } as React.CSSProperties,
  optionRowRec: {
    background: "oklch(0.97 0.02 240)",
  } as React.CSSProperties,
  name: {
    fontSize: 13,
    fontWeight: 600,
    color: "oklch(0.22 0.012 260)",
    display: "flex",
    alignItems: "center",
    gap: 6,
  } as React.CSSProperties,
  sub: {
    fontSize: 11.5,
    color: "oklch(0.48 0.012 260)",
    marginTop: 2,
  } as React.CSSProperties,
  detail: {
    fontSize: 11,
    color: "oklch(0.40 0.012 260)",
    marginTop: 4,
    fontFamily: "ui-monospace, SFMono-Regular, monospace",
  } as React.CSSProperties,
  score: {
    fontSize: 13,
    fontFamily: "ui-monospace, SFMono-Regular, monospace",
    color: "oklch(0.40 0.012 260)",
    textAlign: "right" as const,
  },
  badge: {
    fontSize: 10,
    padding: "1px 6px",
    borderRadius: 4,
    background: "oklch(0.94 0.008 260)",
    color: "oklch(0.40 0.012 260)",
    fontWeight: 500,
    textTransform: "uppercase" as const,
    letterSpacing: 0.4,
  },
  badgeRec: {
    background: "oklch(0.85 0.12 240)",
    color: "oklch(0.25 0.12 240)",
  } as React.CSSProperties,
  selectBtn: {
    fontSize: 11.5,
    padding: "5px 10px",
    borderRadius: 4,
    border: "1px solid oklch(0.85 0.012 260)",
    background: "white",
    color: "oklch(0.22 0.012 260)",
    cursor: "pointer",
    fontWeight: 500,
  } as React.CSSProperties,
  selectBtnRec: {
    background: "oklch(0.55 0.18 240)",
    color: "white",
    borderColor: "oklch(0.55 0.18 240)",
  } as React.CSSProperties,
  foot: {
    padding: "8px 14px",
    borderTop: "1px solid oklch(0.96 0.005 260)",
    fontSize: 11,
    color: "oklch(0.48 0.012 260)",
    display: "flex",
    alignItems: "center",
    gap: 6,
  } as React.CSSProperties,
};

function CountdownRing({ remaining, total }: { remaining: number; total: number }) {
  const pct = Math.round((100 * remaining) / Math.max(total, 1));
  return (
    <span
      data-testid="disambig-countdown-ring"
      aria-label={`${remaining}s remaining`}
      style={{
        display: "inline-block",
        width: 12,
        height: 12,
        borderRadius: "50%",
        background: `conic-gradient(oklch(0.55 0.18 240) ${pct}%, oklch(0.94 0.008 260) 0)`,
      }}
    />
  );
}

export function DisambigCard({
  prompt,
  options,
  onSelect,
  countdownSeconds,
  className,
}: DisambigCardProps) {
  const top = options.find(o => o.recommended) ?? options[0];
  const useCountdown = !!countdownSeconds && countdownSeconds > 0 && !!top;
  const [remaining, setRemaining] = useState(countdownSeconds ?? 0);
  // Track whether the user clicked, so the countdown doesn't fire onSelect twice.
  const firedRef = useRef(false);

  // Single setInterval — avoids the per-tick effect re-run pattern which
  // didn't compose cleanly with React 18 + vitest fake timers (the cleanup
  // would tear down the next pending timeout before it could fire).
  useEffect(() => {
    if (!useCountdown || !top) return;
    const id = setInterval(() => {
      setRemaining(r => {
        if (r <= 1) {
          clearInterval(id);
          if (!firedRef.current) {
            firedRef.current = true;
            onSelect(top);
          }
          return 0;
        }
        return r - 1;
      });
    }, 1000);
    return () => clearInterval(id);
  }, [useCountdown, top, onSelect]);

  const handleSelect = (o: DisambigOption) => {
    if (firedRef.current) return;
    firedRef.current = true;
    onSelect(o);
  };

  return (
    <div
      data-testid="disambig-card"
      className={className}
      style={STYLES.card}
    >
      <div style={STYLES.header}>
        <span aria-hidden="true">⤳</span>
        {prompt ?? "Multiple workflows matched your request."}
      </div>

      {options.map(o => (
        <div
          key={o.id}
          data-testid={`disambig-option-${o.id}`}
          style={{ ...STYLES.optionRow, ...(o.recommended ? STYLES.optionRowRec : {}) }}
        >
          <div>
            <div style={STYLES.name}>
              {o.label}
              {o.badge && (
                <span
                  data-testid={`disambig-badge-${o.id}`}
                  style={{ ...STYLES.badge, ...(o.recommended ? STYLES.badgeRec : {}) }}
                >
                  {o.badge}
                </span>
              )}
            </div>
            {o.sub && <div style={STYLES.sub}>{o.sub}</div>}
            {o.detail && <div style={STYLES.detail}>{o.detail}</div>}
          </div>
          <span style={STYLES.score} title="KB match score" data-testid={`disambig-score-${o.id}`}>
            {o.score}
          </span>
          <button
            type="button"
            data-testid={`disambig-select-${o.id}`}
            onClick={() => handleSelect(o)}
            style={{ ...STYLES.selectBtn, ...(o.recommended ? STYLES.selectBtnRec : {}) }}
          >
            Select
          </button>
        </div>
      ))}

      <div style={STYLES.foot} data-testid="disambig-footer">
        {useCountdown && remaining > 0 && top ? (
          <>
            <CountdownRing remaining={remaining} total={countdownSeconds ?? 0} />
            <span>
              Defaults to{" "}
              <strong style={{ color: "oklch(0.22 0.012 260)" }}>{top.label}</strong>{" "}
              in {remaining}s.
            </span>
          </>
        ) : (
          <span>Pick a workflow to continue — ranked by KB match score.</span>
        )}
      </div>
    </div>
  );
}
