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

import { useState } from 'react'
import type { Message } from '@shared/schema'

// Local copies of speaker helpers — kept in sync with chat-message.tsx but
// duplicated here so this module (and its unit test) does not transitively
// import the full ChatMessage component graph (3Dmol, markdown, etc).
const SPEAKER_LABELS_LOCAL: Record<string, string> = {
  plan: 'PLAN', wf: 'WF', qc: 'QC', loop: 'LOOP', agent: 'AGENT', find: 'FIND',
}
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
  | { kind: 'folded'; speaker: string; hidden: Message[]; latest: Message; key: string }

function isProgress(m: Message): boolean {
  return m.role !== 'user' && (m as any).metadata?.type === 'workflow_progress'
}

function speakerOf(m: Message): string {
  return deriveSpeakerLocal(((m as any).metadata?.kind) as string | undefined)
}

/**
 * Walks a flat message list and emits a render list where consecutive
 * foldable-speaker progress messages of the same speaker are collapsed.
 *
 * @param messages   ordered list of chat messages
 * @param threshold  a run collapses when its length is STRICTLY GREATER than
 *                   this (so threshold=2 collapses runs of 3+, matching
 *                   ChatStream.jsx). Set to 0 to disable folding.
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
    if (isProgress(m)) {
      const sp = speakerOf(m)
      if (FOLDABLE_SPEAKERS_LOCAL.has(sp)) {
        let j = i
        while (
          j < messages.length &&
          isProgress(messages[j]) &&
          speakerOf(messages[j]) === sp
        ) {
          j++
        }
        const run = messages.slice(i, j)
        if (run.length > threshold) {
          const hidden = run.slice(0, run.length - 1)
          const latest = run[run.length - 1]
          out.push({
            kind: 'folded',
            speaker: sp,
            hidden,
            latest,
            key: `fold-${hidden[0].id}-${latest.id}`,
          })
        } else {
          for (const r of run) out.push({ kind: 'single', message: r, key: r.id })
        }
        i = j
        continue
      }
    }
    out.push({ kind: 'single', message: m, key: m.id })
    i++
  }
  return out
}

/**
 * Caret-able summary line: "WF — 5 earlier updates · click to show".
 * Hidden messages are rendered (expanded) on click; they remain in the DOM
 * either way (display:none when collapsed) so search/Ctrl-F still finds them.
 */
export function FoldedProgressGroup({
  speaker,
  hidden,
  renderMessage,
}: {
  speaker: string
  hidden: Message[]
  renderMessage: (m: Message) => React.ReactNode
}) {
  const [open, setOpen] = useState(false)
  const label = SPEAKER_LABELS_LOCAL[speaker] ?? 'WF'
  const n = hidden.length
  return (
    <div
      className="chat-progress-fold"
      data-testid={`progress-fold-${speaker}`}
      data-speaker={speaker}
      data-count={n}
      data-open={open ? 'true' : 'false'}
    >
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        className="chat-progress-fold__caret"
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 6,
          padding: '2px 8px',
          fontSize: 12,
          color: 'var(--bm-text-dim, oklch(0.62 0.010 260))',
          background: 'transparent',
          border: 'none',
          cursor: 'pointer',
          fontFamily: 'var(--bm-font-ui)',
          opacity: 0.85,
        }}
      >
        <span aria-hidden style={{ transform: open ? 'rotate(90deg)' : 'none', transition: 'transform .15s' }}>▶</span>
        <span className="speaker-pill" data-speaker={speaker}>{label}</span>
        <span>— {n} earlier update{n === 1 ? '' : 's'} · click to {open ? 'hide' : 'show'}</span>
      </button>
      <div
        className="chat-progress-fold__hidden"
        style={open ? undefined : { display: 'none' }}
        aria-hidden={!open}
      >
        {hidden.map((m) => (
          <div key={m.id}>{renderMessage(m)}</div>
        ))}
      </div>
    </div>
  )
}
