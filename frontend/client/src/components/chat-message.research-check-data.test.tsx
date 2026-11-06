/**
 * Integration test for the "Check against our data" exit on a research/evidence
 * answer (task #19). Verifies the exit is wired through chat-message to the
 * redo-as-validated-run handler (re-running the question as a validated
 * workflow), and that it is NOT shown when no handler exists (no dead exit).
 */
import { describe, it, expect, vi, afterEach } from "vitest"
import { render, screen, fireEvent } from "@testing-library/react"

// chat-message transitively imports the 3Dmol viewer (window.URL.createObjectURL);
// jsdom lacks it. Stub before import.
vi.mock("3dmol", () => ({ default: {}, GLViewer: class {}, createViewer: () => ({}) }))

import { ChatMessage, type Message } from "./chat-message"

function researchMessage(): Message {
  return {
    id: "m-research-1",
    role: "assistant",
    content: "",
    timestamp: new Date(),
    metadata: {
      type: "research_response",
      research_response: {
        answer: "Pathway Y is upregulated under treatment X in most systems.",
        citations: [{ title: "A study", year: 2024 }],
        confidence: 0.8,
      },
    } as any,
  } as Message
}

describe('research answer → "Check against our data" exit (#19)', () => {
  afterEach(() => { vi.restoreAllMocks() })

  it("fires the redo-as-validated-run handler with THIS message when wired", () => {
    const onRedo = vi.fn()
    render(<ChatMessage message={researchMessage()} onRedoAsValidatedRun={onRedo} />)
    const exit = screen.getByTestId("research-answer-check-data")
    fireEvent.click(exit)
    expect(onRedo).toHaveBeenCalledTimes(1)
    expect(onRedo.mock.calls[0][0]).toMatchObject({ id: "m-research-1" })
  })

  it("does NOT render the exit when no handler is supplied (no dead affordance)", () => {
    render(<ChatMessage message={researchMessage()} />)
    expect(screen.queryByTestId("research-answer-check-data")).toBeNull()
    // The boundary is still always present.
    expect(screen.getByTestId("research-answer-boundary")).toBeInTheDocument()
  })
})
