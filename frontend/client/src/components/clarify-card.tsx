/**
 * ClarifyCard — typed confirm-inference card.
 *
 * Generalises {@link ParamClarificationCard}. Where that card only asks the
 * user to pick a schema enum value for a single param, ClarifyCard presents a
 * multi-question sequence where each *option* carries the concrete value it
 * binds to — a schema value OR a workflow id — plus a pre-selected inferred
 * pick and a "why we're asking" line.
 *
 * The key invariant (from the design prototype, Gap 2): an answer is a schema
 * value or a workflow id, never a sentence to re-parse. The emitted answer is
 * therefore fully typed:
 *
 *   { questionId, target: { type: 'param' | 'workflow', name }, value, source }
 *
 * where `source` is 'inferred' (the pre-selected pick), 'user' (a different
 * typed option), or 'freetext' (the "in my own words" escape hatch — the only
 * path that produces text to re-interpret, and it is marked as such).
 *
 * Round-trip compatibility: like ParamClarificationCard, when an answer binds
 * to a param this card dispatches the existing
 * `biomate:param-clarification-resolved` CustomEvent (detail
 * `{ messageId?, paramName, value }`) so the workflow-panel bridge in
 * chat-with-artifacts.tsx pre-fills the field unchanged. Workflow-id answers
 * dispatch `biomate:clarify-workflow-resolved`. Skips dispatch
 * `biomate:param-clarification-skipped`.
 */

import { useState } from "react"
import { AlertTriangle, X } from "lucide-react"
import { cn } from "@/lib/utils"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** One typed option. Binds to a concrete schema value or workflow id. */
export interface ClarifyOption {
  /** Human label shown to the user. */
  label: string
  /** The concrete value this option binds to (schema value or workflow id). */
  val: string
  /** Short note explaining this option (e.g. "matches 'treated vs control'"). */
  note?: string
  /** Marks the inferred / recommended option, pre-selected by default. */
  pick?: boolean
}

/** What an answer targets. */
export type ClarifyTargetType = "param" | "workflow"

export interface ClarifyQuestion {
  /** Stable id for the question (used as questionId in the emitted answer). */
  id: string
  /** The question text. */
  q: string
  /** The schema field / target name this question resolves. */
  field: string
  /** Whether the field is a workflow param or the workflow id itself. */
  target: ClarifyTargetType
  /** "why we're asking" line. */
  why: string
  /** Short human name of what the value binds to (e.g. "schema value"). */
  binds: string
  /** Typed options. Exactly one may carry `pick: true`. */
  opts: ClarifyOption[]
}

export type ClarifyAnswerSource = "inferred" | "user" | "freetext"

/** The fully typed answer emitted per question. */
export interface ClarifyAnswer {
  questionId: string
  target: { type: ClarifyTargetType; name: string }
  value: string
  source: ClarifyAnswerSource
}

export interface ClarifyCardProps {
  /** The typed questions to walk through. */
  questions: ClarifyQuestion[]
  /**
   * Called when the user confirms — receives the full typed answer set. Answers
   * are also dispatched as CustomEvents for the existing panel bridge.
   */
  onDone?: (answers: ClarifyAnswer[]) => void
  /** Called on skip-one / skip-all with the affected question ids. */
  onSkip?: (questionIds: string[]) => void
  /** Optional messageId threaded into dispatched events (round-trip). */
  messageId?: string
  className?: string
}

// ---------------------------------------------------------------------------
// Event bridge (keeps the existing param-clarification round-trip working)
// ---------------------------------------------------------------------------

function dispatchAnswer(answer: ClarifyAnswer, messageId?: string) {
  if (typeof window === "undefined") return
  if (answer.target.type === "param") {
    window.dispatchEvent(
      new CustomEvent("biomate:param-clarification-resolved", {
        detail: { messageId, paramName: answer.target.name, value: answer.value },
      }),
    )
  } else {
    window.dispatchEvent(
      new CustomEvent("biomate:clarify-workflow-resolved", {
        detail: { messageId, workflowId: answer.value },
      }),
    )
  }
}

