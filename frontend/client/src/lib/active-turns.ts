/**
 * Which chat sessions have a turn in progress — kept OUTSIDE the chat component.
 *
 * The chat (ChatWithArtifacts) is keyed by session id in App.tsx, so the first
 * message of a new chat creates the session and REMOUNTS the component mid-turn.
 * Component state (isTypingLocal, the abort controller ref) was lost: the old
 * instance kept streaming into chat history, but the new one showed an idle
 * composer (no Stop button, no "working" indicator) for the whole turn and Stop
 * could not cancel it (live dev 2026-11-12: a 2-minute image-QC turn showed only
 * its opening sentence, looking finished, while tools were still running).
 */
import { useSyncExternalStore } from "react"

type Turn = { abort: AbortController | null }

const turns = new Map<string, Turn>()
const listeners = new Set<() => void>()
const emit = () => listeners.forEach((l) => l())

export function startTurn(sessionId: string | undefined | null): void {
  if (!sessionId) return
  turns.set(sessionId, { abort: turns.get(sessionId)?.abort ?? null })
  emit()
}

/** The current stream attempt's controller, so Stop works after a remount. */
export function setTurnAbort(sessionId: string | undefined | null, abort: AbortController | null): void {
  if (!sessionId || !turns.has(sessionId)) return
  turns.get(sessionId)!.abort = abort
}

export function endTurn(sessionId: string | undefined | null): void {
  if (!sessionId || !turns.delete(sessionId)) return
  emit()
}

/** Stop: abort the in-flight stream (if any) and end the turn. */
export function abortTurn(sessionId: string | undefined | null): void {
  if (!sessionId) return
  try { turns.get(sessionId)?.abort?.abort() } catch { /* noop */ }
  endTurn(sessionId)
}

export function isTurnActive(sessionId: string | undefined | null): boolean {
  return !!sessionId && turns.has(sessionId)
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => { listeners.delete(listener) }
}

export function useTurnActive(sessionId: string | undefined | null): boolean {
  return useSyncExternalStore(subscribe, () => isTurnActive(sessionId), () => false)
}

/** Test helper. */
export function _resetActiveTurns(): void {
  turns.clear()
  emit()
}
