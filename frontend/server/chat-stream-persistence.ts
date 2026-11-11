/**
 * Ordering rules for the server-side copy of a streamed assistant turn
 * (POST /api/chat/stream → chat_sessions, UPSERT by message_id).
 *
 * The stream keeps generating after the client disconnects (the LLM / workflow
 * pipeline does not observe the disconnect), so a turn can end in two writes:
 *   - partial: on socket close or error — the text streamed so far;
 *   - final:   on successful completion — the full text plus the `final` SSE
 *              payload that carries the workflow card.
 *
 * Bug this closes (docs/20261110_COLDSTART_EXAMPLES_LIVE_AUDIT.md §4.1): one
 * shared `persisted` flag let the disconnect-time partial write block the final
 * write, so a workflow generated after the tab closed was never stored — the
 * session came back as summary text with no card, forever. Rules now:
 *   1. a partial write never blocks the final write;
 *   2. the final write waits for an in-flight partial write, so it lands last;
 *   3. once the final write has started, later partial writes are dropped;
 *   4. at most one final write.
 */
export interface AssistantPersistWrite {
  partial: boolean
  content: string
  /** Thin workflow summary from `workflow_ready` (kept for existing readers). */
  workflowMetadata: any
  /** The `final` SSE payload; the client rebuilds the card from it on reload. */
  finalPayload: any
}

export interface AssistantPersister {
  persist(opts: { partial: boolean }): Promise<void>
}

export function createAssistantPersister(deps: {
  snapshot: () => { content: string; workflowMetadata: any; finalPayload: any }
  /** Performs the UPSERT; resolves true on success. Must not throw. */
  write: (w: AssistantPersistWrite) => Promise<boolean>
}): AssistantPersister {
  let finalStarted = false
  let partialWritten = false
  let inFlight: Promise<unknown> = Promise.resolve()

  return {
    async persist({ partial }) {
      if (partial) {
        if (finalStarted || partialWritten) return
        const snap = deps.snapshot()
        if (!snap.content) return
        partialWritten = true
        const p = deps.write({ partial: true, content: snap.content, workflowMetadata: snap.workflowMetadata, finalPayload: null })
        inFlight = p
        await p
        return
      }
      if (finalStarted) return
      finalStarted = true
      await inFlight.catch(() => undefined)
      const snap = deps.snapshot()
      if (!snap.content) return
      await deps.write({ partial: false, content: snap.content, workflowMetadata: snap.workflowMetadata, finalPayload: snap.finalPayload })
    },
  }
}
