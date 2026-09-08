/**
 * SkipDependency — per-phase skippable state with DAG-aware warnings
 * (design prototype Gap 5).
 *
 * Skip is a declared workflow capability, DAG-validated — not a universal
 * neutral toggle. A phase is only skippable if the workflow declares a skip
 * parameter for it. Skipping a phase that another phase reads directly is
 * blocked ("can't skip — B and C depend on it"). Skipping a phase whose
 * downstream would be left with nothing useful is allowed but warned
 * ("D has nothing to enrich without it").
 *
 * Pure presentational + a local toggle for the skip checkbox; the resolved
 * skip set flows out via onToggle. No fabricated data.
 */

import { useState } from "react"
import { AlertTriangle, Ban } from "lucide-react"
import { cn } from "@/lib/utils"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface PhaseSkipInfo {
  /** Phase id (e.g. "A", "B"). */
  id: string
  /** Whether the workflow declares a skip parameter for this phase. */
  skippable: boolean
  /** The declared skip parameter (only when skippable). */
  param?: string
  /** Explanation of the skip / no-skip decision. */
  why: string
  /** Phases that read this one directly — skipping is BLOCKED if non-empty. */
  blocks?: string[]
  /** Phases left with nothing useful if this is skipped — advisory warning. */
  warn?: string[]
}

export interface SkipDependencyProps {
  phases: PhaseSkipInfo[]
  /**
   * Called with the set of currently-skipped phase ids whenever it changes.
   * Blocked phases can never enter this set.
   */
  onToggle?: (skipped: string[]) => void
  className?: string
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function SkipDependency({ phases, onToggle, className }: SkipDependencyProps) {
  const [skipped, setSkipped] = useState<Set<string>>(new Set())

  const canSkip = (p: PhaseSkipInfo) => p.skippable && !(p.blocks && p.blocks.length > 0)

  const toggle = (p: PhaseSkipInfo) => {
    if (!canSkip(p)) return
    setSkipped((prev) => {
      const next = new Set(prev)
      if (next.has(p.id)) next.delete(p.id)
      else next.add(p.id)
      onToggle?.(Array.from(next))
      return next
    })
  }

  return (
    <div
      data-testid="skip-dependency"
      className={cn(
        "flex flex-col gap-2.5 rounded-lg border bg-card p-4 text-card-foreground shadow-sm",
        className,
      )}
    >
      <span className="text-sm font-medium">Skip phases</span>
      <p className="text-xs text-muted-foreground">
        Skip is a declared workflow capability, DAG-validated — not a universal toggle. A phase other
        phases read directly cannot be skipped.
      </p>

      <div className="flex flex-col gap-2">
        {phases.map((p) => {
          const blocked = p.blocks && p.blocks.length > 0
          const skippable = canSkip(p)
          const isSkipped = skipped.has(p.id)
          return (
            <div
              key={p.id}
              data-testid={`skip-phase-${p.id}`}
              data-skippable={skippable}
              data-skipped={isSkipped}
              className={cn(
                "flex items-start gap-2.5 rounded-md border px-3 py-2",
                skippable ? "border-border" : "border-border bg-muted/40",
              )}
            >
              {/* Toggle */}
              <label
                className={cn(
                  "mt-0.5 flex items-center",
                  skippable ? "cursor-pointer" : "cursor-not-allowed",
                )}
              >
                <input
                  type="checkbox"
                  data-testid={`skip-toggle-${p.id}`}
                  checked={isSkipped}
                  disabled={!skippable}
                  onChange={() => toggle(p)}
                  className="h-3.5 w-3.5 accent-primary disabled:opacity-40"
                />
              </label>

              <span className="flex flex-col gap-0.5 min-w-0">
                <span className="flex flex-wrap items-center gap-2">
                  <span className="text-sm font-medium">Phase {p.id}</span>
                  {p.param && (
                    <span className="font-mono text-[11px] text-muted-foreground">{p.param}</span>
                  )}
                  {!p.skippable && (
                    <span className="inline-flex items-center gap-1 rounded-full border border-border bg-muted px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground">
                      <Ban className="h-2.5 w-2.5" aria-hidden />
                      not declared skippable
                    </span>
                  )}
                </span>
                <span className="text-xs text-muted-foreground">{p.why}</span>

                {/* Blocked: can't skip — X depends on it */}
                {blocked && (
                  <span
                    data-testid={`skip-blocked-${p.id}`}
                    className="mt-0.5 inline-flex items-center gap-1.5 rounded border border-amber-500/40 bg-amber-500/10 px-2 py-1 text-[11px] text-amber-600 dark:text-amber-400"
                  >
                    <AlertTriangle className="h-3 w-3 shrink-0" aria-hidden />
                    Can&apos;t skip — {p.blocks!.join(" and ")}{" "}
                    {p.blocks!.length > 1 ? "depend" : "depends"} on it.
                  </span>
                )}

                {/* Advisory warning when skipped leaves downstream empty */}
                {!blocked && p.warn && p.warn.length > 0 && isSkipped && (
                  <span
                    data-testid={`skip-warn-${p.id}`}
                    className="mt-0.5 inline-flex items-center gap-1.5 rounded border border-amber-500/40 bg-amber-500/10 px-2 py-1 text-[11px] text-amber-600 dark:text-amber-400"
                  >
                    <AlertTriangle className="h-3 w-3 shrink-0" aria-hidden />
                    {p.warn.join(" and ")} {p.warn.length > 1 ? "have" : "has"} nothing to work on
                    without it.
                  </span>
                )}
              </span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
