/**
 * RTL tests for <ClarifyCard> — typed confirm-inference. Uses the ported
 * CLARIFY fixture. Verifies: inferred pre-selection, typed value bind, the
 * param round-trip CustomEvent, workflow-id binding, free-text escape hatch,
 * and skip.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { ClarifyCard, type ClarifyAnswer } from "./clarify-card"
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

  it("shows the why line and the typed bind for each option", () => {
    render(<ClarifyCard questions={CLARIFY_QUESTIONS} />)
    expect(screen.getByText(/two are not interchangeable downstream/)).toBeInTheDocument()
    expect(screen.getByText("reference_build = GRCh38.p14/ens110")).toBeInTheDocument()
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
})
