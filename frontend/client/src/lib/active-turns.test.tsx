/**
 * A chat turn survives the remount caused by the first message of a new chat
 * (App.tsx keys the chat by session id). Live dev 2026-11-12: the composer showed
 * idle — no Stop, no indicator — for a whole 2-minute tool turn.
 */
import React from "react"
import { afterEach, describe, expect, it } from "vitest"
import { act, render, screen } from "@testing-library/react"
import { _resetActiveTurns, abortTurn, endTurn, isTurnActive, setTurnAbort, startTurn, useTurnActive } from "./active-turns"

afterEach(() => _resetActiveTurns())

function Busy({ sessionId }: { sessionId?: string }) {
  return <span data-testid="busy">{useTurnActive(sessionId) ? "busy" : "idle"}</span>
}

describe("active turns", () => {
  it("a component remounted by a key change mid-turn still sees the turn", () => {
    const { rerender } = render(<Busy key="new" sessionId={undefined} />)
    act(() => startTurn("s1")) // send creates the session and starts the turn
    rerender(<Busy key="s1" sessionId="s1" />) // App remounts the chat under the new key
    expect(screen.getByTestId("busy").textContent).toBe("busy")
    act(() => endTurn("s1")) // final arrives (handled by the pre-remount mutation)
    expect(screen.getByTestId("busy").textContent).toBe("idle")
  })

  it("Stop aborts the stream registered before the remount", () => {
    const ctrl = new AbortController()
    startTurn("s2")
    setTurnAbort("s2", ctrl)
    abortTurn("s2")
    expect(ctrl.signal.aborted).toBe(true)
    expect(isTurnActive("s2")).toBe(false)
  })

  it("other sessions are not affected", () => {
    startTurn("a")
    expect(isTurnActive("b")).toBe(false)
    expect(isTurnActive(undefined)).toBe(false)
  })
})
