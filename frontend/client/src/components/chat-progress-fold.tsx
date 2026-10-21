// Same-speaker progress fold for chat-interface.
//
// Ports the collapse logic from reference/claude_design/bioconductor-handoff/
// src/ChatStream.jsx (CollapsedSpeakerBlock + ChatStream.display memo) into
// the live BioMate chat.
//
// A "run" is a maximal sequence of consecutive workflow_progress messages
// whose derived speaker is identical AND is in FOLDABLE_SPEAKERS. Runs longer
// than `threshold` collapse into a single caret-able summary; the last
// message in the run stays visible as the "latest" line so the user always
// sees the most recent status update.
//
// `agent` (reasoning) and `find` (findings) speakers never fold — they carry
// load-bearing content the user must not have to click to see.

import { useEffect, useRef } from 'react'
import type { Message } from '@shared/schema'

// Local copies of speaker helpers — kept in sync with chat-message.tsx but
// duplicated here so this module (and its unit test) does not transitively
// import the full ChatMessage component graph (3Dmol, markdown, etc).
const FOLDABLE_SPEAKERS_LOCAL = new Set(['wf', 'qc', 'loop', 'plan'])
function deriveSpeakerLocal(kind: string | undefined): string {
  if (!kind) return 'wf'
  if (kind.startsWith('workflow.qc_')) return 'qc'
  if (kind.startsWith('workflow.autoloop')) return 'loop'
  if (kind.startsWith('workflow.')) return 'wf'
  if (kind.startsWith('deepagent.')) return 'agent'
  if (kind.startsWith('plan.')) return 'plan'
  if (kind.startsWith('findings.')) return 'find'
  return 'wf'
}

export type ProgressGroup =
  | { kind: 'single'; message: Message; key: string }
  | { kind: 'stream'; messages: Message[]; key: string }

function isProgress(m: Message): boolean {
  if (m.role === 'user') return false
  // Primary signal (live): metadata.type. Durable fallback (reload): the
  // `progress-<inv>-<kind>-<ts>` id created by handleWorkflowProgress survives
  // persistence even though metadata is stripped on save — so a reloaded
  // session's progress lines still fold instead of rendering as full messages.
  return (m as any).metadata?.type === 'workflow_progress'
    || (typeof m.id === 'string' && m.id.startsWith('progress-'))
}

function speakerOf(m: Message): string {
  return deriveSpeakerLocal(((m as any).metadata?.kind) as string | undefined)
}

/**
 * Walks a flat message list and collapses each maximal run of consecutive
 * foldable progress messages (wf / qc / loop / plan — across speakers) into a
 * single `stream` group. The stream renders as one compact, auto-scrolling
 * progress box (ProgressStreamBox) — no per-speaker pills, no fold caret.
 *
 * `agent` (reasoning) and `find` (findings) speakers never collapse — they
 * carry load-bearing content and render as full messages. Non-progress
 * messages (user, workflow cards, text) also render as singles.
 *
 * @param messages   ordered list of chat messages
 * @param threshold  >0 enables streaming (every foldable-progress run boxes);
 *                   0 disables entirely (every message is a single).
 */
export function groupProgressMessages(
  messages: Message[],
  threshold = 2,
): ProgressGroup[] {
  const out: ProgressGroup[] = []
  if (threshold <= 0) {
    for (const m of messages) out.push({ kind: 'single', message: m, key: m.id })
    return out
  }
  let i = 0
  while (i < messages.length) {
    const m = messages[i]
    if (isProgress(m) && FOLDABLE_SPEAKERS_LOCAL.has(speakerOf(m))) {
      let j = i
      while (
        j < messages.length &&
        isProgress(messages[j]) &&
        FOLDABLE_SPEAKERS_LOCAL.has(speakerOf(messages[j]))
      ) {
        j++
      }
      const run = messages.slice(i, j)
      out.push({
        kind: 'stream',
        messages: run,
        key: `stream-${run[0].id}-${run[run.length - 1].id}`,
      })
      i = j
      continue
    }
    out.push({ kind: 'single', message: m, key: m.id })
    i++
  }
  return out
}

/** One progress line's visible text — the message content, stripped. */
function progressLineText(m: Message): string {
  const c = (m as any).content
  const text = typeof c === 'string' ? c : (c == null ? '' : String(c))
  return text.trim()
}

/**
 * Compact, auto-scrolling progress box — streams every progress line in a
 * fixed-height scrollable pane (like Claude's streaming output), newest at the
 * bottom. No per-speaker pills (WF/QC) and no fold caret: it's a single quiet
 * activity log that always shows the latest update and lets the user scroll
 * back through earlier ones.
 */
export function ProgressStreamBox({ messages }: { messages: Message[] }) {
  const ref = useRef<HTMLDivElement>(null)
  // Auto-scroll to the newest line as the stream grows.
  useEffect(() => {
    const el = ref.current
    if (el) el.scrollTop = el.scrollHeight
  }, [messages.length])
  const lines = messages.map((m) => ({ id: m.id, text: progressLineText(m) }))
  return (
    <div
      ref={ref}
      className="chat-progress-stream"
      data-testid="progress-stream"
      data-count={messages.length}
      style={{
        margin: '4px 0 4px 40px',
        maxHeight: 132,
        overflowY: 'auto',
        padding: '6px 10px',
        borderRadius: 8,
        background: 'var(--bm-surface-2, oklch(0.975 0.003 240))',
        border: '1px solid var(--bm-border, oklch(0.9 0.004 240))',
        fontFamily: 'var(--bm-font-mono, ui-monospace, SFMono-Regular, monospace)',
        fontSize: 11.5,
        lineHeight: 1.65,
        color: 'var(--bm-text-dim, oklch(0.58 0.012 260))',
      }}
    >
      {lines.map((l) => (
        <div key={l.id} style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
          {l.text || '…'}
        </div>
      ))}
    </div>
  )
}
