/**
 * Chat turn state — when is an assistant turn still in progress?
 *
 * A workflow turn on POST /api/chat/stream streams the complete summary text
 * ("**Workflow** — … / Input / Key steps / Expected output") early, then keeps
 * the stream open while the server grounds the workflow parameters, and only
 * then sends `workflow_ready` + `final` carrying the card. Measured on dev
 * (2026-11-11): text at ~10 s, card at ~72 s.
 *
 * The UI used to infer "done" from "the reply has text": the typing cue, the
 * Stop button and the soft-queue all switched off as soon as content arrived.
 * For that whole ~60 s window the turn LOOKED finished while the card was
 * still on its way, so anyone who left, reloaded or switched chats lost the
 * card (docs/20261110_COLDSTART_EXAMPLES_LIVE_AUDIT.md §4.1).
 *
 * Rules here:
 *   - `turnBusy` follows the stream lifecycle, never the reply text.
 *   - The progress line inside the placeholder is visible only while the
 *     placeholder has no text (chat-message.tsx), so it suppresses the typing
 *     indicator only then; once text exists the indicator is the sole cue.
 *   - `progress: matched` is the server's signal that a workflow was matched
 *     and a card is coming, so the indicator shows the workflow phase after the
 *     text has streamed.
 */
export type TurnPhase = "thinking" | "workflow"

export interface TurnIndicatorInput {
  /** The stream for the current turn is open (parent isTyping or local). */
  streamOpen: boolean
  /** Short post-success "generating the workflow" cue. */
  showWorkflowCue: boolean
  phase: TurnPhase
  lastMessage?: { role?: string; content?: string; metadata?: any } | null
}

export interface TurnIndicators {
  /** Show the typing indicator below the messages. */
  displayTyping: boolean
  /** The turn is not finished: composer shows Stop, new text is queued. */
  turnBusy: boolean
}

export function computeTurnIndicators(input: TurnIndicatorInput): TurnIndicators {
  const { streamOpen, showWorkflowCue, phase, lastMessage } = input
  const lastIsAssistant = lastMessage?.role === "assistant"
  const hasText = !!lastMessage?.content?.trim()
  const streamingHasContent = streamOpen && lastIsAssistant && hasText
  const progressLineVisible = streamOpen && lastIsAssistant && !hasText && !!lastMessage?.metadata?.progressStatus
  // An agent turn that already ran tools goes silent while the model writes its next step
  // (tens of seconds, no text streaming) — keep the indicator so it never looks finished
  // (live dev 2026-11-12: 13–27 s gaps with only the opening sentence on screen).
  const agentTurnInProgress = streamOpen && lastIsAssistant && (lastMessage?.metadata?.toolBlocks?.length ?? 0) > 0
  const displayTyping =
    showWorkflowCue || (streamOpen && (!streamingHasContent || phase === "workflow" || agentTurnInProgress) && !progressLineVisible)
  return { displayTyping, turnBusy: streamOpen || showWorkflowCue }
}

/** SSE `progress` payload that means a workflow card is on its way. */
export function signalsPendingWorkflow(eventName: string, payload: any): boolean {
  return eventName === "progress" && payload?.stage === "matched"
}
