/**
 * Context-aware injection gate for the <session_datasets> prompt block.
 *
 * Design: docs/20260613_DATASET_INJECTION_GATE_DESIGN.md.
 *
 * Today we always inject the block whenever any datasets are attached.
 * That wastes tokens on pure knowledge turns and risks anchoring the
 * LLM on irrelevant data. A naive intent-only gate fails because the
 * same intent label (e.g. `research_question`) is sometimes about the
 * user's data and sometimes about an abstract concept — relevance
 * depends on conversation state.
 *
 * This module returns INJECT when there is a non-trivial chance the
 * LLM's answer will reference the user's data or run. It's
 * default-ON: skip only when every positive signal is silent AND the
 * intent is a pure abstract-knowledge category. False-skips are
 * worse than false-injects (the LLM may ask the user to re-attach a
 * file they already have).
 */

export interface ChatTurn {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

export interface DatasetRef {
  id?: string;
  name?: string;
  type?: string;
  [k: string]: any;
}

export interface RunState {
  /** True when a workflow is currently running for this chat. */
  active?: boolean;
  /** Last terminal status: 'completed' | 'failed' | undefined. */
  lastStatus?: string;
  /** Epoch ms of the last terminal transition. */
  lastTerminalAt?: number;
}

export interface GateInput {
  message: string;
  intentType?: string | null;
  datasets: DatasetRef[];
  history?: ChatTurn[];
  runState?: RunState;
  /** Optional override for "now" so tests are deterministic. */
  nowMs?: number;
}

export interface GateDecision {
  inject: boolean;
  /** Which signal(s) drove the decision — for audit logging. */
  reason: string;
}

/* ─────────────────────────  Constants  ────────────────────────── */

/** Intents where data context is usually load-bearing. */
const INTENT_SUGGESTS_DATA = new Set([
  'workflow_generation',
  'data_interpretation',
  'parameter_optimization',
  'experiment_design',
  'methods_writing',
]);

/**
 * Pure abstract-knowledge intents — when ALL other signals are silent,
 * these cause SKIP. They never override a positive signal.
 */
const PURE_ABSTRACT_INTENTS = new Set([
  'research_question',
  'comparative_methodology',
  'regulatory_compliance',
]);

const RECENT_RUN_WINDOW_MS = 60_000;
const SHORT_FOLLOWUP_MAX_WORDS = 6;
const HISTORY_DISCUSSION_WINDOW = 3; // turns

/**
 * Word-boundary'd reference terms. "the dataset", "my data", etc.
 * Avoid bare substrings to keep false positives down.
 */
const DATA_PHRASE_RE = new RegExp(
  [
    String.raw`\bthe\s+(?:dataset|file|matrix|metadata|counts?|samples?|reads?|inputs?|outputs?|results?)\b`,
    String.raw`\bmy\s+(?:dataset|file|data|matrix|counts?|samples?)\b`,
    String.raw`\bfile\s+I\s+(?:up)?loaded\b`,
    String.raw`\battached\s+(?:dataset|file|data|csv|tsv)\b`,
    String.raw`\bgalaxy\s+dataset\b`,
    String.raw`\buploaded\s+(?:dataset|file)\b`,
  ].join('|'),
  'i',
);

/** UUID-like or hex-blob id reference (Galaxy dataset ids). */
const DATASET_ID_RE = /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b|\b[0-9a-f]{16,}\b/i;

/* ────────────────────────  Signals (pure)  ───────────────────────── */

/**
 * Does the message explicitly reference attached data? Looks at:
 *   1) Generic data-phrase regex
 *   2) Filename substring match against any attached dataset name
 *   3) Direct id match against any attached dataset id
 */
export function messageReferencesData(message: string, datasets: DatasetRef[]): boolean {
  if (!message) return false;
  if (DATA_PHRASE_RE.test(message)) return true;
  if (DATASET_ID_RE.test(message)) return true;
  for (const d of datasets) {
    if (d?.name && d.name.length > 3) {
      // Match the dataset name as a word-ish token (allow dots and underscores)
      const escaped = d.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const re = new RegExp(`(?:^|[^A-Za-z0-9])${escaped}(?:[^A-Za-z0-9]|$)`, 'i');
      if (re.test(message)) return true;
    }
    if (d?.id && d.id.length >= 8 && message.includes(d.id)) return true;
  }
  return false;
}

/**
 * Is a workflow active right now, OR just finished within the recent
 * window? Either way the conversation is likely centered on the run.
 */
export function runStateRelevant(runState: RunState | undefined, nowMs?: number): boolean {
  if (!runState) return false;
  if (runState.active === true) return true;
  if (typeof runState.lastTerminalAt === 'number') {
    const now = typeof nowMs === 'number' ? nowMs : Date.now();
    if (now - runState.lastTerminalAt <= RECENT_RUN_WINDOW_MS) return true;
  }
  return false;
}

/**
 * Did the most-recent assistant turn reference any of the attached
 * datasets (by id, by filename, or by emitting <session_datasets>)?
 */
export function lastAssistantTurnReferencedData(
  history: ChatTurn[] | undefined,
  datasets: DatasetRef[],
): boolean {
  if (!history?.length) return false;
  const lastAssistant = [...history].reverse().find(m => m.role === 'assistant');
  if (!lastAssistant?.content) return false;
  if (lastAssistant.content.includes('<session_datasets>')) return true;
  return messageReferencesData(lastAssistant.content, datasets);
}

/**
 * Is the user message a short follow-up to a data-thread?
 *   - Message is ≤ N words ("yes", "do that", "what about hERG too")
 *   - AND the last assistant turn referenced data
 *
 * Catches "really?" / "and the next step?" continuations where the
 * data context is implicit.
 */
export function isShortFollowupAfterDataThread(
  message: string,
  history: ChatTurn[] | undefined,
  datasets: DatasetRef[],
): boolean {
  if (!message) return false;
  const words = message.trim().split(/\s+/).filter(Boolean);
  if (words.length === 0 || words.length > SHORT_FOLLOWUP_MAX_WORDS) return false;
  return lastAssistantTurnReferencedData(history, datasets);
}

/**
 * Have any of the last N turns talked about data — either user
 * referencing it or assistant emitting a reference?
 */
export function historyShowsAnyDataDiscussion(
  history: ChatTurn[] | undefined,
  datasets: DatasetRef[],
): boolean {
  if (!history?.length) return false;
  const recent = history.slice(-HISTORY_DISCUSSION_WINDOW);
  for (const turn of recent) {
    if (!turn?.content) continue;
    if (turn.role === 'user' && messageReferencesData(turn.content, datasets)) return true;
    if (turn.role === 'assistant') {
      if (turn.content.includes('<session_datasets>')) return true;
      if (messageReferencesData(turn.content, datasets)) return true;
    }
  }
  return false;
}

export function intentSuggestsData(intentType?: string | null): boolean {
  return !!intentType && INTENT_SUGGESTS_DATA.has(intentType);
}

export function pureAbstractKnowledgeIntent(intentType?: string | null): boolean {
  return !!intentType && PURE_ABSTRACT_INTENTS.has(intentType);
}

/* ───────────────────────  Composition  ───────────────────────── */

export function shouldInjectDatasets(input: GateInput): GateDecision {
  const { message, intentType, datasets, history, runState, nowMs } = input;

  if (!datasets?.length) {
    return { inject: false, reason: 'no_datasets_attached' };
  }

  if (messageReferencesData(message, datasets)) {
    return { inject: true, reason: 'message_references_data' };
  }

  if (runStateRelevant(runState, nowMs)) {
    return { inject: true, reason: 'run_state_relevant' };
  }

  if (isShortFollowupAfterDataThread(message, history, datasets)) {
    return { inject: true, reason: 'short_followup_after_data_thread' };
  }

  if (lastAssistantTurnReferencedData(history, datasets)) {
    return { inject: true, reason: 'last_assistant_referenced_data' };
  }

  if (intentSuggestsData(intentType) && historyShowsAnyDataDiscussion(history, datasets)) {
    return { inject: true, reason: 'data_intent_with_history_discussion' };
  }

  if (pureAbstractKnowledgeIntent(intentType)) {
    return { inject: false, reason: 'pure_abstract_intent_no_signals' };
  }

  // Default-ON: when in doubt, inject. False-skip cost > false-inject cost.
  return { inject: true, reason: 'default_on_no_negative_signals' };
}
