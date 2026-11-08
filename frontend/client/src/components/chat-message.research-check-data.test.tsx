/**
 * Integration test for the "Check against our data" exit on a research/evidence
 * answer (task #19). Verifies the exit is wired through chat-message to the
 * separate planning handler (preparing a composer draft), and that it is NOT shown when no handler exists (no dead exit).
 */
import { describe, it, expect, vi, afterEach } from "vitest"
import { render, screen, fireEvent } from "@testing-library/react"

// chat-message transitively imports the 3Dmol viewer (window.URL.createObjectURL);
// jsdom lacks it. Stub before import.
vi.mock("3dmol", () => ({ default: {}, GLViewer: class {}, createViewer: () => ({}) }))

import { ChatMessage, type Message } from "./chat-message"
import { stageAnalysisPlanDraft } from "@/lib/analysis-plan-draft"

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

  it("prepares an analysis draft without redoing or executing the research answer", () => {
    const onRedo = vi.fn()
    const setDraft = vi.fn()
    const answer = researchMessage()
    const question = { id:'question', role:'user', content:'What supports treatment X?', timestamp:new Date() } as Message
    const onPlan = vi.fn((message: Message) => stageAnalysisPlanDraft([question, answer], message, setDraft, {
      introduction:'Plan an analysis', questionLabel:'Previous question:', evidenceLabel:'Literature context:', requestLabel:'My dataset and analysis question:',
    }))
    const fetcher = vi.fn()
    vi.stubGlobal('fetch', fetcher)
    render(<ChatMessage message={researchMessage()} onRedoAsValidatedRun={onRedo} onPlanAnalysisWithData={onPlan} />)
    const exit = screen.getByTestId("research-answer-check-data")
    fireEvent.click(exit)
    expect(exit).toHaveTextContent('Plan analysis with my data')
    expect(exit).toHaveAttribute('title', expect.stringContaining('draft'))
    expect(onPlan).toHaveBeenCalledTimes(1)
    expect(onPlan.mock.calls[0][0]).toMatchObject({ id: "m-research-1" })
    expect(setDraft).toHaveBeenCalledWith(expect.stringContaining(question.content))
    expect(setDraft).toHaveBeenCalledWith(expect.stringContaining('Pathway Y is upregulated under treatment X'))
    expect(onRedo).not.toHaveBeenCalled()
    expect(fetcher).not.toHaveBeenCalled()
    vi.unstubAllGlobals()
  })

  it("does NOT borrow the separate redo handler when planning is unavailable", () => {
    render(<ChatMessage message={researchMessage()} onRedoAsValidatedRun={vi.fn()} />)
    expect(screen.queryByTestId("research-answer-check-data")).toBeNull()
    // The boundary is still always present.
    expect(screen.getByTestId("research-answer-boundary")).toBeInTheDocument()
  })
})
