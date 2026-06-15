/**
 * IntentClarificationCard
 *
 * Rendered inline in chat when backend's cross-intent ambiguity detector
 * (see galaxy-assistant.ts:_detectCrossIntentAmbiguity) flags that the
 * LLM-classified intent might be wrong for the query — e.g. user asks
 * "Design a PD-1 × VEGF bispecific for NSCLC" and the intent decomposer
 * routed it to tool_search instead of workflow_generation.
 *
 * The card lists the candidate intent types (with the design-workflow
 * option highlighted as primary per the user-in-the-loop principle:
 * lean on execution). Each click dispatches `biomate:intent-clarification-
 * resolved` which the chat-with-artifacts handler picks up and re-submits
 * the original query with `context.intentOverride` set to the picked
 * intent type. The backend's _processMessageInner skips ambiguity
 * detection when intentOverride is present, so the second pass routes
 * straight to the user's choice.
 *
 * Mirrors the inline-not-modal pattern of ParamClarificationCard and
 * WorkflowDisambiguationCard.
 */

import { cn } from "@/lib/utils"

export type IntentCandidate = {
  type: string
  label: string
  /** When true, the candidate is rendered as the primary highlighted button. */
  primary?: boolean
}

interface IntentClarificationCardProps {
  originalMessage: string
  originalIntent: string
  candidates: IntentCandidate[]
  reason?: string
  onPick: (intentType: string, originalMessage: string) => void
  onSkip: () => void
  className?: string
}

function Button({
  candidate,
  onClick,
}: {
  candidate: IntentCandidate
  onClick: () => void
}) {
  return (
    <button
      type="button"
      data-testid={`intent-clarify-${candidate.type}`}
      onClick={onClick}
      className={cn(
        "inline-flex items-center px-3 py-1.5 rounded-md transition-colors",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
        candidate.primary
          ? "bg-primary text-primary-foreground hover:bg-primary/90 font-medium text-sm"
          : "border border-border bg-background hover:bg-accent hover:text-accent-foreground text-xs font-medium",
      )}
    >
      {candidate.label}
    </button>
  )
}

export function IntentClarificationCard({
  originalMessage,
  originalIntent,
  candidates,
  reason,
  onPick,
  onSkip,
  className,
}: IntentClarificationCardProps) {
  if (!candidates || candidates.length === 0) return null
  return (
    <div
      data-testid="intent-clarification-card"
      data-original-intent={originalIntent}
      className={cn("rounded-lg border bg-card text-card-foreground shadow-sm", className)}
    >
      <div className="px-4 pt-3 pb-2 border-b">
        <p className="text-sm leading-snug">
          I want to make sure I do the right thing for{" "}
          <span className="font-mono text-xs px-1 py-0.5 rounded bg-muted">
            {originalMessage.length > 80
              ? originalMessage.slice(0, 80) + "…"
              : originalMessage}
          </span>
          .
        </p>
        <p className="text-xs text-muted-foreground mt-1">
          Pick the option that matches what you want.
        </p>
      </div>
      <div className="px-4 py-3 flex flex-wrap gap-2 items-center">
        {candidates.map((c) => (
          <Button
            key={c.type}
            candidate={c}
            onClick={() => onPick(c.type, originalMessage)}
          />
        ))}
        <button
          type="button"
          data-testid="intent-clarify-skip"
          onClick={onSkip}
          className="text-xs text-muted-foreground hover:text-foreground underline underline-offset-2 px-2 py-1.5 ml-auto"
        >
          Skip — let me rephrase
        </button>
      </div>
      {reason && (
        <div className="px-4 pb-2">
          <p className="text-[10px] text-muted-foreground">
            Why I'm asking: matched patterns — {reason}
          </p>
        </div>
      )}
    </div>
  )
}
