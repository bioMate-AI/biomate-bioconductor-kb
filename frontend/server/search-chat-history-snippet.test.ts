import { describe, expect, it } from 'vitest';
import { extractChatSnippet } from './galaxy-assistant';

// extractChatSnippet is the pure half of the search_chat_history tool: it turns a
// chat_sessions.messages JSONB value into a short human-readable snippet around the
// first matching token. The DB half (user scoping, current-session exclusion) is an
// ILIKE query covered by the handler; this guards the shape-handling + windowing.
describe('extractChatSnippet', () => {
  it('finds the token and windows around it in an array of {role,content} messages', () => {
    const messages = [
      { role: 'user', content: 'We should align the reads to the human reference' },
      { role: 'assistant', content: 'Using GRCh38 for variant calling, calling HaplotypeCaller next.' },
    ];
    const snip = extractChatSnippet(messages, ['grch38']);
    expect(snip.toLowerCase()).toContain('grch38');
    expect(snip).toContain('variant calling');
  });

  it('picks the earliest-occurring token when several are given', () => {
    const messages = [{ role: 'assistant', content: 'alpha beta gamma delta' }];
    // "gamma" appears after "beta"; snippet should still center on the earliest hit.
    const snip = extractChatSnippet(messages, ['gamma', 'beta']);
    expect(snip).toContain('beta');
  });

  it('handles content as an array of parts (block-style messages)', () => {
    const messages = [
      { role: 'assistant', content: [{ type: 'text', text: 'the hERG threshold was set to 0.5' }] },
    ];
    const snip = extractChatSnippet(messages, ['herg']);
    expect(snip).toContain('hERG threshold');
  });

  it('accepts a raw string or arbitrary object without throwing', () => {
    expect(extractChatSnippet('plain transcript mentioning falcon campaign', ['falcon'])).toContain('falcon');
    expect(extractChatSnippet({ nested: { note: 'falcon' } }, ['falcon'])).toContain('falcon');
  });

  it('returns empty string for empty / unusable input', () => {
    expect(extractChatSnippet(null, ['x'])).toBe('');
    expect(extractChatSnippet([], ['x'])).toBe('');
    expect(extractChatSnippet('', ['x'])).toBe('');
  });

  it('adds ellipses only when the snippet is truncated at that edge', () => {
    const long = 'z'.repeat(50) + ' needle ' + 'z'.repeat(400);
    const snip = extractChatSnippet(long, ['needle']);
    expect(snip).toContain('needle');
    // Left edge within 80 chars of start → no leading ellipsis; right edge truncated → trailing ellipsis.
    expect(snip.startsWith('…')).toBe(false);
    expect(snip.endsWith('…')).toBe(true);
  });
});
