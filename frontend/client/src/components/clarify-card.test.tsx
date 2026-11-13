/**
 * RTL tests for <ClarifyCard> — typed confirm-inference. Uses the ported
 * CLARIFY fixture. Verifies: inferred pre-selection, typed value bind, the
 * param round-trip CustomEvent, workflow-id binding, free-text escape hatch,
 * and skip.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { ClarifyCard, type ClarifyAnswer, type ClarifyQuestion } from "./clarify-card"
import { CLARIFY_QUESTIONS } from "./gaps-fixtures"

describe("<ClarifyCard>", () => {
  let events: CustomEvent[]
  const capture = (e: Event) => events.push(e as CustomEvent)

  beforeEach(() => {
    events = []
    window.addEventListener("biomate:param-clarification-resolved", capture)
    window.addEventListener("biomate:clarify-workflow-resolved", capture)
    window.addEventListener("biomate:param-clarification-skipped", capture)
  })
  afterEach(() => {
    window.removeEventListener("biomate:param-clarification-resolved", capture)
    window.removeEventListener("biomate:clarify-workflow-resolved", capture)
    window.removeEventListener("biomate:param-clarification-skipped", capture)
  })

  it("renders nothing for empty questions", () => {
    const { container } = render(<ClarifyCard questions={[]} />)
    expect(container.firstChild).toBeNull()
  })

  it("pre-selects the inferred (recommended) option", () => {
    render(<ClarifyCard questions={CLARIFY_QUESTIONS} />)
    // Q1 option 0 is the pick.
    expect(screen.getByTestId("clarify-opt-reference_build-0")).toHaveAttribute(
      "data-selected",
      "true",
    )
    expect(screen.getByText("recommended")).toBeInTheDocument()
    expect(screen.getByTestId("clarify-count")).toHaveTextContent("1/3")
  })

  it("shows the explanation without internal schema bindings", () => {
    render(<ClarifyCard questions={CLARIFY_QUESTIONS} />)
    expect(screen.getByText(/two are not interchangeable downstream/)).toBeInTheDocument()
    expect(screen.queryByText("reference_build = GRCh38.p14/ens110")).toBeNull()
    expect(screen.queryByText(/binds to a/)).toBeNull()
  })

  it("emits a fully typed answer set and dispatches the param round-trip event", async () => {
    const user = userEvent.setup()
    const onDone = vi.fn<[ClarifyAnswer[]], void>()
    render(<ClarifyCard questions={CLARIFY_QUESTIONS} onDone={onDone} messageId="m1" />)

    // Walk all three questions accepting the inferred picks.
    await user.click(screen.getByTestId("clarify-next")) // -> Q2
    await user.click(screen.getByTestId("clarify-next")) // -> Q3
    await user.click(screen.getByTestId("clarify-next")) // confirm

    expect(onDone).toHaveBeenCalledTimes(1)
    const answers = onDone.mock.calls[0][0]
    expect(answers).toHaveLength(3)
    expect(answers[0]).toEqual({
      questionId: "reference_build",
      target: { type: "param", name: "reference_build" },
      value: "GRCh38.p14/ens110",
      source: "inferred",
    })
    // The workflow question binds to a workflow id, not a param.
    expect(answers[1]).toEqual({
      questionId: "workflow",
      target: { type: "workflow", name: "workflow" },
      value: "wf.rnaseq.de.v4",
      source: "inferred",
    })

    // Param answers dispatch the existing round-trip event; workflow answers a separate one.
    const paramEv = events.find(
      (e) => e.type === "biomate:param-clarification-resolved" && (e.detail as any).paramName === "reference_build",
    )
    expect(paramEv).toBeTruthy()
    expect(paramEv!.detail).toEqual({ messageId: "m1", paramName: "reference_build", value: "GRCh38.p14/ens110" })

    const wfEv = events.find((e) => e.type === "biomate:clarify-workflow-resolved")
    expect(wfEv!.detail).toEqual({ messageId: "m1", workflowId: "wf.rnaseq.de.v4" })
  })

  it("marks source 'user' when a non-inferred option is picked", async () => {
    const user = userEvent.setup()
    const onDone = vi.fn<[ClarifyAnswer[]], void>()
    render(<ClarifyCard questions={CLARIFY_QUESTIONS} onDone={onDone} />)

    await user.click(screen.getByTestId("clarify-opt-reference_build-2")) // legacy GRCh37
    await user.click(screen.getByTestId("clarify-next"))
    await user.click(screen.getByTestId("clarify-next"))
    await user.click(screen.getByTestId("clarify-next"))

    const answers = onDone.mock.calls[0][0]
    expect(answers[0]).toMatchObject({ value: "GRCh37/ens75", source: "user" })
  })

  it("free-text option produces a 'freetext' answer with the typed text", async () => {
    const user = userEvent.setup()
    const onDone = vi.fn<[ClarifyAnswer[]], void>()
    render(<ClarifyCard questions={CLARIFY_QUESTIONS} onDone={onDone} />)

    await user.click(screen.getByTestId("clarify-opt-reference_build-freetext"))
    await user.type(screen.getByTestId("clarify-own-reference_build"), "GRCh38 + internal annotation")
    await user.click(screen.getByTestId("clarify-next"))
    await user.click(screen.getByTestId("clarify-next"))
    await user.click(screen.getByTestId("clarify-next"))

    const answers = onDone.mock.calls[0][0]
    expect(answers[0]).toEqual({
      questionId: "reference_build",
      target: { type: "param", name: "reference_build" },
      value: "GRCh38 + internal annotation",
      source: "freetext",
    })
  })

  it("keeps per-question free-text independent across questions", async () => {
    // Regression: a single shared `own` string made a later free-text answer
    // overwrite an earlier one. Q1 and Q3 both free-texted with DIFFERENT text
    // must both survive to the emitted answer set.
    const user = userEvent.setup()
    const onDone = vi.fn<[ClarifyAnswer[]], void>()
    render(<ClarifyCard questions={CLARIFY_QUESTIONS} onDone={onDone} />)

    // Q1 free-text
    await user.click(screen.getByTestId("clarify-opt-reference_build-freetext"))
    await user.type(screen.getByTestId("clarify-own-reference_build"), "build-ONE")
    await user.click(screen.getByTestId("clarify-next")) // -> Q2
    await user.click(screen.getByTestId("clarify-next")) // -> Q3 (accept inferred workflow)
    // Q3 free-text with different text
    await user.click(screen.getByTestId("clarify-opt-output_template-freetext"))
    await user.type(screen.getByTestId("clarify-own-output_template"), "template-THREE")
    await user.click(screen.getByTestId("clarify-next")) // confirm

    const answers = onDone.mock.calls[0][0]
    expect(answers[0]).toMatchObject({ questionId: "reference_build", value: "build-ONE", source: "freetext" })
    expect(answers[2]).toMatchObject({ questionId: "output_template", value: "template-THREE", source: "freetext" })
  })

  it("skip-one advances and dispatches a skip event", async () => {
    const user = userEvent.setup()
    const onSkip = vi.fn()
    render(<ClarifyCard questions={CLARIFY_QUESTIONS} onSkip={onSkip} />)
    await user.click(screen.getByTestId("clarify-skip"))
    expect(onSkip).toHaveBeenCalledWith(["reference_build"])
    expect(screen.getByTestId("clarify-count")).toHaveTextContent("2/3")
    expect(events.some((e) => e.type === "biomate:param-clarification-skipped")).toBe(true)
  })

  it("skip-all uses the inferred values and reports every question id", async () => {
    const user = userEvent.setup()
    const onSkip = vi.fn()
    const onDone = vi.fn<[ClarifyAnswer[]], void>()
    render(<ClarifyCard questions={CLARIFY_QUESTIONS} onSkip={onSkip} onDone={onDone} />)
    await user.click(screen.getByTestId("clarify-skip-all"))
    expect(onSkip).toHaveBeenCalledWith(["reference_build", "workflow", "output_template"])
    // Inferred values are still handed back.
    expect(onDone.mock.calls[0][0]).toHaveLength(3)
    expect(onDone.mock.calls[0][0][2]).toMatchObject({ value: "tpl.memo.v3", source: "inferred" })
  })

  // Regression (2026-09-11): an enum_violation question has NO pre-selected
  // option (adapter sets no `pick` — the user must choose deliberately). A bare
  // skip/confirm must NOT emit a param-clarification-resolved event silently
  // defaulting to opts[0], which the workflow-panel bridge would pre-fill as if
  // the user had picked it. Nothing chosen → nothing resolved.
  const ENUM_ONLY: ClarifyQuestion[] = [
    {
      id: "aligner",
      q: "Which aligner?",
      field: "aligner",
      target: "param",
      binds: "schema value",
      why: 'You said "bowtie3", but only these are supported.',
      opts: [
        { label: "star", val: "star" },
        { label: "hisat2", val: "hisat2" },
        { label: "salmon", val: "salmon" },
      ], // no `pick` on any option
    },
  ]

  it("does NOT emit a resolved value for a skipped enum question with no pre-select", async () => {
    const user = userEvent.setup()
    const onDone = vi.fn<[ClarifyAnswer[]], void>()
    render(<ClarifyCard questions={ENUM_ONLY} onDone={onDone} messageId="menum" />)
    // No option is pre-highlighted.
    expect(screen.getByTestId("clarify-opt-aligner-0")).toHaveAttribute("data-selected", "false")
    // Skip without choosing.
    await user.click(screen.getByTestId("clarify-skip"))
    // The skip audit event fires…
    expect(events.some((e) => e.type === "biomate:param-clarification-skipped")).toBe(true)
    // …but NO resolved event applies a bogus first value.
    expect(events.some((e) => e.type === "biomate:param-clarification-resolved")).toBe(false)
    // onDone carries no answer for the un-chosen enum.
    expect(onDone).toHaveBeenCalledTimes(1)
    expect(onDone.mock.calls[0][0]).toHaveLength(0)
  })

  it("emits a user-sourced value once an enum option IS explicitly picked", async () => {
    const user = userEvent.setup()
    const onDone = vi.fn<[ClarifyAnswer[]], void>()
    render(<ClarifyCard questions={ENUM_ONLY} onDone={onDone} messageId="menum2" />)
    await user.click(screen.getByTestId("clarify-opt-aligner-1")) // hisat2
    await user.click(screen.getByTestId("clarify-next")) // confirm (single question)
    expect(onDone.mock.calls[0][0]).toHaveLength(1)
    expect(onDone.mock.calls[0][0][0]).toMatchObject({ value: "hisat2", source: "user" })
    const ev = events.find((e) => e.type === "biomate:param-clarification-resolved")
    expect((ev!.detail as any)).toMatchObject({ paramName: "aligner", value: "hisat2" })
  })

  it("zero-opt file prompt: Confirm with NONE emits empty fretext (opens panel bridge)", async () => {
    // Clinic hell 2026-11-13: movies_path clarify with only "Provide the missing input"
    // used to emit nothing on Confirm → right panel stayed closed.
    const user = userEvent.setup()
    const onDone = vi.fn<[ClarifyAnswer[]], void>()
    const FILE_PROMPT: ClarifyQuestion[] = [
      {
        id: "movies_path",
        q: "Which movies_path?",
        field: "movies_path",
        target: "param",
        binds: "file path",
        why: "movies_path is required",
        opts: [], // only fretext escape hatch
      },
    ]
    render(<ClarifyCard questions={FILE_PROMPT} onDone={onDone} messageId="mcryo" />)
    await user.click(screen.getByTestId("clarify-next")) // Confirm and configure
    expect(onDone).toHaveBeenCalledTimes(1)
    expect(onDone.mock.calls[0][0]).toHaveLength(1)
    expect(onDone.mock.calls[0][0][0]).toMatchObject({
      value: "",
      source: "freetext",
      target: { type: "param", name: "movies_path" },
    })
    const ev = events.find((e) => e.type === "biomate:param-clarification-resolved")
    expect(ev).toBeTruthy()
    expect((ev!.detail as any)).toMatchObject({
      messageId: "mcryo",
      paramName: "movies_path",
      value: "",
    })
  })
})
