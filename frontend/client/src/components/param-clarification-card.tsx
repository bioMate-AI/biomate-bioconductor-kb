/**
 * ParamClarificationCard
 *
 * Rendered inline in chat when schema-grounded parameter extraction needs
 * the user to pick a value. Two trigger kinds:
 *
 *   1. enum_violation — the user mentioned a value that's not in the
 *      workflow's allowed enum (e.g. "B cells" when only T_cell/NK_cell/
 *      macrophage are allowed). Card shows the allowed values as
 *      quick-reply chips.
 *
 *   2. missing_required — the workflow requires a parameter and the user's
 *      message didn't mention it. Card shows the param name + description
 *      + example values (if the param is an enum).
 *
 * Clicking a chip emits `onSelect(paramName, value)` which the chat handler
 * patches into the workflow panel's params state. Clicking "Skip" emits
 * `onSkip(paramName)` which closes the clarification without filling.
 *
 * Mirrors the WorkflowDisambiguationCard pattern (inline, not modal, with
 * a footer escape hatch).
 */

import { cn } from "@/lib/utils"

export type ParamClarification =
  | {
      kind: "missing_required"
      paramName: string
      hint?: string
      examples?: string[]
    }
  | {
      kind: "enum_violation"
      paramName: string
      userValue: string
      allowed: string[]
    }

interface ParamClarificationCardProps {
  workflowName: string
  clarifications: ParamClarification[]
  onSelect: (paramName: string, value: string) => void
  onSkip: (paramName: string) => void
  className?: string
}

function Chip({
  value,
  testId,
  onClick,
}: {
  value: string
  testId: string
  onClick: () => void
}) {
  return (
    <button
      type="button"
      data-testid={testId}
      onClick={onClick}
      className={cn(
        "inline-flex items-center px-3 py-1.5 rounded-full",
        "border border-border bg-background hover:bg-accent hover:text-accent-foreground",
        "text-xs font-medium transition-colors",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
      )}
    >
      {value}
    </button>
  )
}

function ClarificationRow({
  clarification,
  onSelect,
  onSkip,
}: {
  clarification: ParamClarification
  onSelect: (value: string) => void
  onSkip: () => void
}) {
  const { paramName } = clarification

  if (clarification.kind === "enum_violation") {
    return (
      <div className="px-4 py-3 flex flex-col gap-2">
        <p className="text-sm leading-snug">
          You mentioned <span className="font-mono text-xs px-1 py-0.5 rounded bg-muted">{clarification.userValue}</span>{" "}
          for <span className="font-mono">{paramName}</span>, but this workflow supports:
        </p>
        <div className="flex flex-wrap gap-2">
          {clarification.allowed.map((v) => (
            <Chip
              key={v}
              value={v}
              testId={`param-clarify-chip-${paramName}-${v}`}
              onClick={() => onSelect(v)}
            />
          ))}
          <button
            type="button"
            data-testid={`param-clarify-skip-${paramName}`}
            onClick={onSkip}
            className="text-xs text-muted-foreground hover:text-foreground underline underline-offset-2 px-2 py-1.5"
          >
            Skip — I'll fill it in the panel
          </button>
        </div>
      </div>
    )
  }

  // missing_required
  return (
    <div className="px-4 py-3 flex flex-col gap-2">
      <p className="text-sm leading-snug">
        <span className="font-mono">{paramName}</span> is required.
        {clarification.hint ? (
          <span className="text-muted-foreground"> — {clarification.hint}</span>
        ) : null}
      </p>
      {clarification.examples && clarification.examples.length > 0 ? (
        <div className="flex flex-wrap gap-2">
          {clarification.examples.map((v) => (
            <Chip
              key={v}
              value={v}
              testId={`param-clarify-chip-${paramName}-${v}`}
              onClick={() => onSelect(v)}
            />
          ))}
          <button
            type="button"
            data-testid={`param-clarify-skip-${paramName}`}
            onClick={onSkip}
            className="text-xs text-muted-foreground hover:text-foreground underline underline-offset-2 px-2 py-1.5"
          >
            Skip — I'll fill it in the panel
          </button>
        </div>
      ) : (
        <button
          type="button"
          data-testid={`param-clarify-skip-${paramName}`}
          onClick={onSkip}
          className="self-start text-xs text-muted-foreground hover:text-foreground underline underline-offset-2"
        >
          I'll fill it in the panel
        </button>
      )}
    </div>
  )
}

export function ParamClarificationCard({
  workflowName,
  clarifications,
  onSelect,
  onSkip,
  className,
}: ParamClarificationCardProps) {
  if (clarifications.length === 0) return null
  return (
    <div
      data-testid="param-clarification-card"
      className={cn("rounded-lg border bg-card text-card-foreground shadow-sm", className)}
    >
      <div className="px-4 pt-3 pb-2 border-b">
        <p className="text-sm text-muted-foreground">
          A few details for{" "}
          <span className="font-mono text-foreground">{workflowName}</span> before we run:
        </p>
      </div>
      <div className="divide-y">
        {clarifications.map((c) => (
          <ClarificationRow
            key={`${c.kind}-${c.paramName}`}
            clarification={c}
            onSelect={(value) => onSelect(c.paramName, value)}
            onSkip={() => onSkip(c.paramName)}
          />
        ))}
      </div>
    </div>
  )
}
