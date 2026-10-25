// Run-owned, unfolded progress streams for workflow responses.

import { useLayoutEffect, useRef, type ReactNode } from 'react'
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

/** Explicit persisted identities only; never infer ownership from message IDs/text. */
function ownerIds(m: Message): string[] {
  return [m.invocationId, m.metadata?.runId, m.metadata?.galaxyInvocationId]
    .filter((id): id is string => typeof id === 'string' && id.trim().length > 0)
}

export type WorkflowResponseGroup = ProgressGroup | {
  kind: 'response'; message: Message; progress: Message[]; findings: Message[]; key: string
}

/** Attach updates only to an unambiguous workflow owner, leaving user turns in place. */
export function groupWorkflowResponses(
  messages: Message[],
  knownRun?: { id: string; invocationId?: string },
): WorkflowResponseGroup[] {
  const owners = new Map<string, Message | null>()
  const responses = new Map<string, Extract<WorkflowResponseGroup, { kind: 'response' }>>()
  for (const m of messages) {
    if (m.role !== 'assistant' || m.metadata?.type !== 'workflow' || !m.metadata?.workflow) continue
    const ids = ownerIds(m)
    if (knownRun?.invocationId && ids.includes(knownRun.id)) ids.push(knownRun.invocationId)
    if (!ids.length) continue
    responses.set(m.id, { kind: 'response', message: m, progress: [], findings: [], key: m.id })
    for (const id of new Set(ids)) owners.set(id, owners.has(id) ? null : m)
  }
  const attached = new Set<string>()
  for (const m of messages) {
    const progress = isProgress(m) && FOLDABLE_SPEAKERS_LOCAL.has(speakerOf(m))
    if (!progress && !(m.role === 'assistant' && m.metadata?.type === 'findings')) continue
    const matches = ownerIds(m).map(id => owners.get(id))
    if (matches.includes(null)) continue
    const candidates = matches.filter(Boolean) as Message[]
    const owner = candidates[0]
    if (!owner || candidates.some(candidate => candidate.id !== owner.id)) continue
    const response = responses.get(owner.id)!
    const target = progress ? response.progress : response.findings
    if (!target.some(existing => existing.id === m.id)) target.push(m)
    attached.add(m.id)
  }
  const out: WorkflowResponseGroup[] = []
  let pending: Message[] = []
  const flush = () => { out.push(...groupProgressMessages(pending)); pending = [] }
  for (const m of messages) {
    if (attached.has(m.id)) continue
    const response = responses.get(m.id)
    if (response) { flush(); out.push(response) }
    else pending.push(m)
  }
  flush()
  return out
}

function isProgress(m: Message): boolean {
  if (m.role === 'user') return false
  // Primary signal (live): metadata.type. Durable fallback (reload): the
  // Older records may have lost metadata. Recognize their display type only;
  // never parse these ambiguous IDs to assign them to a workflow.
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
    const owner = ownerIds(m)[0]
    if (owner && isProgress(m) && FOLDABLE_SPEAKERS_LOCAL.has(speakerOf(m))) {
      let j = i
      while (
        j < messages.length &&
        ownerIds(messages[j])[0] === owner &&
        isProgress(messages[j]) &&
        FOLDABLE_SPEAKERS_LOCAL.has(speakerOf(messages[j]))
      ) {
        j++
      }
      const run = messages.slice(i, j)
      out.push({
        kind: 'stream',
        messages: run,
        key: `stream-${run[0].id}`,
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
export function ProgressStreamBox({ messages, inline = false, plan }: { messages: Message[]; inline?: boolean; plan?: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null)
  const contentRef = useRef<HTMLDivElement>(null)
  const followTail = useRef(true)
  useLayoutEffect(() => {
    const el = ref.current
    if (el && followTail.current) el.scrollTop = el.scrollHeight
  }, [messages, plan])
  useLayoutEffect(() => {
    const observer = new ResizeObserver(() => {
      if (ref.current && followTail.current) ref.current.scrollTop = ref.current.scrollHeight
    })
    if (contentRef.current) observer.observe(contentRef.current)
    return () => observer.disconnect()
  }, [])
  const lines = messages.map((m) => ({ id: m.id, text: progressLineText(m) }))
  return (
    <div
      ref={ref}
      role="log"
      aria-label="Workflow updates"
      aria-live="off"
      tabIndex={0}
      onScroll={(event) => {
        const el = event.currentTarget
        followTail.current = el.scrollHeight - el.scrollTop - el.clientHeight <= 24
      }}
      className="chat-progress-stream"
      data-testid="progress-stream"
      data-count={messages.length}
      style={{
        margin: inline ? '4px 0' : '4px 0 4px 40px',
        width: inline ? '100%' : 'auto',
        minWidth: 0,
        overscrollBehavior: 'contain',
        maxHeight: 132,
        overflowY: 'auto',
        padding: '6px 10px',
        borderRadius: 8,
        background: 'var(--bm-surface-2, oklch(0.975 0.003 240))',
        border: '1px solid var(--bm-border, oklch(0.9 0.004 240))',
        fontFamily: 'var(--bm-font-mono, ui-monospace, SFMono-Regular, monospace)',
        fontSize: 11.5,
        lineHeight: 1.65,
        color: 'var(--bm-text-muted, oklch(0.48 0.012 260))',
      }}
    >
      <div ref={contentRef}>
        {plan && <div data-testid="response-plan">{plan}</div>}
      {lines.map((l) => (
        <div key={l.id} style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
          {l.text || '…'}
        </div>
      ))}
      </div>
    </div>
  )
}
