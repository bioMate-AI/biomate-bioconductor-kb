/**
 * Token-budget-aware chat-history selector.
 *
 * Why this exists
 * ---------------
 * The wjunlin@HKU fix (docs/20260610_REAL_USER_FULL_CHAT_LOGS.md)
 * surfaced a real bug — the client sliced previousMessages to the last 4
 * turns, which dropped early `[Galaxy dataset: ...]` attachment lines,
 * so the LLM lost track of files the user had attached two turns ago.
 *
 * The naive fix (just bump the slice + always include earlier dataset
 * messages) creates an equally real problem: BioMate assistant replies
 * are long (5-15 KB each); 20 of them is ~50K tokens, eating a quarter
 * of Claude's 200K context on history alone. See docs/20260610_CHAT_CONTEXT_AUDIT_4_QUESTIONS.md, question #3.
 *
 * This module is the principled middle ground:
 *   (a) Dataset-attachment messages are retained verbatim — belt-and-
 *       suspenders defense. The CANONICAL path for the LLM to know which
 *       datasets are attached is the <session_datasets> block injected
 *       directly into the system prompt every turn (see
 *       galaxy-assistant.ts:sessionDatasetsBlock). Preserving the inline
 *       blocks here is a fallback for any code path that hasn't been
 *       migrated yet.
 *   (b) Recency comes next — most recent messages added until the byte
 *       budget is nearly exhausted.
 *   (c) Long assistant messages are head-truncated to keep intent without
 *       paying for the entire markdown reply.
 *
 * The cap is a byte cap (cheap to compute), tuned so the assembled
 * payload stays under ~4K tokens (= ~16 KB at the standard 4 chars/token
 * heuristic). Aggressive on purpose — chat-stream still has system
 * prompt + tools + new reply to fit.
 */

export interface ChatMessage {
  role: "user" | "assistant" | "system";
  content: string;
}

export interface SelectorOptions {
  /** Max total bytes of selected message content. Default: 16 KB. */
  byteBudget?: number;
  /** Max chars per individual message after truncation. Default: 1200. */
  perMessageMaxChars?: number;
  /** Always retain at least the last N messages (subject to per-message truncation). Default: 6. */
  guaranteedRecent?: number;
}

const DEFAULT_BYTE_BUDGET = 16 * 1024;
const DEFAULT_PER_MESSAGE_MAX = 1200;
const DEFAULT_GUARANTEED_RECENT = 6;

/** Regex matching the load-bearing dataset/attachment blocks. */
export const DATASET_BLOCK_RE = /\[(?:BioMate dataset|Galaxy dataset|Uploaded datasets?|Attached files?)\s*:/i;

function clipMessage(content: string, maxChars: number): string {
  if (!content || content.length <= maxChars) return content;
  // Preserve any dataset block that might live mid-content by keeping
  // the head + a marker + a small tail (where confirmations / next-asks
  // typically appear). If dataset blocks are present, keep them.
  const head = content.slice(0, Math.floor(maxChars * 0.75));
  const tail = content.slice(-Math.floor(maxChars * 0.15));
  return `${head}\n\n[…truncated for context budget…]\n\n${tail}`;
}

/**
 * Select chat history under a byte budget.
 *
 * Priorities (highest first):
 *   1) Every message that contains a dataset/attachment block — verbatim.
 *   2) The last `guaranteedRecent` messages — possibly truncated.
 *   3) Older messages walking back from the recency window, until budget.
 */
export function selectChatHistoryUnderBudget(
  messages: ChatMessage[],
  opts: SelectorOptions = {}
): ChatMessage[] {
  const byteBudget = opts.byteBudget ?? DEFAULT_BYTE_BUDGET;
  const perMessageMax = opts.perMessageMaxChars ?? DEFAULT_PER_MESSAGE_MAX;
  const guaranteed = opts.guaranteedRecent ?? DEFAULT_GUARANTEED_RECENT;

  if (!Array.isArray(messages) || messages.length === 0) return [];

  // Stable identity: preserve original order on output.
  const order = new Map<ChatMessage, number>();
  messages.forEach((m, i) => order.set(m, i));

  const selected = new Set<ChatMessage>();
  const finalContent = new Map<ChatMessage, string>();
  let usedBytes = 0;

  const tryAdd = (m: ChatMessage, content: string): boolean => {
    if (selected.has(m)) return false;
    const bytes = Buffer.byteLength(content, "utf8");
    if (usedBytes + bytes > byteBudget) return false;
    selected.add(m);
    finalContent.set(m, content);
    usedBytes += bytes;
    return true;
  };

  // --- Priority 1: dataset-attachment messages (verbatim, NEVER truncated) ---
  for (const m of messages) {
    if (m.content && DATASET_BLOCK_RE.test(m.content)) {
      // If a dataset block is larger than the entire budget (extremely
      // unusual), accept it anyway — losing the UUID is worse than
      // overshooting the cap by a few KB.
      const bytes = Buffer.byteLength(m.content, "utf8");
      if (usedBytes + bytes <= byteBudget) {
        tryAdd(m, m.content);
      } else if (selected.size === 0) {
        // Empty budget — take the most recent dataset message and stop.
        selected.add(m);
        finalContent.set(m, m.content);
        usedBytes += bytes;
      }
    }
  }

  // --- Priority 2: last `guaranteed` messages (truncated as needed) ---
  const recentSlice = messages.slice(-guaranteed);
  for (const m of recentSlice) {
    if (selected.has(m)) continue;
    const clipped = clipMessage(m.content, perMessageMax);
    tryAdd(m, clipped);
  }

  // --- Priority 3: walk older messages backward toward priority 1 ---
  const olderReversed = messages.slice(0, Math.max(0, messages.length - guaranteed)).reverse();
  for (const m of olderReversed) {
    if (selected.has(m)) continue;
    const clipped = clipMessage(m.content, perMessageMax);
    if (!tryAdd(m, clipped)) break; // budget exhausted
  }

  // Output in original order
  const result = Array.from(selected)
    .sort((a, b) => (order.get(a) ?? 0) - (order.get(b) ?? 0))
    .map(m => ({ role: m.role, content: finalContent.get(m) ?? m.content }));

  return result;
}
