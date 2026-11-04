// Decision helper for the workflow re-run → chat-card behavior.
//
// When a user clicks "Run again"/"Restart" on a FINISHED run in the workflow
// panel, the fresh run must get its OWN chat card instead of overwriting the
// finished run's card — otherwise the finished run loses its only in-chat
// placeholder (its outputs/findings become unreachable from the thread). This
// pure function decides whether to append a new card.
//
// It must NOT fire for:
//  - a first run (no previous terminal run shown), or
//  - launching a *different* workflow's first run while an unrelated finished
//    run happens to still be on-screen (owner card doesn't point at that run), or
//  - a programmatic run with an explicit sourceMessageId (that path owns its card).

const TERMINAL_STATUSES = ['completed', 'ok', 'succeeded', 'failed', 'cancelled', 'error'];

export function isTerminalStatus(status: string | null | undefined): boolean {
  return TERMINAL_STATUSES.includes(String(status || '').toLowerCase());
}

export interface RerunCardArgs {
  /** Explicit owner set by a programmatic caller — when present, never append. */
  sourceMessageId?: string | null;
  /** The message currently bound to the right panel. */
  panelWorkflowMessageId?: string | null;
  /** Run id shown in the panel at click time (before the fresh run starts). */
  prevPanelRunId: string | null;
  /** Execution status of that panel run at click time. */
  prevPanelStatus: string | null | undefined;
  /** The owner card's current run id (metadata.runId || invocationId). */
  ownerRunId: string | null | undefined;
  /** The id of the freshly started run. */
  newRunId: string;
}

/**
 * True ⟺ this is a re-run of the finished run that the owner card points at,
 * and the fresh run is a distinct run → append a new card, preserve the old one.
 */
export function shouldAppendRerunCard(args: RerunCardArgs): boolean {
  if (args.sourceMessageId) return false;
  if (!args.panelWorkflowMessageId) return false;
  if (!args.prevPanelRunId) return false;
  if (!isTerminalStatus(args.prevPanelStatus)) return false;
  if (args.newRunId === args.prevPanelRunId) return false; // same run (e.g. resume), not a new card
  // The owner card must actually represent the run we were viewing.
  return args.ownerRunId === args.prevPanelRunId;
}
