/**
 * Renders every chat surface Track D touched — the assistant action row (+ the
 * 👎 reason popover), a research answer with its expanded numbered references
 * and search footnote, the source reader, the workflow chip (status + Open),
 * the one-line chat header and the landing cards (every card / track /
 * domain opened) — and returns all visible text + accessible labels.
 *
 * Used by chat-surfaces.locale-{en,zh}.test.tsx, which mock @/lib/i18n with a
 * STRICT lookup into one bundle only (a missing key renders ⟦MISSING:key⟧ —
 * no cross-language fallback), so a string that skips i18n or lacks an entry
 * in that locale is caught.
 */
import React from "react"
import { render, screen, fireEvent, cleanup, within } from "@testing-library/react"
import { Router } from "wouter"
import { memoryLocation } from "wouter/memory-location"
import { ChatMessage, type Message } from "@/components/chat-message"
import { ChatHeaderTitle } from "@/components/chat-header-title"
import { ColdStartDashboard } from "@/components/cold-start-dashboard"
import { SourceReaderPane } from "@/components/source-reader-pane"

/** Data (not UI copy) the surfaces echo back — excluded from the language check. */
export const DATA_STRINGS = [
  "Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2",
  "Genome Biology", "Love MI", "STAR", "HISAT2", "PubMed", "Europe PMC", "nf-core/rnaseq", "EPAR",
]

function texts(root: HTMLElement): string {
  const labels = Array.from(root.querySelectorAll("[aria-label],[title],[placeholder]"))
    .flatMap((el) => ["aria-label", "title", "placeholder"].map((a) => el.getAttribute(a) || ""))
  return [root.textContent || "", ...labels].join("\n")
}

export async function renderChatSurfaces(answerText: string, userTitle: string): Promise<string> {
  const out: string[] = []
  const research: Message = {
    id: "m-r", role: "assistant", content: answerText, timestamp: new Date(),
    metadata: {
      type: "research_response",
      research_response: {
        answer: answerText, confidence: 0.8,
        citations: [{ title: DATA_STRINGS[0], journal: "Genome Biology", year: 2014, pmid: "25516281", doi: "10.1186/s13059-014-0550-8" }],
        retrieval: [{ name: "PubMed", found: 15, kept: 3 }, { name: "Europe PMC", found: 9, kept: 1 }],
        conflicts: [{ topic: "STAR", positions: [{ claim: "STAR", source: "HISAT2" }] }],
      },
    } as any,
  } as Message
  const v1 = render(<ChatMessage message={research} isLatestAssistantMessage />)
  fireEvent.click(screen.getByTestId("citations-toggle"))
  fireEvent.click(screen.getByTestId("inline-feedback-thumbs-down"))
  out.push(texts(document.body))
  v1.unmount()

  const wf: Message = {
    id: "m-w", role: "assistant", content: answerText, timestamp: new Date(),
    metadata: { type: "workflow", workflow: { name: "nf-core/rnaseq", steps: {} } } as any,
  } as Message
  for (const status of ["running", "completed", "failed", "pending", "queued"]) {
    const run = { id: "r1", execution: { status } } as any
    const v = render(<ChatMessage message={wf} isInPanel currentExecutionRun={run} onOpenInPanel={() => {}} />)
    v.rerender(<ChatMessage message={wf} isInPanel={false} currentExecutionRun={run} onOpenInPanel={() => {}} />)
    out.push(texts(v.container))
    v.unmount()
  }

  const loc = memoryLocation({ path: "/" })
  const h = render(<Router hook={loc.hook}><ChatHeaderTitle title={userTitle} projectId="p1" projectName="EPAR" live /></Router>)
  out.push(texts(h.container))
  h.rerender(<Router hook={loc.hook}><ChatHeaderTitle title="New Chat" /></Router>)
  out.push(texts(h.container))
  h.unmount()

  const reader = render(<SourceReaderPane sources={[{ tool_id: "a", tool_name: DATA_STRINGS[0], title: DATA_STRINGS[0], authors: ["Love MI"], year: 2014, journal: "Genome Biology", formatted_apa: "", formatted_short: "", formatted_bibtex: "" } as any]} index={0} onIndexChange={() => {}} />)
  out.push(texts(document.body))
  reader.unmount()

  const cs = render(<ColdStartDashboard onSeed={() => {}} />)
  out.push(texts(cs.container))
  for (const card of screen.getAllByTestId("cold-module-card")) {
    const id = card.getAttribute("data-module-id")!
    const header = within(card).getByTestId("cold-module-expand")
    if (header.getAttribute("aria-expanded") !== "true") fireEvent.click(header)
    const body = within(screen.getAllByTestId("cold-module-card").find((c) => c.getAttribute("data-module-id") === id)!).getByTestId("cold-module-body")
    for (const tab of within(body).getAllByRole("tab")) {
      fireEvent.click(tab)
      out.push(texts(cs.container))
      for (const chip of body.querySelectorAll("[data-testid^='cold-domain-']")) {
        fireEvent.click(chip as HTMLElement)
        out.push(texts(cs.container))
      }
    }
  }
  cs.unmount()
  cleanup()
  return out.join("\n")
}
