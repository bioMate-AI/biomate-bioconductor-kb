import { describe, it, expect } from 'vitest';
import {
  ChatContextBuilder, CANONICAL_ORDER, manifestSummary,
  type ChannelName,
} from './chat-context-harness';

describe('ChatContextBuilder — fired / bytes / scope accounting', () => {
  it('a channel with content fires and counts its UTF-8 bytes', () => {
    const m = new ChatContextBuilder().add({ name: 'project_context', scope: 'project', content: 'Project: X' }).build();
    const c = m.channels.find((x) => x.name === 'project_context')!;
    expect(c.fired).toBe(true);
    expect(c.scope).toBe('project');
    expect(c.bytes).toBe(Buffer.byteLength('Project: X', 'utf8'));
    expect(m.totalBytes).toBe(c.bytes);
  });

  it('empty/whitespace content does NOT fire and contributes 0 bytes', () => {
    const m = new ChatContextBuilder()
      .add({ name: 'standing_instructions', scope: 'project', content: '   ' })
      .add({ name: 'history', scope: 'conversation', content: '' })
      .build();
    expect(m.channels.every((c) => !c.fired)).toBe(true);
    expect(m.prompt).toBe('');
    expect(m.totalBytes).toBe(0);
  });

  it('a failure-signalled channel fires even with a short note (honest empty-result)', () => {
    const m = new ChatContextBuilder()
      .add({ name: 'cross_session', scope: 'user', content: 'No earlier chats matched "hERG".', failureSignalled: true })
      .build();
    const c = m.channels.find((x) => x.name === 'cross_session')!;
    expect(c.fired).toBe(true);
    expect(c.failureSignalled).toBe(true);
    expect(m.prompt).toContain('No earlier chats matched');
  });

  it('multibyte content is counted by bytes, not code units', () => {
    const body = '肿瘤'; // 2 chars, 6 UTF-8 bytes
    const m = new ChatContextBuilder().add({ name: 'project_context', scope: 'project', content: body }).build();
    expect(m.channels[0].bytes).toBe(6);
  });
});

describe('ChatContextBuilder — assembly order & wraps', () => {
  it('assembles fired channels in CANONICAL_ORDER', () => {
    const m = new ChatContextBuilder()
      .add({ name: 'history', scope: 'conversation', content: 'H' })
      .add({ name: 'project_context', scope: 'project', content: 'P' })
      .add({ name: 'session_datasets', scope: 'conversation', content: 'D' })
      .build();
    // project_context precedes session_datasets precedes history in CANONICAL_ORDER
    expect(m.prompt).toBe('P\n\nD\n\nH');
  });

  it('respects an explicit order and appends any un-ordered channel at the end (never dropped)', () => {
    const order: ChannelName[] = ['history', 'project_context'];
    const m = new ChatContextBuilder()
      .add({ name: 'project_context', scope: 'project', content: 'P' })
      .add({ name: 'history', scope: 'conversation', content: 'H' })
      .add({ name: 'skills', scope: 'user', content: 'S' }) // not in `order`
      .build(order);
    expect(m.prompt).toBe('H\n\nP\n\nS');
    expect(m.channels.map((c) => c.name)).toEqual(['history', 'project_context', 'skills']);
  });

  it('applies wrapper tags to a channel', () => {
    const m = new ChatContextBuilder()
      .add({ name: 'cross_session', scope: 'user', content: 'recall', wrap: { open: '<long_term_memory>', close: '</long_term_memory>' } })
      .build();
    expect(m.prompt).toBe('<long_term_memory>\nrecall\n</long_term_memory>');
  });

  it('last write wins for the same channel (staged computation, no double count)', () => {
    const m = new ChatContextBuilder()
      .add({ name: 'project_context', scope: 'project', content: 'draft' })
      .add({ name: 'project_context', scope: 'project', content: 'final version' })
      .build();
    expect(m.channels.filter((c) => c.name === 'project_context')).toHaveLength(1);
    expect(m.prompt).toBe('final version');
  });

  it('CANONICAL_ORDER has no duplicates and covers the 11 named channels', () => {
    expect(new Set(CANONICAL_ORDER).size).toBe(CANONICAL_ORDER.length);
    expect(CANONICAL_ORDER.length).toBe(11);
  });
});

describe('manifestSummary — shadow log line', () => {
  it('lists fired channels with scope/size and flags, plus a total', () => {
    const m = new ChatContextBuilder()
      .add({ name: 'project_context', scope: 'project', content: 'x'.repeat(300) })
      .add({ name: 'standing_instructions', scope: 'project', content: 'y'.repeat(100), truncated: true })
      .add({ name: 'cross_session', scope: 'user', content: 'none found', failureSignalled: true })
      .add({ name: 'history', scope: 'conversation', content: '' }) // not fired → omitted
      .build();
    const s = manifestSummary(m);
    expect(s).toContain('project_context(project,300B)');
    expect(s).toContain('standing_instructions(project,100B,trunc)');
    expect(s).toContain('cross_session(user,10B,miss)');
    expect(s).not.toContain('history(');
    expect(s).toMatch(/total=\d/);
  });
});
