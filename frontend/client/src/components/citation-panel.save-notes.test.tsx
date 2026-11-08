/**
 * Positive + failure-path tests for <CitationPanel>'s "Save to project notes"
 * action (Spec 01 §1.5). The sibling `citation-panel.evidence.test.tsx` only
 * covers the DISABLED state (no active project) — which would still pass even if
 * the feature were completely broken. These tests exercise the real POST so a
 * regression that stops it saving (or fakes success on error) actually FAILS.
 *
 * We control `useActiveProjectIdSafe` (so a project IS active) and spy on
 * `api.request` + `useToast` — unit-level mocks of our own modules, not of the
 * route under test (there is no route under test here; this is the client action).
 */
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, waitFor } from "@testing-library/react"
import userEvent from "@testing-library/user-event"

// Control the active project + capture toasts. importActual-spread so other
// exports of these modules keep working.
const activeIdRef = { current: null as string | null }
vi.mock("@/contexts/active-project-context", async (orig) => ({
  ...(await orig<any>()),
  useActiveProjectIdSafe: () => activeIdRef.current,
}))
const toastSpy = vi.fn()
vi.mock("@/hooks/use-toast", async (orig) => ({
  ...(await orig<any>()),
  useToast: () => ({ toast: toastSpy, dismiss: vi.fn(), toasts: [] }),
}))

import { CitationPanel } from "./citation-panel"
import { api } from "@/lib/api"
import type { Citation } from "@shared/schema"

function makeCitation(over: Record<string, unknown> = {}): Citation {
  return {
    tool_id: "a",
    tool_name: "DESeq2",
    title: "Interferon signalling in disease",
    authors: ["Author A"],
    year: 2023,
    journal: "Cell Rep",
    doi: "10.1000/abc",
    formatted_apa: "Author A et al. (2023).",
    formatted_short: "Author A et al., 2023",
    formatted_bibtex: "@article{a2023}",
    locus: "Fig 3B",
    ...over,
  } as unknown as Citation
}

describe("<CitationPanel> save-to-notes — positive + failure paths", () => {
  beforeEach(() => {
    activeIdRef.current = null
    toastSpy.mockReset()
    vi.restoreAllMocks()
  })

  it("is enabled with an active project and POSTs the answer + sources to the notes endpoint", async () => {
    activeIdRef.current = "proj-1"
    const reqSpy = vi.spyOn(api, "request").mockResolvedValue({ ok: true } as any)
    const user = userEvent.setup()
    render(
      <CitationPanel
        citations={[makeCitation()]}
        isCollapsed={false}
        answerText="Interferon drives disease."
      />,
    )

    const btn = screen.getByTestId("answer-save-notes")
    expect(btn).not.toBeDisabled()
    await user.click(btn)

    await waitFor(() => expect(reqSpy).toHaveBeenCalledTimes(1))
    const [url, opts] = reqSpy.mock.calls[0] as [string, any]
    expect(url).toBe("/memory/projects/proj-1/knowledge")
    expect(opts.method).toBe("POST")
    const body = JSON.parse(opts.body)
    expect(body.knowledgeType).toBe("notes_synthesis")
    // The note carries the real answer + a real source — not an empty payload.
    expect(body.content).toContain("Interferon drives disease.")
    expect(body.content).toContain("Interferon signalling in disease")
    expect(body.content).toContain("cited for: Fig 3B")
    // Success toast, non-destructive.
    expect(toastSpy).toHaveBeenCalledWith(
      expect.objectContaining({ title: expect.stringMatching(/saved to project notes/i) }),
    )
  })

  it("shows a destructive error toast and never claims success when the POST fails", async () => {
    activeIdRef.current = "proj-1"
    const reqSpy = vi.spyOn(api, "request").mockRejectedValue(new Error("boom"))
    const user = userEvent.setup()
    render(
      <CitationPanel citations={[makeCitation()]} isCollapsed={false} answerText="x" />,
    )

    await user.click(screen.getByTestId("answer-save-notes"))
    await waitFor(() => expect(reqSpy).toHaveBeenCalled())

    // Destructive error toast fired…
    await waitFor(() =>
      expect(toastSpy).toHaveBeenCalledWith(
        expect.objectContaining({ variant: "destructive" }),
      ),
    )
    // …and NO "saved" success toast was shown (no fabricated success).
    expect(toastSpy).not.toHaveBeenCalledWith(
      expect.objectContaining({ title: expect.stringMatching(/saved to project notes/i) }),
    )
    // Button re-enabled after failure (isSavingNote reset in finally).
    expect(screen.getByTestId("answer-save-notes")).not.toBeDisabled()
  })
})
