/**
 * Integration test for the ClarifyCard wiring (spec 06 §6.4) through
 * chat-message. Verifies that both backend clarification shapes now render the
 * typed ClarifyCard — NOT the pre-v2 ParamClarificationCard /
 * IntentClarificationCard — and that the round-trip event bridges are preserved:
 *
 *   - paramClarifications → clarify-card with bound values; picking + confirming
 *     dispatches `biomate:param-clarification-resolved` (panel pre-fill bridge).
 *   - intentClarification → clarify-card (workflow target); picking + confirming
 *     dispatches `biomate:intent-clarification-resolved` (intentOverride re-submit
 *     bridge); skip-all dispatches `biomate:intent-clarification-skipped` and
 *     does NOT re-submit.
 *
 * These fail if the wiring is reverted to the old cards or the adapter drops the
 * typed bind / round-trip.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { render, screen } from "@testing-library/react"
import userEvent from "@testing-library/user-event"

// chat-message transitively imports the 3Dmol viewer, which touches
// window.URL.createObjectURL at load; jsdom lacks it. Stub before import.
vi.mock("3dmol", () => ({ default: {}, GLViewer: class {}, createViewer: () => ({}) }))

import { ChatMessage, type Message } from "./chat-message"

function paramMessage(): Message {
  return {
    id: "m-param-1",
    role: "assistant",
    content: "",
    timestamp: new Date(),
    metadata: {
      paramClarifications: [
        {
          kind: "enum_violation",
          paramName: "delivery_cell",
          userValue: "B cells",
          allowed: ["T_cell", "NK_cell", "macrophage"],
        },
      ],
    } as any,
  } as Message
}

function intentMessage(): Message {
  return {
    id: "m-intent-1",
    role: "assistant",
    content: "",
    timestamp: new Date(),
    metadata: {
      intentClarification: {
        originalMessage: "Design a PD-1 x VEGF bispecific for NSCLC",
        originalIntent: "tool_search",
        candidates: [
          { type: "tool_search", label: "search for tools" },
          { type: "workflow_generation", label: "design workflow", primary: true },
        ],
      },
    } as any,
  } as Message
}

describe("chat-message → ClarifyCard wiring (§6.4)", () => {
  let events: CustomEvent[]
  const capture = (e: Event) => events.push(e as CustomEvent)
  const NAMES = [
    "biomate:param-clarification-resolved",
    "biomate:param-clarification-skipped",
    "biomate:clarify-workflow-resolved",
    "biomate:intent-clarification-resolved",
    "biomate:intent-clarification-skipped",
  ]
  beforeEach(() => {
    events = []
    NAMES.forEach((n) => window.addEventListener(n, capture))
  })
  afterEach(() => {
    NAMES.forEach((n) => window.removeEventListener(n, capture))
    vi.restoreAllMocks()
  })

  it("renders the typed ClarifyCard (not the old param card) for paramClarifications", () => {
    render(<ChatMessage message={paramMessage()} />)
    expect(screen.getByTestId("clarify-card")).toBeInTheDocument()
    expect(screen.queryByTestId("param-clarification-card")).not.toBeInTheDocument()
    // Show the human option label, without internal schema assignment text.
    expect(screen.getByTestId("clarify-opt-delivery_cell-0")).toHaveTextContent(
      "T_cell",
    )
  })

  it("param pick + confirm dispatches the panel pre-fill bridge event", async () => {
    const user = userEvent.setup()
    render(<ChatMessage message={paramMessage()} />)
    await user.click(screen.getByTestId("clarify-opt-delivery_cell-1")) // NK_cell
    await user.click(screen.getByTestId("clarify-next")) // Confirm and configure
    const ev = events.find((e) => e.type === "biomate:param-clarification-resolved")
    expect(ev).toBeTruthy()
    expect(ev!.detail).toMatchObject({ paramName: "delivery_cell", value: "NK_cell" })
  })

  it("renders the typed ClarifyCard (not the old intent card) for intentClarification", () => {
    render(<ChatMessage message={intentMessage()} />)
    expect(screen.getByTestId("clarify-card")).toBeInTheDocument()
    expect(screen.queryByTestId("intent-clarification-card")).not.toBeInTheDocument()
  })

  it("intent pick + confirm dispatches the intentOverride re-submit bridge event", async () => {
    const user = userEvent.setup()
    render(<ChatMessage message={intentMessage()} />)
    // workflow_generation is the primary → pre-selected; confirm straight away.
    await user.click(screen.getByTestId("clarify-next"))
    const ev = events.find((e) => e.type === "biomate:intent-clarification-resolved")
    expect(ev).toBeTruthy()
    expect(ev!.detail).toMatchObject({
      intentType: "workflow_generation",
      originalMessage: "Design a PD-1 x VEGF bispecific for NSCLC",
    })
  })

  it("intent skip-all dispatches skipped and does NOT re-submit (no resolved event)", async () => {
    const user = userEvent.setup()
    render(<ChatMessage message={intentMessage()} />)
    await user.click(screen.getByTestId("clarify-skip-all"))
    expect(events.some((e) => e.type === "biomate:intent-clarification-skipped")).toBe(true)
    expect(events.some((e) => e.type === "biomate:intent-clarification-resolved")).toBe(false)
  })
})
