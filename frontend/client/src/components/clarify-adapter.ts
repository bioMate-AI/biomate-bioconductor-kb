/**
 * clarify-adapter — map the deployed backend clarification shapes onto
 * {@link ClarifyQuestion}[] so the typed {@link ClarifyCard} (spec 06 §6.4)
 * can render them.
 *
 * The backend surfaces two clarification shapes today, each with its own
 * (pre-v2) card:
 *
 *   1. `paramClarifications: ParamClarification[]` — schema-grounded param
 *      extraction issues (enum_violation / missing_required). Rendered by
 *      ParamClarificationCard. Each maps to a `target: "param"` question whose
 *      options carry the allowed schema value in `val` (§6.4 binding rule:
 *      answering selects a schema value, never re-parsed as language).
 *
 *   2. `intentClarification` — cross-intent ambiguity (tool_search vs
 *      workflow_generation …) from _detectCrossIntentAmbiguity. Rendered by
 *      IntentClarificationCard. Its candidates are intent TYPES, not schema
 *      values — picking one re-submits the original message with
 *      `context.intentOverride`. This is the "disambiguate by id, never
 *      re-classify the sentence" case: we map it to a `target: "workflow"`
 *      question whose option `val` is the intent type. The card dispatches
 *      `biomate:clarify-workflow-resolved`; the render site translates that
 *      back into the existing `biomate:intent-clarification-resolved`
 *      re-submit so the intentOverride round-trip is preserved unchanged.
 *
 * This module is pure (no React, no window) so it is trivially unit-testable.
 */

import type { ClarifyQuestion, ClarifyOption } from "./clarify-card"
import type { ParamClarification } from "./param-clarification-card"
import type { IntentCandidate } from "./intent-clarification-card"

/** The intent-clarification metadata shape read off message.metadata. */
export interface IntentClarificationMeta {
  originalMessage?: string
  originalIntent?: string
  candidates: IntentCandidate[]
  reason?: string
}

/**
 * Map one {@link ParamClarification} to a typed {@link ClarifyQuestion}.
 *
 * - enum_violation: the allowed values become options, each binding its value.
 *   The user's rejected value is named in the "why" line. No pre-select — none
 *   of the allowed values is inferred (the user's was invalid), so the user
 *   chooses deliberately.
 * - missing_required: the example values (if any) become options; the first is
 *   pre-selected as the recommended pick. The hint feeds the "why" line.
 */
export function paramClarificationToQuestion(c: ParamClarification): ClarifyQuestion {
  if (c.kind === "enum_violation") {
    const opts: ClarifyOption[] = c.allowed.map((v) => ({ label: v, val: v }))
    return {
      id: c.paramName,
      q: `Which ${c.paramName}?`,
      field: c.paramName,
      target: "param",
      binds: "schema value",
      why: `You said "${c.userValue}", but this workflow only supports the values below.`,
      opts,
    }
  }
  // missing_required
  const examples = c.examples ?? []
  const opts: ClarifyOption[] = examples.map((v, i) => ({
    label: v,
    val: v,
    // Pre-select the first example as the recommended value when we have one.
    pick: i === 0,
  }))
  return {
    id: c.paramName,
    q: `Which ${c.paramName}?`,
    field: c.paramName,
    target: "param",
    binds: "schema value",
    why: c.hint
      ? `${c.paramName} is required — ${c.hint}`
      : `${c.paramName} is required for this workflow.`,
    opts,
  }
}

/** Map the whole paramClarifications list to typed questions. */
export function paramClarificationsToQuestions(
  clarifications: ParamClarification[],
): ClarifyQuestion[] {
  return clarifications.map(paramClarificationToQuestion)
}

/**
 * Map the intent-clarification metadata to a single typed {@link ClarifyQuestion}
 * whose `target` is `workflow` (so the ClarifyCard dispatches
 * `biomate:clarify-workflow-resolved` with the picked intent type as the value).
 * The primary candidate — the design/execution lane per the lean-on-execution
 * principle — is the pre-selected recommended pick.
 *
 * Returns null when there are no candidates (nothing to disambiguate).
 */
export function intentClarificationToQuestion(
  meta: IntentClarificationMeta | undefined | null,
): ClarifyQuestion | null {
  if (!meta || !Array.isArray(meta.candidates) || meta.candidates.length === 0) return null
  const opts: ClarifyOption[] = meta.candidates.map((c) => ({
    label: c.label,
    val: c.type,
    pick: !!c.primary,
  }))
  // If no candidate was flagged primary, pre-select the first so a routine can
  // be confirmed in one click (§6.4 — the recommended option is marked).
  if (!opts.some((o) => o.pick) && opts.length > 0) opts[0].pick = true
  const original = meta.originalMessage || ""
  const shortOriginal = original.length > 80 ? original.slice(0, 80) + "…" : original
  return {
    id: "__intent__",
    q: "Which should I do?",
    field: "__intent__",
    target: "workflow",
    binds: "workflow id",
    why: shortOriginal
      ? `Your request — "${shortOriginal}" — could go more than one way. Picking one selects it directly; I do not re-read the sentence.`
      : "Your request could go more than one way. Picking one selects it directly.",
    opts,
  }
}
