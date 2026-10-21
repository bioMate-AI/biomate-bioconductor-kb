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

describe('groupProgressMessages — single compact stream box', () => {
  it('streams the canonical 8-wf / 1-agent / 5-wf fixture into 2 boxes + 1 agent single', () => {
    counter = 0
    const messages: Message[] = [
      ...Array.from({ length: 8 }, () => progress('workflow.step_started')),
      progress('deepagent.thought', 'reasoning…'),
      ...Array.from({ length: 5 }, () => progress('workflow.step_completed')),
    ]
    const groups = groupProgressMessages(messages, 2)
    expect(groups).toHaveLength(3)
    expect(groups[0].kind).toBe('stream')
    if (groups[0].kind === 'stream') expect(groups[0].messages).toHaveLength(8)
    expect(groups[1].kind).toBe('single') // agent never folds
    if (groups[1].kind === 'single') expect(groups[1].message.id).toBe('p9')
    expect(groups[2].kind).toBe('stream')
    if (groups[2].kind === 'stream') expect(groups[2].messages).toHaveLength(5)
  })

  it('boxes every foldable-progress run, including short ones', () => {
    counter = 0
    const messages: Message[] = [progress('workflow.x'), progress('workflow.x')]
    const groups = groupProgressMessages(messages, 2)
    expect(groups).toHaveLength(1)
    expect(groups[0].kind).toBe('stream')
    if (groups[0].kind === 'stream') expect(groups[0].messages).toHaveLength(2)
  })

  it('MERGES different foldable speakers (wf + qc + loop) into ONE box', () => {
    counter = 0
    const messages: Message[] = [
      progress('workflow.a'),
      progress('workflow.a'),
      progress('workflow.qc_passed'), // qc
      progress('workflow.autoloop_x'), // loop
      progress('workflow.a'),
    ]
    const groups = groupProgressMessages(messages, 2)
    expect(groups).toHaveLength(1)
    expect(groups[0].kind).toBe('stream')
    if (groups[0].kind === 'stream') expect(groups[0].messages).toHaveLength(5)
  })

  it('never boxes agent or find speakers', () => {
    counter = 0
    const messages: Message[] = [
      ...Array.from({ length: 5 }, () => progress('deepagent.thought')),
      ...Array.from({ length: 4 }, () => progress('findings.note')),
    ]
    const groups = groupProgressMessages(messages, 2)
    expect(groups).toHaveLength(9)
    expect(groups.every(g => g.kind === 'single')).toBe(true)
  })

  it('breaks the box on an interleaved non-progress message', () => {
    counter = 0
    const messages: Message[] = [
      progress('workflow.a'),
      progress('workflow.a'),
      userMsg('a question'),
      progress('workflow.a'),
      progress('workflow.a'),
    ]
    const groups = groupProgressMessages(messages, 2)
    expect(groups).toHaveLength(3)
    expect(groups[0].kind).toBe('stream')
    expect(groups[1].kind).toBe('single')
    expect(groups[2].kind).toBe('stream')
  })

  it('threshold=0 disables streaming entirely', () => {
    counter = 0
    const messages: Message[] = Array.from({ length: 10 }, () => progress('workflow.a'))
    const groups = groupProgressMessages(messages, 0)
    expect(groups).toHaveLength(10)
    expect(groups.every(g => g.kind === 'single')).toBe(true)
  })

  it('streams reloaded progress lines (metadata stripped on persist) by id prefix', () => {
    counter = 0
    const reloaded = (): Message => {
      counter += 1
      return { id: `progress-inv-step-${counter}`, role: 'assistant', content: 'tick', metadata: {} } as unknown as Message
    }
    const messages: Message[] = Array.from({ length: 6 }, reloaded)
    const groups = groupProgressMessages(messages, 2)
    expect(groups).toHaveLength(1)
    expect(groups[0].kind).toBe('stream')
    if (groups[0].kind === 'stream') expect(groups[0].messages).toHaveLength(6)
  })
})
