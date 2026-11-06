/**
 * RolesCard + VerifyPattern — governance surfaces (design prototype Gap 4).
 *
 * RolesCard: a role → capability table. A control you may not use is shown
 * disabled with the role it needs — never hidden. Hiding it makes the product
 * feel broken; naming the role makes it answerable.
 *
 * VerifyPattern: every check in the product reads the same way —
 * measured · threshold · verdict — so a scientist learns it once. What differs
 * is who measures and what a failure stops. This surface shows all gate kinds
 * (workflow QC, model eval, safety, chemistry, human approval) as that one
 * pattern.
 *
 * Both are pure presentational: data via props, no fabricated values.
 */

import { cn } from "@/lib/utils"
import { tOr } from "@/lib/i18n"

// ---------------------------------------------------------------------------
// RolesCard
// ---------------------------------------------------------------------------

export interface RoleCapability {
  /** The capability (e.g. "Register a model"). */
  capability: string
  /** The role required to use it (e.g. "Owner"). */
  needs: string
  /** Whether the current user can use it. */
  allowed: boolean
}

export interface RolesData {
  /** The current user's role (e.g. "Owner"). */
  you: string
  /** The project / scope name. */
  project: string
  caps: RoleCapability[]
}

export interface RolesCardProps {
  data: RolesData
  className?: string
}

export function RolesCard({ data, className }: RolesCardProps) {
  return (
    <div
      data-testid="roles-card"
      className={cn(
        "flex flex-col gap-2.5 rounded-lg border bg-card p-4 text-card-foreground shadow-sm",
        className,
      )}
    >
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm font-medium">{tOr('panel.permissions_here','Your permissions here')}</span>
        <span
          data-testid="roles-you"
          className="inline-flex items-center rounded-full border border-primary/40 bg-primary/10 px-1.5 py-0.5 text-[10px] font-medium text-primary"
        >
          {data.you}
        </span>
        <span className="flex-1" />
        <span className="text-xs text-muted-foreground/80">{data.project}</span>
      </div>

      <div className="flex flex-col divide-y divide-border rounded-md border border-border">
        {data.caps.map((c) => (
          <div
            key={c.capability}
            data-testid={`role-cap-${c.capability}`}
            className="grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-0.5 px-3 py-2 sm:grid-cols-[1.4fr_1fr_auto]"
          >
            <span className="text-xs">{c.capability}</span>
            <span className="text-xs text-muted-foreground/80">{tOr('panel.needs','needs')} {c.needs}</span>
            <span
              data-testid={`role-verdict-${c.capability}`}
              className={cn(
                "inline-flex items-center gap-1 rounded-full border px-1.5 py-0.5 text-[10px] font-medium",
                c.allowed
                  ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
                  : "border-border bg-muted text-muted-foreground",
              )}
            >
              <span
                className={cn(
                  "h-1.5 w-1.5 rounded-full",
                  c.allowed ? "bg-emerald-500" : "bg-muted-foreground/50",
                )}
              />
              {c.allowed ? tOr('panel.you_can','you can') : tOr('panel.you_cannot','you cannot')}
            </span>
          </div>
        ))}
      </div>

      <p className="text-xs text-muted-foreground">
        {tOr('panel.roles.footer', 'A control you may not use is shown disabled with the role it needs — never hidden. Hiding it makes the product feel broken; naming the role makes it answerable.')}
      </p>
    </div>
  )
}

// ---------------------------------------------------------------------------
// VerifyPattern
// ---------------------------------------------------------------------------

export interface VerifyKind {
  /** Gate name (e.g. "Workflow QC gate"). */
  kind: string
  /** Who / what measures it (e.g. "a measurement on your data"). */
  measuredBy: string
  /** What a failure stops (e.g. "halts the run"). */
  stops: string
  /** Where it's specified (e.g. "Spec 07"). */
  where: string
}

export interface VerifyPatternProps {
  kinds: VerifyKind[]
  /** Optional footer explainer handler; the link is hidden if omitted. */
  onExplain?: () => void
  className?: string
}

export function VerifyPattern({ kinds, onExplain, className }: VerifyPatternProps) {
  return (
    <div
      data-testid="verify-pattern"
      className={cn(
        "flex flex-col gap-2.5 rounded-lg border bg-card p-4 text-card-foreground shadow-sm",
        className,
      )}
    >
      <div className="flex items-center gap-2">
        <span className="text-sm font-medium">{tOr('panel.verify.title', 'One verification pattern')}</span>
        <span className="flex-1" />
        <span className="text-xs text-muted-foreground/80">{tOr('panel.verify.pattern', 'measured · threshold · verdict')}</span>
      </div>
      <p className="text-xs text-muted-foreground">
        {tOr('panel.verify.help', 'Every check in the product reads the same way, so a scientist learns it once. What differs is who measures and what a failure stops.')}
      </p>

      <div className="flex flex-col divide-y divide-border rounded-md border border-border">
        {kinds.map((k) => (
          <div
            key={k.kind}
            data-testid={`verify-kind-${k.kind}`}
            className="grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-0.5 px-3 py-2 sm:grid-cols-[1.3fr_1.3fr_1.2fr_auto]"
          >
            <span className="text-xs font-semibold">{k.kind}</span>
            <span className="text-xs text-muted-foreground/80">{tOr('panel.verify.measured_by', 'measured by {{by}}', { by: k.measuredBy })}</span>
            <span className="text-xs text-muted-foreground">{k.stops}</span>
            <span className="inline-flex items-center rounded-full border border-border bg-muted px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground">
              {k.where}
            </span>
          </div>
        ))}
      </div>

      {onExplain && (
        <button
          type="button"
          data-testid="verify-explain"
          onClick={onExplain}
          className="self-start text-xs text-primary hover:underline"
        >
          {tOr('panel.verify.explain', 'why a human counts as a gate →')}
        </button>
      )}
    </div>
  )
}
