/**
 * Chat context harness — one inspectable assembly point for the chat's "view scope".
 *
 * Today the per-turn context is emergent string concatenation spread across routes.ts (project
 * context, standing instructions, composer instructions, session datasets) and galaxy-assistant.ts
 * (history window, long-term-memory blocks, skills). Nothing reports WHICH channels fired, their
 * sizes, scope, or failure state, so none of it is assertable as a unit
 * (see docs/20261106_CHAT_CONTEXT_HARNESS_SCOPE.md, dimension 9).
 *
 * This module is the testable core: each channel is declared via `add(...)`, and `build(...)`
 * returns both the assembled `prompt` AND a `manifest` describing every channel. It is PURE and
 * side-effect-free — a caller passes already-computed channel contents; the harness decides
 * ordering, wrapping, byte accounting, and the fired/truncated/failure flags. Channels are migrated
 * onto it incrementally (shadow first), so this introduction changes no live behavior.
 */

/** The visibility boundary of a channel — how wide the "universe" it draws from is. */
export type ChannelScope = 'conversation' | 'project' | 'user' | 'request' | 'global';

/** The canonical channels (A1–A11 in the scope doc). Keep in sync with that doc. */
export type ChannelName =
  | 'history'               // A1  prior messages of this chat (windowed)
  | 'history_summary'       // A2  summary of messages dropped beyond the window
  | 'project_context'       // A3  name / description / research goal / background
  | 'standing_instructions' // A4  promoted project_instruction rows
  | 'composer_instructions' // A5  request-scoped instructions + output requirements
  | 'session_datasets'      // A6  attached files / chips
  | 'cross_session'         // A7  recall over past session summaries
  | 'episodes'              // A8  past research episodes (P1)
  | 'corrections'           // A9  user corrections (P2)
  | 'recent_runs'           // A10 recent workflow runs
  | 'skills';               // A11 selected expert packs

/** Canonical assembly order. Durable project/standing context first, then memory, then the
 *  request-scoped and most-recent material closest to the question. A live cutover MUST reproduce
 *  the existing order for the channels it migrates; adjust here deliberately, with a shadow diff. */
export const CANONICAL_ORDER: ChannelName[] = [
  'project_context',
  'standing_instructions',
  'cross_session',
  'episodes',
  'corrections',
  'recent_runs',
  'skills',
  'session_datasets',
  'composer_instructions',
  'history_summary',
  'history',
];

export interface ChannelInput {
  name: ChannelName;
  scope: ChannelScope;
  /** The assembled text for this channel. Empty string = the channel produced nothing this turn. */
  content?: string;
  /** True when content was clipped/dropped to fit a budget (so the model saw a partial view). */
  truncated?: boolean;
  /** True when a lookup MISSED/errored and we are emitting an explicit "found nothing" note rather
   *  than a silent empty — so the model knows a search happened. `content` should hold that note. */
  failureSignalled?: boolean;
  /** Optional wrapper tags, e.g. { open: '<long_term_memory>', close: '</long_term_memory>' }. */
  wrap?: { open: string; close: string };
}

export interface ContextChannel extends Required<Omit<ChannelInput, 'wrap'>> {
  /** The channel contributed to the prompt (had content, or signalled a failure note). */
  fired: boolean;
  /** UTF-8 byte length of the channel's rendered content (0 when not fired). */
  bytes: number;
  wrap: { open: string; close: string } | null;
}

export interface ContextManifest {
  /** Every declared channel, in the order assembled. */
  channels: ContextChannel[];
  /** The channels that fired, concatenated in order (with wraps applied). */
  prompt: string;
  /** Sum of fired channels' byte sizes. */
  totalBytes: number;
}

const byteLen = (s: string): number => Buffer.byteLength(s, 'utf8');

/** Render one channel's text (content + optional wrap). '' when the channel did not fire. */
function renderChannel(c: ContextChannel): string {
  if (!c.fired) return '';
  if (!c.wrap) return c.content;
  return `${c.wrap.open}\n${c.content}\n${c.wrap.close}`;
}

/**
 * Accumulate channels for one chat turn, then `build()` the assembled prompt + manifest.
 * A channel "fired" when it has non-empty content OR it is signalling a failure (an honest
 * "searched, found nothing" note) — both are things the model should see.
 */
export class ChatContextBuilder {
  private inputs = new Map<ChannelName, ChannelInput>();

  /** Declare a channel. A later add() for the same name replaces the earlier one (last write wins),
   *  so a caller can compute a channel in stages without double-counting it. */
  add(input: ChannelInput): this {
    this.inputs.set(input.name, input);
    return this;
  }

  private toChannel(input: ChannelInput): ContextChannel {
    const content = input.content ?? '';
    const failureSignalled = input.failureSignalled ?? false;
    const fired = content.trim().length > 0 || failureSignalled;
    return {
      name: input.name,
      scope: input.scope,
      content,
      truncated: input.truncated ?? false,
      failureSignalled,
      fired,
      bytes: fired ? byteLen(content) : 0,
      wrap: input.wrap ?? null,
    };
  }

  /** Assemble the manifest. `order` defaults to CANONICAL_ORDER; any declared channel not named in
   *  `order` is appended afterwards in insertion order, so nothing is silently dropped. */
  build(order: ChannelName[] = CANONICAL_ORDER): ContextManifest {
    const seen = new Set<ChannelName>();
    const ordered: ContextChannel[] = [];
    for (const name of order) {
      const input = this.inputs.get(name);
      if (input && !seen.has(name)) { ordered.push(this.toChannel(input)); seen.add(name); }
    }
    for (const [name, input] of this.inputs) {
      if (!seen.has(name)) { ordered.push(this.toChannel(input)); seen.add(name); }
    }
    const prompt = ordered.map(renderChannel).filter(Boolean).join('\n\n');
    const totalBytes = ordered.reduce((n, c) => n + c.bytes, 0);
    return { channels: ordered, prompt, totalBytes };
  }
}

/** One-line-per-fired-channel summary for a shadow log, e.g.
 *  `[ctx] project_context(project,312B) standing_instructions(project,480B,trunc) history(conversation,9KB)`.
 *  Channels that signalled a failure are marked `miss`. */
export function manifestSummary(m: ContextManifest): string {
  const human = (n: number) => (n >= 1024 ? `${(n / 1024).toFixed(1)}KB` : `${n}B`);
  const parts = m.channels
    .filter((c) => c.fired)
    .map((c) => {
      const flags = [c.truncated ? 'trunc' : '', c.failureSignalled ? 'miss' : ''].filter(Boolean);
      return `${c.name}(${[c.scope, human(c.bytes), ...flags].join(',')})`;
    });
  return `[ctx] ${parts.join(' ')} total=${human(m.totalBytes)}`;
}
