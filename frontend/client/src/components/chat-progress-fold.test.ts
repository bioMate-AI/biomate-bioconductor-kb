import { describe, expect, it } from 'vitest'
import { groupProgressMessages, groupWorkflowResponses } from './chat-progress-fold'
import type { Message } from '@shared/schema'

let counter = 0
function progress(kind: string, content = 'tick'): Message {
  counter += 1
  return {
    id: `p${counter}`,
    role: 'assistant',
    content,
    invocationId: 'run-default',
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

  it('keeps reloaded progress without ownership as standalone chronological entries', () => {
    counter = 0
    const reloaded = (): Message => {
      counter += 1
      return { id: `progress-inv-step-${counter}`, role: 'assistant', content: 'tick', metadata: {} } as unknown as Message
    }
    const messages: Message[] = Array.from({ length: 6 }, reloaded)
    const groups = groupProgressMessages(messages, 2)
    expect(groups).toHaveLength(6)
    expect(groups.every(group => group.kind === 'single')).toBe(true)
  })
})

const anchor = (id: string, invocationId: string, aliases = {}): Message => ({
  id, role: 'assistant', content: 'I will analyze the inputs.', invocationId,
  metadata: { type: 'workflow', workflow: { name: 'Analysis' }, ...aliases },
} as unknown as Message)
const update = (id: string, invocationId: string): Message => ({
  ...progress('workflow.step_completed', id), id, invocationId,
})

describe('run-owned responses', () => {
  it('places progress and findings within their exact run while preserving user turns', () => {
    const first = anchor('anchor-a', 'run-a', { galaxyInvocationId: 'galaxy-a' })
    const second = anchor('anchor-b', 'run-b')
    const question = userMsg('What about the other sample?')
    const findings = { ...update('answer-a', 'galaxy-a'), metadata: { type: 'findings' } } as Message
    const groups = groupWorkflowResponses([
      first, update('a1', 'galaxy-a'), second, update('b1', 'run-b'), question,
      update('a2', 'galaxy-a'), findings,
    ])
    expect(groups.map(group => group.key)).toEqual(['anchor-a', 'anchor-b', question.id])
    expect(groups[0]).toMatchObject({ kind: 'response', progress: [{ id: 'a1' }, { id: 'a2' }], findings: [{ id: 'answer-a' }] })
    expect(groups[1]).toMatchObject({ kind: 'response', progress: [{ id: 'b1' }], findings: [] })
  })

  it('does not merge adjacent updates from different runs', () => {
    const groups = groupProgressMessages([update('a', 'run-a'), update('b', 'run-b')])
    expect(groups).toHaveLength(2)
  })

  it('retains stream identity when new updates arrive', () => {
    const a = update('a', 'run-a')
    expect(groupProgressMessages([a])[0].key).toBe(groupProgressMessages([a, update('b', 'run-a')])[0].key)
  })

  it('does not attach updates to ambiguous owners or invent legacy ownership', () => {
    const legacy = { ...update('progress-legacy', 'run-a'), invocationId: undefined } as Message
    const groups = groupWorkflowResponses([anchor('a', 'shared'), anchor('b', 'shared'), update('c', 'shared'), legacy])
    expect(groups.filter(group => group.kind === 'response').every(group => group.progress.length === 0)).toBe(true)
    expect(groups.at(-1)).toMatchObject({ kind: 'single', message: { id: 'progress-legacy' } })
  })

  it('keeps deduplicated ownership and association after JSON persistence', () => {
    const a = update('a', 'galaxy-a')
    const messages = JSON.parse(JSON.stringify([anchor('wf', 'run-a', { galaxyInvocationId: 'galaxy-a' }), a, a]))
    const groups = groupWorkflowResponses(messages)
    expect(groups).toHaveLength(1)
    expect(groups[0]).toMatchObject({ kind: 'response', progress: [{ id: 'a' }] })
  })

  it('uses a verified execution-to-invocation mapping for older saved anchors', () => {
    const groups = groupWorkflowResponses([anchor('wf', 'run-a'), update('a', 'galaxy-a')], {
      id: 'run-a', invocationId: 'galaxy-a',
    })
    expect(groups[0]).toMatchObject({ kind: 'response', progress: [{ id: 'a' }] })
  })

  it('leaves conflicting run and invocation identities unattached', () => {
    const conflicted = update('conflict', 'run-a')
    conflicted.metadata = { ...conflicted.metadata, runId: 'run-b' }
    const groups = groupWorkflowResponses([anchor('a', 'run-a'), anchor('b', 'run-b'), conflicted])
    expect(groups.at(-1)).toMatchObject({ kind: 'stream', messages: [{ id: 'conflict' }] })
    expect(groups.filter(group => group.kind === 'response').every(group => group.progress.length === 0)).toBe(true)
  })
})
