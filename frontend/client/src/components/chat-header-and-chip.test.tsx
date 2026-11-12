/** One-line chat header (title + project chip) and the in-chat workflow chip. */
import React from "react"
import { describe, expect, it, vi } from "vitest"
import { render, screen } from "@testing-library/react"
import { Router } from "wouter"
import { memoryLocation } from "wouter/memory-location"
vi.mock("3dmol", () => ({ default: {}, GLViewer: class {}, createViewer: () => ({}) }))
import { ChatHeaderTitle, displayChatTitle } from "./chat-header-title"
import { ChatMessage, wfChipLabel, type Message } from "./chat-message"
import { isChatRoute } from "@/App"

describe("chat header", () => {
  it("is ONE line: title + small project chip — no 'Unfiled / new chat' breadcrumb", () => {
    const loc = memoryLocation({ path: "/", record: true })
    render(<Router hook={loc.hook}><ChatHeaderTitle title="EPAR approvals" projectId="p1" projectName="test" /></Router>)
    const header = screen.getByTestId("chat-header-title")
    expect(header).toHaveTextContent(/^EPAR approvalstest$/)
    expect(header.textContent).not.toMatch(/Unfiled|new chat|\//)
    screen.getByTestId("chat-header-project-chip").click()
    expect(loc.history).toContain("/projects?project=p1")
  })

  it("shows the localized untitled label for the stored 'New Chat' sentinel, and no chip without a project", () => {
    expect(displayChatTitle("New Chat")).toBe("New Chat")
    expect(displayChatTitle("")).toBe("New Chat")
    const loc = memoryLocation({ path: "/" })
    render(<Router hook={loc.hook}><ChatHeaderTitle title={null} /></Router>)
    expect(screen.queryByTestId("chat-header-project-chip")).toBeNull()
  })

  it("the separate project banner is suppressed on the chat route only", () => {
    expect(isChatRoute("/")).toBe(true)
    expect(isChatRoute("/projects")).toBe(false)
    expect(isChatRoute("/files")).toBe(false)
  })
})

describe("in-chat workflow chip", () => {
  const wf: Message = { id: "w", role: "assistant", content: "x", timestamp: new Date(), metadata: { type: "workflow", workflow: { name: "nf-core/rnaseq", steps: {} } } as any } as Message

  it("status labels go through i18n", () => {
    expect(wfChipLabel("succeeded")).toBe("Completed")
    expect(wfChipLabel("pending")).toBe("Ready")
    expect(wfChipLabel("weird")).toBe("Unknown")
    expect(wfChipLabel(undefined)).toBeNull()
  })

  it("has no redundant 'In panel' chip; Open appears only when the panel is closed", () => {
    const run = { id: "r", execution: { status: "running" } } as any
    const v = render(<ChatMessage message={wf} isInPanel currentExecutionRun={run} onOpenInPanel={() => {}} />)
    expect(screen.queryByTestId("wf-chip-in-panel")).toBeNull()
    expect(screen.queryByTestId("wf-chip-open")).toBeNull()
    expect(screen.getByText("Running")).toBeInTheDocument()
    v.rerender(<ChatMessage message={wf} isInPanel={false} currentExecutionRun={run} onOpenInPanel={() => {}} />)
    expect(screen.getByTestId("wf-chip-open")).toHaveTextContent("Open")
  })
})
