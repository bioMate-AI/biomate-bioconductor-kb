import { describe, expect, it } from 'vitest'
import { groupProgressMessages } from './chat-progress-fold'
import type { Message } from '@shared/schema'

let counter = 0
function progress(kind: string, content = 'tick'): Message {
  counter += 1
  return {
    id: `p${counter}`,
    role: 'assistant',
    content,
    metadata: { type: 'workflow_progress', kind },
  } as unknown as Message
}

function userMsg(content = 'hi'): Message {
  counter += 1
  return {
    id: `u${counter}`,
    role: 'user',
    content,
    metadata: {},
  } as unknown as Message
}

describe('groupProgressMessages', () => {
  it('folds the canonical 8-wf / 1-agent / 5-wf fixture', () => {
    counter = 0
    const messages: Message[] = [
      ...Array.from({ length: 8 }, () => progress('workflow.step_started')),
      progress('deepagent.thought', 'reasoning…'),
      ...Array.from({ length: 5 }, () => progress('workflow.step_completed')),
    ]
    const groups = groupProgressMessages(messages, 2)
    // Expected: 1 folded wf group (7 hidden + 1 latest) + 1 agent single +
    // 1 folded wf group (4 hidden + 1 latest) = 3 emitted entries.
    expect(groups).toHaveLength(3)
    expect(groups[0].kind).toBe('folded')
    if (groups[0].kind === 'folded') {
      expect(groups[0].speaker).toBe('wf')
      expect(groups[0].hidden).toHaveLength(7)
      expect(groups[0].latest.id).toBe('p8')
    }
    expect(groups[1].kind).toBe('single')
    if (groups[1].kind === 'single') {
      expect(groups[1].message.id).toBe('p9')
    }
    expect(groups[2].kind).toBe('folded')
    if (groups[2].kind === 'folded') {
      expect(groups[2].speaker).toBe('wf')
      expect(groups[2].hidden).toHaveLength(4)
      expect(groups[2].latest.id).toBe('p14')
    }
  })

  it('does not fold runs of length ≤ threshold', () => {
    counter = 0
    const messages: Message[] = [
      progress('workflow.x'),
      progress('workflow.x'),
    ]
    const groups = groupProgressMessages(messages, 2)
    expect(groups).toHaveLength(2)
    expect(groups.every(g => g.kind === 'single')).toBe(true)
  })

  it('never folds agent or find speakers', () => {
    counter = 0
    const messages: Message[] = [
      ...Array.from({ length: 5 }, () => progress('deepagent.thought')),
      ...Array.from({ length: 4 }, () => progress('findings.note')),
    ]
    const groups = groupProgressMessages(messages, 2)
    expect(groups).toHaveLength(9)
    expect(groups.every(g => g.kind === 'single')).toBe(true)
  })

  it('breaks runs on a different foldable speaker', () => {
    counter = 0
    const messages: Message[] = [
      progress('workflow.a'),
      progress('workflow.a'),
      progress('workflow.a'),
      progress('workflow.qc_passed'), // speaker: qc, different
      progress('workflow.a'),
      progress('workflow.a'),
      progress('workflow.a'),
    ]
    const groups = groupProgressMessages(messages, 2)
    // wf run of 3 → folds; qc run of 1 → single; wf run of 3 → folds
    expect(groups).toHaveLength(3)
    expect(groups[0].kind).toBe('folded')
    expect(groups[1].kind).toBe('single')
    expect(groups[2].kind).toBe('folded')
  })

  it('does not fold non-progress messages interleaved between runs', () => {
    counter = 0
    const messages: Message[] = [
      progress('workflow.a'),
      progress('workflow.a'),
      progress('workflow.a'),
      userMsg('a question'),
      progress('workflow.a'),
      progress('workflow.a'),
      progress('workflow.a'),
    ]
    const groups = groupProgressMessages(messages, 2)
    expect(groups).toHaveLength(3)
    expect(groups[0].kind).toBe('folded')
    expect(groups[1].kind).toBe('single')
    expect(groups[2].kind).toBe('folded')
  })

  it('threshold=0 disables folding entirely', () => {
    counter = 0
    const messages: Message[] = Array.from({ length: 10 }, () => progress('workflow.a'))
    const groups = groupProgressMessages(messages, 0)
    expect(groups).toHaveLength(10)
    expect(groups.every(g => g.kind === 'single')).toBe(true)
  })
})