function dispatchSkip(questionId: string, field: string, messageId?: string) {
  if (typeof window === "undefined") return
  window.dispatchEvent(
    new CustomEvent("biomate:param-clarification-skipped", {
      detail: { messageId, questionId, paramName: field },
    }),
  )
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

const FREETEXT = -1
// No genuine selection: a question with no recommended `pick` (e.g. an
// enum_violation, where the adapter intentionally pre-selects nothing so the
// user chooses deliberately) starts here. A NONE pick is NEVER emitted as a
// resolved answer — skipping/confirming it applies no value, rather than
// silently defaulting to opts[0] (which the panel would pre-fill as if chosen).
const NONE = -2

export function ClarifyCard({
  questions,
  onDone,
  onSkip,
  messageId,
  className,
}: ClarifyCardProps) {
  const N = questions.length
  const [i, setI] = useState(0)
  // Each entry is the picked option index, or FREETEXT for the own-words path.
  const [picks, setPicks] = useState<number[]>(() =>
    questions.map((q) => {
      const idx = q.opts.findIndex((o) => o.pick)
      // No recommended option → NONE (not 0). Prevents a never-chosen enum
      // value from being emitted on skip/confirm.
      return idx === -1 ? NONE : idx
    }),
  )
  // Free-text is keyed PER QUESTION — a single shared string would make a later
  // free-text answer overwrite an earlier one (both read the same value at confirm).
  const [own, setOwn] = useState<Record<string, string>>({})

  if (N === 0) return null

  const q = questions[i]
  const pick = picks[i]
  const setPick = (v: number) => setPicks((a) => a.map((x, j) => (j === i ? v : x)))

  const answerFor = (
    qq: ClarifyQuestion,
    p: number,
    ownMap: Record<string, string>,
  ): ClarifyAnswer => {
    if (p === FREETEXT) {
      return {
        questionId: qq.id,
        target: { type: qq.target, name: qq.field },
        value: ownMap[qq.id] ?? "",
        source: "freetext",
      }
    }
    const opt = qq.opts[p]
    return {
      questionId: qq.id,
      target: { type: qq.target, name: qq.field },
      value: opt.val,
      source: opt.pick ? "inferred" : "user",
    }
  }

  // Emit answers for every question that has a genuine selection (a recommended
  // pick, a user click, or free text). Questions still at NONE — an enum with no
  // pre-select the user never chose — emit nothing: no resolved value is applied.
  // Exception (2026-11-13 clinic hell): a file/path prompt with zero typed opts
  // only offers the fretext escape hatch. Confirm with NONE used to emit nothing,
  // so "Confirm and configure" silently left the right panel closed while chat
  // claimed the workflow was ready. Treat that as empty fretext so the panel
  // bridge opens and the user can fill Movies Path / etc.
  const emit = (pk: number[]) => {
    const answers = questions
      .map((qq, j) => {
        if (pk[j] === NONE) {
          if (qq.opts.length === 0) return answerFor(qq, FREETEXT, own)
          return null
        }
        return answerFor(qq, pk[j], own)
      })
      .filter((a): a is ClarifyAnswer => a !== null)
    answers.forEach((a) => dispatchAnswer(a, messageId))
    onDone?.(answers)
  }

  const confirm = () => emit(picks)

  const advance = () => {
    if (i < N - 1) setI(i + 1)
    else confirm()
  }

  const skipOne = () => {
    dispatchSkip(q.id, q.field, messageId)
    onSkip?.([q.id])
    if (i < N - 1) setI(i + 1)
    else confirm()
  }

  const skipAll = () => {
    questions.forEach((qq) => dispatchSkip(qq.id, qq.field, messageId))
    onSkip?.(questions.map((qq) => qq.id))
    // Skip-all applies the inferred/recommended values that exist; questions
    // with no recommended pick (NONE) apply nothing.
    emit(picks)
  }

  return (
    <div
      data-testid="clarify-card"
      className={cn("w-full min-w-0 rounded-lg border bg-card text-card-foreground shadow-sm break-words", className)}
    >
      {/* Header */}
      <div className="flex items-center gap-2 px-4 pt-3 pb-2 border-b">
        <AlertTriangle className="h-3.5 w-3.5 text-amber-500 shrink-0" aria-hidden />
        <span className="text-sm font-medium leading-snug flex-1 min-w-0">{q.q}</span>
        <span className="text-xs text-muted-foreground tabular-nums" data-testid="clarify-count">
          {i + 1}/{N}
        </span>
        <button
          type="button"
          data-testid="clarify-skip-all"
          title="Skip all and use the inferred values"
          onClick={skipAll}
          className="text-muted-foreground hover:text-foreground p-0.5 rounded focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <X className="h-3 w-3" aria-hidden />
        </button>
      </div>

      {/* Why line */}
      <p className="px-4 pt-2 text-xs text-muted-foreground leading-snug">{q.why}</p>

      {/* Options */}
      <div className="flex flex-col gap-1.5 px-4 py-3">
        {q.opts.map((o, n) => (
          <button
            key={o.val}
            type="button"
            data-testid={`clarify-opt-${q.id}-${n}`}
            data-selected={pick === n}
            onClick={() => setPick(n)}
            className={cn(
              "flex items-start gap-2.5 rounded-md border px-3 py-2 text-left transition-colors",
              "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
              pick === n
                ? "border-primary bg-accent"
                : "border-border bg-background hover:bg-accent/50",
            )}
          >
            <span className="mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded border text-fs-xs text-muted-foreground">
              {n + 1}
            </span>
            <span className="flex flex-col gap-0.5 min-w-0">
              <span className="flex flex-wrap items-center gap-2">
                <span className="text-sm font-medium">{o.label}</span>
                {o.pick && (
                  <span className="inline-flex items-center rounded-full border border-primary/40 bg-primary/10 px-1.5 py-0.5 text-fs-xs font-medium text-primary">
                    recommended
                  </span>
                )}
              </span>
              {o.note && <span className="text-xs text-muted-foreground">{o.note}</span>}

            </span>
          </button>
        ))}

        {/* Own-words escape hatch — the only free-text path. */}
        <button
          type="button"
          data-testid={`clarify-opt-${q.id}-freetext`}
          data-selected={pick === FREETEXT}
          onClick={() => setPick(FREETEXT)}
          className={cn(
            "flex items-start gap-2.5 rounded-md border px-3 py-2 text-left transition-colors",
            "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
            pick === FREETEXT
              ? "border-primary bg-accent"
              : "border-border bg-background hover:bg-accent/50",
          )}
        >
          <span className="mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded border text-fs-xs text-muted-foreground">
            {q.opts.length + 1}
          </span>
          <span className="flex flex-col gap-1.5 min-w-0 w-full">
            <span className="text-sm font-medium">
              {q.opts.length ? "Use a different value" : "Provide the missing input"}
            </span>
            {pick === FREETEXT && (
              <input
                data-testid={`clarify-own-${q.id}`}
                value={own[q.id] ?? ""}
                placeholder="e.g. GRCh38 but with our internal annotation"
                onChange={(e) => setOwn((m) => ({ ...m, [q.id]: e.target.value }))}
                onClick={(e) => e.stopPropagation()}
                className="w-full rounded border border-border bg-background px-2 py-1 text-xs focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              />
            )}
          </span>
        </button>
      </div>

      {/* Footer */}
      <div className="flex flex-wrap items-center gap-2 px-4 pb-3">

        <span className="flex-1" />
        <button
          type="button"
          data-testid="clarify-skip"
          onClick={skipOne}
          className="text-xs text-muted-foreground hover:text-foreground underline underline-offset-2 px-2 py-1"
        >
          Skip
        </button>
        <button
          type="button"
          data-testid="clarify-prev"
          disabled={i === 0}
          onClick={() => setI(i - 1)}
          className="text-xs text-muted-foreground hover:text-foreground disabled:opacity-40 disabled:pointer-events-none px-2 py-1"
        >
          Previous
        </button>
        <button
          type="button"
          data-testid="clarify-next"
          onClick={advance}
          className="rounded-md bg-primary px-3 py-1 text-xs font-medium text-primary-foreground hover:bg-primary/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          {i < N - 1 ? "Next" : "Confirm and configure"}
        </button>
      </div>
    </div>
  )
}
