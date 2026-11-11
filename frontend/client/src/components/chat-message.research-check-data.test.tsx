/**
 * Integration test: a research/evidence answer rendered through chat-message
 * shows none of the removed exits (founder decision 2026-11-10) — no
 * "Plan analysis with my data" button, no "Save to project" button, and no
 * "Boundary:" caveat banner. The compute-result "Redo as a validated run"
 * handler must not leak onto a research answer either.
 */
import { describe, it, expect, vi } from "vitest"
import { render, screen } from "@testing-library/react"

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
        boundary: "Not evidence for dosing in humans.",
      },
    } as any,
  } as Message
}

describe("research answer in chat — removed exits stay removed", () => {
  it("renders no plan/save/boundary affordances, even with a redo handler supplied", () => {
    const onRedo = vi.fn()
    const { container } = render(<ChatMessage message={researchMessage()} onRedoAsValidatedRun={onRedo} />)
    expect(screen.queryByTestId("research-answer-check-data")).toBeNull()
    expect(screen.queryByTestId("research-answer-save")).toBeNull()
    expect(screen.queryByTestId("research-answer-boundary")).toBeNull()
    expect(container.textContent).not.toMatch(/Plan analysis with my data|规划我的数据分析/)
    expect(container.textContent).not.toMatch(/Save to project/)
    expect(container.textContent).not.toMatch(/Boundary:/)
    expect(onRedo).not.toHaveBeenCalled()
  })
})
