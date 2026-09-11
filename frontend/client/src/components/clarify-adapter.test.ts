/**
 * Unit tests for clarify-adapter — mapping the deployed backend clarification
 * shapes onto typed ClarifyQuestion[] for the ClarifyCard (spec 06 §6.4).
 *
 * These are the behavioural contract for the "wire ClarifyCard" fix: they fail
 * if the mapping loses the bound value, drops the inferred pre-select, mis-types
 * a target, or breaks the intent → workflow-target routing.
 */
import { describe, it, expect } from "vitest"
import {
  paramClarificationToQuestion,
  paramClarificationsToQuestions,
  intentClarificationToQuestion,
} from "./clarify-adapter"
import type { ParamClarification } from "./param-clarification-card"

describe("paramClarificationToQuestion", () => {
  it("maps enum_violation → a param question with one option per allowed value, each binding its value", () => {
    const c: ParamClarification = {
      kind: "enum_violation",
      paramName: "delivery_cell",
      userValue: "B cells",
      allowed: ["T_cell", "NK_cell", "macrophage"],
    }
    const q = paramClarificationToQuestion(c)
    expect(q.target).toBe("param")
    expect(q.field).toBe("delivery_cell")
    expect(q.binds).toBe("schema value")
    // Bound value preserved on every option (the §6.4 binding rule).
    expect(q.opts.map((o) => o.val)).toEqual(["T_cell", "NK_cell", "macrophage"])
    // The rejected user value is named in the "why" line, honestly.
    expect(q.why).toContain("B cells")
    // No option is pre-selected — the user's value was invalid, so they choose.
    expect(q.opts.some((o) => o.pick)).toBe(false)
  })

  it("maps missing_required with examples → a param question, first example pre-selected", () => {
    const c: ParamClarification = {
      kind: "missing_required",
      paramName: "reference_build",
      hint: "the workflow needs a specific build",
      examples: ["GRCh38", "GRCh37"],
    }
    const q = paramClarificationToQuestion(c)
    expect(q.target).toBe("param")
    expect(q.opts.map((o) => o.val)).toEqual(["GRCh38", "GRCh37"])
    // First example is the recommended pick (one-click confirm).
    expect(q.opts[0].pick).toBe(true)
    expect(q.opts[1].pick).toBeFalsy()
    expect(q.why).toContain("the workflow needs a specific build")
  })

  it("maps missing_required with no examples → a param question with no options", () => {
    const c: ParamClarification = { kind: "missing_required", paramName: "genome" }
    const q = paramClarificationToQuestion(c)
    expect(q.opts).toHaveLength(0)
    expect(q.why).toContain("genome")
  })

  it("maps a list preserving order", () => {
    const list: ParamClarification[] = [
      { kind: "missing_required", paramName: "a", examples: ["x"] },
      { kind: "enum_violation", paramName: "b", userValue: "q", allowed: ["y", "z"] },
    ]
    const qs = paramClarificationsToQuestions(list)
    expect(qs.map((q) => q.field)).toEqual(["a", "b"])
  })
})

describe("intentClarificationToQuestion", () => {
  it("maps intent candidates → a single workflow-target question, primary pre-selected, intent type bound", () => {
    const q = intentClarificationToQuestion({
      originalMessage: "Design a PD-1 x VEGF bispecific for NSCLC",
      originalIntent: "tool_search",
      candidates: [
        { type: "tool_search", label: "search for tools" },
        { type: "workflow_generation", label: "design workflow", primary: true },
      ],
    })
    expect(q).not.toBeNull()
    expect(q!.target).toBe("workflow")
    expect(q!.binds).toBe("workflow id")
    // Every candidate becomes an option that binds the intent TYPE (not a sentence).
    expect(q!.opts.map((o) => o.val)).toEqual(["tool_search", "workflow_generation"])
    // The primary candidate is the pre-selected recommended pick.
    const primary = q!.opts.find((o) => o.val === "workflow_generation")
    expect(primary!.pick).toBe(true)
    // The original goal is echoed in the "why" line.
    expect(q!.why).toContain("bispecific")
  })

  it("pre-selects the first candidate when none is flagged primary", () => {
    const q = intentClarificationToQuestion({
      candidates: [
        { type: "a", label: "A" },
        { type: "b", label: "B" },
      ],
    })
    expect(q!.opts[0].pick).toBe(true)
    expect(q!.opts[1].pick).toBeFalsy()
  })

  it("returns null when there are no candidates", () => {
    expect(intentClarificationToQuestion({ candidates: [] })).toBeNull()
    expect(intentClarificationToQuestion(null)).toBeNull()
    expect(intentClarificationToQuestion(undefined)).toBeNull()
  })
})
