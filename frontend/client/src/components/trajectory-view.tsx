/**
 * TrajectoryView — the agent-side complement to data lineage (design prototype
 * Gap 8). Data lineage says where a number came from; this says what the agent
 * decided, what it called (with timing), what you answered, and what it told
 * you. Together they make a run auditable.
 *
 * Rows are filterable by kind: all / decisions / tool-calls / answers / notes.
 * The "decisions" filter also includes gate rows (a gate halt is a decision
 * point). Pure presentational — rows flow in via props.
 */

import { useState } from "react"
import { Sparkles, Settings, Check, BookOpen, AlertTriangle } from "lucide-react"
import type { LucideIcon } from "lucide-react"
import { cn } from "@/lib/utils"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type TrajectoryKind = "route" | "tool" | "clarify" | "note" | "gate"

export interface TrajectoryRow {
  /** Timestamp label (e.g. "0.4s", "4m 20s"). */
  t: string
  kind: TrajectoryKind
  /** Short title (e.g. "Routing decision"). */
  k: string
  /** Detail sentence. */
  d: string
  /** Mono meta line (e.g. "lane: Cloud · workflow"). */
  meta?: string
}

/** Filter buckets. `route` bucket also matches `gate` rows. */
export type TrajectoryFilter = "all" | "route" | "tool" | "clarify" | "note"

export interface TrajectoryViewProps {
  rows: TrajectoryRow[]
  /** Optional export handler; the link is hidden if omitted. */
  onExport?: () => void
  className?: string
}

const FILTERS: [TrajectoryFilter, string][] = [
  ["all", "Everything"],
  ["route", "Decisions"],
  ["tool", "Tool calls"],
  ["clarify", "Your answers"],
  ["note", "What it told you"],
]

const KIND_ICON: Record<TrajectoryKind, LucideIcon> = {
  route: Sparkles,
  tool: Settings,
  clarify: Check,
  note: BookOpen,
  gate: AlertTriangle,
}

function matches(row: TrajectoryRow, filter: TrajectoryFilter): boolean {
  if (filter === "all") return true
  if (filter === "route") return row.kind === "route" || row.kind === "gate"
  return row.kind === filter
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function TrajectoryView({ rows, onExport, className }: TrajectoryViewProps) {
  const [filter, setFilter] = useState<TrajectoryFilter>("all")
  const visible = rows.filter((r) => matches(r, filter))

  return (
    <div data-testid="trajectory-view" className={cn("flex flex-col gap-2.5", className)}>
      {/* Header */}
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm font-medium">Agent trajectory</span>
        <span className="flex-1" />
        {onExport && (
          <button
            type="button"
            data-testid="trajectory-export"
            onClick={onExport}
            className="text-xs text-primary hover:underline"
          >
            export →
          </button>
        )}
      </div>
      <p className="text-xs text-muted-foreground">
        Data lineage says where a number came from. This says what the agent decided, what it
        called, and what you told it — the other half of an auditable run.
      </p>

      {/* Filter bar */}
      <div className="flex flex-wrap gap-1" role="tablist" aria-label="Filter trajectory">
        {FILTERS.map(([k, label]) => (
          <button
            key={k}
            type="button"
            role="tab"
            aria-selected={filter === k}
            data-testid={`trajectory-filter-${k}`}
            onClick={() => setFilter(k)}
            className={cn(
              "rounded-full border px-2.5 py-1 text-xs transition-colors",
              "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
              filter === k
                ? "border-primary bg-primary/10 text-primary"
                : "border-border bg-background text-muted-foreground hover:bg-accent",
            )}
          >
            {label}
          </button>
        ))}
      </div>

      {/* Rows */}
      <div className="flex flex-col gap-2" data-testid="trajectory-rows">
        {visible.length === 0 ? (
          <p className="text-xs text-muted-foreground italic" data-testid="trajectory-empty">
            No entries of this kind.
          </p>
        ) : (
          visible.map((r, idx) => {
            const IconCmp = KIND_ICON[r.kind]
            return (
              <div
                key={idx}
                data-testid={`trajectory-row-${r.kind}`}
                className="flex items-start gap-2.5"
              >
                <span className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full border border-border bg-muted text-muted-foreground">
                  <IconCmp className="h-2.5 w-2.5" aria-hidden />
                </span>
                <span className="flex flex-col gap-0.5 min-w-0">
                  <span className="flex flex-wrap items-baseline gap-2">
                    <span className="text-sm font-medium">{r.k}</span>
                    <span className="font-mono text-[11px] text-muted-foreground">{r.t}</span>
                  </span>
                  <span className="text-xs text-muted-foreground">{r.d}</span>
                  {r.meta && (
                    <span className="font-mono text-[11px] text-muted-foreground/80">{r.meta}</span>
                  )}
                </span>
              </div>
            )
          })
        )}
      </div>
    </div>
  )
}
