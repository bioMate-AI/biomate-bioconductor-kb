/**
 * ApprovalGate — human approval expressed in the same
 * measured · threshold · verdict vocabulary as a QC gate (design prototype
 * Gap 7). A human approval is a gate whose measurement is a person.
 *
 * Pause → "needs your approval: what / why / cost" → approve / deny / ask a
 * reviewer. On resolution it records who / when / reason via `onResolve`, so
 * the caller can write it to the audit trail.
 *
 * Pure presentational: all data flows in via props; no fabricated values.
 */

import { AlertTriangle } from "lucide-react"
import { cn } from "@/lib/utils"
import { tOr } from "@/lib/i18n"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type Verdict = "pass" | "needs approval" | "fail" | "warn"

/** One measured row: measurement · threshold · verdict. */
export interface MeasuredRow {
  /** What is being measured (e.g. "Consumers affected"). */
  key: string
  /** The measured value (e.g. "2 downstream runs"). */
  measured: string
  /** The threshold / rule (e.g. "approval required above 1"). */
  threshold: string
  /** The verdict. */
  verdict: Verdict
}

export interface ApprovalGateData {
  /** What action is awaiting approval. */
  what: string
  /** Why it needs approval. */
  why: string
  /** The cost / consequence line. */
  cost: string
  /** The measured rows. */
  measured: MeasuredRow[]
  /** Who can approve (e.g. "You can approve this — you own this project."). */
  who: string
  /** The governing policy line. */
  policy: string
}

export type ApprovalDecision = "approve" | "deny" | "delegate"

/** Recorded on resolution — who / when / reason for the audit trail. */
export interface ApprovalRecord {
  decision: ApprovalDecision
  at: Date
  /** Optional human name / actor — passed through by the caller. */
  who?: string
  /** The reason shown to the approver (the `why`), recorded verbatim. */
  reason: string
}

export interface ApprovalGateProps {
  data: ApprovalGateData
  onResolve: (record: ApprovalRecord) => void
  /** Optional actor name recorded on the decision. */
  actor?: string
  className?: string
}

// ---------------------------------------------------------------------------
// Verdict chip (shared visual grammar with VerifyPattern)
// ---------------------------------------------------------------------------

export function VerdictChip({ verdict }: { verdict: Verdict }) {
  const ok = verdict === "pass"
  return (
    <span
      data-testid={`verdict-${verdict}`}
      className={cn(
        "inline-flex items-center gap-1 rounded-full border px-1.5 py-0.5 text-[10px] font-medium",
        ok
          ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
          : "border-amber-500/40 bg-amber-500/10 text-amber-600 dark:text-amber-400",
      )}
    >
      <span className={cn("h-1.5 w-1.5 rounded-full", ok ? "bg-emerald-500" : "bg-amber-500")} />
      {tOr('panel.verdict_' + verdict.replace(/\s+/g, '_'), verdict)}
    </span>
  )
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function ApprovalGate({ data, onResolve, actor, className }: ApprovalGateProps) {
  const resolve = (decision: ApprovalDecision) =>
    onResolve({ decision, at: new Date(), who: actor, reason: data.why })

  return (
    <div
      data-testid="approval-gate"
      className={cn(
        "flex flex-col gap-3 rounded-lg border border-amber-500/40 bg-card p-4 text-card-foreground shadow-sm",
        className,
      )}
    >
      {/* Header */}
      <div className="flex flex-wrap items-center gap-2">
        <AlertTriangle className="h-4 w-4 text-amber-500 shrink-0" aria-hidden />
        <span className="text-sm font-semibold">Paused — needs your approval</span>
        <span className="flex-1" />
        <span className="inline-flex items-center gap-1 rounded-full border border-amber-500/40 bg-amber-500/10 px-2 py-0.5 text-[10px] font-medium text-amber-600 dark:text-amber-400">
          <span className="h-1.5 w-1.5 rounded-full bg-amber-500 animate-pulse" />
          human gate
        </span>
      </div>

      {/* What / why / cost */}
      <div className="flex flex-col gap-1">
        <span className="text-sm font-medium">{data.what}</span>
        <span className="text-xs text-muted-foreground">{data.why}</span>
        <span className="text-xs text-muted-foreground/80">{data.cost}</span>
      </div>

      {/* Measured rows: measured · threshold · verdict */}
      <div className="flex flex-col divide-y divide-border rounded-md border border-border">
        {data.measured.map((m) => (
          <div
            key={m.key}
            data-testid={`approval-measured-${m.key}`}
            className="grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-0.5 px-3 py-2 sm:grid-cols-[1.4fr_1fr_1.4fr_auto]"
          >
            <span className="text-xs text-muted-foreground">{m.key}</span>
            <span className="font-mono text-xs">{m.measured}</span>
            <span className="text-xs text-muted-foreground/80">{m.threshold}</span>
            <VerdictChip verdict={m.verdict} />
          </div>
        ))}
      </div>

      {/* Who / policy */}
      <p className="text-xs text-muted-foreground">
        <span className="font-semibold text-foreground">Who: </span>
        {data.who} <span className="text-muted-foreground/80">{data.policy}</span>
      </p>

      {/* Actions */}
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          data-testid="approval-approve"
          onClick={() => resolve("approve")}
          className="rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:bg-primary/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          Approve
        </button>
        <button
          type="button"
          data-testid="approval-deny"
          onClick={() => resolve("deny")}
          className="rounded-md border border-border bg-background px-3 py-1.5 text-xs font-medium hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          Deny
        </button>
        <button
          type="button"
          data-testid="approval-delegate"
          onClick={() => resolve("delegate")}
          className="rounded-md border border-border bg-background px-3 py-1.5 text-xs font-medium hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          Ask a reviewer
        </button>
      </div>
    </div>
  )
}
