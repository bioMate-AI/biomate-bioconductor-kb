/**
 * Composer must clear after sending (bug 2026-11-10): /?project=…&attachFile=…&draft=…
 * → send → the draft re-appeared. Reproduces the real lifecycle: the owner (RootRoute)
 * holds the URL draft; the consumer (ChatWithArtifacts) is KEYED by session id and
 * remounts when the first send turns "new" into a real session.
 */
import React, { useState } from "react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { act, render } from "@testing-library/react"
import { readAndStripUrlParam, useApplyInitialDraft, useOneShotUrlParam } from "./one-shot-url-param"

afterEach(() => window.history.replaceState(null, "", "/"))

function Chat({ draft, onConsumed, setter }: { draft?: string; onConsumed: () => void; setter: (d: string) => void }) {
  useApplyInitialDraft(draft, () => setter, "ready", onConsumed)
  return null
}

let remountAsSession: () => void = () => {}
function Root({ setter }: { setter: (d: string) => void }) {
  const [draft, consume] = useOneShotUrlParam("draft")
  const [sessionId, setSessionId] = useState<string | null>(null)
  remountAsSession = () => setSessionId("s-1")
  return <Chat key={sessionId ?? "new"} draft={draft} onConsumed={consume} setter={setter} />
}

describe("one-shot ?draft=", () => {
  it("strips only the draft param and keeps ?project= / ?attachFile=", () => {
    window.history.replaceState(null, "", "/?project=p1&attachFile=f1&draft=QC%20this%20file")
    expect(readAndStripUrlParam("draft")).toBe("QC this file")
    expect(window.location.search).toBe("?project=p1&attachFile=f1")
  })

  it("is applied exactly once — the remount after the first send does NOT put it back", () => {
    window.history.replaceState(null, "", "/?project=p1&attachFile=f1&draft=Run%20full%20QC")
    const setter = vi.fn()
    render(<Root setter={setter} />)
    expect(setter).toHaveBeenCalledTimes(1)
    expect(setter).toHaveBeenCalledWith("Run full QC")
    // User sends → chat becomes a real session → keyed consumer remounts.
    act(() => remountAsSession())
    expect(setter).toHaveBeenCalledTimes(1)
  })

  it("regression guard: without consumption the remount WOULD re-apply (the original bug)", () => {
    const setter = vi.fn()
    function LeakyRoot() {
      const [sessionId, setSessionId] = useState<string | null>(null)
      remountAsSession = () => setSessionId("s-1")
      return <Chat key={sessionId ?? "new"} draft="Run full QC" onConsumed={() => {}} setter={setter} />
    }
    render(<LeakyRoot />)
    act(() => remountAsSession())
    expect(setter).toHaveBeenCalledTimes(2)
  })
})
