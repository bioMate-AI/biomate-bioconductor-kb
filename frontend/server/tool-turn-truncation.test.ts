import { describe, it, expect } from 'vitest';
import { FINAL_ANSWER_INSTRUCTION, TRUNCATED_REPLY_INSTRUCTION, finalAnswerRequest, toolCallDisplayFor, truncatedTurnFollowUp } from './galaxy-assistant';

describe('truncatedTurnFollowUp (turn stopped on max_tokens)', () => {
  // Live shape (dev 2026-11-12, GLM via OpenRouter): narration + a tool_use cut mid-input.
  const cut = [
    { type: 'text', text: '现在让我生成可视化的 QC 报告：' },
    { type: 'tool_use', id: 'call_5', name: 'run_code', input: {} },
  ];
  it('keeps only the text (an unrun tool_use would need a tool_result) and asks to continue', () => {
    const [assistant, user] = truncatedTurnFollowUp(cut);
    expect(assistant).toEqual({ role: 'assistant', content: [{ type: 'text', text: '现在让我生成可视化的 QC 报告：' }] });
    expect(user).toEqual({ role: 'user', content: TRUNCATED_REPLY_INSTRUCTION });
  });
  it('an empty truncated turn still yields a valid assistant entry', () => {
    expect(truncatedTurnFollowUp([{ type: 'tool_use', id: 'x', name: 'run_code', input: {} }])[0].content).toEqual([{ type: 'text', text: ' ' }]);
    expect(truncatedTurnFollowUp(undefined)[0].content).toEqual([{ type: 'text', text: ' ' }]);
  });
  it('the final-answer turn after a truncation merges into the follow-up (no two user turns in a row)', () => {
    const transcript = [{ role: 'user', content: 'QC this image' }, ...truncatedTurnFollowUp(cut)];
    const req = finalAnswerRequest({ model: 'm', messages: [] }, transcript, [{ name: 'run_code' }]);
    expect(req.messages).toHaveLength(3);
    expect(req.messages[2]).toEqual({ role: 'user', content: [
      { type: 'text', text: TRUNCATED_REPLY_INSTRUCTION }, { type: 'text', text: FINAL_ANSWER_INSTRUCTION },
    ] });
    expect(transcript[2].content).toBe(TRUNCATED_REPLY_INSTRUCTION); // caller's transcript not mutated
  });
});

describe('toolCallDisplayFor — the chat card never shows raw tool input', () => {
  const context = { sessionDatasets: [{ id: 'b9ce582c-fded-4db5-838f-bdd96820f72c', name: '0.jpeg', type: 'jpeg' }] };
  it('a dataset id becomes the dataset name (live screenshot input)', () => {
    expect(toolCallDisplayFor({ galaxy_dataset_id: 'b9ce582c-fded-4db5-838f-bdd96820f72c' }, context)).toBe('0.jpeg');
  });
  it('an unknown id is dropped, never shown', () => {
    expect(toolCallDisplayFor({ galaxy_dataset_id: 'f0f0f0f0-1111-2222-3333-444455556666' }, context)).toBe('');
    expect(toolCallDisplayFor({ dataset_id: '0123456789abcdef0123' }, context)).toBe('');
  });
  it('storage URIs reduce to the file name; queries are kept; code is skipped', () => {
    expect(toolCallDisplayFor({ path: 's3://bucket/uploads/u1/sample_metadata.csv' })).toBe('sample_metadata.csv');
    expect(toolCallDisplayFor({ query: 'CRISPR screen QC metrics', n_results: 5 })).toBe('CRISPR screen QC metrics');
    expect(toolCallDisplayFor({ code: 'import os\nprint(1)', language: 'python' })).toBe('python');
  });
});
